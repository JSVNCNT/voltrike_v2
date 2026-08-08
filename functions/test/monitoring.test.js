'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { wrapScheduledTask } = require('../monitoring');

test('scheduled monitoring preserves results and rethrows failures', async () => {
  const successful = wrapScheduledTask(async (event) => event.value);
  assert.equal(await successful({ value: 42 }), 42);

  const expected = new Error('scheduled task failed');
  const failing = wrapScheduledTask(async () => {
    throw expected;
  });
  await assert.rejects(failing({}), (error) => error === expected);
});
