'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { passwordResetMessage } = require('../auth-integrations');

test('password reset wiring passes the generated Firebase link to the template', () => {
  const link = 'https://example.test/reset?oobCode=secure';
  const message = passwordResetMessage({ displayName: 'Passenger' }, link);

  assert.match(message.htmlContent, /reset\?oobCode=secure/);
  assert.match(message.textContent, /reset\?oobCode=secure/);
});
