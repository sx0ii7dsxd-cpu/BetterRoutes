const assert = require('node:assert/strict');
const test = require('node:test');
const { TrustedService } = require('./trusted_service');
const { TrustedApiError, makeInvitationToken, requireAdmin } = require('./trusted_auth');
const { buildAuthorizedUserUids } = require('./shipment_authorization');
const { setAdminClaim } = require('./admin_claims');

class Snap {
  constructor(value, ref) { this.value = value; this.ref = ref; this.id = ref?.id; this.exists = value !== undefined; }
  data() { return this.value; }
}
class Ref {
  constructor(db, path) { this.db = db; this.path = path; this.id = path.split('/').pop(); }
  collection(name) { return new Collection(this.db, `${this.path}/${name}`); }
  async get() { return new Snap(this.db.store.get(this.path), this); }
  async create(value) { if (this.db.store.has(this.path)) throw new Error('exists'); this.db.store.set(this.path, { ...value }); }
}
class Collection {
  constructor(db, path) { this.db = db; this.path = path; }
  doc(id) { return new Ref(this.db, `${this.path}/${id || `generated-${++this.db.ids}`}`); }
  where(field, op, value) {
    const self = this;
    return { where: (f, o, v) => self.where2(field, value, f, v), get: async () => ({ docs: [...self.db.store.entries()].filter(([k, d]) => k.startsWith(`${self.path}/`) && d[field] === value).map(([k, d]) => new Snap(d, new Ref(self.db, k))) }) };
  }
  where2(a, av, b, bv) { return { get: async () => ({ docs: [...this.db.store.entries()].filter(([k, d]) => k.startsWith(`${this.path}/`) && d[a] === av && d[b] === bv).map(([k, d]) => new Snap(d, new Ref(this.db, k))) }) }; }
}
class Db {
  constructor() { this.store = new Map(); this.ids = 0; }
  collection(name) { return new Collection(this, name); }
  async runTransaction(fn) {
    const writes = [];
    const tx = {
      get: (ref) => ref.get(),
      create: (ref, value) => writes.push(['create', ref, value]),
      update: (ref, value) => writes.push(['update', ref, value]),
      delete: (ref) => writes.push(['delete', ref]),
    };
    const result = await fn(tx);
    for (const [kind, ref, value] of writes) {
      if (kind === 'create' && this.store.has(ref.path)) throw new Error('exists');
      if (kind === 'delete') {
        this.store.delete(ref.path);
      } else {
        this.store.set(ref.path, { ...(this.store.get(ref.path) || {}), ...value });
      }
    }
    return result;
  }
}
function service(db, now = 100000) {
  return new TrustedService({ db, FieldValue: { serverTimestamp: () => now }, env: { INVITATION_TOKEN_SECRET: 'test-secret' }, now: () => now });
}

test('admin denial is enforced by verified claims, not request fields', () => {
  assert.throws(() => requireAdmin({ uid: 'user' }, { BETTERROUTES_BOOTSTRAP_UID: 'bootstrap' }), TrustedApiError);
  assert.doesNotThrow(() => requireAdmin({ uid: 'admin', admin: true }, {}));
});

test('admin claim changes revoke refresh tokens', async () => {
  const calls = [];
  const auth = {
    async getUser() { return { customClaims: { existing: true } }; },
    async setCustomUserClaims(uid, claims) { calls.push(['set', uid, claims]); },
    async revokeRefreshTokens(uid) { calls.push(['revoke', uid]); },
  };
  const result = await setAdminClaim({ auth, targetUid: 'u1', enabled: false });
  assert.equal(result.tokenRefreshRequired, true);
  assert.deepEqual(calls, [
    ['set', 'u1', { existing: true }],
    ['revoke', 'u1'],
  ]);
});

test('revoking admin claims removes alternate role claims', async () => {
  const calls = [];
  const auth = {
    async getUser() { return { customClaims: { admin: true, role: 'admin', roles: ['admin'] } }; },
    async setCustomUserClaims(uid, claims) { calls.push(['set', uid, claims]); },
    async revokeRefreshTokens() {},
  };
  await setAdminClaim({ auth, targetUid: 'u1', enabled: false });
  assert.deepEqual(calls, [['set', 'u1', {}]]);
});

