const crypto = require('node:crypto');
const net = require('node:net');

const {
  createOtp,
  hashOtp,
  hashesMatch,
  isValidOtp,
  normalizeEmail,
  timestampMillis,
} = require('./email_change_utils');

const FLOW_COLLECTION = 'emailChangeChallenges';
const RATE_LIMIT_COLLECTION = 'emailChangeRateLimits';
const FLOW_DURATION_MS = 24 * 60 * 60 * 1000;
const OTP_DURATION_MS = 10 * 60 * 1000;
const RESEND_DELAY_MS = 60 * 1000;
const UPDATE_RECOVERY_MS = 2 * 60 * 1000;
const MAX_RESENDS = 3;
const MAX_FAILED_ATTEMPTS = 5;
const REQUEST_WINDOW_MS = 60 * 60 * 1000;
const EMAIL_WINDOW_MS = 24 * 60 * 60 * 1000;
const MAX_REQUESTS_PER_UID_PER_HOUR = 60;
const MAX_REQUESTS_PER_IP_PER_HOUR = 120;
const MAX_EMAILS_PER_UID_PER_DAY = 5;
const MAX_EMAILS_PER_IP_PER_HOUR = 20;
const MAX_EMAILS_PER_ADDRESS_PER_DAY = 5;
const MAX_EMAILS_PER_PROJECT_PER_DAY = 80;

const HTTP_STATUS_BY_CODE = {
  'already-exists': 409,
  'deadline-exceeded': 410,
  'failed-precondition': 412,
  internal: 500,
  'invalid-argument': 400,
  'not-found': 404,
  'permission-denied': 403,
  'resource-exhausted': 429,
  unauthenticated: 401,
  unavailable: 503,
};

class ApiError extends Error {
  constructor(code, message, details = null) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.details = details;
    this.statusCode = HTTP_STATUS_BY_CODE[code] ?? 500;
  }
}

function requireOtp(value) {
  if (!isValidOtp(value)) {
    throw new ApiError(
      'invalid-argument',
      'Enter the six-digit code from the email.',
    );
  }
  return value;
}

function flowDocument(db, uid) {
  return db.collection(FLOW_COLLECTION).doc(uid);
}

function rateLimitDocument(db, secret, name, value) {
  const id = crypto
    .createHmac('sha256', secret)
    .update(`${name}:${value}`)
    .digest('hex');
  return db.collection(RATE_LIMIT_COLLECTION).doc(`${name}_${id}`);
}

function toPublicStatus(flow, extra = {}) {
  return {
    stage: flow.stage,
    newEmail: flow.newEmail,
    cooldownUntil: timestampMillis(flow.cooldownUntil),
    otpExpiresAt: timestampMillis(flow.otpExpiresAt),
    resendAvailableAt: timestampMillis(flow.resendAvailableAt),
    resendCount: flow.oldResends ?? 0,
    maxResends: MAX_RESENDS,
    attemptsRemaining: Math.max(
      0,
      MAX_FAILED_ATTEMPTS - (flow.failedAttempts ?? 0),
    ),
    ...extra,
  };
}

function codeDigest(uid, flowId, code, secret) {
  return hashOtp(uid, flowId, code, secret);
}

function checkCode(flow, uid, code, secret, now) {
  const expiry = timestampMillis(flow.otpExpiresAt);
  if (expiry == null || expiry <= now) return 'expired';
  return hashesMatch(
    flow.otpHash,
    codeDigest(uid, flow.flowId, code, secret),
  )
    ? 'valid'
    : 'invalid';
}

function codeError(outcome, attemptsRemaining) {
  if (outcome === 'wrong') {
    return new ApiError('permission-denied', 'That code is incorrect.', {
      attemptsRemaining,
    });
  }
  if (outcome === 'expired') {
    return new ApiError(
      'deadline-exceeded',
      'That code has expired. Request another code to continue this change.',
    );
  }
  if (outcome === 'locked') {
    return new ApiError(
      'resource-exhausted',
      'Too many incorrect codes. Start a new change after the 24-hour wait.',
      { attemptsRemaining },
    );
  }
  return null;
}

