const { TrustedApiError, hashInvitationToken, makeInvitationToken } = require('./trusted_auth');
const { buildAuthorizedUserUids } = require('./shipment_authorization');

const ACTIVE = new Set(['pending', 'approved', 'accepted']);

function requireString(value, name) {
  if (typeof value !== 'string' || !value.trim()) throw new TrustedApiError('invalid-argument', `${name} is required.`);
  return value.trim();
}

class TrustedService {
  constructor({ db, FieldValue, auth, env = process.env, now = () => Date.now(), tokenSecret }) {
    this.db = db; this.FieldValue = FieldValue; this.auth = auth; this.env = env;
    this.now = now; this.tokenSecret = tokenSecret || env.INVITATION_TOKEN_SECRET || env.OTP_HMAC_SECRET;
    if (!this.tokenSecret) throw new Error('INVITATION_TOKEN_SECRET or OTP_HMAC_SECRET is required.');
  }

  stamp() { return this.FieldValue?.serverTimestamp ? this.FieldValue.serverTimestamp() : new Date(this.now()); }
  id(collection) { return this.db.collection(collection).doc().id; }

  async approveTruckRequest({ requestId, adminUid }) {
    const requestRef = this.db.collection('truckRegistrationRequests').doc(requireString(requestId, 'requestId'));
    const truckId = requireString(requestId, 'requestId');
    const truckRef = this.db.collection('trucks').doc(truckId);
    await this.db.runTransaction(async (tx) => {
      const request = await tx.get(requestRef);
      if (!request.exists) throw new TrustedApiError('not-found', 'Truck request was not found.');
      const data = request.data() || {};
      if (data.status !== 'approved' && data.status !== 'pending') throw new TrustedApiError('failed-precondition', 'Only pending requests can be approved.');
      const warehouse = await tx.get(this.db.collection('warehouses').doc(requireString(data.warehouseId, 'warehouseId')));
      if (!warehouse.exists) throw new TrustedApiError('failed-precondition', 'The request warehouse no longer exists.');
      const warehouseData = warehouse.data() || {};
      const truck = {
        truckId, registrationNumber: data.registrationNumber, truckType: data.truckType,
        capacity: data.capacity, capacityUnit: data.capacityUnit, details: data.details || null,
        warehouseId: data.warehouseId, warehouseCode: warehouseData.code || data.warehouseCode || null,
        warehouseOwnerUid: warehouseData.ownerUid || null, sourceRequestId: requestId,
        ownerUid: null, driverUid: null, status: 'active',
        createdAt: this.stamp(), updatedAt: this.stamp(), approvedAt: this.stamp(), approvedByUid: adminUid,
      };
      const existing = await tx.get(truckRef);
      if (!existing.exists) tx.create(truckRef, truck);
      if (data.status !== 'approved') tx.update(requestRef, { status: 'approved', truckId, approvedByUid: adminUid, updatedAt: this.stamp() });
    });
    return { requestId, truckId, status: 'approved' };
  }

