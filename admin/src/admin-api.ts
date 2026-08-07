import { httpsCallable } from 'firebase/functions';
import {
  collection,
  limit,
  onSnapshot,
  orderBy,
  query,
  type Unsubscribe,
} from 'firebase/firestore';
import { auth, db, firebaseAppCheckToken, functions } from './firebase';
import { ref, uploadBytes } from 'firebase/storage';
import { storage } from './firebase';
import type {
  AdminMetrics,
  OverviewAnalytics,
  BookingOperation,
  Driver,
  DriverRatingRecord,
  DriverViolation,
  DriverViolationStatus,
  FareConfig,
  LiveDriver,
  PageResult,
  Point,
  Report,
  RouteRestriction,
  SafetyIncident,
  Toda,
  TodaCommission,
  TodaCommissionDriverSummary,
  TodaCommissionReport,
  TodaCommissionReportOptions,
  ViolationFilters,
  ViolationMessage,
  ZoneRequest,
} from './types';

async function call<T>(name: string, data: Record<string, unknown>): Promise<T> {
  if (name !== 'requestBrandedVerificationEmail') {
    return goOperation<T>(name, data);
  }
  try {
    return (await httpsCallable<Record<string, unknown>, T>(functions, name)(data)).data;
  } catch (error) {
    throw new Error(callableErrorMessage(name, error));
  }
}

async function goOperation<T>(
  name: string,
  payload: Record<string, unknown>,
): Promise<T> {
  const baseUrl = String(import.meta.env.VITE_VOLTRIKE_API_BASE_URL || '')
    .trim()
    .replace(/\/$/, '');
  const user = auth.currentUser;
  if (!baseUrl || !user) {
    throw new Error('The authenticated VolTrike V2 API is not configured.');
  }
  const token = await user.getIdToken();
  const appCheckToken = await firebaseAppCheckToken();
  const response = await fetch(
    `${baseUrl}/api/v2/operations/${encodeURIComponent(name)}`,
    {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
        ...(appCheckToken ? { 'X-Firebase-AppCheck': appCheckToken } : {}),
      },
      body: JSON.stringify({ commandId: crypto.randomUUID(), payload }),
    },
  );
  const decoded = await response.json().catch(() => ({})) as {
    data?: unknown;
    error?: { message?: string };
  };
  if (!response.ok) {
    throw new Error(decoded.error?.message || `The ${name} operation failed.`);
  }
  return decoded.data as T;
}

type UnknownRecord = Record<string, unknown>;

function asRecord(value: unknown): UnknownRecord {
  return value !== null && typeof value === 'object' ? value as UnknownRecord : {};
}

async function uploadAndFinalizeTodaDocument(
  todaId: string,
  field: string,
  file: File,
): Promise<string> {
  const extension = file.name.includes('.')
    ? file.name.split('.').pop()?.replace(/[^a-zA-Z0-9]/g, '') || 'bin'
    : 'bin';
  const uid = auth.currentUser?.uid;
  if (!uid) throw new Error('Sign in before uploading documents.');
  const stagingPath = `staging/${uid}/${crypto.randomUUID()}/${field}.${extension}`;
  const uploaded = await uploadBytes(ref(storage, stagingPath), file, {
    contentType: file.type,
    customMetadata: { ownerUid: uid, targetType: 'toda_document' },
  });
  const finalized = await call<{ reference: string }>('finalizeMedia', {
    stagingPath: uploaded.ref.fullPath,
    generation: Number(uploaded.metadata.generation),
    targetType: 'toda_document',
    targetId: todaId,
    field,
  });
  if (!finalized.reference) throw new Error('Media finalization returned no reference.');
  return finalized.reference;
}

