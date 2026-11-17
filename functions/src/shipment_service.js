const crypto = require('node:crypto');

const { buildAuthorizedUserUids } = require('./shipment_authorization');

class ShipmentServiceError extends Error {
  constructor(code, message, details = null) {
    super(message);
    this.name = 'ShipmentServiceError';
    this.code = code;
    this.details = details;
  }
}

class TrackingCodeCollision extends Error {
  constructor() {
    super('Tracking code collision.');
    this.name = 'TrackingCodeCollision';
  }
}

class ShipmentService {
  constructor({
    db,
    FieldValue,
    randomBytes = crypto.randomBytes,
    maxAttempts = 20,
  }) {
    this.db = db;
    this.FieldValue = FieldValue;
    this.randomBytes = randomBytes;
    this.maxAttempts = maxAttempts;
  }

  async createShipment({ creatorUid, data }) {
    if (!creatorUid) {
      throw new ShipmentServiceError(
        'unauthenticated',
        'Sign in before creating a shipment.',
      );
    }

    const request = this.validateRequest(data);
    const warehouse = await this.resolveWarehouse(request.warehouseId);
    if (warehouse.ownerUid !== creatorUid) {
      throw new ShipmentServiceError(
        'permission-denied',
        'You are not permitted to create a shipment for this warehouse.',
      );
    }

    const authorizedUserUids = buildAuthorizedUserUids({
      verifiedCreatorUid: creatorUid,
      verifiedWarehouseOwnerUid: warehouse.ownerUid,
    });

    for (let attempt = 0; attempt < this.maxAttempts; attempt += 1) {
      const trackingCode = this.generateTrackingCode();
      const shipmentRef = this.db.collection('shipments').doc(trackingCode);
      const eventRef = shipmentRef.collection('events').doc('created');
      const now = this.FieldValue.serverTimestamp();

      try {
        await this.db.runTransaction(async (transaction) => {
          const existing = await transaction.get(shipmentRef);
          if (existing.exists) throw new TrackingCodeCollision();

          transaction.create(shipmentRef, {
            shipmentId: trackingCode,
            trackingCode,
            status: 'created',
            ...(request.origin ? { origin: request.origin } : {}),
            ...(request.destination ? { destination: request.destination } : {}),
            warehouseId: warehouse.warehouseId,
            warehouseCode: warehouse.code,
            createdByUid: creatorUid,
            authorizedUserUids,
            createdAt: now,
            updatedAt: now,
          });
          transaction.create(eventRef, {
            eventId: 'created',
            status: 'created',
            title: 'Shipment created',
            description: 'Shipment creation was recorded.',
            updatedBy: creatorUid,
            timestamp: now,
          });
        });

        return {
          shipmentId: trackingCode,
          trackingCode,
          status: 'created',
        };
      } catch (error) {
        if (error instanceof TrackingCodeCollision) continue;
        throw error;
      }
    }

    throw new ShipmentServiceError(
      'aborted',
      'Could not generate a unique tracking code. Please try again.',
    );
  }

  validateRequest(data) {
    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      throw new ShipmentServiceError(
        'invalid-argument',
        'Request body must be an object.',
      );
    }

    const allowedFields = new Set(['warehouseId', 'origin', 'destination']);
    const unsupportedField = Object.keys(data).find(
      (field) => !allowedFields.has(field),
    );
    if (unsupportedField) {
      throw new ShipmentServiceError(
        'invalid-argument',
        `Field "${unsupportedField}" cannot be supplied by the client.`,
      );
    }

    if (
      typeof data.warehouseId !== 'string' ||
      data.warehouseId.trim().length === 0
    ) {
      throw new ShipmentServiceError(
        'invalid-argument',
        'warehouseId is required.',
      );
    }

    return {
      warehouseId: data.warehouseId.trim(),
      origin: normalizePlace(data.origin, 'origin'),
      destination: normalizePlace(data.destination, 'destination'),
    };
  }

  async resolveWarehouse(warehouseId) {
    const snapshot = await this.db
      .collection('warehouses')
      .doc(warehouseId)
      .get();
    if (!snapshot.exists) {
      throw new ShipmentServiceError('not-found', 'Warehouse was not found.');
    }

    const data = snapshot.data();
    if (
      typeof data?.warehouseId !== 'string' ||
      typeof data?.ownerUid !== 'string' ||
      typeof data?.code !== 'string'
    ) {
      throw new ShipmentServiceError(
        'failed-precondition',
        'Warehouse data is incomplete.',
      );
    }
    if (data.deletionPending === true) {
      throw new ShipmentServiceError(
        'failed-precondition',
        'The warehouse is being deleted and cannot receive new shipments.',
      );
    }
    return {
      warehouseId: data.warehouseId,
      ownerUid: data.ownerUid,
      code: data.code,
    };
  }

  generateTrackingCode() {
    return `SHP-${this.randomBytes(4).toString('hex').toUpperCase()}`;
  }
}

function normalizePlace(value, fieldName) {
  if (value == null) return null;
  if (typeof value !== 'object' || Array.isArray(value)) {
    throw new ShipmentServiceError(
      'invalid-argument',
      `${fieldName} must be an object.`,
    );
  }

  const allowedFields = new Set([
    'name',
    'address',
    'latitude',
    'longitude',
  ]);
  const unsupportedField = Object.keys(value).find(
    (field) => !allowedFields.has(field),
  );
  if (unsupportedField) {
    throw new ShipmentServiceError(
      'invalid-argument',
      `${fieldName}.${unsupportedField} is not supported.`,
    );
  }

  const normalized = {};
  for (const field of ['name', 'address']) {
    if (value[field] != null) {
      if (typeof value[field] !== 'string' || value[field].trim().length === 0) {
        throw new ShipmentServiceError(
          'invalid-argument',
          `${fieldName}.${field} must be a non-empty string.`,
        );
      }
      normalized[field] = value[field].trim();
    }
  }

  for (const field of ['latitude', 'longitude']) {
    if (value[field] != null) {
      if (typeof value[field] !== 'number' || !Number.isFinite(value[field])) {
        throw new ShipmentServiceError(
          'invalid-argument',
          `${fieldName}.${field} must be a finite number.`,
        );
      }
      normalized[field] = value[field];
    }
  }

  if (
    normalized.latitude != null &&
    (normalized.latitude < -90 || normalized.latitude > 90)
  ) {
    throw new ShipmentServiceError(
      'invalid-argument',
      `${fieldName}.latitude is out of range.`,
    );
  }
  if (
    normalized.longitude != null &&
    (normalized.longitude < -180 || normalized.longitude > 180)
  ) {
    throw new ShipmentServiceError(
      'invalid-argument',
      `${fieldName}.longitude is out of range.`,
    );
  }
  if ((normalized.latitude == null) !== (normalized.longitude == null)) {
    throw new ShipmentServiceError(
      'invalid-argument',
      `${fieldName} must provide both coordinates together.`,
    );
  }

  return normalized;
}

module.exports = {
  ShipmentService,
  ShipmentServiceError,
  TrackingCodeCollision,
  normalizePlace,
};
