const {
  cert,
  getApps,
  initializeApp,
} = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const {
  FieldValue,
  getFirestore,
  Timestamp,
} = require('firebase-admin/firestore');

const { createEmailChangeApi } = require('./src/email_change_api');

function createFirebaseApp() {
  const rawServiceAccount = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!rawServiceAccount) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is required.');
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(rawServiceAccount);
  } catch {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON must be valid JSON.');
  }

  const projectId = process.env.FIREBASE_PROJECT_ID;
  if (!projectId || serviceAccount.project_id !== projectId) {
    throw new Error(
      'FIREBASE_PROJECT_ID must match the service account project_id.',
    );
  }

  const appName = 'better-routes-email-api';
  const existingApp = getApps().find((app) => app.name === appName);
  return (
    existingApp ??
    initializeApp(
      {
        credential: cert(serviceAccount),
        projectId,
      },
      appName,
    )
  );
}

const app = createFirebaseApp();

module.exports = createEmailChangeApi({
  auth: getAuth(app),
  db: getFirestore(app),
  FieldValue,
  Timestamp,
  env: process.env,
});