function pendingError(flow) {
  const cooldownUntil = timestampMillis(flow.cooldownUntil);
  return new ApiError(
    'resource-exhausted',
    `An email change is already in progress. Try again after ${new Date(cooldownUntil).toLocaleString('en-US', { timeZone: 'UTC' })} UTC.`,
    { cooldownUntil },
  );
}

function requestIp(request) {
  const forwardedFor = request.headers['x-forwarded-for'];
  const candidate =
    typeof forwardedFor === 'string'
      ? forwardedFor.split(',')[0].trim()
      : '';
  return net.isIP(candidate) ? candidate : 'unknown';
}

function rateLimitError(spec, retryAt) {
  return new ApiError('resource-exhausted', spec.message, { retryAt });
}

async function consumeRateLimits({
  transaction,
  db,
  secret,
  now,
  Timestamp,
  specs,
}) {
  const windows = specs.map((spec) => ({
    ...spec,
    windowStart: Math.floor(now / spec.windowMs) * spec.windowMs,
    ref: rateLimitDocument(db, secret, spec.name, spec.value),
  }));
  const snapshots = await Promise.all(
    windows.map(({ ref }) => transaction.get(ref)),
  );

  const counts = windows.map(({ windowStart }, index) => {
    const data = snapshots[index].exists ? snapshots[index].data() : null;
    return data?.windowStart === windowStart ? data.count : 0;
  });
  const exceededIndex = windows.findIndex(
    (spec, index) => counts[index] >= spec.limit,
  );
  if (exceededIndex !== -1) {
    const spec = windows[exceededIndex];
    return rateLimitError(spec, spec.windowStart + spec.windowMs);
  }

  windows.forEach((spec, index) => {
    transaction.set(
      spec.ref,
      {
        windowStart: spec.windowStart,
        count: counts[index] + 1,
        updatedAt: Timestamp.fromMillis(now),
      },
      { merge: true },
    );
  });
  return null;
}

function requestRateLimits(uid, ip) {
  return [
    {
      name: 'request_uid',
      value: uid,
      windowMs: REQUEST_WINDOW_MS,
      limit: MAX_REQUESTS_PER_UID_PER_HOUR,
      message: 'Too many requests. Please wait before trying again.',
    },
    {
      name: 'request_ip',
      value: ip,
      windowMs: REQUEST_WINDOW_MS,
      limit: MAX_REQUESTS_PER_IP_PER_HOUR,
      message: 'Too many requests from this network. Please wait and try again.',
    },
  ];
}

function emailRateLimits(uid, ip, oldEmail) {
  return [
    {
      name: 'email_uid',
      value: uid,
      windowMs: EMAIL_WINDOW_MS,
      limit: MAX_EMAILS_PER_UID_PER_DAY,
      message: 'Too many verification emails were requested for this account today.',
    },
    {
      name: 'email_ip',
      value: ip,
      windowMs: REQUEST_WINDOW_MS,
      limit: MAX_EMAILS_PER_IP_PER_HOUR,
      message: 'Too many verification emails were requested from this network.',
    },
    {
      name: 'email_address',
      value: oldEmail,
      windowMs: EMAIL_WINDOW_MS,
      limit: MAX_EMAILS_PER_ADDRESS_PER_DAY,
      message: 'Too many verification emails were sent to this address today.',
    },
    {
      name: 'email_project',
      value: 'all',
      windowMs: EMAIL_WINDOW_MS,
      limit: MAX_EMAILS_PER_PROJECT_PER_DAY,
      message: 'The daily verification-email limit has been reached. Please try again tomorrow.',
    },
  ];
}

