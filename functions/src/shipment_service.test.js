const assert = require('node:assert/strict');
const test = require('node:test');

const {
  ShipmentService,
  ShipmentServiceError,
} = require('./shipment_service');
const { buildAuthorizedUserUids } = require('./shipment_authorization');

class FakeSnapshot {
  constructor(value) {
    this.value = value;
    this.exists = value !== undefined;
  }

  data() {
    return this.value && { ...this.value };
  }
}

class FakeDocument {
  constructor(store, collection, id) {
    this.store = store;
    this.collectionName = collection;
    this.id = id;
    this.key = `${collection}/${id}`;
  }

  collection(name) {
    return new FakeCollection(this.store, `${this.key}/${name}`);
  }

  async get() {
    return new FakeSnapshot(this.store.get(this.key));
  }
}

class FakeCollection {
  constructor(store, name) {
    this.store = store;
    this.name = name;
  }

  doc(id) {
    return new FakeDocument(this.store, this.name, id);
  }
}

class FakeFirestore {
  constructor() {
    this.store = new Map();
    this.transactionCount = 0;
  }

  collection(name) {
    return new FakeCollection(this.store, name);
  }

  async runTransaction(callback) {
    this.transactionCount += 1;
    const writes = [];
    const transaction = {
      get: (ref) => ref.get(),
      create: (ref, value) => writes.push({ ref, value }),
    };
    const result = await callback(transaction);
    for (const write of writes) {
      if (this.store.has(write.ref.key)) {
        throw new Error(`Already exists: ${write.ref.key}`);
      }
      this.store.set(write.ref.key, { ...write.value });
    }
    return result;
  }
}

function createService({ db = new FakeFirestore(), randomBytes } = {}) {
  const service = new ShipmentService({
    db,
    FieldValue: { serverTimestamp: () => 'SERVER_TIMESTAMP' },
    randomBytes,
  });
  return { db, service };
}

function addWarehouse(db, id = 'warehouse-1', ownerUid = 'creator-1') {
  db.store.set(`warehouses/${id}`, {
    warehouseId: id,
    ownerUid,
    code: 'WH-12345',
  });
}

test('rejects client-supplied identity and authorization fields', async () => {
  const { service } = createService();

  await assert.rejects(
    service.createShipment({
      creatorUid: 'creator-1',
      data: {
        warehouseId: 'warehouse-1',
        createdByUid: 'attacker',
      },
    }),
    (error) =>
      error instanceof ShipmentServiceError &&
      error.code === 'invalid-argument',
  );
});

test('rejects an unauthorised creator and missing warehouse', async () => {
  const { db, service } = createService();
  addWarehouse(db, 'warehouse-1', 'different-user');

  await assert.rejects(
    service.createShipment({
      creatorUid: 'creator-1',
      data: { warehouseId: 'warehouse-1' },
    }),
    (error) =>
      error instanceof ShipmentServiceError &&
      error.code === 'permission-denied',
  );

  await assert.rejects(
    service.createShipment({
      creatorUid: 'creator-1',
      data: { warehouseId: 'missing' },
    }),
    (error) =>
      error instanceof ShipmentServiceError && error.code === 'not-found',
  );
});

test('resolves warehouse ownership and creates shipment and event atomically', async () => {
  const { db, service } = createService({
    randomBytes: () => Buffer.from('abcdef01', 'hex'),
  });
  addWarehouse(db);

  const result = await service.createShipment({
    creatorUid: 'creator-1',
    data: {
      warehouseId: 'warehouse-1',
      origin: { name: 'Origin', latitude: 26.9, longitude: 75.7 },
    },
  });

  assert.deepEqual(result, {
    shipmentId: 'SHP-ABCDEF01',
    trackingCode: 'SHP-ABCDEF01',
    status: 'created',
  });
  assert.equal(db.store.get('shipments/SHP-ABCDEF01').warehouseCode, 'WH-12345');
  assert.deepEqual(
    db.store.get('shipments/SHP-ABCDEF01').authorizedUserUids,
    ['creator-1'],
  );
  assert.equal(
    db.store.get('shipments/SHP-ABCDEF01/events/created').status,
    'created',
  );
});

test('retries a tracking-code collision transactionally', async () => {
  const { db, service } = createService({
    randomBytes: (() => {
      const values = [
        Buffer.from('00000000', 'hex'),
        Buffer.from('11111111', 'hex'),
      ];
      return () => values.shift();
    })(),
  });
  addWarehouse(db);
  db.store.set('shipments/SHP-00000000', { shipmentId: 'existing' });

  const result = await service.createShipment({
    creatorUid: 'creator-1',
    data: { warehouseId: 'warehouse-1' },
  });

  assert.equal(result.trackingCode, 'SHP-11111111');
  assert.equal(db.transactionCount, 2);
});

test('deduplicates only verified authorization identities', () => {
  assert.deepEqual(
    buildAuthorizedUserUids({
      verifiedCreatorUid: 'user-1',
      verifiedWarehouseOwnerUid: 'user-1',
      verifiedCustomerUid: '',
      verifiedReceiverUid: null,
      verifiedTruckOwnerUid: 'user-2',
      verifiedDriverUid: 'user-2',
    }),
    ['user-1', 'user-2'],
  );
});
