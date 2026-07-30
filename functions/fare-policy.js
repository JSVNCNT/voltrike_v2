'use strict';

const DEFAULT_FARE = Object.freeze({
  version: 1,
  baseFare: 20,
  includedMeters: 1000,
  distanceStepMeters: 500,
  distanceStepPrice: 5,
  additionalPassengerFee: 40,
  baggageFee: 20,
  outsideTodaSurcharge: 20,
  currency: 'PHP',
});

const CENTAVOS_PER_PESO = 100;

function finiteNumber(value, fallback) {
  return typeof value === 'number' && Number.isFinite(value)
    ? value
    : fallback;
}

function positiveInteger(value, fallback) {
  return Number.isInteger(value) && value > 0 ? value : fallback;
}

function toCentavos(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  const [coefficient, exponent = '0'] = String(number).split('e');
  const shifted = Number(
    `${coefficient}e${Number(exponent) + 2}`,
  );
  return shifted < 0 ? -Math.round(-shifted) : Math.round(shifted);
}

function fromCentavos(value) {
  return value / CENTAVOS_PER_PESO;
}

function roundCurrency(value) {
  return fromCentavos(toCentavos(value));
}

function nonNegativeCurrency(value, fallback) {
  return typeof value === 'number' &&
    Number.isFinite(value) &&
    value >= 0
    ? roundCurrency(value)
    : fallback;
}

function nonNegativeInteger(value) {
  return typeof value === 'number' && Number.isFinite(value)
    ? Math.max(0, Math.floor(value))
    : 0;
}

function fareSnapshot(data) {
  const source = data || {};
  return {
    version: positiveInteger(source.version, DEFAULT_FARE.version),
    baseFare: nonNegativeCurrency(source.baseFare, DEFAULT_FARE.baseFare),
    includedMeters: positiveInteger(
      source.includedMeters,
      DEFAULT_FARE.includedMeters,
    ),
    distanceStepMeters: positiveInteger(
      source.distanceStepMeters,
      DEFAULT_FARE.distanceStepMeters,
    ),
    distanceStepPrice: nonNegativeCurrency(
      source.distanceStepPrice,
      DEFAULT_FARE.distanceStepPrice,
    ),
    additionalPassengerFee: nonNegativeCurrency(
      source.additionalPassengerFee,
      DEFAULT_FARE.additionalPassengerFee,
    ),
    baggageFee: nonNegativeCurrency(
      source.baggageFee,
      DEFAULT_FARE.baggageFee,
    ),
    outsideTodaSurcharge: nonNegativeCurrency(
      source.outsideTodaSurcharge,
      DEFAULT_FARE.outsideTodaSurcharge,
    ),
    currency: source.currency === 'PHP' ? source.currency : DEFAULT_FARE.currency,
  };
}

function calculateFareBreakdown({
  config,
  distanceMeters,
  additionalPassengers = 0,
  baggageCount = 0,
  isOutsideToda = false,
}) {
  const snapshot = fareSnapshot(config);
  const normalizedIsOutsideToda = isOutsideToda === true;
  const distance = Math.max(
    0,
    Math.round(finiteNumber(distanceMeters, 0)),
  );
  const chargeableMeters = Math.max(0, distance - snapshot.includedMeters);
  const distanceSteps = Math.ceil(
    chargeableMeters / snapshot.distanceStepMeters,
  );
  const normalizedAdditionalPassengers =
    nonNegativeInteger(additionalPassengers);
  const normalizedBaggageCount = nonNegativeInteger(baggageCount);
  const distanceFareCentavos =
    distanceSteps * toCentavos(snapshot.distanceStepPrice);
  const additionalPassengerFareCentavos =
    normalizedAdditionalPassengers *
    toCentavos(snapshot.additionalPassengerFee);
  const baggageFareCentavos =
    normalizedBaggageCount * toCentavos(snapshot.baggageFee);
  const boundarySurchargeCentavos =
    normalizedIsOutsideToda
      ? toCentavos(snapshot.outsideTodaSurcharge)
      : 0;
  const totalCentavos =
    toCentavos(snapshot.baseFare) +
    distanceFareCentavos +
    additionalPassengerFareCentavos +
    baggageFareCentavos +
    boundarySurchargeCentavos;
  return {
    baseFare: snapshot.baseFare,
    includedMeters: snapshot.includedMeters,
    chargeableMeters,
    distanceSteps,
    distanceStepMeters: snapshot.distanceStepMeters,
    distanceStepPrice: snapshot.distanceStepPrice,
    distanceFare: fromCentavos(distanceFareCentavos),
    additionalPassengers: normalizedAdditionalPassengers,
    additionalPassengerFare: fromCentavos(
      additionalPassengerFareCentavos,
    ),
    baggageCount: normalizedBaggageCount,
    baggageFare: fromCentavos(baggageFareCentavos),
    isOutsideToda: normalizedIsOutsideToda,
    boundarySurcharge: fromCentavos(boundarySurchargeCentavos),
    currency: snapshot.currency,
    total: fromCentavos(totalCentavos),
  };
}

function calculateFare(options) {
  return calculateFareBreakdown(options).total;
}

module.exports = {
  DEFAULT_FARE,
  calculateFare,
  calculateFareBreakdown,
  fareSnapshot,
  fromCentavos,
  roundCurrency,
  toCentavos,
};
