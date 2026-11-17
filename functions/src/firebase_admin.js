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

function createFirebaseApp({
  env = process.env,
  appName = 'better-routes-email-api',
} = {}) {
  const rawServiceAccount = env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!rawServiceAccount) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is required.');
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(rawServiceAccount);
  } catch {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON must be valid JSON.');
  }

  const projectId = env.FIREBASE_PROJECT_ID;
  if (!projectId || serviceAccount.project_id !== projectId) {
    throw new Error(
      'FIREBASE_PROJECT_ID must match the service account project_id.',
    );
  }

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

function getFirebaseServices(options = {}) {
  const app = createFirebaseApp(options);
  return {
    app,
    auth: getAuth(app),
    db: getFirestore(app),
    FieldValue,
    Timestamp,
  };
}

module.exports = {
  createFirebaseApp,
  getFirebaseServices,
};
