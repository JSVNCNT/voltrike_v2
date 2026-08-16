'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  DEFAULT_FARE,
  calculateFare,
  calculateFareBreakdown,
  fareSnapshot,
  roundCurrency,
} = require('../fare-policy');

test('fare snapshots are versioned and legacy-safe', () => {
  assert.deepEqual(fareSnapshot(null), DEFAULT_FARE);
  assert.equal(fareSnapshot({ version: 4, baseFare: 30 }).version, 4);
  assert.equal(fareSnapshot({ version: 4, baseFare: 30 }).baseFare, 30);
});

test('backend fare matches the stepped VolTrike formula', () => {
  assert.equal(calculateFare({
    config: DEFAULT_FARE,
    distanceMeters: 1000,
  }), 20);
  assert.equal(calculateFare({
    config: DEFAULT_FARE,
    distanceMeters: 1001,
  }), 25);
  assert.equal(calculateFare({
    config: DEFAULT_FARE,
    distanceMeters: 2100,
    additionalPassengers: 1,
    baggageCount: 2,
    isOutsideToda: true,
  }), 135);
});

test('fare breakdown exposes every admin-controlled component', () => {
  assert.deepEqual(calculateFareBreakdown({
    config: DEFAULT_FARE,
    distanceMeters: 2100,
    additionalPassengers: 1,
    baggageCount: 1,
    isOutsideToda: true,
  }), {
    baseFare: 20,
    includedMeters: 1000,
    chargeableMeters: 1100,
    distanceSteps: 3,
    distanceStepMeters: 500,
    distanceStepPrice: 5,
    distanceFare: 15,
    additionalPassengers: 1,
    additionalPassengerFare: 40,
    baggageCount: 1,
    baggageFare: 20,
    dropoffCount: 1,
    additionalDropoffs: 0,
    additionalDropoffFare: 0,
    isOutsideToda: true,
    boundarySurcharge: 20,
    currency: 'PHP',
    total: 115,
  });
});

test('a second drop-off uses the configured flat fee once', () => {
  const breakdown = calculateFareBreakdown({
    config: DEFAULT_FARE,
    distanceMeters: 1000,
    dropoffCount: 2,
  });
  assert.equal(breakdown.additionalDropoffs, 1);
  assert.equal(breakdown.additionalDropoffFare, 10);
  assert.equal(breakdown.total, 30);
});

test('currency values are rounded to centavos before totals are added', () => {
  assert.equal(roundCurrency(10.075), 10.08);
  assert.equal(roundCurrency(1.005), 1.01);
  assert.equal(fareSnapshot({
    baseFare: 10.075,
    distanceStepPrice: -1,
  }).baseFare, 10.08);
  assert.equal(fareSnapshot({
    baseFare: 10.075,
    distanceStepPrice: -1,
  }).distanceStepPrice, DEFAULT_FARE.distanceStepPrice);
});

const parityFixture = JSON.parse(fs.readFileSync(path.join(
  __dirname,
  '..',
  '..',
  'test',
  'fixtures',
  'fare_parity_v1.json',
), 'utf8'));

for (const fixture of parityFixture.cases) {
  test(`shared fare parity: ${fixture.name}`, () => {
    const actual = calculateFareBreakdown({
      config: fixture.config,
      ...fixture.input,
    });
    const {
      dropoffCount: _dropoffCount,
      additionalDropoffs: _additionalDropoffs,
      additionalDropoffFare: _additionalDropoffFare,
      ...legacyShape
    } = actual;
    assert.deepEqual(legacyShape, fixture.expected);
  });
}
