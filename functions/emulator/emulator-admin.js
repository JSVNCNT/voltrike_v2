'use strict';

const admin = require('firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || 'demo-voltrike';
if (projectId !== 'demo-voltrike' || !projectId.startsWith('demo-')) {
  throw new Error(
    `Refusing emulator utility against non-demo project: ${projectId}`,
  );
}

process.env.GCLOUD_PROJECT = projectId;
process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId,
  databaseURL: `https://${projectId}-default-rtdb.firebaseio.com`,
  storageBucket: `${projectId}.appspot.com`,
});
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.FIREBASE_DATABASE_EMULATOR_HOST =
  process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';
process.env.FIREBASE_STORAGE_EMULATOR_HOST =
  process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:9199';

if (admin.apps.length === 0) {
  admin.initializeApp({
    projectId,
    databaseURL: `https://${projectId}-default-rtdb.firebaseio.com`,
    storageBucket: `${projectId}.appspot.com`,
  });
}

module.exports = {
  admin,
  auth: admin.auth(),
  db: admin.firestore(),
  projectId,
  realtime: admin.database(),
};
