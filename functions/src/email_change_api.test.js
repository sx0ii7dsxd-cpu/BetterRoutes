const assert = require('node:assert/strict');
const test = require('node:test');

const { createEmailChangeApi } = require('./email_change_api');

class FakeTimestamp {
  constructor(value) {
    this.value = value;
  }

  toMillis() {
    return this.value;
  }

  static fromMillis(value) {
    return new FakeTimestamp(value);
  }
}

class FakeSnapshot {
  constructor(ref, value) {
    this.ref = ref;
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
    this.collection = collection;
    this.id = id;
    this.key = `${collection}/${id}`;
  }

  async get() {
    return new FakeSnapshot(this, this.store.get(this.key));
  }

  async update(value) {
    const current = this.store.get(this.key);
    if (!current) throw new Error(`Missing document: ${this.key}`);
    this.store.set(this.key, { ...current, ...value });
  }

  async delete() {
    this.store.delete(this.key);
  }
}

class FakeFirestore {
  constructor() {
    this.store = new Map();
  }

  collection(name) {
    return {
      doc: (id) => new FakeDocument(this.store, name, id),
    };
  }

  async runTransaction(callback) {
    const writes = [];
    const transaction = {
      get: (ref) => ref.get(),
      set: (ref, value, options = {}) => writes.push({ kind: 'set', ref, value, options }),
      update: (ref, value) => writes.push({ kind: 'update', ref, value }),
    };
    const result = await callback(transaction);
    for (const write of writes) {
      const current = this.store.get(write.ref.key);
      if (write.kind === 'update' && !current) {
        throw new Error(`Missing document: ${write.ref.key}`);
      }
      this.store.set(
        write.ref.key,
        write.kind === 'update' ||
            (write.kind === 'set' && write.options.merge)
          ? { ...current, ...write.value }
          : { ...write.value },
      );
    }
    return result;
  }
}

function createHarness() {
  let now = 1_800_000_000_000;
  const db = new FakeFirestore();
  const user = { uid: 'user-1', email: 'old@example.com' };
  const sentCodes = [];
  const sentRecipients = [];
  const updates = [];
  const auth = {
    async verifyIdToken(token, checkRevoked) {
      assert.equal(checkRevoked, true);
      if (token !== 'valid-token') throw new Error('Invalid token');
      return { uid: user.uid };
    },
    async getUser(uid) {
      assert.equal(uid, user.uid);
      return { ...user };
    },
    async getUserByEmail(email) {
      if (email.toLowerCase() === user.email.toLowerCase()) return { ...user };
      const error = new Error('User not found');
      error.code = 'auth/user-not-found';
      throw error;
    },
    async updateUser(uid, values) {
      updates.push({ uid, ...values });
      Object.assign(user, values);
      return { ...user };
    },
  };
  const api = createEmailChangeApi({
    auth,
    db,
    FieldValue: { delete: () => '__delete__' },
    Timestamp: FakeTimestamp,
    env: {
      OTP_HMAC_SECRET: 'test-secret-with-sufficient-randomness',
      RESEND_API_KEY: 'test-resend-key',
      EMAIL_FROM: 'BetterRoutes <security@example.com>',
    },
    now: () => now,
    logger: { error() {} },
    sendEmail: async ({ code, to }) => {
      sentCodes.push(code);
      sentRecipients.push(to);
    },
  });

  return {
    api,
    db,
    sentCodes,
    sentRecipients,
    updates,
    setNow(value) {
      now = value;
    },
  };
}

async function request(api, action, data = {}, token = 'valid-token') {
  const response = {
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
  await api(
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        'x-forwarded-for': '203.0.113.8',
      },
      body: { action, ...data },
    },
    response,
  );
  return response;
}

test('requires a valid Firebase ID token on every API action', async () => {
  const { api, db } = createHarness();

  const response = await request(api, 'emailChangeStatus', {}, 'invalid-token');

  assert.equal(response.statusCode, 401);
  assert.equal(response.body.error.code, 'unauthenticated');
  assert.equal(db.store.size, 0);
});