function finiteNumber(value: unknown): number | null {
  if (typeof value !== 'number' && (typeof value !== 'string' || !value.trim())) {
    return null;
  }
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function dateString(value: unknown): string | null {
  if (typeof value === 'string' && value.trim()) return value;
  if (typeof value === 'number' && Number.isFinite(value)) {
    return new Date(value).toISOString();
  }
  const source = asRecord(value);
  if (typeof source.toDate === 'function') {
    const converted = (source.toDate as () => unknown)();
    return converted instanceof Date ? converted.toISOString() : null;
  }
  const seconds = finiteNumber(source.seconds ?? source._seconds);
  if (seconds !== null) return new Date(seconds * 1000).toISOString();
  return null;
}

function textValue(value: unknown, fallback = ''): string {
  return typeof value === 'string' && value.trim() ? value : fallback;
}

function normalizeLiveDriver(value: unknown): LiveDriver {
  const source = asRecord(value);
  const location = asRecord(source.location);
  const vehicle = asRecord(source.vehicle);
  const applicant = asRecord(source.applicant);
  const applicantName = [
    textValue(applicant.firstName),
    textValue(applicant.middleName),
    textValue(applicant.lastName),
  ].filter(Boolean).join(' ');

  return {
    uid: textValue(source.uid ?? source.driverId ?? source.id),
    name: textValue(source.name ?? source.driverName ?? source.displayName,
      applicantName || 'Unnamed driver'),
    todaId: textValue(source.todaId ?? source.driverTodaId),
    latitude: finiteNumber(location.latitude ?? location.lat ?? source.latitude) ?? 0,
    longitude: finiteNumber(location.longitude ?? location.lng ?? source.longitude) ?? 0,
    accuracy: finiteNumber(location.accuracy ?? source.accuracy) ?? 0,
    timestamp: finiteNumber(location.timestamp ?? location.updatedAt ?? source.timestamp) ?? 0,
    bookingId: textValue(source.bookingId ?? source.currentBookingId) || null,
    bookingStatus: textValue(source.bookingStatus ?? source.status,
      source.isOnline === true ? 'available' : 'not_recorded'),
    vehicleType: textValue(source.vehicleType ?? vehicle.type ?? vehicle.model) || null,
    plateNumber: textValue(source.plateNumber ?? vehicle.plateNumber) || null,
  };
}

function normalizeDriver(value: unknown): Driver {
  const source = asRecord(value);
  const applicantSource = asRecord(source.applicant ?? source.user ?? source.profile);
  const vehicleSource = asRecord(source.vehicle);
  const applicant = {
    firstName: textValue(applicantSource.firstName ?? source.firstName ?? source.givenName),
    middleName: textValue(applicantSource.middleName ?? source.middleName),
    lastName: textValue(applicantSource.lastName ?? source.lastName ?? source.familyName ?? source.surname),
    email: textValue(applicantSource.email ?? source.email),
    phoneNumber: textValue(applicantSource.phoneNumber ?? applicantSource.phone ?? source.phoneNumber ?? source.phone),
    dateOfBirth: textValue(applicantSource.dateOfBirth ?? applicantSource.birthDate ?? source.dateOfBirth ?? source.birthDate),
    profileImage: textValue(applicantSource.profileImage ?? source.profileImage ?? source.profilePhotoUrl),
  };
  const status = source.driverStatus === 'approved' || source.driverStatus === 'rejected' ||
      source.driverStatus === 'suspended' ? source.driverStatus : 'pending';
  const vehicleId = textValue(source.vehicleId ?? vehicleSource.id);
  const vehicle = Object.keys(vehicleSource).length > 0 || vehicleId
    ? {
      id: vehicleId,
      isVerified: vehicleSource.isVerified === true,
      vehicleNumber: textValue(vehicleSource.vehicleNumber ?? source.vehicleNumber),
      plateNumber: textValue(vehicleSource.plateNumber ?? source.plateNumber),
      model: textValue(vehicleSource.model ?? source.vehicleModel ?? source.vehicleType),
    }
    : null;
  return {
    ...source,
    uid: textValue(source.uid ?? source.driverId ?? source.id),
    todaId: textValue(source.todaId ?? source.driverTodaId),
    driverStatus: status,
    isOnline: source.isOnline === true,
    rating: finiteNumber(source.rating) ?? 0,
    ratingCount: finiteNumber(source.ratingCount) ?? 0,
    completedTrips: finiteNumber(source.completedTrips) ?? 0,
    totalEarnings: finiteNumber(source.totalEarnings) ?? 0,
    licenseNumber: textValue(source.licenseNumber),
    licenseExpiry: dateString(source.licenseExpiry) ?? undefined,
    profilePhotoUrl: textValue(source.profilePhotoUrl ?? source.profileImage) || undefined,
    driverLicenseFrontUrl: textValue(source.driverLicenseFrontUrl) || undefined,
    driverLicenseBackUrl: textValue(source.driverLicenseBackUrl) || undefined,
    governmentIdUrl: textValue(source.governmentIdUrl) || undefined,
    orDocumentUrl: textValue(source.orDocumentUrl) || undefined,
    crDocumentUrl: textValue(source.crDocumentUrl) || undefined,
    vehiclePhotoUrl: textValue(source.vehiclePhotoUrl) || undefined,
    applicant,
    vehicleId: vehicleId || undefined,
    vehicle,
  } as Driver;
}

function normalizeBookingOperation(value: unknown): BookingOperation {
  const source = asRecord(value);
  const acknowledgement = source.acknowledgement === 'accidental' ||
    source.acknowledgement === 'needs_review'
    ? source.acknowledgement
    : undefined;
  return {
    bookingId: textValue(source.bookingId ?? source.id),
    schemaVersion: finiteNumber(source.schemaVersion) ?? 0,
    status: textValue(source.status, 'not_recorded'),
    acknowledgement,
    passengerName: textValue(source.passengerName, 'Passenger unavailable'),
    driverName: textValue(source.driverName) || null,
    driverId: textValue(source.driverId) || null,
    plateNumber: textValue(source.plateNumber) || null,
    todaId: textValue(source.todaId ?? source.driverTodaId) || null,
    todaName: textValue(source.todaName) || null,
    pickupName: textValue(source.pickupName) || null,
    destinationName: textValue(source.destinationName) || null,
    pickupAddress: textValue(source.pickupAddress, 'Pickup unavailable'),
    destinationAddress: textValue(source.destinationAddress, 'Destination unavailable'),
    amountDue: finiteNumber(source.amountDue ?? source.totalFare) ?? 0,
    paymentMethod: textValue(source.paymentMethod, 'not recorded'),
    settlementStatus: textValue(source.settlementStatus, 'not_recorded'),
    adjustmentStatus: textValue(source.adjustmentStatus, 'not_recorded'),
    disputeReason: textValue(source.disputeReason) || null,
    receiptNumber: textValue(source.receiptNumber) || null,
    cancellationCode: textValue(source.cancellationCode) || null,
    createdAt: dateString(source.createdAt),
    updatedAt: dateString(source.updatedAt),
  };
}

function normalizeRating(value: unknown): DriverRatingRecord {
  const source = asRecord(value);
  return {
    ...source,
    id: textValue(source.id ?? source.ratingId),
    ratingId: textValue(source.ratingId ?? source.id) || undefined,
    bookingId: textValue(source.bookingId),
    driverId: textValue(source.driverId),
    passengerId: textValue(source.passengerId),
    todaId: textValue(source.todaId) || null,
    todaName: textValue(source.todaName) || null,
    driverName: textValue(source.driverName) || null,
    passengerName: textValue(source.passengerName) || null,
    rating: finiteNumber(source.rating) ?? 0,
    comment: textValue(source.comment),
    createdAt: dateString(source.createdAt),
  } as DriverRatingRecord;
}

function normalizePerson(value: unknown) {
  const source = asRecord(value);
  if (Object.keys(source).length === 0) return undefined;
  return {
    firstName: textValue(source.firstName ?? source.givenName),
    middleName: textValue(source.middleName),
    lastName: textValue(source.lastName ?? source.familyName ?? source.surname),
    email: textValue(source.email),
    phoneNumber: textValue(source.phoneNumber ?? source.phone),
    role: textValue(source.role) || undefined,
    isActive: typeof source.isActive === 'boolean' ? source.isActive : undefined,
  };
}

function normalizeReport(value: unknown): Report {
  const source = asRecord(value);
  return {
    ...source,
    id: textValue(source.id ?? source.reportId),
    bookingId: textValue(source.bookingId),
    reporterId: textValue(source.reporterId ?? source.reportedBy),
    reportedUserId: textValue(source.reportedUserId ?? source.reportedId),
    todaId: textValue(source.todaId ?? source.driverTodaId) || undefined,
    reporterRole: source.reporterRole === 'driver' ? 'driver' : 'passenger',
    reportedRole: source.reportedRole === 'driver' ? 'driver' : 'passenger',
    category: textValue(source.category, 'Uncategorized report'),
    details: textValue(source.details ?? source.description),
    status: source.status === 'resolved' || source.status === 'dismissed' ? source.status : 'open',
    action: textValue(source.action) || undefined,
    reporter: normalizePerson(source.reporter ?? source.reporterProfile),
    reportedUser: normalizePerson(source.reportedUser ?? source.reportedUserProfile),
  } as Report;
}

function normalizeSafetyIncident(value: unknown): SafetyIncident {
  const source = asRecord(value);
  const rawLocation = asRecord(source.driverLocation ?? source.location);
  const latitude = finiteNumber(rawLocation.latitude ?? rawLocation.lat);
  const longitude = finiteNumber(rawLocation.longitude ?? rawLocation.lng ?? rawLocation.lon);
  const driverLocation = latitude !== null && longitude !== null &&
      Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180
    ? {
      latitude,
      longitude,
      accuracy: finiteNumber(rawLocation.accuracy) ?? undefined,
      bearing: finiteNumber(rawLocation.bearing ?? rawLocation.heading) ?? undefined,
      speed: finiteNumber(rawLocation.speed) ?? undefined,
      timestamp: finiteNumber(rawLocation.timestamp) ?? undefined,
      online: rawLocation.online === true,
    }
    : null;
  return {
    ...source,
    id: textValue(source.id ?? source.incidentId),
    bookingId: textValue(source.bookingId),
    category: textValue(source.category, 'sos'),
    reporterRole: textValue(source.reporterRole, 'passenger'),
    passengerId: textValue(source.passengerId),
    passengerName: textValue(source.passengerName) || null,
    driverId: textValue(source.driverId) || null,
    driverName: textValue(source.driverName) || null,
    todaId: textValue(source.todaId) || null,
    todaName: textValue(source.todaName) || null,
    bookingStatus: textValue(source.bookingStatus ?? source.status, 'not_recorded'),
    pickupAddress: textValue(source.pickupAddress) || null,
    destinationAddress: textValue(source.destinationAddress) || null,
    driverLocation,
    status: textValue(source.status, 'open'),
    responseStatus: source.responseStatus === 'acknowledged' || source.responseStatus === 'responding' || source.responseStatus === 'resolved' ? source.responseStatus : 'reported',
    deliveryStatus: typeof source.deliveryStatus === 'string' ? source.deliveryStatus as SafetyIncident['deliveryStatus'] : null,
    deliveryRecipientCount: finiteNumber(source.deliveryRecipientCount) ?? 0,
    deliveryAttemptCount: finiteNumber(source.deliveryAttemptCount) ?? 0,
    deliverySuccessCount: finiteNumber(source.deliverySuccessCount) ?? 0,
    escalationLevel: finiteNumber(source.escalationLevel) ?? 0,
    bookingCancelledForSafety: source.bookingCancelledForSafety === true,
    bookingSafetyAction: textValue(source.bookingSafetyAction) || null,
    locationSource: source.locationSource === 'live_driver_location' ? 'live_driver_location' : 'sos_snapshot',
    emergencyDispatch: textValue(source.emergencyDispatch),
    requiresManualEmergencyContact: source.requiresManualEmergencyContact === true,
    createdAt: dateString(source.createdAt),
    updatedAt: dateString(source.updatedAt),
    deliveredAt: dateString(source.deliveredAt),
    acknowledgedAt: dateString(source.acknowledgedAt),
    respondingAt: dateString(source.respondingAt),
    resolvedAt: dateString(source.resolvedAt),
    escalatedAt: dateString(source.escalatedAt),
    lastResponseNote: textValue(source.lastResponseNote ?? source.responseNote) || null,
    resolutionNote: textValue(source.resolutionNote) || null,
  } as SafetyIncident;
}

function normalizeCommissionReport(value: unknown): TodaCommissionReport {
  const source = asRecord(value);
  const summary = asRecord(source.summary);
  const items = Array.isArray(source.items) ? source.items : [];
  const driverSummaries = Array.isArray(source.driverSummaries)
    ? source.driverSummaries
    : [];
  return {
    summary: {
      grossFare: finiteNumber(summary.grossFare) ?? 0,
      commissionAmount: finiteNumber(summary.commissionAmount) ?? 0,
      commissionDue: finiteNumber(summary.commissionDue) ?? 0,
      commissionSettled: finiteNumber(summary.commissionSettled) ?? 0,
      driverNetEarnings: finiteNumber(summary.driverNetEarnings) ?? 0,
      completedRides: finiteNumber(summary.completedRides ?? summary.tripCount) ?? 0,
      pendingSettlements: finiteNumber(summary.pendingSettlements) ?? 0,
      settledSettlements: finiteNumber(summary.settledSettlements) ?? 0,
      disputedSettlements: finiteNumber(summary.disputedSettlements) ?? 0,
    },
    items: items.map((value) => {
      const item = asRecord(value);
      return {
        bookingId: textValue(item.bookingId ?? item.id),
        receiptNumber: textValue(item.receiptNumber) || null,
        driverId: textValue(item.driverId),
        driverName: textValue(item.driverName, 'Driver name unavailable'),
        completedAt: dateString(item.completedAt ?? item.settlementTimestamp),
        grossFare: finiteNumber(item.grossFare ?? item.amountDue) ?? 0,
        commissionPercent: finiteNumber(item.commissionPercent) ?? 0,
        commissionAmount: finiteNumber(item.commissionAmount) ?? 0,
        commissionSettlementStatus: item.commissionSettlementStatus === 'settled'
          ? 'settled' as const
          : 'due' as const,
        commissionSettledAt: dateString(item.commissionSettledAt),
        driverNetEarnings: finiteNumber(item.driverNetEarnings) ?? 0,
        settlementStatus: textValue(item.settlementStatus ?? item.status, 'not_recorded'),
        adjustmentStatus: textValue(item.adjustmentStatus) || null,
        disputeReason: textValue(item.disputeReason) || null,
      };
    }).filter((item) => Boolean(item.bookingId)),
    driverSummaries: driverSummaries.map((value): TodaCommissionDriverSummary => {
      const item = asRecord(value);
      const driverId = textValue(item.driverId ?? item.uid);
      return {
        driverId,
        driverName: textValue(item.driverName ?? item.name, 'Registered driver'),
        completedRides: finiteNumber(item.completedRides ?? item.tripCount) ?? 0,
        grossFare: finiteNumber(item.grossFare) ?? 0,
        commissionAmount: finiteNumber(item.commissionAmount) ?? 0,
        commissionDue: finiteNumber(item.commissionDue) ?? 0,
        commissionSettled: finiteNumber(item.commissionSettled) ?? 0,
        driverNetEarnings: finiteNumber(item.driverNetEarnings) ?? 0,
      };
    }).filter((item) => Boolean(item.driverId)),
    nextCursor: textValue(source.nextCursor) || null,
  };
}

function decodePoint(value: unknown): Point | null {
  if (Array.isArray(value)) {
    const longitude = finiteNumber(value[0]);
    const latitude = finiteNumber(value[1]);
    if (longitude === null || latitude === null) return null;
    if (Math.abs(longitude) > 180 || Math.abs(latitude) > 90) return null;
    return [longitude, latitude];
  }

  const source = asRecord(value);
  const longitude = finiteNumber(source.longitude ?? source.lng);
  const latitude = finiteNumber(source.latitude ?? source.lat);
  if (longitude === null || latitude === null) return null;
  if (Math.abs(longitude) > 180 || Math.abs(latitude) > 90) return null;
  return [longitude, latitude];
}

function decodeArea(value: unknown): Point[] {
  const source = asRecord(value);
  const rawPoints = Array.isArray(value)
    ? value
    : source.points ?? source.coordinates ?? source.vertices ?? source.polygon;
  if (!Array.isArray(rawPoints)) return [];
  return rawPoints.map(decodePoint).filter((point): point is Point => point !== null);
}

function decodeAreas(value: unknown): Point[][] {
  const source = asRecord(value);
  const rawAreas = Array.isArray(value) ? value : source.areas;
  if (!Array.isArray(rawAreas)) return [];
  return rawAreas.map(decodeArea).filter((area) => area.length > 0);
}

function normalizeZoneRequest(id: string, value: unknown): ZoneRequest {
  const source = asRecord(value);
  const decodedPolygon = decodeArea(source.polygon);
  const decodedAreas = decodeAreas(source.areas);
  const areas = decodedAreas.length > 0
    ? decodedAreas
    : decodedPolygon.length > 0 ? [decodedPolygon] : [];
  const polygon = decodedPolygon.length > 0 ? decodedPolygon : areas[0] ?? [];
  const status = source.status === 'approved' || source.status === 'declined'
    ? source.status
    : 'pending';

  return {
    ...source,
    id,
    todaId: typeof source.todaId === 'string' ? source.todaId : '',
    polygon,
    areas,
    status,
    notes: typeof source.notes === 'string' ? source.notes : '',
    geometryVersion: finiteNumber(source.geometryVersion) ?? undefined,
  };
}

function normalizeRouteRestriction(id: string, value: unknown): RouteRestriction {
  const source = asRecord(value);
  const type: RouteRestriction['type'] =
    source.type === 'no_service_area' || source.type === 'restricted_crossing'
      ? source.type
      : 'prohibited_highway';
  const geometryType: NonNullable<RouteRestriction['geometryType']> =
    source.geometryType === 'polygon' || source.geometryType === 'corridor'
      ? source.geometryType
      : type === 'prohibited_highway' ? 'corridor' : 'polygon';
  const decodedCoordinates = decodeArea(source.coordinates);
  const decodedPolygon = decodeArea(source.polygon);
  const decodedAreas = decodeAreas(source.areas);
  const polygon = decodedCoordinates.length > 0
    ? decodedCoordinates
    : decodedPolygon.length > 0 ? decodedPolygon : decodedAreas[0] ?? [];
  const areas = decodedAreas.length > 0
    ? decodedAreas
    : geometryType === 'polygon' && polygon.length > 0 ? [polygon] : [];

  return {
    ...source,
    id,
    name: typeof source.name === 'string' ? source.name : 'Unnamed restriction',
    type,
    geometryType,
    polygon,
    areas,
    bufferMeters: finiteNumber(source.bufferMeters) ?? 0,
    notes: typeof source.notes === 'string' ? source.notes : '',
    isActive: source.isActive !== false,
    geometryVersion: finiteNumber(source.geometryVersion) ?? undefined,
  };
}

function normalizeViolationStatus(value: unknown): DriverViolationStatus {
  if (value === 'acknowledged' || value === 'responding' ||
      value === 'resolved' || value === 'dismissed') return value;
  if (value === 'investigating') return 'responding';
  return 'open';
}

function normalizeDriverViolation(id: string, value: unknown): DriverViolation {
  const source = asRecord(value);
  const rawLocation = asRecord(
    source.eventLocation ?? source.location ?? source.driverLocation,
  );
  const rawRestriction = asRecord(
    source.restriction ?? source.restrictionSnapshot,
  );
  const hasRestriction = Object.keys(rawRestriction).length > 0
    || typeof source.restrictionId === 'string'
    || typeof source.restrictionName === 'string'
    || typeof source.restrictionType === 'string';
  const latitude = finiteNumber(
    rawLocation.latitude ?? rawLocation.lat ?? source.latitude,
  ) ?? 0;
  const longitude = finiteNumber(
    rawLocation.longitude ?? rawLocation.lng ?? source.longitude,
  ) ?? 0;
  const decodedAreas = decodeAreas(rawRestriction.areas);
  const decodedPolygon = decodeArea(
    rawRestriction.polygon ?? rawRestriction.coordinates,
  );
  const restrictionAreas = decodedAreas.length > 0
    ? decodedAreas
    : decodedPolygon.length > 0 ? [decodedPolygon] : [];

  return {
    id,
    schemaVersion: finiteNumber(source.schemaVersion) ?? undefined,
    eventClass: typeof source.eventClass === 'string'
      ? source.eventClass
      : typeof source.type === 'string' ? source.type : 'unknown',
    status: normalizeViolationStatus(source.status),
    severity: typeof source.severity === 'string' ? source.severity : undefined,
    driverId: typeof source.driverId === 'string' ? source.driverId : '',
    driverName: typeof source.driverName === 'string' ? source.driverName : null,
    ownerTodaId: typeof source.ownerTodaId === 'string'
      ? source.ownerTodaId
      : typeof source.todaId === 'string' ? source.todaId : null,
    ownerTodaName: typeof source.ownerTodaName === 'string'
      ? source.ownerTodaName
      : typeof source.todaName === 'string' ? source.todaName : null,
    bookingId: typeof source.bookingId === 'string' ? source.bookingId : null,
    bookingStatus: typeof source.bookingStatus === 'string'
      ? source.bookingStatus
      : null,
    context: typeof source.context === 'string'
      ? source.context
      : typeof source.bookingStatus === 'string' ? source.bookingStatus : 'unknown',
    restriction: hasRestriction ? {
      id: typeof rawRestriction.id === 'string'
        ? rawRestriction.id
        : typeof rawRestriction.restrictionId === 'string'
          ? rawRestriction.restrictionId
          : typeof source.restrictionId === 'string'
            ? source.restrictionId
            : null,
      name: typeof rawRestriction.name === 'string'
        ? rawRestriction.name
        : typeof source.restrictionName === 'string'
          ? source.restrictionName
          : 'Restricted area',
      type: typeof rawRestriction.type === 'string'
        ? rawRestriction.type
        : typeof source.restrictionType === 'string'
          ? source.restrictionType
          : null,
      revision: finiteNumber(
        rawRestriction.revision ?? source.restrictionRevision,
      ),
      geometryVersion: finiteNumber(rawRestriction.geometryVersion),
      polygon: decodedPolygon,
      areas: restrictionAreas,
    } : null,
    eventLocation: {
      latitude,
      longitude,
      accuracy: finiteNumber(rawLocation.accuracy),
      bearing: finiteNumber(rawLocation.bearing ?? rawLocation.heading),
      speed: finiteNumber(rawLocation.speed),
      timestamp: finiteNumber(rawLocation.timestamp ?? rawLocation.capturedAt),
      observedAt: finiteNumber(
        rawLocation.observedAt ?? source.locationObservedAt,
      ),
    },
    evidence: Object.keys(asRecord(source.evidence)).length > 0
      ? asRecord(source.evidence)
      : null,
    source: typeof source.source === 'string' ? source.source : null,
    confidence: typeof source.confidence === 'string' ||
      typeof source.confidence === 'number' ? source.confidence : null,
    routeAdvisory: typeof source.routeAdvisory === 'string'
      ? source.routeAdvisory
      : null,
    enteredAt: dateString(source.enteredAt),
    exitedAt: dateString(source.exitedAt),
    occurredAt: dateString(source.occurredAt),
    createdAt: dateString(source.createdAt),
    updatedAt: dateString(source.updatedAt),
    acknowledgedAt: dateString(source.acknowledgedAt),
    resolvedAt: dateString(source.resolvedAt),
    delivery: normalizeViolationDelivery(source.delivery),
    driverDelivery: normalizeViolationDelivery(source.driverDelivery),
    resolutionNote: typeof source.resolutionNote === 'string'
      ? source.resolutionNote
      : null,
    latestAdminNote: typeof source.latestAdminNote === 'string'
      ? source.latestAdminNote
      : typeof asRecord(source.response).note === 'string'
        ? asRecord(source.response).note as string
        : null,
    unreadMessageCount: finiteNumber(source.unreadMessageCount) ?? 0,
    messageCount: finiteNumber(source.messageCount) ?? 0,
    lastMessage: typeof source.lastMessage === 'string'
      ? source.lastMessage
      : null,
    lastMessageAt: dateString(source.lastMessageAt),
  };
}

function normalizeViolationDelivery(value: unknown) {
  const source = asRecord(value);
  if (Object.keys(source).length === 0) return null;
  return {
    status: typeof source.status === 'string' ? source.status : null,
    recipientCount: finiteNumber(source.recipientCount) ?? 0,
    attemptedCount: finiteNumber(source.attemptedCount) ?? 0,
    successCount: finiteNumber(source.successCount) ?? 0,
    lastAttemptAt: dateString(source.lastAttemptAt),
  };
}

function normalizeViolationMessage(id: string, value: unknown): ViolationMessage {
  const source = asRecord(value);
  return {
    id,
    violationId: typeof source.violationId === 'string'
      ? source.violationId
      : '',
    senderId: typeof source.senderId === 'string' ? source.senderId : '',
    senderName: typeof source.senderName === 'string'
      ? source.senderName
      : typeof source.senderRole === 'string'
        ? source.senderRole.split('_').join(' ')
        : 'Case participant',
    senderRole: typeof source.senderRole === 'string'
      ? source.senderRole
      : 'unknown',
    text: typeof source.body === 'string'
      ? source.body
      : typeof source.text === 'string' ? source.text : '',
    createdAt: dateString(source.sentAt ?? source.createdAt),
    readBy: Array.isArray(source.seenBy)
      ? source.seenBy.filter((entry): entry is string => typeof entry === 'string')
      : Array.isArray(source.readBy)
        ? source.readBy.filter((entry): entry is string => typeof entry === 'string')
        : [],
  };
}

function callableErrorMessage(name: string, error: unknown): string {
  const source = asRecord(error);
  const code = typeof source.code === 'string' ? source.code : '';
  const rawMessage = error instanceof Error
    ? error.message
    : typeof source.message === 'string' ? source.message : '';
  const usefulMessage = rawMessage.trim()
    && !/^(internal|internal error|unknown|an unknown error occurred)[.:]?$/i.test(rawMessage.trim())
    && !/functions\/internal/i.test(rawMessage);

  if (code.includes('unauthenticated')) {
    return 'Your administrator session expired. Sign in again and retry.';
  }
  if (code.includes('permission-denied')) {
    return 'Your current administrator account cannot perform this action. Sign in again if its permissions recently changed.';
  }
  if (usefulMessage) return rawMessage;
  if (name === 'adminSubmitZoneRequest' || name === 'adminUpdateZoneRequest') {
    return 'The server could not save the coverage geometry. Refresh and try again; if it repeats, verify that the deployed admin Functions support geometry version 2.';
  }
  if (name === 'adminReviewZoneRequest') {
    return 'The server could not review this coverage request. Refresh the request list and try again.';
  }
  if (name === 'adminCreateRouteRestriction') {
    return 'The server could not save the route restriction. Refresh and try again; if it repeats, verify that the deployed admin Functions support geometry version 2.';
  }
  if (name === 'adminSetRouteRestrictionStatus') {
    return 'The server could not change this route restriction status. Refresh the restriction list and try again.';
  }
  if (name === 'adminListDriverViolations') {
    return 'The server could not load restriction violations for this administrator scope. Refresh and try again.';
  }
  if (name === 'adminGetTodaCommissionReport') {
    return 'The server could not load this TODA commission report. Refresh and try again.';
  }
  if (name === 'adminUpdateDriverViolation') {
    return 'The server could not update this violation case. Refresh the case and try again.';
  }
  if (name === 'sendDriverViolationMessage') {
    return 'The server could not send this case message. Your draft was kept; retry when the connection is restored.';
  }
  return 'The server could not complete this administrator action. Refresh and try again.';
}

export const adminApi = {
  metrics: () => call<AdminMetrics>('adminGetMetrics', {}),
  overviewAnalytics: () => call<OverviewAnalytics>('adminGetOverviewAnalytics', {}),
  bootstrap: (code: string) => call<{ role: string }>('bootstrapDeveloperAdmin', { code }),
  requestBrandedVerificationEmail: () =>
    call<{ sent: boolean; alreadyVerified: boolean }>(
      'requestBrandedVerificationEmail',
      {},
    ),
  registerToda: (data: Record<string, unknown>) => call<{ todaId: string }>('registerToda', data),
  reviewTodaRegistration: (todaId: string, status: 'approved' | 'declined') => call<{ updated: boolean }>('adminReviewTodaRegistration', { todaId, status }),
  setTodaStatus: (todaId: string, isActive: boolean) => call<{ updated: boolean }>('adminSetTodaStatus', { todaId, isActive }),
  attachTodaRegistrationDocuments: (todaId: string, documents: Record<string, string>) => call<{ updated: boolean }>('attachTodaRegistrationDocuments', { todaId, documents }),
  todaDocumentUrl: (todaId: string, reference: string) =>
    call<{ url: string; expiresAt: string }>('adminGetTodaDocumentUrl', { todaId, reference }),
  updateFare: (fare: FareConfig) => call<{ updated: boolean }>('adminUpdateFare', { fare }),
  setDriverStatus: (uid: string, status: string, license?: { number: string; expiry: string }) =>
    call<{ updated: boolean }>('adminSetDriverStatus', {
      uid,
      status,
      licenseNumber: license?.number || '',
      licenseExpiry: license?.expiry || '',
    }),
  setVehicleVerification: (driverId: string, isVerified: boolean) => call<{ updated: boolean }>('adminSetVehicleVerification', { driverId, isVerified }),
  setUserStatus: (uid: string, isActive: boolean, sourceReportId = '') => call<{ updated: boolean }>('adminSetUserStatus', { uid, isActive, sourceReportId }),
  resolveReport: (reportId: string, status: string, action: string) => call<{ updated: boolean }>('adminResolveReport', { reportId, status, action }),
  resolveSettlementDispute: (bookingId: string, resolution: string) => call<{ updated: boolean }>('adminResolveSettlementDispute', { bookingId, resolution }),
  submitZone: (todaId: string, polygon: [number, number][], notes: string, areas?: [number, number][][]) => call<{ zoneRequestId: string }>('adminSubmitZoneRequest', { todaId, polygon, notes, areas }),
  reviewZone: (zoneRequestId: string, status: string) => call<{ updated: boolean }>('adminReviewZoneRequest', { zoneRequestId, status }),
  updateZone: (zoneRequestId: string, polygon: [number, number][], notes: string, areas?: [number, number][][]) => call<{ updated: boolean }>('adminUpdateZoneRequest', { zoneRequestId, polygon, notes, areas }),
  createRouteRestriction: (name: string, type: RouteRestriction['type'], geometryType: 'polygon' | 'corridor', polygon: [number, number][], bufferMeters: number, notes: string, areas?: [number, number][][], minimumAlignedTravelMeters?: number) => call<{ restrictionId: string }>('adminCreateRouteRestriction', { name, type, geometryType, polygon, bufferMeters, notes, areas, minimumAlignedTravelMeters }),
  setRouteRestrictionStatus: (restrictionId: string, isActive: boolean) => call<{ updated: boolean }>('adminSetRouteRestrictionStatus', { restrictionId, isActive }),
  async todas(): Promise<Toda[]> {
    return (await call<{ items: Toda[] }>('adminListTodas', {})).items;
  },
  async driverPage(cursor?: string | null, search = ''): Promise<PageResult<Driver>> {
    const result = await call<{ items?: unknown[]; nextCursor?: unknown }>('adminListDrivers', {
      cursor: cursor || '',
      search,
      pageSize: 25,
    });
    return {
      items: Array.isArray(result.items)
        ? result.items.map(normalizeDriver).filter((item) => Boolean(item.uid))
        : [],
      nextCursor: textValue(result.nextCursor) || null,
    };
  },
  async drivers(_todaId?: string): Promise<Driver[]> {
    return (await adminApi.driverPage()).items;
  },
  async ratingPage(cursor?: string | null): Promise<PageResult<DriverRatingRecord>> {
    const result = await call<{ items?: unknown[]; nextCursor?: unknown }>('adminListRatings', {
      cursor: cursor || '',
      pageSize: 50,
    });
    return {
      items: Array.isArray(result.items) ? result.items.map(normalizeRating) : [],
      nextCursor: textValue(result.nextCursor) || null,
    };
  },
  async ratings(): Promise<DriverRatingRecord[]> {
    return (await adminApi.ratingPage()).items;
  },
  async reportPage(cursor?: string | null, search = ''): Promise<PageResult<Report>> {
    const result = await call<{ items?: unknown[]; nextCursor?: unknown }>('adminListReports', {
      cursor: cursor || '',
      search,
      pageSize: 25,
    });
    return {
      items: Array.isArray(result.items)
        ? result.items.map(normalizeReport).filter((item) => Boolean(item.id))
        : [],
      nextCursor: textValue(result.nextCursor) || null,
    };
  },
  async reports(_todaId?: string): Promise<Report[]> {
    return (await adminApi.reportPage()).items;
  },
  async bookingPage(cursor?: string | null, search = ''): Promise<PageResult<BookingOperation>> {
    const result = await call<{ items?: unknown[]; nextCursor?: unknown }>('adminListBookings', {
      cursor: cursor || '',
      search,
      pageSize: 25,
    });
    return {
      items: Array.isArray(result.items)
        ? result.items.map(normalizeBookingOperation).filter((item) => Boolean(item.bookingId))
        : [],
      nextCursor: typeof result.nextCursor === 'string' && result.nextCursor
        ? result.nextCursor
        : null,
    };
  },
  async safetyIncidentPage(cursor?: string | null): Promise<PageResult<SafetyIncident>> {
    const result = await call<{ items?: unknown[]; nextCursor?: unknown }>('adminListSafetyIncidents', {
      cursor: cursor || '',
      pageSize: 50,
    });
    return {
      items: Array.isArray(result.items)
        ? result.items.map(normalizeSafetyIncident).filter((item) => Boolean(item.id))
        : [],
      nextCursor: textValue(result.nextCursor) || null,
    };
  },
  async liveDrivers(): Promise<LiveDriver[]> {
    const result = await call<{ items?: unknown[] }>('adminListLiveDrivers', {});
    return Array.isArray(result.items)
      ? result.items.map(normalizeLiveDriver).filter((item) => Boolean(item.uid))
      : [];
  },
  todaCommission: () => call<TodaCommission>('adminGetTodaCommission', {}),
  setTodaCommission: (percent: number) =>
    call<TodaCommission>('adminSetTodaCommission', { percent }),
  settleDriverCommission: (driverId: string, startDate: string, endDate: string) =>
    call<{ settledBookingCount: number; commissionAmount: number }>(
      'adminSettleDriverCommission',
      { driverId, startDate, endDate },
    ),
  async todaCommissionReport(
    startDate: string,
    endDate: string,
    options: TodaCommissionReportOptions = {},
  ): Promise<TodaCommissionReport> {
    const data: Record<string, unknown> = {
      startDate,
      endDate,
      summaryOnly: options.summaryOnly === true,
    };
    if (!options.summaryOnly) {
      data.cursor = options.cursor || '';
      data.pageSize = 25;
    }
    const result = await call<unknown>(
      'adminGetTodaCommissionReport',
      data,
    );
    return normalizeCommissionReport(result);
  },
  cancelBookingForSafety: (incidentId: string) =>
    call<{ cancelled: boolean }>('adminCancelBookingForSafety', { incidentId }),
  updateSafetyIncidentResponse: (
    incidentId: string,
    action: 'acknowledge' | 'responding' | 'resolve',
    note = '',
  ) => call<{ responseStatus: SafetyIncident['responseStatus'] }>(
    'adminUpdateSafetyIncidentResponse',
    { incidentId, action, note },
  ),
  async violationPage(
    cursor?: string | null,
    filters: ViolationFilters = {},
  ): Promise<PageResult<DriverViolation>> {
    const result = await call<{
      items?: unknown[];
      nextCursor?: unknown;
    }>('adminListDriverViolations', {
      cursor: cursor || '',
      limit: 50,
      status: filters.status || '',
      eventClass: filters.eventClass || '',
    });
    const items = (result.items || [])
      .map((entry) => {
        const source = asRecord(entry);
        const id = typeof source.id === 'string'
          ? source.id
          : typeof source.violationId === 'string' ? source.violationId : '';
        return normalizeDriverViolation(id, source);
      })
      .filter((entry) => Boolean(entry.id));
    return {
      items,
      nextCursor: typeof result.nextCursor === 'string' &&
          result.nextCursor.trim()
        ? result.nextCursor
        : null,
    };
  },
  async violation(violationId: string): Promise<DriverViolation> {
    const result = await call<{ item?: unknown }>('adminGetDriverViolation', {
      violationId,
    });
    const source = asRecord(result.item);
    const id = typeof source.id === 'string'
      ? source.id
      : typeof source.violationId === 'string'
        ? source.violationId
        : violationId;
    if (!Object.keys(source).length || !id) {
      throw new Error('The violation case is unavailable in your administrator scope.');
    }
    return normalizeDriverViolation(id, source);
  },
  updateViolation: (
    violationId: string,
    action: 'acknowledge' | 'respond' | 'resolve' | 'dismiss',
    note = '',
  ) => call<{ violationId: string; status: DriverViolationStatus }>(
    'adminUpdateDriverViolation',
    { violationId, action, note },
  ),
  sendViolationMessage: (violationId: string, messageId: string, message: string) =>
    call<{ violationId: string; messageId: string; idempotent: boolean }>(
      'sendDriverViolationMessage',
      { violationId, messageId, message },
    ),
  markViolationMessagesRead: (violationId: string) =>
    call<{ markedRead: number }>('markDriverViolationMessagesRead', {
      violationId,
    }),
  listenViolationMessages(
    violationId: string,
    onMessages: (messages: ViolationMessage[]) => void,
    onError: (error: Error) => void,
  ): Unsubscribe {
    const source = collection(db, 'driverViolations', violationId, 'messages');
    return onSnapshot(
      query(source, orderBy('createdAt', 'asc'), limit(250)),
      (snapshot) => {
        onMessages(snapshot.docs.map((entry) =>
          normalizeViolationMessage(entry.id, entry.data())));
      },
      (error) => onError(new Error(callableErrorMessage(
        'listenDriverViolationMessages',
        error,
      ))),
    );
  },
  async zones(todaId?: string): Promise<ZoneRequest[]> {
    const result = await call<{ items: unknown[] }>('adminListZones', { todaId: todaId || '' });
    return result.items
      .map((entry) => { const source = asRecord(entry); return normalizeZoneRequest(String(source.id || ''), source); })
      .sort((left, right) => {
        if (left.status === 'pending' && right.status !== 'pending') return -1;
        if (right.status === 'pending' && left.status !== 'pending') return 1;
        return left.todaId.localeCompare(right.todaId);
      });
  },
  async routeRestrictions(): Promise<RouteRestriction[]> {
    const result = await call<{ items: unknown[] }>('adminListRouteRestrictions', {});
    return result.items
      .map((entry) => { const source = asRecord(entry); return normalizeRouteRestriction(String(source.id || ''), source); })
      .sort((left, right) => Number(right.isActive) - Number(left.isActive) || left.name.localeCompare(right.name));
  },
  async fare(): Promise<FareConfig> {
    const result = await call<{ fare: Record<string, unknown> }>('adminGetFare', {});
    const source = result.fare;
    return {
      baseFare: Number(source.baseFare ?? 20),
      includedMeters: Number(source.includedMeters ?? 1000),
      distanceStepMeters: Number(source.distanceStepMeters ?? 500),
      distanceStepPrice: Number(source.distanceStepPrice ?? 5),
      additionalPassengerFee: Number(source.additionalPassengerFee ?? 40),
      baggageFee: Number(source.baggageFee ?? 20),
      outsideTodaSurcharge: Number(source.outsideTodaSurcharge ?? 20),
    };
  },
  async uploadTodaRegistrationDocuments(todaId: string, files: Record<string, File>): Promise<void> {
    const documents = await Promise.all(Object.entries(files).map(async ([key, file]) => {
      return [key, await uploadAndFinalizeTodaDocument(todaId, key, file)] as const;
    }));
    await adminApi.attachTodaRegistrationDocuments(todaId, Object.fromEntries(documents));
  },
};
