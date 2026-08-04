'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { driverEarningsPeriodStarts } = require('../driver-earnings-periods');

test('earnings periods use Manila midnight and Monday week start', () => {
  const starts = driverEarningsPeriodStarts(
    Date.parse('2026-08-04T16:30:00.000Z'),
  );
  assert.equal(starts.day.toISOString(), '2026-08-04T16:00:00.000Z');
  assert.equal(starts.week.toISOString(), '2026-08-02T16:00:00.000Z');
  assert.equal(starts.month.toISOString(), '2026-07-31T16:00:00.000Z');
});

test('Sunday stays in the preceding Monday earnings week', () => {
  const starts = driverEarningsPeriodStarts(
    Date.parse('2026-08-09T12:00:00.000Z'),
  );
  assert.equal(starts.week.toISOString(), '2026-08-02T16:00:00.000Z');
});
