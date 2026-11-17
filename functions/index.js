const { createEmailChangeApi } = require('./src/email_change_api');
const { getFirebaseServices } = require('./src/firebase_admin');

const { auth, db, FieldValue, Timestamp } = getFirebaseServices();

module.exports = createEmailChangeApi({
  auth,
  db,
  FieldValue,
  Timestamp,
  env: process.env,
});
