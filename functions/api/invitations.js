const { createTrustedApi } = require('../src/trusted_api');
const { isAdminToken } = require('../src/trusted_auth');
module.exports = createTrustedApi({
  action: ({ service, body, token }) => {
    if (body?.action === 'accept') return service.acceptInvitation({ token: body.token, uid: token.uid });
    return service.createInvitation({ inviterUid: token.uid, inviterIsAdmin: isAdminToken(token), type: body?.type, targetUid: body?.targetUid, shipmentId: body?.shipmentId, truckId: body?.truckId, expiresInMs: body?.expiresInMs });
  },
});
