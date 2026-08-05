'use strict';

const { createHash } = require('node:crypto');
const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

async function adminIdentity(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const profile = await admin.firestore().collection('users').doc(request.auth.uid).get();
  const data = profile.data() || {};
  if (!profile.exists || data.isActive !== true ||
      !['developer_admin', 'toda_admin'].includes(data.role)) {
    throw new HttpsError('permission-denied', 'Administrator access is required.');
  }
  return { uid: request.auth.uid, role: data.role, todaId: data.todaId || null };
}

function tokenData(request) {
  const token = String(request.data?.token || '').trim();
  if (token.length < 20 || token.length > 4096) {
    throw new HttpsError('invalid-argument', 'A valid push token is required.');
  }
  return { token, id: createHash('sha256').update(token).digest('hex') };
}

const registerAdminWebPushToken = onCall({ region: 'asia-southeast1', enforceAppCheck: true }, async (request) => {
  const actor = await adminIdentity(request);
  const { token, id } = tokenData(request);
  const device = admin.firestore().collection('users').doc(actor.uid).collection('devices').doc(id);
  const registry = admin.firestore().collection('adminWebPushTokens').doc(id);
  await admin.firestore().runTransaction(async (transaction) => {
    const owner = await transaction.get(registry);
    const previousUid = owner.data()?.ownerUid;
    if (previousUid && previousUid !== actor.uid) {
      transaction.delete(admin.firestore().collection('users').doc(previousUid).collection('devices').doc(id));
    }
    transaction.set(device, {
      token, platform: 'web', ownerUid: actor.uid, adminRole: actor.role,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(registry, {
      tokenHash: id, ownerUid: actor.uid, ownerRole: actor.role,
      ownerTodaId: actor.todaId, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return { registered: true, deviceId: id };
});

const unregisterAdminWebPushToken = onCall({ region: 'asia-southeast1', enforceAppCheck: true }, async (request) => {
  const actor = await adminIdentity(request);
  const { id } = tokenData(request);
  const registry = admin.firestore().collection('adminWebPushTokens').doc(id);
  await admin.firestore().runTransaction(async (transaction) => {
    const owner = await transaction.get(registry);
    if (owner.data()?.ownerUid !== actor.uid) return;
    transaction.delete(registry);
    transaction.delete(admin.firestore().collection('users').doc(actor.uid).collection('devices').doc(id));
  });
  return { unregistered: true, deviceId: id };
});

module.exports = { registerAdminWebPushToken, unregisterAdminWebPushToken };
