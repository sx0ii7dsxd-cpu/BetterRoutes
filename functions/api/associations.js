const { createTrustedApi } = require('../src/trusted_api');
module.exports = createTrustedApi({
  action: ({ service, body, token }) => body?.action === 'truck-ownership-request'
    ? service.createTruckOwnershipRequest({ requesterUid: token.uid, truckId: body?.truckId, requestedOwnerUid: body?.requestedOwnerUid })
    : service.createAssociation({ requesterUid: token.uid, warehouseId: body?.warehouseId, targetUid: body?.targetUid }),
});
