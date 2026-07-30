'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  commissionReportDateRange,
  commissionReportItem,
  commissionReportPageSize,
  commissionReportSummary,
  commissionReportSummaryOnly,
  cursorBelongsToReport,
} = require('../toda-commission-report');

test('commission date range uses inclusive Manila calendar dates', () => {
  const range = commissionReportDateRange('2026-07-01', '2026-07-31');
  assert.equal(range.start.toISOString(), '2026-06-30T16:00:00.000Z');
  assert.equal(
    range.endExclusive.toISOString(),
    '2026-07-31T16:00:00.000Z',
  );
  assert.equal(range.reportDays, 31);
});

test('commission date range rejects invalid or unbounded requests', () => {
  assert.throws(
    () => commissionReportDateRange('2026-02-30', '2026-03-01'),
    /valid calendar date/,
  );
  assert.throws(
    () => commissionReportDateRange('2026-07-02', '2026-07-01'),
    /on or before/,
  );
  assert.throws(
    () => commissionReportDateRange('2025-01-01', '2026-01-02'),
    /limited to 366 days/,
  );
  assert.throws(
    () => commissionReportPageSize(101),
    /between 1 and 100/,
  );
  assert.equal(commissionReportPageSize(undefined), 25);
});

test('commission summary-only mode requires an actual boolean', () => {
  assert.equal(commissionReportSummaryOnly(undefined), false);
  assert.equal(commissionReportSummaryOnly(false), false);
  assert.equal(commissionReportSummaryOnly(true), true);
  assert.throws(
    () => commissionReportSummaryOnly('true'),
    /must be a boolean/,
  );
  assert.throws(
    () => commissionReportSummaryOnly(1),
    /must be a boolean/,
  );
  assert.throws(
    () => commissionReportSummaryOnly(null),
    /must be a boolean/,
  );
});

test('commission summary is centavo-safe and distinguishes settlement state', () => {
  assert.deepEqual(commissionReportSummary({
    aggregate: {
      grossFare: 400.006,
      commissionAmount: 40.004,
      driverNetEarnings: 360.002,
      completedRides: 4,
    },
    settledSettlements: 3,
    disputedSettlements: 1,
  }), {
    grossFare: 400.01,
    commissionAmount: 40,
    driverNetEarnings: 360,
    completedRides: 4,
    pendingSettlements: 1,
    settledSettlements: 3,
    disputedSettlements: 1,
  });
});

test('commission report rows prefer authoritative booking identity and time', () => {
  const row = commissionReportItem('booking-123', {
    bookingId: 'booking-123',
    driverId: 'driver-123',
    grossFare: 100.005,
    commissionPercent: 10,
    commissionAmount: 10,
    driverNetEarnings: 90.005,
    status: 'settled',
    adjustmentStatus: 'disputed',
    disputeReason: 'Incorrect amount',
    settlementTimestamp: new Date('2026-07-30T04:00:00.000Z'),
  }, {
    driverName: 'A Driver',
    completedAt: new Date('2026-07-30T03:59:00.000Z'),
    receiptNumber: 'VT-123',
  });
  assert.deepEqual(row, {
    bookingId: 'booking-123',
    receiptNumber: 'VT-123',
    driverId: 'driver-123',
    driverName: 'A Driver',
    completedAt: '2026-07-30T03:59:00.000Z',
    grossFare: 100.01,
    commissionPercent: 10,
    commissionAmount: 10,
    driverNetEarnings: 90.01,
    settlementStatus: 'settled',
    adjustmentStatus: 'disputed',
    disputeReason: 'Incorrect amount',
  });
});

test('report cursor must stay inside the claimed TODA and selected dates', () => {
  const range = commissionReportDateRange('2026-07-01', '2026-07-31');
  assert.equal(cursorBelongsToReport({
    todaId: 'toda-a',
    settlementTimestamp: new Date('2026-07-01T00:00:00.000Z'),
  }, 'toda-a', range), true);
  assert.equal(cursorBelongsToReport({
    todaId: 'toda-b',
    settlementTimestamp: new Date('2026-07-01T00:00:00.000Z'),
  }, 'toda-a', range), false);
  assert.equal(cursorBelongsToReport({
    todaId: 'toda-a',
    settlementTimestamp: new Date('2026-08-01T00:00:00.000Z'),
  }, 'toda-a', range), false);
});
