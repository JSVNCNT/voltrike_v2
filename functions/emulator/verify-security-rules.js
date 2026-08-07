'use strict';

const assert = require('node:assert/strict');
const { admin, auth, db, projectId, realtime } = require('./emulator-admin');

const password = 'RulesOnly123!';
const authBase = 'http://127.0.0.1:9099';
const firestoreBase = `http://127.0.0.1:8080/v1/projects/${projectId}/databases/(default)/documents`;
const realtimeBase = 'http://127.0.0.1:9000';
const namespace = `${projectId}-default-rtdb`;

async function account(uid, email, claims, profile) {
  await auth.createUser({ uid, email, password });
  await auth.setCustomUserClaims(uid, claims);
  await db.doc(`users/${uid}`).set({ uid, ...profile });
}

async function token(email) {
  const response = await fetch(
    `${authBase}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
      signal: AbortSignal.timeout(10_000),
    },
  );
  const data = await response.json();
  assert.ok(response.ok && data.idToken, JSON.stringify(data));
  return data.idToken;
}

async function expectStatus(description, url, expected, idToken) {
  const response = await fetch(url, {
    headers: idToken ? { Authorization: `Bearer ${idToken}` } : {},
    signal: AbortSignal.timeout(10_000),
  });
  assert.ok(expected.includes(response.status), `${description}: HTTP ${response.status}`);
}

async function main() {
  await account('developer-rules', 'developer-rules@voltrike.test', {
    adminRole: 'developer_admin',
  }, { role: 'developer_admin', isActive: true });
  await account('toda-rules', 'toda-rules@voltrike.test', {
    adminRole: 'toda_admin', todaId: 'toda-1',
  }, { role: 'toda_admin', todaId: 'toda-1', isActive: true });
  await account('passenger-rules', 'passenger-rules@voltrike.test', {
    role: 'passenger',
  }, { role: 'passenger', isActive: true });
  await db.doc('todas/toda-1').set({ name: 'Public TODA', isActive: true });
  await db.doc('todaApplications/toda-1').set({
    adminUid: 'toda-rules', status: 'pending', registration: { presidentTin: 'private' },
  });
  const developerToken = await token('developer-rules@voltrike.test');
  const todaToken = await token('toda-rules@voltrike.test');
  const passengerToken = await token('passenger-rules@voltrike.test');

  await expectStatus('public TODA directory is anonymous-readable', `${firestoreBase}/todas/toda-1`, [200]);
  await expectStatus('legal application is anonymous-private', `${firestoreBase}/todaApplications/toda-1`, [401, 403]);
  await expectStatus('TODA admin cannot bypass the private application API', `${firestoreBase}/todaApplications/toda-1`, [403], todaToken);
  await expectStatus('developer can audit legal applications', `${firestoreBase}/todaApplications/toda-1`, [200], developerToken);

  await realtime.ref('driver_locations/driver-1').set({
    latitude: 10.67, longitude: 122.95, accuracy: 5, timestamp: Date.now(), online: true,
  });
  await realtime.ref('driver_tracking_access/passenger-rules/driver-1').set({
    bookingId: 'booking-1', grantedAt: Date.now() - 1000, expiresAt: Date.now() + 60_000,
  });
  const locationUrl = `${realtimeBase}/driver_locations/driver-1.json?ns=${namespace}`;
  await expectStatus('fresh tracking grant permits passenger location', `${locationUrl}&auth=${passengerToken}`, [200]);
  await realtime.ref('driver_tracking_access/passenger-rules/driver-1/expiresAt').set(Date.now() - 1);
  await expectStatus('expired tracking grant denies passenger location', `${locationUrl}&auth=${passengerToken}`, [401, 403]);
  console.log('Security rules verification passed.');
}

main()
  .then(async () => {
    await admin.app().delete();
    process.exit(0);
  })
  .catch(async (error) => {
    console.error(error);
    try {
      await admin.app().delete();
    } finally {
      process.exit(1);
    }
  });
