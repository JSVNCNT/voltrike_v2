'use strict';

// Firebase Functions is deliberately an integration-only runtime. Domain
// commands, policy, dispatch, settlement, safety state, and admin authority
// live in the Go V2 API. Keep this file as an export manifest.
const { wrapCallable, wrapCloudEvent } = require('./monitoring');
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

exports.processGoOutbox = wrapCloudEvent(processGoOutbox);
exports.requestBrandedPasswordResetEmail = wrapCallable(requestBrandedPasswordResetEmail);
exports.requestBrandedVerificationEmail = wrapCallable(requestBrandedVerificationEmail);
exports.registerAdminWebPushToken = wrapCallable(registerAdminWebPushToken);
exports.unregisterAdminWebPushToken = wrapCallable(unregisterAdminWebPushToken);
exports.runGoMaintenance = wrapCloudEvent(runGoMaintenance);
