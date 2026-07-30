'use strict';

const { roundCurrency } = require('./fare-policy');

const MANILA_OFFSET_MILLISECONDS = 8 * 60 * 60 * 1000;
const MILLISECONDS_PER_DAY = 24 * 60 * 60 * 1000;
const MAX_REPORT_DAYS = 366;
const MAX_REPORT_PAGE_SIZE = 100;
const DEFAULT_REPORT_PAGE_SIZE = 25;

function dateParts(value, name) {
  if (typeof value !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new RangeError(`${name} must use YYYY-MM-DD.`);
  }
  const [year, month, day] = value.split('-').map(Number);
  const utc = Date.UTC(year, month - 1, day);
  const normalized = new Date(utc);
  if (normalized.getUTCFullYear() !== year ||
      normalized.getUTCMonth() !== month - 1 ||
      normalized.getUTCDate() !== day) {
    throw new RangeError(`${name} is not a valid calendar date.`);
  }
  return { day, month, utc, year };
}

function commissionReportDateRange(startDate, endDate) {
  const start = dateParts(startDate, 'Start date');
  const end = dateParts(endDate, 'End date');
  if (start.utc > end.utc) {
    throw new RangeError('Start date must be on or before end date.');
  }
  const reportDays = Math.round(
    (end.utc - start.utc) / MILLISECONDS_PER_DAY,
  ) + 1;
  if (reportDays > MAX_REPORT_DAYS) {
    throw new RangeError(
      `Commission reports are limited to ${MAX_REPORT_DAYS} days.`,
    );
  }
  return {
    start: new Date(start.utc - MANILA_OFFSET_MILLISECONDS),
    endExclusive: new Date(
      end.utc + MILLISECONDS_PER_DAY - MANILA_OFFSET_MILLISECONDS,
    ),
    reportDays,
  };
}

function commissionReportPageSize(value) {
  if (value == null) return DEFAULT_REPORT_PAGE_SIZE;
  if (!Number.isInteger(value) ||
      value < 1 ||
      value > MAX_REPORT_PAGE_SIZE) {
    throw new RangeError(
      `Page size must be between 1 and ${MAX_REPORT_PAGE_SIZE}.`,
    );
  }
  return value;
}

function commissionReportSummaryOnly(value) {
  if (value === undefined) return false;
  if (typeof value !== 'boolean') {
    throw new TypeError('Summary-only mode must be a boolean.');
  }
  return value;
}

function nonNegativeInteger(value) {
  const number = Number(value);
  return Number.isFinite(number)
    ? Math.max(0, Math.floor(number))
    : 0;
}

function reportMoney(value) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0
    ? roundCurrency(number)
    : 0;
}

function commissionReportSummary({
  aggregate,
  settledSettlements,
  disputedSettlements,
}) {
  const completedRides = nonNegativeInteger(aggregate?.completedRides);
  const settled = Math.min(
    completedRides,
    nonNegativeInteger(settledSettlements),
  );
  return {
    grossFare: reportMoney(aggregate?.grossFare),
    commissionAmount: reportMoney(aggregate?.commissionAmount),
    driverNetEarnings: reportMoney(aggregate?.driverNetEarnings),
    completedRides,
    pendingSettlements: completedRides - settled,
    settledSettlements: settled,
    disputedSettlements: Math.min(
      completedRides,
      nonNegativeInteger(disputedSettlements),
    ),
  };
}

function reportDate(value) {
  if (value?.toDate instanceof Function) {
    return value.toDate().toISOString();
  }
  if (value instanceof Date && !Number.isNaN(value.valueOf())) {
    return value.toISOString();
  }
  if (typeof value === 'string') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString();
  }
  return null;
}

function reportString(value, fallback = '') {
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : fallback;
}

function commissionReportItem(id, settlement, booking = {}) {
  const bookingId = reportString(settlement?.bookingId, id);
  return {
    bookingId,
    receiptNumber:
      reportString(settlement?.receiptNumber, null) ||
      reportString(booking?.receiptNumber, null),
    driverId: reportString(
      settlement?.driverId,
      reportString(booking?.driverId),
    ),
    driverName: reportString(
      booking?.driverName,
      reportString(settlement?.driverName, 'Driver'),
    ),
    completedAt:
      reportDate(booking?.completedAt) ||
      reportDate(settlement?.settlementTimestamp),
    grossFare: reportMoney(
      settlement?.grossFare ?? settlement?.amountDue,
    ),
    commissionPercent: reportMoney(settlement?.commissionPercent),
    commissionAmount: reportMoney(settlement?.commissionAmount),
    driverNetEarnings: reportMoney(settlement?.driverNetEarnings),
    settlementStatus: reportString(settlement?.status, 'pending'),
    adjustmentStatus: reportString(
      settlement?.adjustmentStatus,
      'none',
    ),
    disputeReason: reportString(settlement?.disputeReason, null),
  };
}

function timestampMillis(value) {
  if (value?.toMillis instanceof Function) return value.toMillis();
  if (value?.toDate instanceof Function) return value.toDate().valueOf();
  if (value instanceof Date) return value.valueOf();
  return Number.NaN;
}

function cursorBelongsToReport(data, todaId, range) {
  if (!data || data.todaId !== todaId) return false;
  const value = timestampMillis(data.settlementTimestamp);
  return Number.isFinite(value) &&
    value >= range.start.valueOf() &&
    value < range.endExclusive.valueOf();
}

module.exports = {
  DEFAULT_REPORT_PAGE_SIZE,
  MAX_REPORT_DAYS,
  MAX_REPORT_PAGE_SIZE,
  commissionReportDateRange,
  commissionReportItem,
  commissionReportPageSize,
  commissionReportSummary,
  commissionReportSummaryOnly,
  cursorBelongsToReport,
};