async function sendOtpEmail({ to, code, apiKey, from, logger }) {
  if (!apiKey || !from) {
    throw new ApiError(
      'failed-precondition',
      'Email delivery is not configured. Contact support.',
    );
  }

  let response;
  try {
    response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      signal: AbortSignal.timeout(10000),
      body: JSON.stringify({
        from,
        to: [to],
        subject: 'Your BetterRoutes email-change code',
        text:
          `Your BetterRoutes verification code is ${code}. ` +
          'Enter it in the app to confirm this email change. ' +
          'The code expires in 10 minutes. If you did not request this, ignore this email.',
        html:
          '<p>Your BetterRoutes verification code is:</p>' +
          `<p style="font-size:28px;font-weight:700;letter-spacing:6px">${code}</p>` +
          '<p>Enter it in the app to confirm this email change. The code expires in 10 minutes.</p>' +
          '<p>If you did not request this, ignore this email.</p>',
      }),
    });
  } catch (error) {
    logger.error('Could not reach the email delivery service.', {
      message: error.message,
    });
    throw new ApiError(
      'unavailable',
      'Could not reach the email service. Please try again.',
    );
  }

  if (!response.ok) {
    logger.error('Resend rejected an email-change OTP request.', {
      status: response.status,
    });
    throw new ApiError(
      'unavailable',
      'Could not send the verification email. Please try again.',
    );
  }
}

function parseBody(request) {
  if (typeof request.body === 'string') {
    try {
      return JSON.parse(request.body);
    } catch {
      throw new ApiError('invalid-argument', 'Request body must be valid JSON.');
    }
  }
  return request.body;
}

function setCorsHeaders(response, origin, allowedOrigins) {
  if (!origin) return;
  if (!allowedOrigins.has(origin)) {
    throw new ApiError('permission-denied', 'This app origin is not allowed.');
  }
  response.setHeader('Access-Control-Allow-Origin', origin);
  response.setHeader('Vary', 'Origin');
  response.setHeader(
    'Access-Control-Allow-Headers',
    'Authorization, Content-Type',
  );
  response.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
}

function sendError(response, error, logger) {
  if (!(error instanceof ApiError)) {
    logger.error('Email-change API request failed unexpectedly.', {
      message: error?.message ?? 'unknown error',
    });
    error = new ApiError('internal', 'Could not complete the email change.');
  }
  response.status(error.statusCode).json({
    error: {
      code: error.code,
      message: error.message,
      details: error.details,
    },
  });
}

