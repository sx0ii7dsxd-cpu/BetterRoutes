const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createOtp,
  hashOtp,
  hashesMatch,
  isValidOtp,
  normalizeEmail,
  timestampMillis,
} = require('./email_change_utils');

test('normalizes valid email addresses and rejects malformed values', () => {
  assert.equal(normalizeEmail('  User@Example.com '), 'user@example.com');
  assert.equal(normalizeEmail('not an email'), null);
  assert.equal(normalizeEmail('user@example'), null);
  assert.equal(normalizeEmail(null), null);
});

test('accepts only six-digit OTP strings', () => {
  assert.equal(isValidOtp('012345'), true);
  assert.equal(isValidOtp('12345'), false);
  assert.equal(isValidOtp('12345x'), false);
  assert.equal(isValidOtp(123456), false);
});

test('generates six-digit OTPs and verifies only matching HMACs', () => {
  const code = createOtp();
  const codeHash = hashOtp('uid', 'flow', code, 'test-secret');

  assert.equal(isValidOtp(code), true);
  assert.equal(hashesMatch(codeHash, hashOtp('uid', 'flow', code, 'test-secret')), true);
  assert.equal(hashesMatch(codeHash, hashOtp('uid', 'flow', '999999', 'test-secret')), false);
  assert.equal(hashesMatch(codeHash, hashOtp('other-user', 'flow', code, 'test-secret')), false);
});

test('converts Firestore timestamps without accepting arbitrary values', () => {
  assert.equal(timestampMillis({ toMillis: () => 1234 }), 1234);
  assert.equal(timestampMillis(null), null);
  assert.equal(timestampMillis('1234'), null);
});
