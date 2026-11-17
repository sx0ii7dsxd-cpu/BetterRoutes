const assert = require('node:assert/strict');
const test = require('node:test');

const { createShipmentApi } = require('./shipment_api');

function responseHarness() {
  return {
    headers: {},
    statusCode: null,
    body: null,
    setHeader(name, value) {
      this.headers[name] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(value) {
      this.body = value;
      return this;
    },
    end() {
      return this;
    },
  };
}

function createApi({ token = 'valid-token', serviceError = null } = {}) {
  const auth = {
    async verifyIdToken(value, checkRevoked) {
      assert.equal(checkRevoked, true);
      if (value !== token) throw new Error('Invalid token');
      return { uid: 'creator-1' };
    },
  };
  const calls = [];
  const api = createShipmentApi({
    auth,
    db: {},
    FieldValue: {},
    shipmentServiceFactory: () => ({
      async createShipment(request) {
        calls.push(request);
        if (serviceError) throw serviceError;
        return {
          shipmentId: 'SHP-ABCDEF01',
          trackingCode: 'SHP-ABCDEF01',
          status: 'created',
        };
      },
    }),
  });
  return { api, calls };
}

async function request(api, options = {}) {
  const response = responseHarness();
  await api(
    {
      method: options.method ?? 'POST',
      headers: {
        authorization:
          'authorization' in options
            ? options.authorization
            : 'Bearer valid-token',
      },
      body: options.body ?? { warehouseId: 'warehouse-1' },
    },
    response,
  );
  return response;
}

test('rejects missing and invalid authentication', async () => {
  const { api } = createApi();

  const missing = await request(api, { authorization: undefined });
  assert.equal(missing.statusCode, 401);
  assert.equal(missing.body.error.code, 'unauthenticated');

  const invalid = await request(api, { authorization: 'Bearer invalid-token' });
  assert.equal(invalid.statusCode, 401);
  assert.equal(invalid.body.error.code, 'unauthenticated');
});

test('rejects unsupported methods and malformed request bodies', async () => {
  const { api } = createApi();

  const method = await request(api, { method: 'GET' });
  assert.equal(method.statusCode, 400);

  const malformed = await request(api, { body: '{invalid-json' });
  assert.equal(malformed.statusCode, 400);
  assert.equal(malformed.body.error.code, 'invalid-argument');
});

test('authenticates and forwards only the verified creator UID', async () => {
  const { api, calls } = createApi();
  const response = await request(api, {
    body: {
      warehouseId: 'warehouse-1',
      origin: { name: 'Origin' },
    },
  });

  assert.equal(response.statusCode, 201);
  assert.equal(calls[0].creatorUid, 'creator-1');
  assert.deepEqual(calls[0].data, {
    warehouseId: 'warehouse-1',
    origin: { name: 'Origin' },
  });
});
