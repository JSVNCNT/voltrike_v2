'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  calculateSettlementBreakdown,
  normalizedCommissionPercent,
  settlementInvariantHolds,
} = require('../settlement-policy');

test('settlement calculation uses integer centavos and remains balanced', () => {
  const result = calculateSettlementBreakdown({
    grossFare: 123.45,
    commissionPercent: 7.5,
  });
  assert.deepEqual(result, {
    grossFare: 123.45,
    commissionPercent: 7.5,
    commissionAmount: 9.26,
    driverNetEarnings: 114.19,
  });
  assert.equal(settlementInvariantHolds(result), true);
});

test('settlement accepts zero and maximum configured commission', () => {
  assert.deepEqual(calculateSettlementBreakdown({
    grossFare: 100.01,
    commissionPercent: 0,
  }), {
    grossFare: 100.01,
    commissionPercent: 0,
    commissionAmount: 0,
    driverNetEarnings: 100.01,
  });
  assert.deepEqual(calculateSettlementBreakdown({
    grossFare: 100.01,
    commissionPercent: 30,
  }), {
    grossFare: 100.01,
    commissionPercent: 30,
    commissionAmount: 30,
    driverNetEarnings: 70.01,
  });
});

test('invalid legacy commission falls back to zero without losing fare', () => {
  assert.equal(normalizedCommissionPercent(undefined), 0);
  assert.equal(normalizedCommissionPercent(-1), 0);
  assert.equal(normalizedCommissionPercent(31), 0);
  assert.deepEqual(calculateSettlementBreakdown({
    grossFare: 80,
    commissionPercent: 99,
  }), {
    grossFare: 80,
    commissionPercent: 0,
    commissionAmount: 0,
    driverNetEarnings: 80,
  });
});

test('invalid gross fares cannot produce settlements', () => {
  assert.throws(
    () => calculateSettlementBreakdown({
      grossFare: Number.NaN,
      commissionPercent: 10,
    }),
    /Gross fare/,
  );
  assert.throws(
    () => calculateSettlementBreakdown({
      grossFare: -0.01,
      commissionPercent: 10,
    }),
    /Gross fare/,
  );
});
