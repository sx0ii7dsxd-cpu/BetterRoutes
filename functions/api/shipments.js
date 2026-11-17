const { getFirebaseServices } = require('../src/firebase_admin');
const { createShipmentApi } = require('../src/shipment_api');

const { auth, db, FieldValue } = getFirebaseServices();

module.exports = createShipmentApi({
  auth,
  db,
  FieldValue,
  env: process.env,
});
