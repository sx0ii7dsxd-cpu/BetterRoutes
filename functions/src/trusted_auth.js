const crypto = require('node:crypto');

const HTTP_STATUS_BY_CODE = {
  unauthenticated: 401,
  'permission-denied': 403,
  'invalid-argument': 400,
  'not-found': 404,
  'already-exists': 409,
  'failed-precondition': 412,
  internal: 500,
};

class TrustedApiError extends Error {
  constructor(code, message, details = null) {
    super(message);
    this.name = 'TrustedApiError';
    this.code = code;
    this.details = details;
    this.statusCode = HTTP_STATUS_BY_CODE[code] || 500;
  }
}

async function verifyRequest(request, auth) {
  const header = request.headers && request.headers.authorization;
  const match = typeof header === 'string' && /^Bearer\s+(.+)$/i.exec(header);
  if (!match) throw new TrustedApiError('unauthenticated', 'Authentication is required.');
  try {
    const token = await auth.verifyIdToken(match[1], true);
    if (!token || typeof token.uid !== 'string' || !token.uid) throw new Error('Missing uid');
    return token;
  } catch {
    throw new TrustedApiError('unauthenticated', 'Your sign-in has expired. Sign in again.');
  }
}

function isAdminToken(token, env = process.env) {
  return token?.admin === true ||
    (env.BETTERROUTES_BOOTSTRAP_UID && token?.uid === env.BETTERROUTES_BOOTSTRAP_UID);
}

function requireAdmin(token, env) {
  if (!isAdminToken(token, env)) throw new TrustedApiError('permission-denied', 'Administrator permission is required.');
}

function parseJsonBody(request) {
  if (typeof request.body !== 'string') return request.body;
  try { return JSON.parse(request.body); } catch {
    throw new TrustedApiError('invalid-argument', 'Request body must be valid JSON.');
  }
}

function hashInvitationToken(token, secret) {
  if (typeof token !== 'string' || token.length < 16 || token.length > 256) return null;
  return crypto.createHmac('sha256', secret).update(token).digest('hex');
}

function makeInvitationToken(secret) {
  const token = crypto.randomBytes(32).toString('base64url');
  return { token, tokenHash: hashInvitationToken(token, secret) };
}

function safeError(response, error, logger = console) {
  if (!(error instanceof TrustedApiError)) {
    logger.error('Trusted backend request failed.', { message: error?.message || 'unknown error' });
    error = new TrustedApiError('internal', 'The request could not be completed.');
  }
  return response.status(error.statusCode).json({ error: { code: error.code, message: error.message, details: error.details } });
}

module.exports = {
  TrustedApiError, verifyRequest, isAdminToken, requireAdmin, parseJsonBody,
  hashInvitationToken, makeInvitationToken, safeError,
};
