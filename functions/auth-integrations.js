'use strict';

const { createHash } = require('node:crypto');
const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const {
  passwordResetEmail, sendBrevoEmail, validEmail, verificationEmail,
} = require('./brevo-communications');

const smtpLogin = defineSecret('BREVO_SMTP_LOGIN');
const smtpKey = defineSecret('BREVO_SMTP_KEY');
const senderEmail = defineSecret('BREVO_SENDER_EMAIL');

async function deliver(to, name, message) {
  return sendBrevoEmail({
    smtpLogin: smtpLogin.value(), smtpKey: smtpKey.value(),
    senderEmail: senderEmail.value(), senderName: 'VolTrike',
    to, name, ...message,
  });
}

function passwordResetMessage(user, link) {
  return passwordResetEmail({
    name: user.displayName || 'VolTrike user',
    resetLink: link,
  });
}

const authCallableOptions = {
  region: 'asia-southeast1',
  // This client is privately distributed by Quick Share. Requiring the debug
  // provider would make every new phone depend on a manually registered
  // Firebase Console token. Firebase Auth and the callable's own checks remain.
  enforceAppCheck: false,
};
const emailOptions = {
  ...authCallableOptions,
  secrets: [smtpLogin, smtpKey, senderEmail],
};

const requestBrandedVerificationEmail = onCall(emailOptions, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const user = await admin.auth().getUser(request.auth.uid);
  if (user.emailVerified) return { sent: false, alreadyVerified: true };
  if (!user.email || !validEmail(user.email)) {
    throw new HttpsError('failed-precondition', 'The account has no valid email.');
  }
  const limiter = admin.firestore().collection('communicationRateLimits')
    .doc(`verification-${request.auth.uid}`);
  const now = Date.now();
  const allowed = await admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(limiter);
    const last = snapshot.data()?.lastRequestedAt?.toMillis?.() || 0;
    if (now - last < 60_000) return false;
    transaction.set(limiter, {
      purpose: 'account_verification', uid: request.auth.uid,
      lastRequestedAt: admin.firestore.Timestamp.fromMillis(now),
      expiresAt: admin.firestore.Timestamp.fromMillis(now + 86_400_000),
    }, { merge: true });
    return true;
  });
  if (!allowed) throw new HttpsError('resource-exhausted', 'Wait one minute before retrying.');
  const link = await admin.auth().generateEmailVerificationLink(user.email);
  const message = verificationEmail({
    name: user.displayName || 'VolTrike user', verificationLink: link,
  });
  let response;
  try {
    response = await deliver(user.email, user.displayName, message);
  } catch (error) {
    // Do not consume the one-minute resend window when the provider did not
    // accept the message. The mobile client can then use Firebase Auth's
    // built-in verification email as a safe fallback.
    await limiter.delete().catch(() => undefined);
    console.error('Verification email provider rejected delivery.', {
      code: error?.code,
      responseCode: error?.responseCode,
    });
    throw new HttpsError(
      'unavailable',
      'Verification email delivery is temporarily unavailable.',
    );
  }
  await recordDelivery(request.auth.uid, 'account_verification', response);
  return { sent: true, alreadyVerified: false };
});

const requestBrandedPasswordResetEmail = onCall(emailOptions, async (request) => {
  const email = String(request.data?.email || '').trim().toLowerCase();
  if (!validEmail(email)) throw new HttpsError('invalid-argument', 'Enter a valid email.');
  const hash = createHash('sha256').update(email).digest('hex');
  const limiter = admin.firestore().collection('communicationRateLimits')
    .doc(`password-reset-${hash}`);
  const now = Date.now();
  const allowed = await admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(limiter);
    const last = snapshot.data()?.lastRequestedAt?.toMillis?.() || 0;
    if (now - last < 60_000) return false;
    transaction.set(limiter, {
      purpose: 'password_reset', emailHash: hash,
      lastRequestedAt: admin.firestore.Timestamp.fromMillis(now),
      expiresAt: admin.firestore.Timestamp.fromMillis(now + 86_400_000),
    }, { merge: true });
    return true;
  });
  if (!allowed) return { accepted: true };
  const user = await admin.auth().getUserByEmail(email).catch((error) => {
    if (error?.code === 'auth/user-not-found') return null;
    throw error;
  });
  if (!user) return { accepted: true };
  const link = await admin.auth().generatePasswordResetLink(email);
  const message = passwordResetMessage(user, link);
  const response = await deliver(email, user.displayName, message);
  await recordDelivery(user.uid, 'password_reset', response);
  return { accepted: true };
});

// Firebase Authentication owns the verified-email state. Firestore keeps a
// denormalized copy for profile and admin displays, updated only by trusted
// server code so a client cannot claim an unverified address is verified.
const syncMyEmailVerification = onCall(authCallableOptions, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');

  const user = await admin.auth().getUser(request.auth.uid);
  const profile = admin.firestore().collection('users').doc(request.auth.uid);
  const snapshot = await profile.get();
  if (!snapshot.exists) {
    throw new HttpsError('failed-precondition', 'The account profile was not found.');
  }

  const emailVerified = user.emailVerified === true;
  const changed = snapshot.data()?.emailVerified !== emailVerified;
  if (changed) {
    await profile.update({
      emailVerified,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return { emailVerified, changed };
});

async function recordDelivery(uid, purpose, response) {
  await admin.firestore().collection('communicationDeliveries').add({
    recipientId: uid, purpose, channel: 'email', provider: 'brevo',
    providerMessageId: String(response?.messageId || ''), status: 'accepted',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 86_400_000),
  });
}

module.exports = {
  authCallableOptions,
  passwordResetMessage,
  requestBrandedPasswordResetEmail,
  requestBrandedVerificationEmail,
  syncMyEmailVerification,
};
