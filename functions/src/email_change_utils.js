const crypto = require('node:crypto');

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const OTP_PATTERN = /^\d{6}$/;

function normalizeEmail(value) {
  if (typeof value !== 'string') return null;
  const email = value.trim().toLowerCase();
  return email.length <= 254 && EMAIL_PATTERN.test(email) ? email : null;
}

function isValidOtp(value) {
  return typeof value === 'string' && OTP_PATTERN.test(value);
}

function createOtp() {
  return crypto.randomInt(100000, 1000000).toString();
}

function hashOtp(uid, flowId, code, secret) {
  return crypto
    .createHmac('sha256', secret)
    .update(`${uid}:${flowId}:${code}`)
    .digest('hex');
}

function hashesMatch(expected, actual) {
  if (typeof expected !== 'string' || typeof actual !== 'string') return false;
  if (!/^[\da-f]{64}$/i.test(expected) || !/^[\da-f]{64}$/i.test(actual)) {
    return false;
  }
  return crypto.timingSafeEqual(
    Buffer.from(expected, 'hex'),
    Buffer.from(actual, 'hex'),
  );
}

function timestampMillis(value) {
  return value && typeof value.toMillis === 'function'
    ? value.toMillis()
    : null;
}

module.exports = {
  createOtp,
  hashOtp,
  hashesMatch,
  isValidOtp,
  normalizeEmail,
  timestampMillis,
};