test('truck approval creates one truck and duplicate approval is idempotent', async () => {
  const db = new Db();
  db.store.set('truckRegistrationRequests/request-1', { status: 'pending', warehouseId: 'w1', requestedByUid: 'owner', registrationNumber: 'TR-1' });
  db.store.set('warehouses/w1', { warehouseId: 'w1', ownerUid: 'owner', code: 'WH-12345' });
  const result = await service(db).approveTruckRequest({ requestId: 'request-1', adminUid: 'admin' });
  assert.equal(result.status, 'approved');
  assert.equal(db.store.get('trucks/request-1').ownerUid, null);
  assert.equal(db.store.get('trucks/request-1').sourceRequestId, 'request-1');
  assert.equal(db.store.get('trucks/request-1').warehouseCode, 'WH-12345');
  assert.equal(db.store.get('trucks/request-1').warehouseOwnerUid, 'owner');
  assert.ok(db.store.get('trucks/request-1').approvedAt);
  await service(db).approveTruckRequest({ requestId: 'request-1', adminUid: 'admin' });
  assert.equal([...db.store.keys()].filter((key) => key === 'trucks/request-1').length, 1);
});

test('ownership request approval and revocation are admin-audited', async () => {
  const db = new Db();
  db.store.set('trucks/truck-1', { truckId: 'truck-1', warehouseId: 'w1', ownerUid: null, status: 'active' });
  db.store.set('warehouses/w1', { ownerUid: 'warehouse-owner' });
  const trusted = service(db);
  const request = await trusted.createTruckOwnershipRequest({
    requesterUid: 'warehouse-owner', truckId: 'truck-1', requestedOwnerUid: 'truck-owner',
  });
  assert.equal(db.store.get('truckOwnershipRequests/' + request.requestId).requestedOwnerUid, 'warehouse-owner');
  await trusted.decideTruckOwnership({ requestId: request.requestId, status: 'approved', adminUid: 'admin-1' });
  assert.equal(db.store.get('trucks/truck-1').ownerUid, 'warehouse-owner');
  assert.equal(db.store.get('trucks/truck-1').ownershipChangedByUid, 'admin-1');
  await trusted.decideTruckOwnership({ requestId: request.requestId, status: 'revoked', adminUid: 'admin-2' });
  assert.equal(db.store.get('trucks/truck-1').ownerUid, null);
  assert.equal(db.store.get('truckOwnershipRequests/' + request.requestId).decidedByUid, 'admin-2');
});

test('safe list operations return only intended records', async () => {
  const db = new Db();
  db.store.set('truckRegistrationRequests/pending', { status: 'pending', requestedByUid: 'u1' });
  db.store.set('truckRegistrationRequests/approved', { status: 'approved', requestedByUid: 'u1' });
  db.store.set('trucks/t1', { status: 'active', ownerUid: 'u1' });
  db.store.set('trucks/t2', { status: 'suspended', ownerUid: 'u1' });
  db.store.set('truckOwnershipRequests/o1', { status: 'pending', requestedByUid: 'u1' });
  db.store.set('invitations/i1', { targetUid: 'u1', tokenHash: 'secret-hash', status: 'pending' });
  const trusted = service(db);
  assert.equal((await trusted.listPendingTruckRequests()).length, 1);
  assert.equal((await trusted.listApprovedTrucks()).length, 1);
  assert.equal((await trusted.listUserApprovedTrucks('u1')).length, 1);
  assert.equal((await trusted.listUserRequests('u1')).ownershipRequests.length, 1);
  assert.equal((await trusted.listUserInvitations('u1'))[0].tokenHash, undefined);
});

test('invitation is target-bound, one-time, and expires', async () => {
  const db = new Db(); db.store.set('trucks/truck-1', { ownerUid: null, warehouseId: 'w1', status: 'active', driverUid: null }); db.store.set('warehouses/w1', { ownerUid: 'owner' }); const trusted = service(db);
  const invitation = await trusted.createInvitation({ inviterUid: 'owner', type: 'driver', targetUid: 'driver', truckId: 'truck-1', expiresInMs: 60000 });
  await assert.rejects(() => trusted.acceptInvitation({ token: invitation.token, uid: 'other' }), (e) => e.code === 'permission-denied');
  await trusted.acceptInvitation({ token: invitation.token, uid: 'driver' });
  await assert.rejects(() => trusted.acceptInvitation({ token: invitation.token, uid: 'driver' }), (e) => e.code === 'failed-precondition');
  db.store.set('shipments/shipment-1', { createdByUid: 'owner', authorizedUserUids: ['owner'] });
  const expired = service(db, 100000);
  const old = await expired.createInvitation({ inviterUid: 'owner', type: 'customer', targetUid: 'customer', shipmentId: 'shipment-1', expiresInMs: 60000 });
  const later = service(db, 200000);
  await assert.rejects(() => later.acceptInvitation({ token: old.token, uid: 'customer' }), (e) => e.code === 'failed-precondition');
});

