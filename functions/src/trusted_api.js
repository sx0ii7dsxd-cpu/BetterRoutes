const { getFirebaseServices } = require('./firebase_admin');
const { TrustedService } = require('./trusted_service');
const { TrustedApiError, verifyRequest, requireAdmin, parseJsonBody, safeError } = require('./trusted_auth');

function createTrustedApi({ action, adminOnly = false, env = process.env }) {
  const { auth, db, FieldValue } = getFirebaseServices({ env });
  return async (request, response) => {
    try {
      if (request.method === 'OPTIONS') return response.status(204).end();
      if (request.method !== 'POST') throw new TrustedApiError('invalid-argument', 'Use POST for this endpoint.');
      const token = await verifyRequest(request, auth);
      if (adminOnly) requireAdmin(token, env);
      const body = parseJsonBody(request);
      const service = new TrustedService({ db, FieldValue, auth, env });
      const result = await action({ service, body, token, env });
      return response.status(200).json(result);
    } catch (error) { return safeError(response, error); }
  };
}

module.exports = { createTrustedApi };