  async rejectTruckRequest({ requestId, adminUid, reason }) {
    const ref = this.db.collection('truckRegistrationRequests').doc(requireString(requestId, 'requestId'));
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new TrustedApiError('not-found', 'Truck request was not found.');
      const data = snap.data() || {};
      if (data.status === 'rejected') return;
      if (data.status !== 'pending') throw new TrustedApiError('failed-precondition', 'Only pending requests can be rejected.');
      tx.update(ref, { status: 'rejected', rejectionReason: reason ? String(reason).slice(0, 500) : null, rejectedByUid: adminUid, updatedAt: this.stamp() });
    });
    return { requestId, status: 'rejected' };
  }

  async setTruckStatus({ truckId, status, adminUid }) {
    if (!['active', 'suspended', 'revoked'].includes(status)) throw new TrustedApiError('invalid-argument', 'Invalid truck status.');
    const ref = this.db.collection('trucks').doc(requireString(truckId, 'truckId'));
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new TrustedApiError('not-found', 'Truck was not found.');
      tx.update(ref, { status, updatedAt: this.stamp(), statusChangedByUid: adminUid });
    });
    await this.synchronizeShipmentsForTruck(truckId);
    return { truckId, status };
  }

  async createAssociation({ requesterUid, warehouseId, targetUid }) {
    warehouseId = requireString(warehouseId, 'warehouseId');
    if (targetUid != null && requireString(targetUid, 'targetUid') !== requesterUid) {
      throw new TrustedApiError('invalid-argument', 'Association requests must target the authenticated requester.');
    }
    const warehouse = await this.db.collection('warehouses').doc(warehouseId).get();
    if (!warehouse.exists || warehouse.data()?.ownerUid !== requesterUid) throw new TrustedApiError('permission-denied', 'Only the warehouse owner may request ownership.');
    const id = this.id('ownershipAssociationRequests');
    await this.db.collection('ownershipAssociationRequests').doc(id).create({
      requestId: id, warehouseId, requesterUid, targetUid: requesterUid,
      status: 'pending', createdAt: this.stamp(), updatedAt: this.stamp(),
    });
    return { requestId: id, status: 'pending' };
  }

  async createTruckOwnershipRequest({ requesterUid, truckId, requestedOwnerUid }) {
    truckId = requireString(truckId, 'truckId');
    // Ownership cannot be transferred to an arbitrary client-supplied UID.
    // A separate authenticated target-acceptance flow can be added later.
    requestedOwnerUid = requesterUid;
    const truck = await this.db.collection('trucks').doc(truckId).get();
    if (!truck.exists) throw new TrustedApiError('not-found', 'Truck was not found.');
    const warehouse = await this.db.collection('warehouses').doc(requireString(truck.data()?.warehouseId, 'warehouseId')).get();
    if (!warehouse.exists || (warehouse.data()?.ownerUid !== requesterUid && truck.data()?.ownerUid !== requesterUid)) {
      throw new TrustedApiError('permission-denied', 'Only an authorized warehouse or truck owner may request ownership.');
    }
    const id = this.id('truckOwnershipRequests');
    await this.db.collection('truckOwnershipRequests').doc(id).create({
      requestId: id, truckId, requestedByUid: requesterUid, requestedOwnerUid,
      status: 'pending', createdAt: this.stamp(), updatedAt: this.stamp(),
    });
    return { requestId: id, status: 'pending' };
  }

  async decideTruckOwnership({ requestId, status, adminUid }) {
    if (!['approved', 'revoked'].includes(status)) throw new TrustedApiError('invalid-argument', 'Invalid ownership status.');
    const requestRef = this.db.collection('truckOwnershipRequests').doc(requireString(requestId, 'requestId'));
    let affectedTruckId;
    await this.db.runTransaction(async (tx) => {
      const request = await tx.get(requestRef);
      if (!request.exists) throw new TrustedApiError('not-found', 'Truck ownership request was not found.');
      const data = request.data() || {};
      const truckRef = this.db.collection('trucks').doc(requireString(data.truckId, 'truckId'));
      affectedTruckId = data.truckId;
      const truck = await tx.get(truckRef);
      if (!truck.exists) throw new TrustedApiError('not-found', 'Truck was not found.');
      const ownerUid = status === 'approved' ? requireString(data.requestedOwnerUid, 'requestedOwnerUid') : null;
      tx.update(truckRef, {
        ownerUid, ownershipStatus: status, ownershipChangedByUid: adminUid,
        ownershipChangedAt: this.stamp(), updatedAt: this.stamp(),
      });
      tx.update(requestRef, {
        status, decidedByUid: adminUid, decidedAt: this.stamp(), updatedAt: this.stamp(),
      });
    });
    await this.synchronizeShipmentsForTruck(affectedTruckId);
    return { requestId, status };
  }

  async decideAssociation({ requestId, status, adminUid }) {
    if (!['approved', 'revoked'].includes(status)) throw new TrustedApiError('invalid-argument', 'Invalid association status.');
    const ref = this.db.collection('ownershipAssociationRequests').doc(requireString(requestId, 'requestId'));
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref); if (!snap.exists) throw new TrustedApiError('not-found', 'Association request was not found.');
      const data = snap.data() || {};
      tx.update(ref, { status, decidedByUid: adminUid, updatedAt: this.stamp() });
      const associationRef = this.db.collection('warehouseAssociations').doc(requireString(requestId, 'requestId'));
      const association = await tx.get(associationRef);
      if (status === 'approved' && !association.exists) tx.create(associationRef, { associationId: requestId, warehouseId: data.warehouseId, ownerUid: data.targetUid, status: 'active', createdAt: this.stamp(), updatedAt: this.stamp() });
      if (status === 'revoked' && association.exists) tx.update(associationRef, { status: 'revoked', updatedAt: this.stamp() });
    });
    await this.synchronizeShipmentsForWarehouse(
      (await ref.get()).data()?.warehouseId,
    );
    return { requestId, status };
  }

  async deleteWarehouse({ warehouseId, requesterUid }) {
    warehouseId = requireString(warehouseId, 'warehouseId');
    const warehouseRef = this.db.collection('warehouses').doc(warehouseId);
    const initial = await warehouseRef.get();
    if (!initial.exists) throw new TrustedApiError('not-found', 'Warehouse was not found.');
    if (initial.data()?.ownerUid !== requesterUid) {
      throw new TrustedApiError('permission-denied', 'Only the warehouse owner may delete this warehouse.');
    }

    await this.db.runTransaction(async (tx) => {
      const warehouse = await tx.get(warehouseRef);
      if (!warehouse.exists || warehouse.data()?.ownerUid !== requesterUid) {
        throw new TrustedApiError('permission-denied', 'Only the warehouse owner may delete this warehouse.');
      }
      tx.update(warehouseRef, { deletionPending: true, updatedAt: this.stamp() });
    });

    const shipments = await this.db.collection('shipments')
      .where('warehouseId', '==', warehouseId)
      .get();
    const shipmentIds = shipments.docs
      .map((doc) => doc.id || doc.data()?.shipmentId)
      .filter(Boolean);
    const results = [];
    for (let offset = 0; offset < shipmentIds.length; offset += 100) {
      const batch = shipmentIds.slice(offset, offset + 100);
      for (const shipmentId of batch) {
        results.push(await this.synchronizeShipmentAuthorizationWithRetry(
          shipmentId,
          3,
          warehouseId,
        ));
      }
    }

    await this.db.runTransaction(async (tx) => {
      const warehouse = await tx.get(warehouseRef);
      if (
        !warehouse.exists ||
        warehouse.data()?.ownerUid !== requesterUid ||
        warehouse.data()?.deletionPending !== true
      ) {
        throw new TrustedApiError('failed-precondition', 'Warehouse deletion could not be completed safely.');
      }
      tx.delete(warehouseRef);
      const code = warehouse.data()?.code;
      if (typeof code === 'string' && code) {
        tx.delete(this.db.collection('warehouseCodeReservations').doc(code));
      }
    });

    return {
      warehouseId,
      status: 'deleted',
      synchronizedShipmentCount: results.length,
    };
  }

  async createInvitation({ inviterUid, type, targetUid, shipmentId, truckId, expiresInMs = 24 * 60 * 60 * 1000, inviterIsAdmin = false }) {
    if (!['driver', 'customer', 'receiver'].includes(type)) throw new TrustedApiError('invalid-argument', 'Invalid invitation type.');
    targetUid = requireString(targetUid, 'targetUid');
    if (type === 'driver') {
      const truck = await this.db.collection('trucks').doc(requireString(truckId, 'truckId')).get();
      if (!truck.exists || truck.data()?.status !== 'active') throw new TrustedApiError('permission-denied', 'Only an active truck may receive a driver assignment.');
      const warehouse = await this.db.collection('warehouses').doc(requireString(truck.data()?.warehouseId, 'warehouseId')).get();
      const warehouseOwner = warehouse.exists ? warehouse.data()?.ownerUid : null;
      if (!inviterIsAdmin && truck.data()?.ownerUid !== inviterUid && warehouseOwner !== inviterUid) throw new TrustedApiError('permission-denied', 'Only the truck owner or warehouse owner may assign a driver.');
    }
    if ((type === 'customer' || type === 'receiver')) {
      const shipment = await this.db.collection('shipments').doc(requireString(shipmentId, 'shipmentId')).get();
      if (!shipment.exists) throw new TrustedApiError('not-found', 'Shipment was not found.');
      if (shipment.data()?.createdByUid !== inviterUid && !(shipment.data()?.authorizedUserUids || []).includes(inviterUid)) throw new TrustedApiError('permission-denied', 'You are not permitted to invite a shipment participant.');
    }
    const token = makeInvitationToken(this.tokenSecret); const id = this.id('invitations');
    const expiresAt = new Date(this.now() + Math.min(Math.max(Number(expiresInMs) || 0, 60 * 1000), 7 * 24 * 60 * 60 * 1000));
    const data = { invitationId: id, type, inviterUid, targetUid: targetUid ? requireString(targetUid, 'targetUid') : null, shipmentId: shipmentId ? requireString(shipmentId, 'shipmentId') : null, truckId: truckId ? requireString(truckId, 'truckId') : null, tokenHash: token.tokenHash, status: 'pending', expiresAt, createdAt: this.stamp(), updatedAt: this.stamp() };
    await this.db.collection('invitations').doc(id).create(data);
    return { invitationId: id, token: token.token, type, expiresAt: expiresAt.toISOString() };
  }

  async acceptInvitation({ token, uid }) {
    const tokenHash = hashInvitationToken(token, this.tokenSecret);
    if (!tokenHash) throw new TrustedApiError('invalid-argument', 'Invalid invitation token.');
    const query = this.db.collection('invitations').where('tokenHash', '==', tokenHash);
    const result = await query.get();
    if (!result.docs?.length) throw new TrustedApiError('not-found', 'Invitation was not found.');
    const ref = result.docs[0].ref;
    let acceptedShipmentId = null;
    let acceptedTruckId = null;
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref); if (!snap.exists) throw new TrustedApiError('not-found', 'Invitation was not found.');
      const data = snap.data() || {};
      if (data.status !== 'pending') throw new TrustedApiError('failed-precondition', 'Invitation has already been used.');
      const expiry = data.expiresAt?.toMillis ? data.expiresAt.toMillis() : new Date(data.expiresAt).getTime();
      if (!Number.isFinite(expiry) || expiry <= this.now()) throw new TrustedApiError('failed-precondition', 'Invitation has expired.');
      if (data.targetUid && data.targetUid !== uid) throw new TrustedApiError('permission-denied', 'Invitation is not addressed to this account.');
      tx.update(ref, { status: 'accepted', acceptedByUid: uid, acceptedAt: this.stamp(), updatedAt: this.stamp() });
      if (data.type === 'driver' && data.truckId) {
        acceptedTruckId = data.truckId;
        const truckRef = this.db.collection('trucks').doc(data.truckId);
        const truck = await tx.get(truckRef);
        if (!truck.exists || truck.data()?.status !== 'active') throw new TrustedApiError('failed-precondition', 'Truck is no longer available for assignment.');
        tx.update(truckRef, { driverUid: uid, updatedAt: this.stamp() });
      }
      if (data.shipmentId) {
        const shipmentRef = this.db.collection('shipments').doc(data.shipmentId);
        tx.update(shipmentRef, { updatedAt: this.stamp() });
        if (data.type === 'customer' || data.type === 'receiver') {
          tx.create(
            shipmentRef.collection('participants').doc(data.invitationId),
            {
              participantId: data.invitationId,
              invitationId: data.invitationId,
              uid,
              role: data.type,
              status: 'accepted',
              createdAt: this.stamp(),
              updatedAt: this.stamp(),
            },
          );
        }
      }
      acceptedShipmentId = data.shipmentId;
    });
    if (acceptedShipmentId) await this.synchronizeShipmentAuthorization(acceptedShipmentId);
    if (acceptedTruckId) await this.synchronizeShipmentsForTruck(acceptedTruckId);
    return { status: 'accepted' };
  }

  async revokeInvitation({ invitationId, adminUid }) {
    const ref = this.db.collection('invitations').doc(requireString(invitationId, 'invitationId'));
    let affectedTruckId = null;
    let affectedShipmentId = null;
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref); if (!snap.exists) throw new TrustedApiError('not-found', 'Invitation was not found.');
      const data = snap.data() || {};
      affectedTruckId = data.truckId || null;
      affectedShipmentId = data.shipmentId || null;
      tx.update(ref, { status: 'revoked', revokedByUid: adminUid, updatedAt: this.stamp() });
      if (data.type === 'driver' && data.truckId) {
        const truckRef = this.db.collection('trucks').doc(data.truckId);
        const truck = await tx.get(truckRef);
        if (truck.exists && truck.data()?.driverUid === data.acceptedByUid) {
          tx.update(truckRef, { driverUid: null, updatedAt: this.stamp() });
        }
      }
      if (
        affectedShipmentId &&
        (data.type === 'customer' || data.type === 'receiver')
      ) {
        const participantRef = this.db
          .collection('shipments')
          .doc(affectedShipmentId)
          .collection('participants')
          .doc(invitationId);
        const participant = await tx.get(participantRef);
        if (participant.exists) {
          tx.update(participantRef, {
            status: 'revoked',
            revokedByUid: adminUid,
            updatedAt: this.stamp(),
          });
        }
      }
    });
    if (affectedTruckId) await this.synchronizeShipmentsForTruck(affectedTruckId);
    if (affectedShipmentId) await this.synchronizeShipmentAuthorization(affectedShipmentId);
    return { invitationId, status: 'revoked' };
  }

  async synchronizeShipmentsForTruck(truckId, limit = 100) {
    const snapshot = await this.db.collection('shipments').where('truckId', '==', requireString(truckId, 'truckId')).get();
    const ids = snapshot.docs.map((doc) => doc.id || doc.data()?.shipmentId).filter(Boolean);
    const results = [];
    for (let offset = 0; offset < ids.length; offset += Math.min(limit, 100)) {
      results.push(...await this.synchronizeShipmentAuthorizationBatch(ids.slice(offset, offset + Math.min(limit, 100)), limit));
    }
    return results;
  }

  async synchronizeShipmentsForWarehouse(warehouseId, limit = 100) {
    const snapshot = await this.db.collection('shipments')
      .where('warehouseId', '==', requireString(warehouseId, 'warehouseId'))
      .get();
    const ids = snapshot.docs.map((doc) => doc.id || doc.data()?.shipmentId).filter(Boolean);
    const results = [];
    for (let offset = 0; offset < ids.length; offset += Math.min(limit, 100)) {
      results.push(...await this.synchronizeShipmentAuthorizationBatch(ids.slice(offset, offset + Math.min(limit, 100)), limit));
    }
    return results;
  }

  async listPendingTruckRequests() {
    return this.listDocuments('truckRegistrationRequests', 'status', 'pending');
  }

  async listApprovedTrucks() {
    return this.listDocuments('trucks', 'status', 'active');
  }

  async listOwnershipRequests() {
    return this.listDocuments('truckOwnershipRequests', 'status', 'pending');
  }

  async listUserApprovedTrucks(uid) {
    const [owned, driven, warehouseOwned] = await Promise.all([
      this.listDocuments('trucks', 'ownerUid', uid),
      this.listDocuments('trucks', 'driverUid', uid),
      this.listDocuments('trucks', 'warehouseOwnerUid', uid),
    ]);
    return this.mergeDocuments([...owned, ...driven, ...warehouseOwned])
      .filter((truck) => truck.status === 'active');
  }

  async listUserRequests(uid) {
    const [truck, ownership] = await Promise.all([
      this.listDocuments('truckRegistrationRequests', 'requestedByUid', uid),
      this.listDocuments('truckOwnershipRequests', 'requestedByUid', uid),
    ]);
    return { truckRequests: truck, ownershipRequests: ownership };
  }

  async listUserInvitations(uid) {
    const [targeted, sent] = await Promise.all([
      this.listDocuments('invitations', 'targetUid', uid),
      this.listDocuments('invitations', 'inviterUid', uid),
    ]);
    return this.mergeDocuments([...targeted, ...sent]).map((invitation) => {
      const { tokenHash, ...safe } = invitation;
      return safe;
    });
  }

  async listAllInvitations() {
    return this.listDocuments('invitations').map(({ tokenHash, ...safe }) => safe);
  }

  async listDocuments(collection, field, value) {
    const snapshot = field === undefined
      ? await this.db.collection(collection).get()
      : await this.db.collection(collection).where(field, '==', value).get();
    return (snapshot.docs || []).map((doc) => ({ id: doc.id, ...(doc.data() || {}) }));
  }

  mergeDocuments(documents) {
    return [...new Map(documents.map((doc) => [doc.id, doc])).values()];
  }

  async synchronizeShipmentAuthorization(shipmentId, excludedWarehouseId = null) {
    const ref = this.db.collection('shipments').doc(requireString(shipmentId, 'shipmentId'));
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref); if (!snap.exists) throw new TrustedApiError('not-found', 'Shipment was not found.');
      const shipment = snap.data() || {}; const ids = [shipment.createdByUid];
      if (shipment.warehouseId && shipment.warehouseId !== excludedWarehouseId) {
        const warehouse = await tx.get(this.db.collection('warehouses').doc(shipment.warehouseId));
        if (warehouse.exists) ids.push(warehouse.data()?.ownerUid);
        const associations = await tx.get(this.db.collection('warehouseAssociations').where('warehouseId', '==', shipment.warehouseId).where('status', '==', 'active'));
        associations.docs.forEach((d) => ids.push(d.data()?.ownerUid));
      }
      if (shipment.truckId) {
        const truck = await tx.get(this.db.collection('trucks').doc(shipment.truckId));
        if (truck.exists && truck.data()?.status === 'active') ids.push(truck.data().ownerUid, truck.data().driverUid);
      }
      const invitations = await tx.get(this.db.collection('invitations').where('shipmentId', '==', shipmentId).where('status', '==', 'accepted'));
      invitations.docs
        .filter((d) => ['customer', 'receiver'].includes(d.data()?.type))
        .forEach((d) => ids.push(d.data()?.acceptedByUid));
      const authorizedUserUids = buildAuthorizedUserUids({ verifiedCreatorUid: ids[0], verifiedWarehouseOwnerUid: ids[1], verifiedCustomerUid: ids[2], verifiedReceiverUid: ids[3], verifiedTruckOwnerUid: ids[4], verifiedDriverUid: ids[5], additionalVerifiedUids: ids.slice(6) });
      tx.update(ref, { authorizedUserUids, updatedAt: this.stamp() });
      return { shipmentId, authorizedUserUids };
    });
  }

  async synchronizeShipmentAuthorizationWithRetry(
    shipmentId,
    attempts = 3,
    excludedWarehouseId = null,
  ) {
    let lastError;
    for (let attempt = 0; attempt < attempts; attempt += 1) {
      try {
        return await this.synchronizeShipmentAuthorization(
          shipmentId,
          excludedWarehouseId,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError;
  }

  async synchronizeShipmentAuthorizationBatch(shipmentIds, limit = 100) {
    const ids = [...new Set((shipmentIds || []).filter((id) => typeof id === 'string'))].slice(0, Math.min(limit, 100));
    const results = [];
    for (const id of ids) {
      results.push(await this.synchronizeShipmentAuthorizationWithRetry(id));
    }
    return results;
  }
}

module.exports = { TrustedService, ACTIVE };
