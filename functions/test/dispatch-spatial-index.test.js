'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  dispatchCellForLocation,
  dispatchIndexUpdates,
} = require('../dispatch-spatial-index');

test('cell keys are stable and reject invalid coordinates', () => {
  assert.equal(
    dispatchCellForLocation({ latitude: 10.67, longitude: 122.95 }),
    '2013:6058',
  );
  assert.equal(dispatchCellForLocation({ latitude: 91, longitude: 0 }), null);
});

test('moving cells removes the old entry and creates the new one', () => {
  const updates = dispatchIndexUpdates({
    driverId: 'driver-1',
    before: { latitude: 10.67, longitude: 122.95, online: true },
    after: {
      latitude: 10.72,
      longitude: 122.95,
      accuracy: 8,
      timestamp: 1234,
      online: true,
    },
  });
  assert.equal(updates['dispatchCells/2013:6058/driver-1'], null);
  assert.equal(
    updates['dispatchCells/2014:6058/driver-1'].timestamp,
    1234,
  );
  assert.equal(updates['dispatchDriverCells/driver-1'], '2014:6058');
});

test('offline transition removes the active cell', () => {
  const updates = dispatchIndexUpdates({
    driverId: 'driver-1',
    before: { latitude: 10.67, longitude: 122.95, online: true },
    after: null,
  });
  assert.equal(updates['dispatchCells/2013:6058/driver-1'], null);
  assert.equal(updates['dispatchDriverCells/driver-1'], null);
});
