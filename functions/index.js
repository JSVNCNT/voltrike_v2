'use strict';

// Firebase Functions is deliberately an integration-only runtime. Domain
// commands, policy, dispatch, settlement, safety state, and admin authority
// live in the Go V2 API. Keep this file as an export manifest.
const admin = require('firebase-admin');

if (admin.apps.length === 0) admin.initializeApp();

const { processGoOutbox } = require('./outbox-worker');
const {
  requestBrandedPasswordResetEmail,
  requestBrandedVerificationEmail,
} = require('./auth-integrations');
const {
  registerAdminWebPushToken,
  unregisterAdminWebPushToken,
} = require('./device-integrations');
const { runGoMaintenance } = require('./maintenance-trigger');

exports.processGoOutbox = processGoOutbox;
exports.requestBrandedPasswordResetEmail = requestBrandedPasswordResetEmail;
exports.requestBrandedVerificationEmail = requestBrandedVerificationEmail;
exports.registerAdminWebPushToken = registerAdminWebPushToken;
exports.unregisterAdminWebPushToken = unregisterAdminWebPushToken;
exports.runGoMaintenance = runGoMaintenance;
