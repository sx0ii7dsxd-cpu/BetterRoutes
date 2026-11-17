const { createTrustedApi } = require('../src/trusted_api');
const { isAdminToken, TrustedApiError } = require('../src/trusted_auth');

module.exports = createTrustedApi({
  action: async ({ service, body, token, env }) => {
    const action = body?.action;
    if (action === 'list-active-trucks') return service.listUserApprovedTrucks(token.uid);
    if (action === 'list-own-requests') return service.listUserRequests(token.uid);
    if (action === 'list-invitations') return service.listUserInvitations(token.uid);
    if (
      action === 'list-pending-trucks' ||
      action === 'list-approved-trucks' ||
      action === 'list-ownership-requests' ||
      action === 'list-all-invitations'
    ) {
      if (!isAdminToken(token, env)) throw new TrustedApiError('permission-denied', 'Administrator permission is required.');
      if (action === 'list-pending-trucks') return service.listPendingTruckRequests();
      if (action === 'list-approved-trucks') return service.listApprovedTrucks();
      if (action === 'list-all-invitations') return service.listAllInvitations();
      return service.listOwnershipRequests();
    }
    throw new TrustedApiError('invalid-argument', 'Unknown read action.');
  },
});
