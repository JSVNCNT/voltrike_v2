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
  additionalDropoffFee: 10,
  eTrikeSurcharge: 0,
  eTuktukSurcharge: 10,
  eTrikeEnabled: true,
  eTuktukEnabled: true,
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
    additionalDropoffFee: nonNegativeCurrency(
      source.additionalDropoffFee,
      DEFAULT_FARE.additionalDropoffFee,
    ),
    eTrikeSurcharge: nonNegativeCurrency(
      source.eTrikeSurcharge,
      DEFAULT_FARE.eTrikeSurcharge,
    ),
    eTuktukSurcharge: nonNegativeCurrency(
      source.eTuktukSurcharge,
      DEFAULT_FARE.eTuktukSurcharge,
    ),
    eTrikeEnabled: typeof source.eTrikeEnabled === 'boolean'
      ? source.eTrikeEnabled
      : DEFAULT_FARE.eTrikeEnabled,
    eTuktukEnabled: typeof source.eTuktukEnabled === 'boolean'
      ? source.eTuktukEnabled
      : DEFAULT_FARE.eTuktukEnabled,
    currency: source.currency === 'PHP' ? source.currency : DEFAULT_FARE.currency,
  };
}

function calculateFareBreakdown({
  config,
  distanceMeters,
  additionalPassengers = 0,
  baggageCount = 0,
  isOutsideToda = false,
  dropoffCount = 1,
  requestedVehicleType,
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
  const normalizedDropoffCount = Math.max(1, nonNegativeInteger(dropoffCount));
  const additionalDropoffs = Math.max(0, normalizedDropoffCount - 1);
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
  const additionalDropoffFareCentavos =
    additionalDropoffs * toCentavos(snapshot.additionalDropoffFee);
  const rideType = normalizeRideType(requestedVehicleType) || 'e_trike';
  const rideTypeFareCentavos = toCentavos(
    rideType === 'electric_tuktuk'
      ? snapshot.eTuktukSurcharge
      : snapshot.eTrikeSurcharge,
  );
  const totalCentavos =
    toCentavos(snapshot.baseFare) +
    distanceFareCentavos +
    additionalPassengerFareCentavos +
    baggageFareCentavos +
    boundarySurchargeCentavos +
    additionalDropoffFareCentavos +
    rideTypeFareCentavos;
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
    dropoffCount: normalizedDropoffCount,
    additionalDropoffs,
    additionalDropoffFare: fromCentavos(additionalDropoffFareCentavos),
    isOutsideToda: normalizedIsOutsideToda,
    boundarySurcharge: fromCentavos(boundarySurchargeCentavos),
    ...(requestedVehicleType === undefined ? {} : {
      requestedVehicleType: rideType,
      rideTypeFare: fromCentavos(rideTypeFareCentavos),
    }),
    currency: snapshot.currency,
    total: fromCentavos(totalCentavos),
  };
}

function normalizeRideType(value) {
  if (typeof value !== 'string') return '';
  const normalized = value.trim().toLowerCase().replace(/[^a-z]/g, '');
  if (normalized === 'etrike') return 'e_trike';
  if (['electrictuktuk', 'etuktuk', 'electrictricycle'].includes(normalized)) {
    return 'electric_tuktuk';
  }
  return '';
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
  normalizeRideType,
  toCentavos,
};
