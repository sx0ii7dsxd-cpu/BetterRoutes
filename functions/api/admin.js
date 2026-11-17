const { createTrustedApi } = require('../src/trusted_api');
const { TrustedApiError, requireAdmin } = require('../src/trusted_auth');
const { getFirebaseServices } = require('../src/firebase_admin');
const { setAdminClaim } = require('../src/admin_claims');

module.exports = createTrustedApi({
  adminOnly: false,
  action: async ({ body, token, env }) => {
    const action = body?.action;
    if (action === 'bootstrap-admin' || action === 'revoke-admin') {
      if (!env.BETTERROUTES_BOOTSTRAP_UID || token.uid !== env.BETTERROUTES_BOOTSTRAP_UID) throw new TrustedApiError('permission-denied', 'Bootstrap access is not available.');
      const targetUid = typeof body.targetUid === 'string' ? body.targetUid.trim() : '';
      if (!targetUid) throw new TrustedApiError('invalid-argument', 'targetUid is required.');
      const { auth } = getFirebaseServices({ env });
      return setAdminClaim({ auth, targetUid, enabled: action === 'bootstrap-admin' });
    }
    requireAdmin(token, env);
    if (action === 'approve-truck') return new (require('../src/trusted_service').TrustedService)({ ...getFirebaseServices({ env }), env }).approveTruckRequest({ requestId: body.requestId, adminUid: token.uid });
    if (action === 'reject-truck') return new (require('../src/trusted_service').TrustedService)({ ...getFirebaseServices({ env }), env }).rejectTruckRequest({ requestId: body.requestId, adminUid: token.uid, reason: body.reason });
    if (action === 'truck-status') return new (require('../src/trusted_service').TrustedService)({ ...getFirebaseServices({ env }), env }).setTruckStatus({ truckId: body.truckId, status: body.status, adminUid: token.uid });
    if (action === 'association-decision') return new (require('../src/trusted_service').TrustedService)({ ...getFirebaseServices({ env }), env }).decideAssociation({ requestId: body.requestId, status: body.status, adminUid: token.uid });
    if (action === 'truck-ownership-decision') return new (require('../src/trusted_service').TrustedService)({ ...getFirebaseServices({ env }), env }).decideTruckOwnership({ requestId: body.requestId, status: body.status, adminUid: token.uid });
    if (action === 'revoke-invitation') return new (require('../src/trusted_service').TrustedService)({ ...getFirebaseServices({ env }), env }).revokeInvitation({ invitationId: body.invitationId, adminUid: token.uid });
    const service = new (require('../src/trusted_service').TrustedService)({ ...getFirebaseServices({ env }), env });
    if (action === 'list-pending-trucks') return service.listPendingTruckRequests();
    if (action === 'list-approved-trucks') return service.listApprovedTrucks();
    if (action === 'list-ownership-requests') return service.listOwnershipRequests();
    throw new TrustedApiError('invalid-argument', 'Unknown administrator action.');
  },
});