test('preserves status, resend, attempt and single-OTP completion contracts', async () => {
  const { api, db, sentCodes, sentRecipients, updates, setNow } = createHarness();

  const idle = await request(api, 'emailChangeStatus');
  assert.equal(idle.statusCode, 200);
  assert.deepEqual(idle.body, { stage: 'idle', email: null });

  const started = await request(api, 'startEmailChange', {
    newEmail: 'new@example.com',
  });
  assert.equal(started.statusCode, 200);
  assert.equal(started.body.stage, 'verifyOld');
  assert.equal(started.body.newEmail, 'new@example.com');
  assert.equal(started.body.attemptsRemaining, 5);
  assert.equal(sentCodes.length, 1);
  assert.deepEqual(sentRecipients, ['old@example.com']);
  const storedFlow = db.store.get('emailChangeChallenges/user-1');
  assert.ok(storedFlow.otpHash);
  assert.equal(storedFlow.code, undefined);
  const wrong = await request(api, 'verifyOldEmailCode', { code: '000000' });
  assert.equal(wrong.statusCode, 403);
  assert.equal(wrong.body.error.details.attemptsRemaining, 4);

  const tooSoon = await request(api, 'resendEmailChangeCode');
  assert.equal(tooSoon.statusCode, 429);

  setNow(1_800_000_060_000);
  const resent = await request(api, 'resendEmailChangeCode');
  assert.equal(resent.statusCode, 200, JSON.stringify(resent.body));
  assert.equal(resent.body.resendCount, 1);
  assert.equal(sentCodes.length, 2);

  const verified = await request(api, 'verifyOldEmailCode', {
    code: sentCodes[1],
  });
  assert.equal(verified.statusCode, 200);
  assert.deepEqual(verified.body, {
    stage: 'complete',
    email: 'new@example.com',
  });
  assert.deepEqual(updates, [
    { uid: 'user-1', email: 'new@example.com', emailVerified: false },
  ]);
});

test('enforces the server-side per-user request limit', async () => {
  const { api } = createHarness();

  for (let index = 0; index < 60; index += 1) {
    const response = await request(api, 'emailChangeStatus');
    assert.equal(response.statusCode, 200);
  }
  const limited = await request(api, 'emailChangeStatus');

  assert.equal(limited.statusCode, 429);
  assert.equal(limited.body.error.code, 'resource-exhausted');
});

test('rejects an expired OTP without updating the Firebase user', async () => {
  const { api, sentCodes, updates, setNow } = createHarness();

  await request(api, 'startEmailChange', { newEmail: 'new@example.com' });
  setNow(1_800_000_600_000);
  const expired = await request(api, 'verifyOldEmailCode', {
    code: sentCodes[0],
  });

  assert.equal(expired.statusCode, 410);
  assert.equal(expired.body.error.code, 'deadline-exceeded');
  assert.deepEqual(updates, []);
});

test('locks verification after the maximum failed attempts', async () => {
  const { api, updates } = createHarness();

  await request(api, 'startEmailChange', { newEmail: 'new@example.com' });
  let response;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    response = await request(api, 'verifyOldEmailCode', { code: '000000' });
  }

  assert.equal(response.statusCode, 429);
  assert.equal(response.body.error.code, 'resource-exhausted');
  assert.equal(response.body.error.details.attemptsRemaining, 0);
  assert.deepEqual(updates, []);
});

test('reserves an interrupted email change for 24 hours', async () => {
  const { api, sentCodes, setNow } = createHarness();

  const started = await request(api, 'startEmailChange', {
    newEmail: 'first@example.com',
  });
  assert.equal(started.statusCode, 200);

  const blocked = await request(api, 'startEmailChange', {
    newEmail: 'second@example.com',
  });
  assert.equal(blocked.statusCode, 429);

  setNow(1_800_000_000_000 + 24 * 60 * 60 * 1000);
  const resumedAsNewRequest = await request(api, 'startEmailChange', {
    newEmail: 'second@example.com',
  });

  assert.equal(resumedAsNewRequest.statusCode, 200);
  assert.equal(resumedAsNewRequest.body.newEmail, 'second@example.com');
  assert.equal(sentCodes.length, 2);
});

test('caps OTP resends after the configured resend count', async () => {
  const { api, setNow } = createHarness();
  await request(api, 'startEmailChange', { newEmail: 'new@example.com' });

  for (let resendCount = 1; resendCount <= 3; resendCount += 1) {
    setNow(1_800_000_000_000 + resendCount * 60_000);
    const response = await request(api, 'resendEmailChangeCode');
    assert.equal(response.statusCode, 200);
    assert.equal(response.body.resendCount, resendCount);
  }

  setNow(1_800_000_240_000);
  const exhausted = await request(api, 'resendEmailChangeCode');

  assert.equal(exhausted.statusCode, 429);
  assert.match(exhausted.body.error.message, /all resend attempts/i);
});
