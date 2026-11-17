const { createTrustedApi } = require('../src/trusted_api');
const { TrustedApiError } = require('../src/trusted_auth');

module.exports = createTrustedApi({
  action: ({ service, body, token }) => {
    if (body?.action !== 'delete') {
      throw new TrustedApiError('invalid-argument', 'Unknown warehouse action.');
    }
    return service.deleteWarehouse({
      warehouseId: body.warehouseId,
      requesterUid: token.uid,
    });
  },
});
