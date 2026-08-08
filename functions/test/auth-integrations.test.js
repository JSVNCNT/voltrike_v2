'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  authCallableOptions,
  passwordResetMessage,
  syncMyEmailVerification,
} = require('../auth-integrations');

test('private APK auth email callables do not require per-device App Check', () => {
  assert.equal(authCallableOptions.enforceAppCheck, false);
});

test('verified-email profile synchronization is exported as a callable', () => {
  assert.equal(typeof syncMyEmailVerification, 'function');
});

test('password reset wiring passes the generated Firebase link to the template', () => {
  const link = 'https://example.test/reset?oobCode=secure';
  const message = passwordResetMessage({ displayName: 'Passenger' }, link);

  assert.match(message.htmlContent, /reset\?oobCode=secure/);
  assert.match(message.textContent, /reset\?oobCode=secure/);
});
