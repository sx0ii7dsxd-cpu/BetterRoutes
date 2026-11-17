const HTTP_STATUS_BY_CODE = {
  aborted: 409,
  'failed-precondition': 412,
  internal: 500,
  'invalid-argument': 400,
  'not-found': 404,
  'permission-denied': 403,
  unauthenticated: 401,
};

class ShipmentApiError extends Error {
  constructor(code, message, details = null) {
    super(message);
    this.name = 'ShipmentApiError';
    this.code = code;
    this.details = details;
    this.statusCode = HTTP_STATUS_BY_CODE[code] ?? 500;
  }
}

function createShipmentApi({
  auth,
  db,
  FieldValue,
  env = process.env,
  logger = console,
  shipmentServiceFactory,
}) {
  const allowedOrigins = new Set(
    (env.SHIPMENT_ALLOWED_ORIGINS ?? '')
      .split(',')
      .map((origin) => origin.trim())
      .filter(Boolean),
  );
  const createService =
    shipmentServiceFactory ??
    (() => {
      const { ShipmentService } = require('./shipment_service');
      return new ShipmentService({ db, FieldValue });
    });

  async function authenticate(request) {
    const header = request.headers.authorization;
    const match =
      typeof header === 'string' ? /^Bearer\s+(.+)$/i.exec(header) : null;
    if (!match) {
      throw new ShipmentApiError(
        'unauthenticated',
        'Sign in before creating a shipment.',
      );
    }

    try {
      const decodedToken = await auth.verifyIdToken(match[1], true);
      if (!decodedToken.uid) throw new Error('Token has no UID.');
      return decodedToken.uid;
    } catch {
      throw new ShipmentApiError(
        'unauthenticated',
        'Your sign-in has expired. Sign in again and retry.',
      );
    }
  }

  return async function shipmentApi(request, response) {
    try {
      setCorsHeaders(response, request.headers.origin, allowedOrigins);
      if (request.method === 'OPTIONS') return response.status(204).end();
      if (request.method !== 'POST') {
        throw new ShipmentApiError(
          'invalid-argument',
          'Use POST for this endpoint.',
        );
      }

      const creatorUid = await authenticate(request);
      const body = parseBody(request);
      const service = createService();
      const shipment = await service.createShipment({
        creatorUid,
        data: body,
      });
      return response.status(201).json(shipment);
    } catch (error) {
      return sendError(response, error, logger);
    }
  };
}

function parseBody(request) {
  if (typeof request.body === 'string') {
    try {
      return JSON.parse(request.body);
    } catch {
      throw new ShipmentApiError(
        'invalid-argument',
        'Request body must be valid JSON.',
      );
    }
  }
  return request.body;
}

function setCorsHeaders(response, origin, allowedOrigins) {
  if (!origin) return;
  if (!allowedOrigins.has(origin)) {
    throw new ShipmentApiError(
      'permission-denied',
      'This app origin is not allowed.',
    );
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
  if (error?.name === 'ShipmentServiceError') {
    error = new ShipmentApiError(error.code, error.message, error.details);
  }
  if (!(error instanceof ShipmentApiError)) {
    logger.error('Shipment API request failed unexpectedly.', {
      message: error?.message ?? 'unknown error',
    });
    error = new ShipmentApiError(
      'internal',
      'Could not create the shipment.',
    );
  }
  return response.status(error.statusCode).json({
    error: {
      code: error.code,
      message: error.message,
      details: error.details,
    },
  });
}

module.exports = {
  ShipmentApiError,
  createShipmentApi,
  parseBody,
  setCorsHeaders,
};
