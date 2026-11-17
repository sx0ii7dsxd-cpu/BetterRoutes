const { createTrustedApi } = require('../src/trusted_api');
const { TrustedApiError } = require('../src/trusted_auth');
module.exports = createTrustedApi({
  adminOnly: true,
  action: ({ service, body }) => {
    if (body?.action === 'batch') return service.synchronizeShipmentAuthorizationBatch(body.shipmentIds, body.limit);
    if (body?.shipmentId) return service.synchronizeShipmentAuthorization(body.shipmentId);
    throw new TrustedApiError('invalid-argument', 'shipmentId is required.');
  },
});