test('additional verified relationship UIDs are retained and normalized', () => {
  assert.deepEqual(buildAuthorizedUserUids({
    verifiedCreatorUid: ' creator ',
    additionalVerifiedUids: ['customer-1', '', ' customer-2 ', 'customer-1', null],
  }), ['creator', 'customer-1', 'customer-2']);
});

test('driver acceptance supports reassignment and safe revocation', async () => {
  const db = new Db();
  db.store.set('trucks/t1', { ownerUid: null, warehouseId: 'w1', status: 'active', driverUid: null });
  db.store.set('warehouses/w1', { ownerUid: 'warehouse-owner' });
  const trusted = service(db);
  const first = await trusted.createInvitation({ inviterUid: 'warehouse-owner', type: 'driver', targetUid: 'driver-1', truckId: 't1' });
  await trusted.acceptInvitation({ token: first.token, uid: 'driver-1' });
  const second = await trusted.createInvitation({ inviterUid: 'warehouse-owner', type: 'driver', targetUid: 'driver-2', truckId: 't1' });
  await trusted.acceptInvitation({ token: second.token, uid: 'driver-2' });
  await trusted.revokeInvitation({ invitationId: first.invitationId, adminUid: 'admin' });
  assert.equal(db.store.get('trucks/t1').driverUid, 'driver-2');
  await trusted.revokeInvitation({ invitationId: second.invitationId, adminUid: 'admin' });
  assert.equal(db.store.get('trucks/t1').driverUid, null);
});

test('driver invitations cannot add a driver directly to shipment authorization', async () => {
  const db = new Db();
  db.store.set('shipments/s1', { createdByUid: 'creator', warehouseId: 'w1', truckId: 't1', authorizedUserUids: ['creator'] });
  db.store.set('trucks/t1', { ownerUid: null, driverUid: null, warehouseId: 'w1', status: 'active' });
  db.store.set('warehouses/w1', { ownerUid: 'warehouse-owner' });
  const trusted = service(db);
  const invitation = await trusted.createInvitation({
    inviterUid: 'warehouse-owner',
    type: 'driver',
    targetUid: 'driver-1',
    truckId: 't1',
    shipmentId: 's1',
  });
  await trusted.acceptInvitation({ token: invitation.token, uid: 'driver-1' });
  assert.deepEqual(db.store.get('shipments/s1').authorizedUserUids, ['creator', 'warehouse-owner', 'driver-1']);
});

test('warehouse deletion synchronizes shipments before deleting the warehouse', async () => {
  const db = new Db();
  db.store.set('warehouses/w1', {
    warehouseId: 'w1',
    ownerUid: 'warehouse-owner',
    code: 'WH-12345',
  });
  db.store.set('warehouseCodeReservations/WH-12345', {
    warehouseId: 'w1',
    ownerUid: 'warehouse-owner',
  });
  db.store.set('shipments/s1', {
    createdByUid: 'creator',
    warehouseId: 'w1',
    authorizedUserUids: ['creator', 'warehouse-owner'],
  });
  const result = await service(db).deleteWarehouse({
    warehouseId: 'w1',
    requesterUid: 'warehouse-owner',
  });
  assert.equal(result.status, 'deleted');
  assert.equal(result.synchronizedShipmentCount, 1);
  assert.equal(db.store.has('warehouses/w1'), false);
  assert.equal(db.store.has('warehouseCodeReservations/WH-12345'), false);
  assert.deepEqual(db.store.get('shipments/s1').authorizedUserUids, ['creator']);
});

test('accepted shipment participants are persisted and revoked safely', async () => {
  const db = new Db();
  db.store.set('shipments/s1', {
    createdByUid: 'creator',
    authorizedUserUids: ['creator'],
  });
  const trusted = service(db);
  const invitation = await trusted.createInvitation({
    inviterUid: 'creator',
    type: 'customer',
    targetUid: 'customer-1',
    shipmentId: 's1',
  });

  await trusted.acceptInvitation({
    token: invitation.token,
    uid: 'customer-1',
  });
  assert.equal(
    db.store.get('shipments/s1/participants/' + invitation.invitationId).status,
    'accepted',
  );

  await trusted.revokeInvitation({
    invitationId: invitation.invitationId,
    adminUid: 'admin',
  });
  assert.equal(
    db.store.get('shipments/s1/participants/' + invitation.invitationId).status,
    'revoked',
  );
});

test('invalid invitation tokens cannot be replayed or guessed', async () => {
  const db = new Db(); const trusted = service(db);
  const generated = makeInvitationToken('other-secret');
  await assert.rejects(() => trusted.acceptInvitation({ token: generated.token, uid: 'driver' }), (e) => e.code === 'not-found');
});