function createEmailChangeApi({
  auth,
  db,
  FieldValue,
  Timestamp,
  env,
  logger = console,
  now = Date.now,
  sendEmail = sendOtpEmail,
}) {
  const secret = env.OTP_HMAC_SECRET;
  const allowedOrigins = new Set(
    (env.EMAIL_CHANGE_ALLOWED_ORIGINS ?? '')
      .split(',')
      .map((origin) => origin.trim())
      .filter(Boolean),
  );

  if (!secret) throw new Error('OTP_HMAC_SECRET is required.');

  async function authenticate(request) {
    const header = request.headers.authorization;
    const match =
      typeof header === 'string' ? /^Bearer\s+(.+)$/i.exec(header) : null;
    if (!match) {
      throw new ApiError('unauthenticated', 'Sign in before changing your email.');
    }

    try {
      const decodedToken = await auth.verifyIdToken(match[1], true);
      if (!decodedToken.uid) throw new Error('Token has no UID.');
      return decodedToken.uid;
    } catch {
      throw new ApiError(
        'unauthenticated',
        'Your sign-in has expired. Sign in again and retry.',
      );
    }
  }

  async function applyRequestRateLimits(uid, ip, requestTime) {
    const error = await db.runTransaction((transaction) =>
      consumeRateLimits({
        transaction,
        db,
        secret,
        now: requestTime,
        Timestamp,
        specs: requestRateLimits(uid, ip),
      }),
    );
    if (error) throw error;
  }

  async function loadActiveFlow(uid) {
    const ref = flowDocument(db, uid);
    const snapshot = await ref.get();
    if (!snapshot.exists) return { ref, flow: null };

    let flow = snapshot.data();
    const cooldownUntil = timestampMillis(flow.cooldownUntil);
    if (cooldownUntil == null || cooldownUntil <= now()) {
      await ref.delete();
      return { ref, flow: null };
    }

    const user = await auth.getUser(uid);
    if (user.email?.toLowerCase() === flow.newEmail) {
      await ref.delete();
      return { ref, flow: null, completedEmail: user.email };
    }

    const updateStartedAt = timestampMillis(flow.updateStartedAt);
    if (
      flow.stage === 'updating' &&
      (updateStartedAt == null ||
        now() - updateStartedAt >= UPDATE_RECOVERY_MS)
    ) {
      await ref.update({
        stage: 'verifyOld',
        updateStartedAt: FieldValue.delete(),
      });
      const refreshed = await ref.get();
      if (!refreshed.exists) return { ref, flow: null };
      flow = refreshed.data();
    }
    return { ref, flow };
  }

  async function status(uid) {
    const { flow, completedEmail } = await loadActiveFlow(uid);
    if (!flow) {
      return {
        stage: completedEmail ? 'complete' : 'idle',
        email: completedEmail ?? null,
      };
    }
    return toPublicStatus(flow);
  }

  async function start(uid, ip, data) {
    const newEmail = normalizeEmail(data?.newEmail);
    if (!newEmail) {
      throw new ApiError('invalid-argument', 'Enter a valid email address.');
    }

    const user = await auth.getUser(uid);
    const oldEmail = normalizeEmail(user.email);
    if (!oldEmail) {
      throw new ApiError(
        'failed-precondition',
        'Your account does not have an email address to verify.',
      );
    }
    if (newEmail === oldEmail) {
      throw new ApiError(
        'invalid-argument',
        'Enter an email address different from your current one.',
      );
    }

    try {
      const existing = await auth.getUserByEmail(newEmail);
      if (existing.uid !== uid) {
        throw new ApiError(
          'already-exists',
          'That email address is already associated with an account.',
        );
      }
    } catch (error) {
      if (error instanceof ApiError) throw error;
      if (error.code !== 'auth/user-not-found') throw error;
    }

    const code = createOtp();
    const requestTime = now();
    const flowId = crypto.randomUUID();
    const flow = {
      flowId,
      stage: 'verifyOld',
      oldEmail,
      newEmail,
      otpHash: codeDigest(uid, flowId, code, secret),
      otpExpiresAt: Timestamp.fromMillis(requestTime + OTP_DURATION_MS),
      cooldownUntil: Timestamp.fromMillis(requestTime + FLOW_DURATION_MS),
      resendAvailableAt: Timestamp.fromMillis(requestTime + RESEND_DELAY_MS),
      oldResends: 0,
      failedAttempts: 0,
    };
    const ref = flowDocument(db, uid);
    const reservation = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        const existingFlow = snapshot.data();
        const cooldownUntil = timestampMillis(existingFlow.cooldownUntil);
        if (cooldownUntil != null && cooldownUntil > requestTime) {
          return { pending: existingFlow };
        }
      }

      const rateLimitError = await consumeRateLimits({
        transaction,
        db,
        secret,
        now: requestTime,
        Timestamp,
        specs: emailRateLimits(uid, ip, oldEmail),
      });
      if (rateLimitError) return { error: rateLimitError };

      transaction.set(ref, flow);
      return { created: true };
    });
    if (reservation.error) throw reservation.error;
    if (!reservation.created) throw pendingError(reservation.pending);

    try {
      await sendEmail({
        to: oldEmail,
        code,
        apiKey: env.RESEND_API_KEY,
        from: env.EMAIL_FROM?.trim(),
        logger,
      });
    } catch (error) {
      try {
        const snapshot = await ref.get();
        if (snapshot.exists && snapshot.data().flowId === flowId) {
          await ref.delete();
        }
      } catch (cleanupError) {
        logger.error('Could not release a failed email-change reservation.', {
          message: cleanupError.message,
        });
        throw new ApiError(
          'internal',
          'Email delivery failed. Please wait before trying again.',
        );
      }
      throw error;
    }

    return toPublicStatus(flow);
  }

  async function verify(uid, data) {
    const code = requireOtp(data?.code);
    const ref = flowDocument(db, uid);
    const requestTime = now();
    const outcome = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) return { error: 'missing' };

      const flow = snapshot.data();
      if (timestampMillis(flow.cooldownUntil) <= requestTime) {
        return { error: 'missing' };
      }
      if (flow.stage !== 'verifyOld') return { error: 'wrong-stage' };
      if (flow.failedAttempts >= MAX_FAILED_ATTEMPTS) {
        return { error: 'locked', attemptsRemaining: 0 };
      }

      const codeResult = checkCode(flow, uid, code, secret, requestTime);
      if (codeResult === 'expired') return { error: 'expired' };
      if (codeResult === 'invalid') {
        const failedAttempts = flow.failedAttempts + 1;
        transaction.update(ref, { failedAttempts });
        return {
          error:
            failedAttempts >= MAX_FAILED_ATTEMPTS ? 'locked' : 'wrong',
          attemptsRemaining: Math.max(
            0,
            MAX_FAILED_ATTEMPTS - failedAttempts,
          ),
        };
      }

      transaction.update(ref, {
        stage: 'updating',
        updateStartedAt: Timestamp.fromMillis(requestTime),
      });
      return { flow };
    });

    if (outcome.error === 'missing') {
      throw new ApiError(
        'not-found',
        'This email-change request has expired. Start a new request.',
      );
    }
    if (outcome.error === 'wrong-stage') {
      throw new ApiError(
        'failed-precondition',
        'The current verification step has changed. Refresh and continue.',
      );
    }
    if (outcome.error) {
      throw codeError(outcome.error, outcome.attemptsRemaining);
    }

    try {
      const existing = await auth.getUserByEmail(outcome.flow.newEmail);
      if (existing.uid !== uid) {
        await ref.update({
          stage: 'verifyOld',
          updateStartedAt: FieldValue.delete(),
        });
        throw new ApiError(
          'already-exists',
          'That email address is already associated with another account.',
        );
      }
    } catch (error) {
      if (error instanceof ApiError) throw error;
      if (error.code !== 'auth/user-not-found') {
        await ref.update({
          stage: 'verifyOld',
          updateStartedAt: FieldValue.delete(),
        });
        throw error;
      }
    }

    try {
      await auth.updateUser(uid, {
        email: outcome.flow.newEmail,
        emailVerified: false,
      });
    } catch (error) {
      await ref.update({
        stage: 'verifyOld',
        updateStartedAt: FieldValue.delete(),
      });
      logger.error('Firebase rejected an email change.', {
        code: error.code ?? 'unknown',
      });
      if (error.code === 'auth/email-already-exists') {
        throw new ApiError(
          'already-exists',
          'That email address is already associated with another account.',
        );
      }
      throw new ApiError(
        'internal',
        'Could not update your email. Please try again.',
      );
    }

    try {
      await ref.delete();
    } catch (error) {
      logger.error('Could not clear a completed email-change request.', {
        message: error.message,
      });
    }
    return { stage: 'complete', email: outcome.flow.newEmail };
  }

  async function resend(uid, ip) {
    const ref = flowDocument(db, uid);
    const code = createOtp();
    const requestTime = now();
    const outcome = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) return { error: 'missing' };

      const flow = snapshot.data();
      if (timestampMillis(flow.cooldownUntil) <= requestTime) {
        return { error: 'missing' };
      }
      if (flow.stage !== 'verifyOld') return { error: 'wrong-stage' };
      if (flow.failedAttempts >= MAX_FAILED_ATTEMPTS) {
        return { error: 'locked' };
      }

      const oldResends = flow.oldResends ?? 0;
      if (oldResends >= MAX_RESENDS) return { error: 'resend-limit' };
      const resendAvailableAt = timestampMillis(flow.resendAvailableAt);
      if (resendAvailableAt != null && resendAvailableAt > requestTime) {
        return { error: 'resend-wait', retryAt: resendAvailableAt };
      }

      const rateLimitError = await consumeRateLimits({
        transaction,
        db,
        secret,
        now: requestTime,
        Timestamp,
        specs: emailRateLimits(uid, ip, flow.oldEmail),
      });
      if (rateLimitError) return { rateLimitError };

      const updatedFlow = {
        ...flow,
        otpHash: codeDigest(uid, flow.flowId, code, secret),
        otpExpiresAt: Timestamp.fromMillis(requestTime + OTP_DURATION_MS),
        resendAvailableAt: Timestamp.fromMillis(requestTime + RESEND_DELAY_MS),
        oldResends: oldResends + 1,
      };
      transaction.update(ref, {
        otpHash: updatedFlow.otpHash,
        otpExpiresAt: updatedFlow.otpExpiresAt,
        resendAvailableAt: updatedFlow.resendAvailableAt,
        oldResends: updatedFlow.oldResends,
      });
      return { flow: updatedFlow };
    });

    if (outcome.rateLimitError) throw outcome.rateLimitError;
    if (outcome.error === 'missing') {
      throw new ApiError(
        'not-found',
        'This email-change request has expired. Start a new request.',
      );
    }
    if (outcome.error === 'wrong-stage') {
      throw new ApiError(
        'failed-precondition',
        'There is no code to resend for the current step.',
      );
    }
    if (outcome.error === 'locked') throw codeError('locked', 0);
    if (outcome.error === 'resend-limit') {
      throw new ApiError(
        'resource-exhausted',
        'You have used all resend attempts for this step.',
      );
    }
    if (outcome.error === 'resend-wait') {
      throw new ApiError(
        'resource-exhausted',
        'Please wait before requesting another code.',
        { retryAt: outcome.retryAt },
      );
    }

    try {
      await sendEmail({
        to: outcome.flow.oldEmail,
        code,
        apiKey: env.RESEND_API_KEY,
        from: env.EMAIL_FROM?.trim(),
        logger,
      });
    } catch (error) {
      await ref.update({
        resendAvailableAt: Timestamp.fromMillis(now()),
      });
      throw error;
    }
    return toPublicStatus(outcome.flow);
  }

  return async function emailChangeApi(request, response) {
    try {
      const origin = request.headers.origin;
      setCorsHeaders(response, origin, allowedOrigins);
      if (request.method === 'OPTIONS') {
        return response.status(204).end();
      }
      if (request.method !== 'POST') {
        throw new ApiError('invalid-argument', 'Use POST for this endpoint.');
      }

      const uid = await authenticate(request);
      const ip = requestIp(request);
      const requestTime = now();
      await applyRequestRateLimits(uid, ip, requestTime);

      const body = parseBody(request);
      if (!body || typeof body !== 'object' || Array.isArray(body)) {
        throw new ApiError('invalid-argument', 'Request body must be an object.');
      }

      let result;
      switch (body.action) {
        case 'emailChangeStatus':
          result = await status(uid);
          break;
        case 'startEmailChange':
          result = await start(uid, ip, body);
          break;
        case 'verifyOldEmailCode':
          result = await verify(uid, body);
          break;
        case 'resendEmailChangeCode':
          result = await resend(uid, ip);
          break;
        default:
          throw new ApiError('invalid-argument', 'Unknown email-change action.');
      }
      return response.status(200).json(result);
    } catch (error) {
      return sendError(response, error, logger);
    }
  };
}

module.exports = {
  ApiError,
  createEmailChangeApi,
  consumeRateLimits,
  emailRateLimits,
  requestRateLimits,
};
