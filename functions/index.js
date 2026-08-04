const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onValueWritten } = require('firebase-functions/v2/database');
const { createHash, randomUUID } = require('node:crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { logger } = require('firebase-functions');
const { defineSecret, defineString } = require('firebase-functions/params');
const admin = require('firebase-admin');
const {
  AggregateField,
  FieldPath,
  FieldValue,
  Timestamp,
} = require('firebase-admin/firestore');
const { ServerValue } = require('firebase-admin/database');
const {
  BOOKING_STATUS,
  cancellationExpectedStatuses,
  distanceMeters,
  nextRatingAggregate,
  normalizeCoordinate,
  validBookingId,
  validOperationId,
} = require('./booking-lifecycle');
const {
  CALL_DURATION_MS,
  CALL_INVITATION_MS,
  CALL_STATUS,
  acceptedCallNeedsScheduledEnd,
  callAllowedForBookingStatus,
  effectiveCallStatus,
  participantRole,
  recipientFor,
  remainingCallSeconds,
  terminalCallStatus,
  timestampMillis: callTimestampMillis,
} = require('./booking-call-policy');
const {
  adminIdentityMatches,
  canManageToda,
} = require('./admin-policy');
const {
  calculateFareBreakdown,
  fareSnapshot,
} = require('./fare-policy');
const {
  calculateSettlementBreakdown,
  normalizedCommissionPercent,
} = require('./settlement-policy');
const {
  commissionReportDateRange,
  commissionReportItem,
  commissionReportPageSize,
  commissionReportSummary,
  commissionReportSummaryOnly,
  cursorBelongsToReport,
} = require('./toda-commission-report');
const {
  classifyTripCoverage,
  decodePolyline,
  firstHighwayTravelConflict,
  firstRestrictedEndpointConflict,
  firstRouteConflict,
  firestoreGeometry,
  firestoreRestrictionGeometry,
  normalizeGeometry,
  recordContainsPoint,
} = require('./service-area-policy');
const {
  DRIVER_VIOLATION_EVENT_CLASS,
  DRIVER_VIOLATION_STATUS,
  actorCanAccessDriverViolation,
  driverViolationContext,
  nextDriverViolationStatus,
  nextRestrictionObservation,
  normalizeDriverLocation,
  validIdentifier: validDriverViolationIdentifier,
} = require('./driver-violation-policy');
const {
  GOOGLE_ROUTES_FIELD_MASK,
  googleDrivingRouteRequest,
  googleHighwayRouteAdvisory,
} = require('./routes-policy');
const {
  bookingDriverServicePriority,
  compareDispatchClaims,
  driverDispatchStats,
  dispatchScoreSnapshot,
  nextDriverDispatchStats,
  selectDispatchBatch,
} = require('./dispatch-policy');
const {
  SAFETY_RESPONSE_STATUS,
  SOS_ACKNOWLEDGEMENT_MS,
  SOS_UNRESPONSIVE_MS,
  escalationLevel: safetyEscalationLevel,
  nextAdminResponseStatus,
  normalizedResponseStatus,
} = require('./safety-policy');
const {
  passwordResetEmail,
  safetyAlertEmail,
  sendBrevoEmail,
  todaApplicationEmail,
  validEmail,
  verificationEmail,
} = require('./brevo-communications');
const {
  GoServiceError,
  createGoServiceClient,
} = require('./go-service-client');
const { dispatchIndexUpdates } = require('./dispatch-spatial-index');
const { driverEarningsPeriodStarts } = require('./driver-earnings-periods');
const functionsEmulator = process.env.FUNCTIONS_EMULATOR === 'true';
const runtimeProjectId =
  process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || '';
if (functionsEmulator && runtimeProjectId !== 'demo-voltrike') {
  throw new Error(
    `Refusing local Functions against non-demo project: ${runtimeProjectId}`,
  );
}
admin.initializeApp(functionsEmulator ? {
  projectId: runtimeProjectId,
  databaseURL:
    'https://demo-voltrike-default-rtdb.firebaseio.com',
  storageBucket: 'demo-voltrike.appspot.com',
} : undefined);
const db = admin.firestore();
const realtime = admin.database();
const liveKitApiKey = defineSecret('LIVEKIT_API_KEY');
const liveKitApiSecret = defineSecret('LIVEKIT_API_SECRET');
const liveKitUrl = defineString('LIVEKIT_URL');
const adminBootstrapCode = defineSecret('ADMIN_BOOTSTRAP_CODE');
const googleRoutesApiKey = defineSecret('GOOGLE_ROUTES_API_KEY');
const goServiceUrl = defineString('GO_SERVICE_URL', { default: '' });
const goQuoteMode = defineString('GO_QUOTE_MODE', { default: 'off' });
const goDispatchMode = defineString('GO_DISPATCH_MODE', { default: 'off' });
const goLocalInternalKey = defineString('GO_LOCAL_INTERNAL_KEY', {
  default: '',
});
const goService = createGoServiceClient({
  baseUrl: () => goServiceUrl.value(),
  quoteMode: () => goQuoteMode.value(),
  dispatchMode: () => goDispatchMode.value(),
  localInternalKey: () => goLocalInternalKey.value(),
  emulator: functionsEmulator,
});

async function invalidateGoPolicyCache(reason) {
  if (!goService.quotesEnabled()) return;
  try {
    await goService.invalidatePolicy();
  } catch (error) {
    logger.warn('Go policy cache invalidation failed.', {
      reason,
      error: error?.message || String(error),
    });
  }
}
const brevoSmtpKey = defineSecret('BREVO_SMTP_KEY');
const brevoSmtpLogin = defineString('BREVO_SMTP_LOGIN', {
  default: 'a5cd23001@smtp-brevo.com',
});
const brevoSenderEmail = defineString('BREVO_SENDER_EMAIL', {
  default: 'noreply@voltrikeride.online',
});
const brevoSenderName = defineString('BREVO_SENDER_NAME', {
  default: 'VolTrike',
});
const adminPortalUrl = defineString('ADMIN_PORTAL_URL', {
  default: 'https://voltrike-v2.web.app',
});
const emailLogoUrl = defineString('EMAIL_LOGO_URL', {
  default: 'https://voltrike-v2.web.app/images/appLogo.png',
});
const bacolodBarangayCodes = new Set([
  '064501001', '064501002', '064501003', '064501004', '064501005', '064501006',
  '064501007', '064501008', '064501009', '064501010', '064501011', '064501012',
  '064501013', '064501014', '064501015', '064501016', '064501017', '064501018',
  '064501019', '064501020', '064501021', '064501022', '064501023', '064501024',
  '064501025', '064501026', '064501027', '064501028', '064501029', '064501030',
  '064501031', '064501032', '064501033', '064501034', '064501035', '064501036',
  '064501037', '064501038', '064501039', '064501040', '064501041', '064501042',
  '064501043', '064501044', '064501045', '064501046', '064501047', '064501048',
  '064501049', '064501050', '064501051', '064501052', '064501053', '064501054',
  '064501055', '064501056', '064501057', '064501058', '064501059', '064501060',
  '064501061',
]);

// The nationwide PSGC data is only needed while registering a TODA. Keeping
// this 10 MB dataset out of module startup lets Firebase discover functions
// promptly during deployment and cold starts.
let psgcData;
function getPsgcData() {
  if (!psgcData) {
    psgcData = {
      regions: require('./data/regionJson/regions.json'),
      cities: require('./data/regionJson/cities-municipalities.json'),
      barangays: require('./data/regionJson/barangays.json'),
    };
  }
  return psgcData;
}

function timestamp() {
  return FieldValue.serverTimestamp();
}

async function getAdminProfile(uid) {
  const snapshot = await db.collection('users').doc(uid).get();
  return snapshot.exists ? snapshot.data() : null;
}

async function requireAdmin(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in before using the admin panel.');
  }
  const profile = await getAdminProfile(request.auth.uid);
  if (!profile || profile.isActive === false ||
      !['developer_admin', 'toda_admin'].includes(profile.role)) {
    throw new HttpsError('permission-denied', 'An active administrator account is required.');
  }
  if (!adminIdentityMatches(profile, request.auth.token)) {
    throw new HttpsError(
      'permission-denied',
      'Administrator permissions changed. Sign out and sign in again.',
    );
  }
  if (profile.requiresEmailVerification === true &&
      request.auth.token.email_verified !== true) {
    throw new HttpsError(
      'permission-denied',
      'Verify the administrator email address before using the admin panel.',
    );
  }
  return { uid: request.auth.uid, ...profile };
}

async function requireDeveloperAdmin(request) {
  const profile = await requireAdmin(request);
  if (profile.role !== 'developer_admin') {
    throw new HttpsError('permission-denied', 'Developer administrator access is required.');
  }
  return profile;
}

function requiredString(value, name) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', `${name} is required.`);
  }
  return value.trim();
}

function validCurrency(value, name, min = 0, max = 9999) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
    throw new HttpsError('invalid-argument', `${name} must be between ${min} and ${max}.`);
  }
  return Math.round(value * 100) / 100;
}

function validPositiveInteger(value, name, min = 1, max = 9999) {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new HttpsError('invalid-argument', `${name} must be a whole number between ${min} and ${max}.`);
  }
  return value;
}

function validNonNegativeInteger(value, name, max = 9999) {
  if (!Number.isInteger(value) || value < 0 || value > max) {
    throw new HttpsError(
      'invalid-argument',
      `${name} must be a whole number between 0 and ${max}.`,
    );
  }
  return value;
}

function lifecycleIdentity(data) {
  const bookingId = data?.bookingId;
  const operationId = data?.operationId;
  if (!validBookingId(bookingId)) {
    throw new HttpsError('invalid-argument', 'A valid booking ID is required.');
  }
  if (!validOperationId(operationId)) {
    throw new HttpsError('invalid-argument', 'A valid operation ID is required.');
  }
  return { bookingId, operationId };
}

function operationReference(bookingId, uid, operationId) {
  return db.collection('bookingOperations')
    .doc(`${bookingId}_${uid}_${operationId}`);
}

function auditReference(bookingId, uid, operationId) {
  return db.collection('auditLogs')
    .doc(`booking_${bookingId}_${uid}_${operationId}`);
}

function parseCoordinate(value, name) {
  try {
    return normalizeCoordinate(value, name);
  } catch (error) {
    throw new HttpsError('invalid-argument', error.message);
  }
}

function snapshotDateMillis(value) {
  if (value != null && typeof value.toMillis === 'function') {
    const millis = value.toMillis();
    return Number.isFinite(millis) ? millis : null;
  }
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

function isAtLeast18(value, now = Date.now()) {
  const birthMillis = snapshotDateMillis(value);
  if (birthMillis == null) return false;
  const birth = new Date(birthMillis);
  const today = new Date(now);
  const eighteenthBirthday = new Date(
    birth.getUTCFullYear() + 18,
    birth.getUTCMonth(),
    birth.getUTCDate(),
  );
  return eighteenthBirthday.getTime() <= today.getTime();
}

async function trustedRoute(pickup, destination, restrictions = []) {
  const endpointConflict = firstRestrictedEndpointConflict(
    pickup,
    destination,
    restrictions,
  );
  if (endpointConflict) {
    throw new HttpsError(
      'failed-precondition',
      `E-trikes cannot pick up, drop off, or travel through ${
        endpointConflict.name || 'this restricted area'
      }. Move the pin outside the red boundary.`,
      {
        restrictionIds: endpointConflict.id ? [endpointConflict.id] : [],
        restrictionNames: endpointConflict.name
          ? [endpointConflict.name]
          : [],
      },
    );
  }
  // The demo project deliberately has no live Google credentials. Keep
  // lifecycle tests deterministic and isolated while production continues to
  // require the trusted Routes API.
  if (process.env.FUNCTIONS_EMULATOR === 'true' &&
      process.env.VOLTRIKE_USE_REAL_ROUTES_IN_EMULATOR !== 'true') {
    const straightLineMeters = distanceMeters(pickup, destination);
    const routeDistanceMeters = Math.max(
      1,
      Math.round(straightLineMeters * 1.2),
    );
    const routePoints = [pickup, destination];
    const conflict = firstRouteConflict(routePoints, restrictions);
    const highwayConflict = firstHighwayTravelConflict(routePoints, restrictions);
    if (conflict || highwayConflict) {
      const blocked = conflict || highwayConflict.restriction;
      throw new HttpsError(
        'failed-precondition',
        'No permitted e-trike route is available for this trip.',
        {
          restrictionIds: blocked.id ? [blocked.id] : [],
          restrictionNames: blocked.name ? [blocked.name] : [],
        },
      );
    }
    return {
      distanceMeters: routeDistanceMeters,
      duration: `${Math.max(60, Math.round(routeDistanceMeters / 6))}s`,
      encodedPolyline: null,
      avoidedRestrictionIds: [],
      avoidedRestrictionNames: [],
      highwayRouteAdvisory: {
        requestedAvoidHighways: true,
        provider: 'emulator',
        routeRestrictionsPartiallyIgnored: null,
        status: 'not_evaluated_emulator',
        confirmedViolation: false,
      },
      restrictionIdsChecked: restrictions
        .filter((restriction) => restriction.isActive !== false)
        .map((restriction) => restriction.id)
        .filter(Boolean),
    };
  }
  const response = await fetch(
    'https://routes.googleapis.com/directions/v2:computeRoutes',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': googleRoutesApiKey.value(),
        'X-Goog-FieldMask': GOOGLE_ROUTES_FIELD_MASK,
      },
      body: JSON.stringify(googleDrivingRouteRequest(
        pickup,
        destination,
      )),
    },
  );
  if (!response.ok) {
    logger.error('Trusted route lookup failed.', {
      status: response.status,
      body: (await response.text()).slice(0, 500),
    });
    throw new HttpsError(
      'unavailable',
      'The route could not be validated. Please try again.',
    );
  }
  const payload = await response.json();
  const routes = Array.isArray(payload.routes) ? payload.routes : [];
  let sawValidRoute = false;
  let advisoryFallback = null;
  const avoidedRestrictionIds = new Set();
  const avoidedRestrictionNames = new Set();
  for (const route of routes) {
    if (!Number.isInteger(route?.distanceMeters) ||
        route.distanceMeters <= 0) {
      continue;
    }
    const encodedPolyline = route.polyline?.encodedPolyline;
    if (typeof encodedPolyline !== 'string' ||
        encodedPolyline.length === 0) {
      continue;
    }
    let routePoints;
    try {
      routePoints = decodePolyline(encodedPolyline);
    } catch {
      continue;
    }
    if (routePoints.length < 2) continue;
    sawValidRoute = true;
    const conflict = firstRouteConflict(routePoints, restrictions);
    const highwayConflict = firstHighwayTravelConflict(routePoints, restrictions);
    const blocked = conflict || highwayConflict?.restriction;
    if (blocked) {
      if (blocked.id) avoidedRestrictionIds.add(blocked.id);
      if (blocked.name) avoidedRestrictionNames.add(blocked.name);
      continue;
    }
    const highwayRouteAdvisory = googleHighwayRouteAdvisory(route);
    const candidate = {
      distanceMeters: route.distanceMeters,
      duration: typeof route.duration === 'string' ? route.duration : null,
      encodedPolyline,
      avoidedRestrictionIds: [...avoidedRestrictionIds],
      avoidedRestrictionNames: [...avoidedRestrictionNames],
      restrictionIdsChecked: restrictions
        .filter((restriction) => restriction.isActive !== false)
        .map((restriction) => restriction.id)
        .filter(Boolean),
      // Google exposes a route-level advisory, not proof that the driver
      // entered or travelled along a legally prohibited Bacolod road.
      highwayRouteAdvisory,
    };
    if (!highwayRouteAdvisory.routeRestrictionsPartiallyIgnored) {
      return candidate;
    }
    advisoryFallback ??= candidate;
  }
  // Pilot policy: retain a usable polygon-safe route when Google says its
  // soft highway preference may have been ignored, but persist a strong,
  // explicitly unconfirmed advisory for both clients and operations.
  if (advisoryFallback) {
    return advisoryFallback;
  }
  if (sawValidRoute) {
    throw new HttpsError(
      'failed-precondition',
      'No permitted e-trike route is available for this trip.',
      {
        restrictionIds: [...avoidedRestrictionIds],
        restrictionNames: [...avoidedRestrictionNames],
      },
    );
  }
  if (routes.length === 0) {
    throw new HttpsError(
      'failed-precondition',
      'No valid driving route is available for these locations.',
    );
  }
  throw new HttpsError(
    'unavailable',
    'The returned route could not be validated. Please try again.',
  );
}

async function expireBookingOffers(bookingId, status) {
  const offers = await db.collectionGroup('bookingOffers')
    .where('bookingId', '==', bookingId)
    .limit(200)
    .get();
  if (offers.empty) return;
  const batch = db.batch();
  offers.docs.forEach((offer) => {
    batch.set(offer.ref, {
      status,
      updatedAt: timestamp(),
    }, { merge: true });
  });
  await batch.commit();
}

const dispatchRadiusMeters = 5000;
const driverLocationMaxAgeMs = 35000;
const dispatchBatchSize = 5;
const bookingSearchDurationMs = 60000;
// Keep offers inside the passenger's authoritative search lifetime. This
// leaves a small margin for timeout cancellation and offer cleanup.
const offerDurationMs = 55000;
const acceptanceWindowMs = 1500;
const acceptanceFinalizationGraceMs = 500;

function vehicleCanServeBooking(vehicle, booking) {
  const requiredSeats = Number(booking.additionalPassengers || 0) + 1;
  const capacity = Number(vehicle.capacity);
  if (!Number.isInteger(requiredSeats) || requiredSeats < 1 ||
      requiredSeats > 4 || !Number.isInteger(capacity) ||
      capacity < requiredSeats) {
    return false;
  }
  const type = String(
    vehicle.vehicleType ||
    vehicle.type ||
    vehicle.model ||
    vehicle.vehicleNumber ||
    '',
  )
    .trim()
    .toLowerCase()
    .replace(/[^a-z]/g, '');
  const electricTuktuk = type === 'electrictuktuk' ||
    type === 'etuktuk' ||
    type === 'electrictricycle';
  return requiredSeats <= 2 || electricTuktuk;
}

async function rankedDispatchDriversFromGo(booking) {
  const pickup = normalizeCoordinate(booking.pickup, 'Pickup');
  const response = await goService.dispatchCandidates({
    pickup,
    primaryTodaIds: Array.isArray(booking.primaryTodaIds)
      ? booking.primaryTodaIds
      : [],
    secondaryTodaIds: Array.isArray(booking.secondaryTodaIds)
      ? booking.secondaryTodaIds
      : [],
    allowAnyActiveToda: booking.allowAnyActiveToda === true,
    maximumResults: 100,
  });
  const excluded = new Set(
    Array.isArray(booking.offeredDriverIds) ? booking.offeredDriverIds : [],
  );
  const rawCandidates = Array.isArray(response?.candidates)
    ? response.candidates.filter((candidate) =>
      typeof candidate?.driverId === 'string' &&
      candidate.driverId.length > 0 &&
      Number.isInteger(candidate.distanceMeters) &&
      candidate.distanceMeters >= 0 &&
      candidate.distanceMeters <= dispatchRadiusMeters &&
      !excluded.has(candidate.driverId))
    : [];
  if (rawCandidates.length === 0) return [];
  const unique = [...new Map(
    rawCandidates.map((candidate) => [candidate.driverId, candidate]),
  ).values()];
  const driverSnapshots = await db.getAll(...unique.map((candidate) =>
    db.collection('drivers').doc(candidate.driverId)));
  const now = Date.now();
  const nearby = driverSnapshots.map((driver, index) => {
    if (!driver.exists) return null;
    const data = driver.data();
    if (data.driverStatus !== 'approved' || data.isOnline !== true ||
        data.isAvailable !== true || data.currentBookingId != null ||
        typeof data.todaId !== 'string' || data.todaId.trim().length === 0 ||
        typeof data.vehicleId !== 'string' ||
        data.vehicleId.trim().length === 0) {
      return null;
    }
    const servicePriority = bookingDriverServicePriority(booking, data.todaId);
    if (servicePriority == null) return null;
    const stats = driverDispatchStats(data, now);
    const dispatchScore = dispatchScoreSnapshot({
      driverId: driver.id,
      servicePriority,
      distanceMeters: unique[index].distanceMeters,
      dailyAwards: stats.dailyAwardCount,
      completedAssignments: stats.completedAssignments,
      driverFaultCancellations: stats.driverFaultCancellations,
      rating: data.rating,
      ratingCount: data.ratingCount,
    });
    return {
      driver,
      driverId: driver.id,
      distanceMeters: unique[index].distanceMeters,
      servicePriority,
      dailyAwards: dispatchScore.dailyAwards,
      reliabilityScore: dispatchScore.reliabilityScore,
      qualityScore: dispatchScore.qualityScore,
      dispatchScore,
    };
  }).filter(Boolean);
  if (nearby.length === 0) return [];
  const eligibility = await db.getAll(...nearby.flatMap(({ driver }) => [
    db.collection('users').doc(driver.id),
    db.collection('todas').doc(driver.data().todaId),
    db.collection('vehicles').doc(driver.data().vehicleId),
  ]));
  const eligible = nearby.filter(({ driver }, index) => {
    const user = eligibility[index * 3];
    const toda = eligibility[index * 3 + 1];
    const vehicle = eligibility[index * 3 + 2];
    const licenseExpiry = snapshotDateMillis(driver.data().licenseExpiry);
    return user.exists && user.data().isActive !== false &&
      user.data().role === 'driver' &&
      toda.exists && toda.data().isActive === true &&
      vehicle.exists && vehicle.data().isVerified === true &&
      vehicleCanServeBooking(vehicle.data(), booking) &&
      typeof driver.data().licenseNumber === 'string' &&
      driver.data().licenseNumber.trim().length > 0 &&
      licenseExpiry != null && licenseExpiry >= now;
  });
  eligible.sort(compareDispatchClaims);
  return eligible;
}

async function rankedDispatchDriversLegacy(booking) {
  const pickup = normalizeCoordinate(booking.pickup, 'Pickup');
  const [drivers, locations] = await Promise.all([
    db.collection('drivers')
      .where('driverStatus', '==', 'approved')
      .where('isOnline', '==', true)
      .where('isAvailable', '==', true)
      .limit(500)
      .get(),
    realtime.ref('driver_locations').get(),
  ]);
  const locationMap = locations.val() || {};
  const now = Date.now();
  const excluded = new Set(
    Array.isArray(booking.offeredDriverIds) ? booking.offeredDriverIds : [],
  );
  const nearby = drivers.docs.map((driver) => {
    const driverData = driver.data();
    if (typeof driverData.todaId !== 'string' ||
        driverData.todaId.trim().length === 0 ||
        typeof driverData.vehicleId !== 'string' ||
        driverData.vehicleId.trim().length === 0 ||
        driverData.currentBookingId != null) {
      return null;
    }
    const servicePriority =
      bookingDriverServicePriority(booking, driverData.todaId);
    if (servicePriority == null) return null;
    const location = locationMap[driver.id];
    if (!location || location.online !== true ||
        !Number.isFinite(Number(location.timestamp)) ||
        now - Number(location.timestamp) > driverLocationMaxAgeMs ||
        Number(location.timestamp) > now + 10000 ||
        !Number.isFinite(Number(location.accuracy)) ||
        Number(location.accuracy) > 100 ||
        excluded.has(driver.id)) {
      return null;
    }
    let point;
    try {
      point = normalizeCoordinate(location, 'Driver');
    } catch {
      return null;
    }
    const proximity = distanceMeters(pickup, point);
    if (proximity > dispatchRadiusMeters) return null;
    const distance = Math.round(proximity);
    const stats = driverDispatchStats(driverData, now);
    const dispatchScore = dispatchScoreSnapshot({
      driverId: driver.id,
      servicePriority,
      distanceMeters: distance,
      dailyAwards: stats.dailyAwardCount,
      completedAssignments: stats.completedAssignments,
      driverFaultCancellations: stats.driverFaultCancellations,
      rating: driverData.rating,
      ratingCount: driverData.ratingCount,
    });
    return {
      driver,
      driverId: driver.id,
      distanceMeters: distance,
      servicePriority,
      dailyAwards: dispatchScore.dailyAwards,
      reliabilityScore: dispatchScore.reliabilityScore,
      qualityScore: dispatchScore.qualityScore,
      dispatchScore,
    };
  }).filter(Boolean);

  if (nearby.length === 0) return [];
  const eligibilityRefs = nearby.flatMap(({ driver }) => [
    db.collection('users').doc(driver.id),
    db.collection('todas').doc(driver.data().todaId),
    db.collection('vehicles').doc(driver.data().vehicleId),
  ]);
  const eligibility = await db.getAll(...eligibilityRefs);
  const eligible = nearby.filter(({ driver }, index) => {
    const user = eligibility[index * 3];
    const toda = eligibility[index * 3 + 1];
    const vehicle = eligibility[index * 3 + 2];
    const licenseExpiry = snapshotDateMillis(driver.data().licenseExpiry);
    return user.exists && user.data().isActive !== false &&
      user.data().role === 'driver' &&
      toda.exists && toda.data().isActive === true &&
      vehicle.exists &&
      vehicle.data().isVerified === true &&
      vehicleCanServeBooking(vehicle.data(), booking) &&
      typeof driver.data().licenseNumber === 'string' &&
      driver.data().licenseNumber.trim().length > 0 &&
      licenseExpiry != null &&
      licenseExpiry >= now;
  });
  eligible.sort(compareDispatchClaims);
  return eligible;
}

async function rankedDispatchDrivers(booking) {
  if (!goService.dispatchEnabled()) {
    return rankedDispatchDriversLegacy(booking);
  }
  try {
    return await rankedDispatchDriversFromGo(booking);
  } catch (error) {
    logger.warn('Go dispatch lookup failed; using the legacy safety path.', {
      bookingId: booking.bookingId || null,
      error: error?.message || String(error),
    });
    return rankedDispatchDriversLegacy(booking);
  }
}

async function dispatchNextOfferBatch(bookingId) {
  const bookingRef = db.collection('bookings').doc(bookingId);
  const claimedBooking = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists || snapshot.data().status !== BOOKING_STATUS.pending) {
      return null;
    }
    const current = snapshot.data();
    const searchExpiresAt = snapshotDateMillis(current.searchExpiresAt);
    if (searchExpiresAt != null && searchExpiresAt <= Date.now()) return null;
    const nextDispatchAt = snapshotDateMillis(current.nextDispatchAt);
    if (nextDispatchAt != null && nextDispatchAt > Date.now()) return null;
    transaction.update(bookingRef, {
      nextDispatchAt: Timestamp.fromMillis(
        Date.now() + offerDurationMs,
      ),
      dispatchLeaseAt: timestamp(),
    });
    return current;
  });
  if (!claimedBooking) return 0;
  const booking = claimedBooking;

  const candidates = selectDispatchBatch(
    await rankedDispatchDrivers(booking),
    dispatchBatchSize,
  );
  const previousDrivers = Array.isArray(booking.offeredDriverIds)
    ? booking.offeredDriverIds
    : [];
  const expiresAt = Timestamp.fromMillis(
    Math.min(
      Date.now() + offerDurationMs,
      snapshotDateMillis(booking.searchExpiresAt) ??
        Date.now() + offerDurationMs,
    ),
  );
  const dispatchedCandidates = await db.runTransaction(
    async (transaction) => {
      const currentSnapshot = await transaction.get(bookingRef);
      if (!currentSnapshot.exists ||
          currentSnapshot.data().status !== BOOKING_STATUS.pending) {
        return [];
      }
      const current = currentSnapshot.data();
      const searchExpiresAt = snapshotDateMillis(current.searchExpiresAt);
      if (searchExpiresAt != null && searchExpiresAt <= Date.now()) return [];
      const offerRound = Number(current.offerRound || 0) + 1;
      previousDrivers.forEach((driverId) => {
        transaction.set(
          db.doc(`drivers/${driverId}/bookingOffers/${bookingId}`),
          { status: 'expired', updatedAt: timestamp() },
          { merge: true },
        );
      });
      candidates.forEach(({
        driver,
        distanceMeters: proximity,
        servicePriority,
        dailyAwards,
        reliabilityScore,
        qualityScore,
        dispatchScore,
      }, index) => {
        const zoneRevision = Number(
          booking.coverageDecision?.geofenceRevisions?.[
            driver.data().todaId
          ] ?? 0,
        );
        transaction.set(
          db.doc(`drivers/${driver.id}/bookingOffers/${bookingId}`),
          {
            bookingId,
            driverId: driver.id,
            todaId: driver.data().todaId,
            distanceMeters: proximity,
            servicePriority,
            serviceTier:
              Array.isArray(booking.primaryTodaIds) &&
              booking.primaryTodaIds.length > 0
                ? servicePriority === 0
                  ? 'primary'
                  : servicePriority === 1
                    ? 'secondary'
                    : 'fallback'
                : booking.coverageDecision?.configured === false
                  ? 'open'
                  : 'fallback',
            dailyAwards,
            reliabilityScore,
            qualityScore,
            dispatchScore,
            dispatchPolicyVersion: 3,
            dispatchRank: index + 1,
            zoneRevision:
              Number.isInteger(zoneRevision) && zoneRevision >= 0
                ? zoneRevision
                : 0,
            offerRound,
            status: 'offered',
            queueEnteredAt:
              booking.queueEnteredAt || booking.createdAt || timestamp(),
            bookingCreatedAt: booking.createdAt || timestamp(),
            createdAt: timestamp(),
            updatedAt: timestamp(),
            expiresAt,
          },
        );
      });
      const bookingUpdate = {
        offerRound,
        currentOfferDriverIds:
          candidates.map(({ driver }) => driver.id),
        lastOfferAt: timestamp(),
        nextDispatchAt: expiresAt,
        awardWindowEndsAt: null,
        awardWindowRound: null,
        updatedAt: timestamp(),
      };
      if (candidates.length > 0) {
        bookingUpdate.offeredDriverIds = FieldValue.arrayUnion(
          ...candidates.map(({ driver }) => driver.id),
        );
      }
      transaction.set(bookingRef, bookingUpdate, { merge: true });
      return candidates;
    },
  );
  await Promise.all(dispatchedCandidates
    .map(({ driver, distanceMeters: proximity }) =>
    sendToUser(
      driver.id,
      'New VolTrike booking',
      `A passenger ${proximity < 1000
        ? `${proximity} m`
        : `${(proximity / 1000).toFixed(1)} km`} away is requesting a ride.`,
      { bookingId, target: 'driver', type: 'booking_offer' },
    )));
  logger.info('Distance-ranked booking offers dispatched', {
    bookingId,
    count: dispatchedCandidates.length,
    radiusMeters: dispatchRadiusMeters,
    offerRound: Number(booking.offerRound || 0) + 1,
  });
  return dispatchedCandidates.length;
}

function slugify(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60);
}

function selectedPsgcLocation(data) {
  const { regions, cities, barangays } = getPsgcData();
  const regionCode = requiredString(data.regionCode, 'Region');
  const cityCode = requiredString(data.cityCode, 'City or municipality');
  const barangayCode = requiredString(data.barangayCode, 'Barangay');
  const region = regions.find((item) => item.code === regionCode);
  const city = cities.find((item) => item.code === cityCode && item.regionCode === regionCode);
  const barangay = barangays.find((item) => item.code === barangayCode &&
    item.regionCode === regionCode &&
    (item.cityCode === cityCode || item.municipalityCode === cityCode));
  if (!region || !city || !barangay) {
    throw new HttpsError('invalid-argument', 'Select a valid region, city or municipality, and barangay from the official list.');
  }
  return { region, city, barangay };
}

function normalizedTodaRegistration(registration) {
  return {
    secCertificateNumber: requiredString(registration?.secCertificateNumber, 'SEC certificate number'),
    spResolutionNumber: requiredString(registration?.spResolutionNumber, 'SP resolution number'),
    mayorsPermitNumber: requiredString(registration?.mayorsPermitNumber, "Mayor's permit number"),
    barangayClearanceNumber: requiredString(registration?.barangayClearanceNumber, 'Barangay clearance number'),
    presidentName: requiredString(registration?.presidentName, "President's name"),
    presidentLicenseNumber: requiredString(registration?.presidentLicenseNumber, "President's driver license"),
    presidentTin: requiredString(registration?.presidentTin, "President's TIN"),
  };
}

const todaDocumentKeys = [
  'secCertificate', 'spResolution', 'mayorsPermit', 'barangayClearance', 'presidentLicense',
];

function validTodaDocuments(todaId, documents) {
  if (!documents || typeof documents !== 'object' || Array.isArray(documents)) return false;
  const expectedPrefix = encodeURIComponent(`toda_documents/${todaId}/`);
  return todaDocumentKeys.every((key) =>
    typeof documents[key] === 'string' && documents[key].includes(expectedPrefix));
}

async function assertTodaScope(profile, todaId) {
  if (!canManageToda(profile, todaId)) {
    throw new HttpsError('permission-denied', 'This record is outside of your TODA.');
  }
}

function adminAudit(ref, {
  actor,
  action,
  targetType,
  targetId,
  details = {},
}) {
  return ref.set(adminAuditData({
    actor,
    action,
    targetType,
    targetId,
    details,
  }));
}

function adminAuditData({
  actor,
  action,
  targetType,
  targetId,
  details = {},
}) {
  return {
    type: 'admin_action',
    actorId: actor.uid,
    actorRole: actor.role,
    actorTodaId: actor.todaId || null,
    action,
    targetType,
    targetId,
    details,
    createdAt: timestamp(),
  };
}

async function activeDriverBooking(driverData) {
  const bookingId = driverData?.currentBookingId;
  if (typeof bookingId !== 'string' || bookingId.length === 0) return null;
  const booking = await db.collection('bookings').doc(bookingId).get();
  if (!booking.exists) return null;
  return [BOOKING_STATUS.completed, BOOKING_STATUS.cancelled]
    .includes(booking.data().status) ? null : booking;
}

async function sendToUser(userId, title, body, data) {
  const devices = await db.collection('users').doc(userId).collection('devices').get();
  const deviceTokens = devices.docs
    .map((doc) => ({ doc, token: doc.data().token }))
    .filter((entry) => typeof entry.token === 'string' && entry.token.length > 0);
  const tokens = deviceTokens.map((entry) => entry.token);
  if (tokens.length === 0) return { attempted: 0, succeeded: 0 };
  const type = data.type;
  const channelId = type === 'chat_message'
    ? 'chat_messages'
    : type === 'incoming_call'
      ? 'incoming_calls_v2'
      : type === 'safety_incident'
        ? 'safety_incidents'
        : ['driver_violation', 'driver_violation_message'].includes(type)
          ? 'driver_restriction_alerts_v1'
      : 'booking_updates';
  const sound = type === 'chat_message'
    ? 'chat_ringtone'
    : type === 'incoming_call'
      ? 'call_ringtone'
      : 'booking_ringtone';
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
    android: {
      priority: 'high',
      notification: { channelId, sound },
    },
  });
  await Promise.all(response.responses.map((result, index) => {
    if (!result.success && ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(result.error?.code)) {
      return deviceTokens[index].doc.ref.delete();
    }
    return null;
  }));
  return {
    attempted: tokens.length,
    succeeded: response.successCount,
  };
}

function adminWebPushToken(value) {
  if (typeof value !== 'string' ||
      value.length < 1 ||
      value.length > 4096 ||
      value.trim() !== value) {
    throw new HttpsError(
      'invalid-argument',
      'A valid Firebase web push token is required.',
    );
  }
  return value;
}

function optionalFirestoreDocumentId(value, name, maximumLength = 512) {
  if (value === undefined || value === null || value === '') return '';
  if (typeof value !== 'string' ||
      value.length > maximumLength ||
      value.includes('/')) {
    throw new HttpsError(
      'invalid-argument',
      `${name} is invalid.`,
    );
  }
  return value;
}

function adminWebPushDeviceId(token) {
  return createHash('sha256').update(token).digest('hex');
}

exports.registerAdminWebPushToken = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const token = adminWebPushToken(request.data?.token);
    const deviceId = adminWebPushDeviceId(token);
    const previousUid = optionalFirestoreDocumentId(
      request.data?.previousUid,
      'Previous administrator ID',
      128,
    );
    const previousDeviceId = optionalFirestoreDocumentId(
      request.data?.previousDeviceId,
      'Previous web push device ID',
    );
    if (previousDeviceId && !previousUid) {
      throw new HttpsError(
        'invalid-argument',
        'A previous administrator ID is required with a previous device ID.',
      );
    }

    const registryRef = db.collection('adminWebPushTokens').doc(deviceId);
    const currentDeviceRef = db.collection('users')
      .doc(actor.uid)
      .collection('devices')
      .doc(deviceId);
    const result = await db.runTransaction(async (transaction) => {
      const registry = await transaction.get(registryRef);
      const currentDevice = await transaction.get(currentDeviceRef);
      const registryOwnerUid = registry.exists &&
        typeof registry.data().ownerUid === 'string'
        ? registry.data().ownerUid
        : '';

      // A locally remembered previous UID is accepted only for the first
      // migration, before a trusted registry record exists. Once registered,
      // registry ownership is the sole source used for cross-account cleanup.
      let priorDeviceRef = null;
      if (registryOwnerUid && registryOwnerUid !== actor.uid) {
        priorDeviceRef = db.collection('users')
          .doc(registryOwnerUid)
          .collection('devices')
          .doc(deviceId);
      } else if (!registry.exists && previousUid) {
        priorDeviceRef = db.collection('users')
          .doc(previousUid)
          .collection('devices')
          .doc(previousDeviceId || deviceId);
      }
      if (priorDeviceRef?.path === currentDeviceRef.path) {
        priorDeviceRef = null;
      }
      const priorDevice = priorDeviceRef
        ? await transaction.get(priorDeviceRef)
        : null;

      let removedPreviousOwner = false;
      if (priorDevice?.exists && priorDevice.data().token === token) {
        transaction.delete(priorDevice.ref);
        removedPreviousOwner = true;
      }
      transaction.set(currentDeviceRef, {
        token,
        platform: 'web',
        managedBy: 'trusted_admin_callable',
        ownerUid: actor.uid,
        adminRole: actor.role,
        updatedAt: timestamp(),
        ...(!currentDevice.exists ? { createdAt: timestamp() } : {}),
      }, { merge: true });
      transaction.set(registryRef, {
        schemaVersion: 1,
        tokenHash: deviceId,
        ownerUid: actor.uid,
        ownerRole: actor.role,
        ownerTodaId: actor.todaId || null,
        updatedAt: timestamp(),
        ...(!registry.exists ? { createdAt: timestamp() } : {}),
      }, { merge: true });
      return {
        previousOwnerUid: registryOwnerUid ||
          (!registry.exists ? previousUid : ''),
        removedPreviousOwner,
      };
    });
    await adminAudit(db.collection('auditLogs').doc(), {
      actor,
      action: 'register_admin_web_push_token',
      targetType: 'adminWebPushToken',
      targetId: deviceId,
      details: {
        migratedFromPreviousAccount: result.removedPreviousOwner,
        previousOwnerUid: result.previousOwnerUid || null,
      },
    });
    return { registered: true, deviceId };
  },
);

exports.unregisterAdminWebPushToken = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const token = adminWebPushToken(request.data?.token);
    const deviceId = adminWebPushDeviceId(token);
    const requestedDeviceId = optionalFirestoreDocumentId(
      request.data?.deviceId,
      'Web push device ID',
    );
    if (requestedDeviceId && requestedDeviceId !== deviceId) {
      throw new HttpsError(
        'invalid-argument',
        'The web push token does not match the device ID.',
      );
    }

    const registryRef = db.collection('adminWebPushTokens').doc(deviceId);
    const currentDeviceRef = db.collection('users')
      .doc(actor.uid)
      .collection('devices')
      .doc(deviceId);
    const unregistered = await db.runTransaction(async (transaction) => {
      const [registry, currentDevice] = await Promise.all([
        transaction.get(registryRef),
        transaction.get(currentDeviceRef),
      ]);
      const registryOwned = registry.exists &&
        registry.data().ownerUid === actor.uid;
      const currentOwned = currentDevice.exists &&
        currentDevice.data().token === token &&
        (!currentDevice.data().ownerUid ||
          currentDevice.data().ownerUid === actor.uid);
      if (!registryOwned || !currentOwned) return false;
      transaction.delete(currentDeviceRef);
      transaction.delete(registryRef);
      return true;
    });
    if (unregistered) {
      await adminAudit(db.collection('auditLogs').doc(), {
        actor,
        action: 'unregister_admin_web_push_token',
        targetType: 'adminWebPushToken',
        targetId: deviceId,
      });
    }
    return { unregistered, deviceId };
  },
);

async function safetyAdminRecipients(todaId) {
  const [developers, todaCandidates] = await Promise.all([
    db.collection('users')
      .where('role', '==', 'developer_admin')
      .limit(100)
      .get(),
    todaId
      ? db.collection('users').where('todaId', '==', todaId).limit(100).get()
      : Promise.resolve({ docs: [] }),
  ]);
  const recipients = new Map();
  for (const entry of [...developers.docs, ...todaCandidates.docs]) {
    const data = entry.data();
    if (data.isActive === false ||
        !['developer_admin', 'toda_admin'].includes(data.role) ||
        (data.role === 'toda_admin' && data.todaId !== todaId)) {
      continue;
    }
    let email = data.safetyContactEmail || data.email || '';
    if (!validEmail(email)) {
      const authUser = await admin.auth().getUser(entry.id).catch(() => null);
      email = authUser?.email || '';
    }
    recipients.set(entry.id, {
      uid: entry.id,
      name: [data.firstName, data.lastName].filter(Boolean).join(' ') ||
        'Administrator',
      email,
      emailEnabled: data.safetyEmailEnabled !== false,
    });
  }
  return [...recipients.values()];
}

function communicationDeliveryId({
  incidentId,
  recipientId,
  channel,
  stage,
}) {
  return createHash('sha256')
    .update(`${incidentId}:${recipientId}:${channel}:${stage}`)
    .digest('hex');
}

async function deliverSafetyCommunication({
  recipient,
  channel,
  provider,
  stage,
  incidentId,
  bookingId,
  send,
}) {
  const deliveryId = communicationDeliveryId({
    incidentId,
    recipientId: recipient.uid,
    channel,
    stage,
  });
  const deliveryRef = db.collection('communicationDeliveries').doc(deliveryId);
  const claimed = await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(deliveryRef);
    if (existing.exists) return false;
    transaction.create(deliveryRef, {
      deliveryId,
      incidentId,
      bookingId,
      recipientId: recipient.uid,
      channel,
      stage,
      purpose: 'administrator_safety_alert',
      status: 'sending',
      createdAt: timestamp(),
      updatedAt: timestamp(),
    });
    return true;
  });
  if (!claimed) return { deduplicated: true, sent: false };
  try {
    const response = await send();
    await deliveryRef.update({
      status: 'accepted',
      provider,
      providerMessageId: String(
        response?.messageId ||
        response?.messageIds?.[0] ||
        response?.[0]?.message_id ||
        '',
      ),
      acceptedAt: timestamp(),
      updatedAt: timestamp(),
    });
    return { deduplicated: false, sent: true };
  } catch (error) {
    await deliveryRef.update({
      status: 'failed',
      errorCode: String(error?.status || error?.code || 'provider_error'),
      failedAt: timestamp(),
      updatedAt: timestamp(),
    });
    logger.error('Could not deliver administrator safety communication', {
      incidentId,
      recipientId: recipient.uid,
      channel,
      provider,
      stage,
      error,
    });
    return { deduplicated: false, sent: false };
  }
}

async function notifySafetyAdmins({
  incidentId,
  bookingId,
  todaId,
  title,
  body,
  escalationLevel = 0,
  stage = 'initial',
  incident = {},
}) {
  const recipients = await safetyAdminRecipients(todaId);
  const pushDeliveries = await Promise.all(recipients.map((recipient) =>
    sendToUser(recipient.uid, title, body, {
      type: 'safety_incident',
      incidentId,
      bookingId,
      escalationLevel,
    }).catch((error) => {
      logger.error('Could not deliver an SOS administrator notification', {
        incidentId,
        userId: recipient.uid,
        error,
      });
      return { attempted: 0, succeeded: 0 };
  })));
  const smtpKey = brevoSmtpKey.value();
  const emailDeliveries = await Promise.all(recipients.map((recipient) => {
    if (recipient.emailEnabled && validEmail(recipient.email)) {
      const message = safetyAlertEmail({
        recipientName: recipient.name,
        eventLabel: title,
        adminPortalUrl: adminPortalUrl.value(),
        logoUrl: emailLogoUrl.value(),
        incident: {
          ...incident,
          bookingId,
          escalationLevel,
        },
      });
      return deliverSafetyCommunication({
        recipient,
        channel: 'email',
        provider: 'brevo',
        stage,
        incidentId,
        bookingId,
        send: () => sendBrevoEmail({
          smtpLogin: brevoSmtpLogin.value(),
          smtpKey,
          senderEmail: brevoSenderEmail.value(),
          senderName: brevoSenderName.value(),
          to: recipient.email,
          name: recipient.name,
          ...message,
        }),
      });
    }
    return { deduplicated: false, sent: false };
  }));
  const pushSummary = pushDeliveries.reduce((summary, delivery) => ({
    recipients: summary.recipients + 1,
    attempted: summary.attempted + delivery.attempted,
    succeeded: summary.succeeded + delivery.succeeded,
  }), { recipients: 0, attempted: 0, succeeded: 0 });
  return {
    ...pushSummary,
    emailSent: emailDeliveries.filter((entry) => entry.sent).length,
    emailDeduplicated: emailDeliveries
      .filter((entry) => entry.deduplicated).length,
  };
}

exports.notifyRideChatMessage = onDocumentCreated(
  'chat/{bookingId}/messages/{messageId}',
  async (event) => {
    const message = event.data?.data();
    if (!message?.senderId || typeof message.text !== 'string') return;
    const bookingId = event.params.bookingId;
    const booking = await db.collection('bookings').doc(bookingId).get();
    if (!booking.exists) return;
    const data = booking.data();
    const recipient = data.passengerId === message.senderId
      ? data.driverId
      : data.passengerId;
    if (!recipient) return;
    await sendToUser(
      recipient,
      'New ride message',
      message.text.slice(0, 120),
      { bookingId, type: 'chat_message' },
    );
  },
);

exports.requestBrandedVerificationEmail = onCall(
  { region: 'asia-southeast1', secrets: [brevoSmtpKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'Sign in before requesting email verification.',
      );
    }
    const authUser = await admin.auth().getUser(request.auth.uid);
    if (!authUser.email || !validEmail(authUser.email)) {
      throw new HttpsError(
        'failed-precondition',
        'The account does not have a valid email address.',
      );
    }
    if (authUser.emailVerified) return { sent: false, alreadyVerified: true };
    const userRef = db.collection('users').doc(request.auth.uid);
    const now = Date.now();
    await db.runTransaction(async (transaction) => {
      const profile = await transaction.get(userRef);
      const lastSent = snapshotDateMillis(
        profile.data()?.verificationEmailRequestedAt,
      );
      if (lastSent != null && now - lastSent < 60 * 1000) {
        throw new HttpsError(
          'resource-exhausted',
          'Wait one minute before requesting another verification email.',
        );
      }
      transaction.set(userRef, {
        verificationEmailRequestedAt: timestamp(),
        updatedAt: timestamp(),
      }, { merge: true });
    });
    const profile = await userRef.get();
    const profileData = profile.data() || {};
    const name = [
      profileData.firstName,
      profileData.middleName,
      profileData.lastName,
    ].filter(Boolean).join(' ') || authUser.displayName || 'VolTrike user';
    const verificationLink = await admin.auth()
      .generateEmailVerificationLink(authUser.email);
    const message = verificationEmail({
      name,
      verificationLink,
      logoUrl: emailLogoUrl.value(),
    });
    try {
      const response = await sendBrevoEmail({
        smtpLogin: brevoSmtpLogin.value(),
        smtpKey: brevoSmtpKey.value(),
        senderEmail: brevoSenderEmail.value(),
        senderName: brevoSenderName.value(),
        to: authUser.email,
        name,
        ...message,
      });
      await db.collection('communicationDeliveries').add({
        recipientId: request.auth.uid,
        channel: 'email',
        purpose: 'account_verification',
        status: 'accepted',
        provider: 'brevo',
        providerMessageId: String(response?.messageId || ''),
        acceptedAt: timestamp(),
        createdAt: timestamp(),
        updatedAt: timestamp(),
      });
      return { sent: true, alreadyVerified: false };
    } catch (error) {
      await userRef.set({
        verificationEmailLastFailureAt: timestamp(),
        updatedAt: timestamp(),
      }, { merge: true });
      logger.error('Could not send branded verification email', {
        uid: request.auth.uid,
        error,
      });
      throw new HttpsError(
        'unavailable',
        'The branded verification email is temporarily unavailable.',
      );
    }
  },
);

exports.requestBrandedPasswordResetEmail = onCall(
  { region: 'asia-southeast1', secrets: [brevoSmtpKey] },
  async (request) => {
    const email = requiredString(request.data?.email, 'Email').toLowerCase();
    if (!validEmail(email)) {
      throw new HttpsError(
        'invalid-argument',
        'Enter a valid email address.',
      );
    }

    // The hash prevents storing an unauthenticated email address in the rate
    // limiter. A one-minute cooldown and five-per-day ceiling prevent a reset
    // form from becoming an email-spam relay.
    const emailHash = createHash('sha256').update(email).digest('hex');
    const rateRef = db.collection('communicationRateLimits')
      .doc(`password-reset-${emailHash}`);
    const now = Date.now();
    const allowed = await db.runTransaction(async (transaction) => {
      const current = await transaction.get(rateRef);
      const data = current.data() || {};
      const lastRequestedAt = snapshotDateMillis(data.lastRequestedAt);
      const windowStartedAt = snapshotDateMillis(data.windowStartedAt);
      const withinWindow = windowStartedAt != null &&
        now - windowStartedAt < 24 * 60 * 60 * 1000;
      const requestCount = withinWindow
        ? Number(data.requestCount || 0)
        : 0;
      if ((lastRequestedAt != null && now - lastRequestedAt < 60 * 1000) ||
          requestCount >= 5) {
        return false;
      }
      transaction.set(rateRef, {
        purpose: 'password_reset',
        emailHash,
        lastRequestedAt: Timestamp.fromMillis(now),
        windowStartedAt: withinWindow
          ? data.windowStartedAt
          : Timestamp.fromMillis(now),
        requestCount: requestCount + 1,
        updatedAt: Timestamp.fromMillis(now),
      }, { merge: true });
      return true;
    });
    if (!allowed) return { accepted: true };

    // Never reveal whether an account exists. The app receives the same result
    // for unknown addresses, rate-limited requests, and accepted deliveries.
    const authUser = await admin.auth().getUserByEmail(email)
      .catch((error) => {
        if (error?.code === 'auth/user-not-found') return null;
        throw error;
      });
    if (!authUser) return { accepted: true };

    try {
      const profile = await db.collection('users').doc(authUser.uid).get();
      const profileData = profile.data() || {};
      const name = [
        profileData.firstName,
        profileData.middleName,
        profileData.lastName,
      ].filter(Boolean).join(' ') ||
        authUser.displayName ||
        'VolTrike user';
      const resetLink = await admin.auth().generatePasswordResetLink(email);
      const message = passwordResetEmail({
        name,
        resetLink,
        logoUrl: emailLogoUrl.value(),
      });
      const response = await sendBrevoEmail({
        smtpLogin: brevoSmtpLogin.value(),
        smtpKey: brevoSmtpKey.value(),
        senderEmail: brevoSenderEmail.value(),
        senderName: brevoSenderName.value(),
        to: email,
        name,
        ...message,
      });
      await db.collection('communicationDeliveries').add({
        recipientId: authUser.uid,
        recipientEmailHash: emailHash,
        channel: 'email',
        purpose: 'password_reset',
        status: 'accepted',
        provider: 'brevo_smtp',
        providerMessageId: String(response?.messageId || ''),
        acceptedAt: timestamp(),
        createdAt: timestamp(),
        updatedAt: timestamp(),
      });
    } catch (error) {
      logger.error('Could not send branded password reset email', {
        uid: authUser.uid,
        emailHash,
        error,
      });
      await db.collection('communicationDeliveries').add({
        recipientId: authUser.uid,
        recipientEmailHash: emailHash,
        channel: 'email',
        purpose: 'password_reset',
        status: 'failed',
        provider: 'brevo_smtp',
        errorCode: String(error?.code || 'provider_error'),
        failedAt: timestamp(),
        createdAt: timestamp(),
        updatedAt: timestamp(),
      });
    }
    return { accepted: true };
  },
);

async function sendTodaRegistrationStatusEmail({
  todaId,
  status,
  application,
}) {
  const adminUid = application.adminUid;
  if (!adminUid) return;
  const deliveryId = createHash('sha256')
    .update(`toda-registration:${todaId}:${adminUid}:${status}`)
    .digest('hex');
  const deliveryRef = db.collection('communicationDeliveries').doc(deliveryId);
  const claimed = await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(deliveryRef);
    if (existing.exists) return false;
    transaction.create(deliveryRef, {
      deliveryId,
      recipientId: adminUid,
      todaId,
      channel: 'email',
      purpose: 'toda_registration_status',
      stage: status,
      status: 'sending',
      createdAt: timestamp(),
      updatedAt: timestamp(),
    });
    return true;
  });
  if (!claimed) return;
  try {
    const [authUser, profile, toda] = await Promise.all([
      admin.auth().getUser(adminUid),
      db.collection('users').doc(adminUid).get(),
      db.collection('todas').doc(todaId).get(),
    ]);
    if (!authUser.email || !validEmail(authUser.email)) {
      throw new Error('The TODA administrator email is invalid.');
    }
    const data = profile.data() || {};
    const name = [data.firstName, data.lastName].filter(Boolean).join(' ') ||
      authUser.displayName || 'Administrator';
    const message = todaApplicationEmail({
      administratorName: name,
      todaName: toda.data()?.name || todaId,
      status,
      adminPortalUrl: adminPortalUrl.value(),
      logoUrl: emailLogoUrl.value(),
    });
    const response = await sendBrevoEmail({
      smtpLogin: brevoSmtpLogin.value(),
      smtpKey: brevoSmtpKey.value(),
      senderEmail: brevoSenderEmail.value(),
      senderName: brevoSenderName.value(),
      to: authUser.email,
      name,
      ...message,
    });
    await deliveryRef.update({
      status: 'accepted',
      provider: 'brevo',
      providerMessageId: String(response?.messageId || ''),
      acceptedAt: timestamp(),
      updatedAt: timestamp(),
    });
  } catch (error) {
    await deliveryRef.update({
      status: 'failed',
      errorCode: String(error?.status || error?.code || 'provider_error'),
      failedAt: timestamp(),
      updatedAt: timestamp(),
    });
    logger.error('Could not send TODA registration status email', {
      todaId,
      status,
      error,
    });
  }
}

exports.notifyTodaRegistrationSubmitted = onDocumentCreated(
  {
    document: 'todaApplications/{todaId}',
    region: 'asia-southeast1',
    secrets: [brevoSmtpKey],
  },
  async (event) => {
    const application = event.data?.data();
    if (!application || application.status !== 'pending') return;
    await sendTodaRegistrationStatusEmail({
      todaId: event.params.todaId,
      status: 'submitted',
      application,
    });
  },
);

exports.notifyTodaRegistrationDecision = onDocumentUpdated(
  {
    document: 'todaApplications/{todaId}',
    region: 'asia-southeast1',
    secrets: [brevoSmtpKey],
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after || before?.status === after.status ||
        !['approved', 'declined'].includes(after.status)) {
      return;
    }
    await sendTodaRegistrationStatusEmail({
      todaId: event.params.todaId,
      status: after.status,
      application: after,
    });
  },
);

// One-time setup for the first developer administrator. The bootstrap code is
// a Secret Manager value, never exposed to the browser bundle. Once a
// developer admin exists, this callable permanently rejects further use.
exports.bootstrapDeveloperAdmin = onCall(
  { region: 'asia-southeast1', secrets: [adminBootstrapCode] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before setup.');
    }
    if (request.data?.code !== adminBootstrapCode.value()) {
      throw new HttpsError('permission-denied', 'The bootstrap code is invalid.');
    }
    const existing = await db.collection('users').where('role', '==', 'developer_admin').limit(1).get();
    if (!existing.empty) {
      throw new HttpsError('failed-precondition', 'A developer administrator already exists.');
    }
    const user = await admin.auth().getUser(request.auth.uid);
    await admin.auth().setCustomUserClaims(request.auth.uid, { adminRole: 'developer_admin' });
    await db.collection('users').doc(request.auth.uid).set({
      uid: request.auth.uid,
      email: user.email || '',
      firstName: user.displayName || 'Developer',
      middleName: '',
      lastName: 'Admin',
      phoneNumber: user.phoneNumber || '',
      role: 'developer_admin',
      todaId: null,
      profileImage: user.photoURL || '',
      emailVerified: user.emailVerified,
      isActive: true,
      createdAt: timestamp(),
      updatedAt: timestamp(),
    }, { merge: true });
    return { role: 'developer_admin' };
  },
);

exports.adminCreateToda = onCall({ region: 'asia-southeast1' }, async (request) => {
  await requireDeveloperAdmin(request);
  const data = request.data || {};
  const name = requiredString(data.name, 'TODA name');
  const barangayCode = requiredString(data.barangayCode, 'Barangay');
  if (!bacolodBarangayCodes.has(barangayCode)) {
    throw new HttpsError('invalid-argument', 'Select an official Bacolod barangay.');
  }
  const normalizedRegistration = normalizedTodaRegistration(data.registration);
  const id = `${slugify(name)}-${Date.now().toString(36)}`;
  const batch = db.batch();
  batch.set(db.collection('todas').doc(id), {
    id, name, barangayCode, regionCode: '06', provinceCode: 'NEG', cityCode: 'BACOLOD',
    isActive: true, adminUid: null,
    createdAt: timestamp(), updatedAt: timestamp(),
  });
  batch.set(db.collection('todaApplications').doc(id), {
    todaId: id, registration: normalizedRegistration, documents: {}, status: 'approved',
    createdAt: timestamp(), updatedAt: timestamp(),
  });
  await batch.commit();
  return { todaId: id };
});

// TODA administrators create their own pending application. No privileged
// claim is issued until a developer administrator explicitly approves it.
exports.registerToda = onCall({ region: 'asia-southeast1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in before registering a TODA.');
  const data = request.data || {};
  const name = requiredString(data.name, 'TODA name');
  const { region, city, barangay } = selectedPsgcLocation(data);
  const registration = normalizedTodaRegistration(data.registration);
  const userRef = db.collection('users').doc(request.auth.uid);
  const existing = await userRef.get();
  if (existing.exists && ['developer_admin', 'toda_admin'].includes(existing.data().role)) {
    throw new HttpsError('failed-precondition', 'This account already has administrator access.');
  }
  const id = `${slugify(name)}-${Date.now().toString(36)}`;
  const user = await admin.auth().getUser(request.auth.uid);
  const batch = db.batch();
  batch.set(db.collection('todas').doc(id), {
    id, name, adminUid: request.auth.uid, isActive: false, status: 'pending',
    regionCode: region.code, regionName: region.name,
    cityCode: city.code, cityName: city.name,
    barangayCode: barangay.code, barangayName: barangay.name,
    createdAt: timestamp(), updatedAt: timestamp(),
  });
  batch.set(db.collection('todaApplications').doc(id), {
    todaId: id, adminUid: request.auth.uid, registration, documents: {}, status: 'pending',
    createdAt: timestamp(), updatedAt: timestamp(),
  });
  batch.set(userRef, {
    uid: request.auth.uid, email: user.email || '', role: 'toda_admin_pending', todaId: id,
    safetyContactEmail: user.email || '',
    safetyEmailEnabled: true,
    requiresEmailVerification: true,
    isActive: true, todaApplicationStatus: 'pending', createdAt: timestamp(), updatedAt: timestamp(),
  }, { merge: true });
  await batch.commit();
  return { todaId: id };
});

exports.adminReviewTodaRegistration = onCall({ region: 'asia-southeast1' }, async (request) => {
  const developer = await requireDeveloperAdmin(request);
  const todaId = requiredString(request.data?.todaId, 'TODA ID');
  const status = request.data?.status;
  if (!['approved', 'declined'].includes(status)) throw new HttpsError('invalid-argument', 'Unsupported TODA decision.');
  const todaRef = db.collection('todas').doc(todaId);
  const toda = await todaRef.get();
  if (!toda.exists || toda.data().status !== 'pending') throw new HttpsError('failed-precondition', 'A pending TODA application is required.');
  const applicationRef = db.collection('todaApplications').doc(todaId);
  const application = await applicationRef.get();
  if (status === 'approved' &&
      (!application.exists || !application.data().registration || !validTodaDocuments(todaId, application.data().documents))) {
    throw new HttpsError('failed-precondition', 'The TODA must provide all legal registration details and five evidence files before approval.');
  }
  const uid = toda.data().adminUid;
  if (status === 'approved') {
    await admin.auth().setCustomUserClaims(uid, { adminRole: 'toda_admin', todaId });
    const batch = db.batch();
    batch.update(todaRef, { status: 'approved', isActive: true, approvedBy: developer.uid, approvedAt: timestamp(), updatedAt: timestamp() });
    batch.set(applicationRef, { status: 'approved', reviewedBy: developer.uid, reviewedAt: timestamp(), updatedAt: timestamp() }, { merge: true });
    batch.set(db.collection('users').doc(uid), { role: 'toda_admin', todaId, isActive: true, todaApplicationStatus: 'approved', updatedAt: timestamp() }, { merge: true });
    batch.create(db.collection('auditLogs').doc(), {
      type: 'admin_action', actorId: developer.uid, actorRole: developer.role,
      action: 'approve_toda', targetType: 'toda', targetId: todaId,
      createdAt: timestamp(),
    });
    await batch.commit();
    await admin.auth().revokeRefreshTokens(uid);
  } else {
    await admin.auth().setCustomUserClaims(uid, null);
    const batch = db.batch();
    batch.update(todaRef, { status: 'declined', isActive: false, reviewedBy: developer.uid, reviewedAt: timestamp(), updatedAt: timestamp() });
    batch.set(applicationRef, { status: 'declined', reviewedBy: developer.uid, reviewedAt: timestamp(), updatedAt: timestamp() }, { merge: true });
    batch.set(db.collection('users').doc(uid), { role: 'toda_admin_pending', todaId, todaApplicationStatus: 'declined', updatedAt: timestamp() }, { merge: true });
    batch.create(db.collection('auditLogs').doc(), {
      type: 'admin_action', actorId: developer.uid, actorRole: developer.role,
      action: 'decline_toda', targetType: 'toda', targetId: todaId,
      createdAt: timestamp(),
    });
    await batch.commit();
    await admin.auth().revokeRefreshTokens(uid);
  }
  return { updated: true };
});

// Promotion intentionally suspends the former driver's operating profile.
// The account becomes a TODA-admin identity and cannot take rides until a
// developer deliberately restores it as a driver.
exports.adminAssignTodaAdmin = onCall({ region: 'asia-southeast1' }, async (request) => {
  const developer = await requireDeveloperAdmin(request);
  const uid = requiredString(request.data?.uid, 'User ID');
  const todaId = requiredString(request.data?.todaId, 'TODA ID');
  const [user, toda] = await Promise.all([
    admin.auth().getUser(uid), db.collection('todas').doc(todaId).get(),
  ]);
  if (!toda.exists || toda.data().isActive === false) {
    throw new HttpsError('not-found', 'An active TODA is required.');
  }
  const driver = db.collection('drivers').doc(uid);
  const driverSnapshot = await driver.get();
  if (driverSnapshot.exists &&
      await activeDriverBooking(driverSnapshot.data())) {
    throw new HttpsError(
      'failed-precondition',
      'Complete or cancel the active ride before promoting this driver.',
    );
  }
  await admin.auth().setCustomUserClaims(uid, { adminRole: 'toda_admin', todaId });
  const batch = db.batch();
  batch.set(db.collection('users').doc(uid), {
    uid, email: user.email || '', role: 'toda_admin', todaId, isActive: true,
    updatedAt: timestamp(),
  }, { merge: true });
  batch.update(toda.ref, { adminUid: uid, updatedAt: timestamp() });
  if (driverSnapshot.exists) {
    batch.update(driver, { driverStatus: 'suspended', isOnline: false, isAvailable: false, updatedAt: timestamp() });
  }
  batch.create(db.collection('auditLogs').doc(), {
    type: 'admin_action', actorId: developer.uid, actorRole: developer.role,
    action: 'assign_toda_admin', targetType: 'user', targetId: uid,
    details: { todaId }, createdAt: timestamp(),
  });
  await batch.commit();
  await admin.auth().revokeRefreshTokens(uid);
  logger.info('TODA administrator assigned', { uid, todaId, by: developer.uid });
  return { assigned: true };
});

exports.adminSetTodaStatus = onCall({ region: 'asia-southeast1' }, async (request) => {
  const developer = await requireDeveloperAdmin(request);
  const todaId = requiredString(request.data?.todaId, 'TODA ID');
  if (typeof request.data?.isActive !== 'boolean') {
    throw new HttpsError('invalid-argument', 'TODA status is required.');
  }
  const ref = db.collection('todas').doc(todaId);
  if (!(await ref.get()).exists) throw new HttpsError('not-found', 'TODA not found.');
  if (!request.data.isActive) {
    const drivers = await db.collection('drivers').where('todaId', '==', todaId).get();
    const activeChecks = await Promise.all(
      drivers.docs.map((driver) => activeDriverBooking(driver.data())),
    );
    if (activeChecks.some(Boolean)) {
      throw new HttpsError(
        'failed-precondition',
        'This TODA has an active ride. Suspend it after all active rides finish.',
      );
    }
    const geofenceRef = db.collection('geofences').doc(todaId);
    await Promise.all([
      ref.update({ isActive: false, updatedAt: timestamp() }),
      geofenceRef.get().then((geofence) => geofence.exists
        ? geofenceRef.set({
          isActive: false,
          updatedAt: timestamp(),
        }, { merge: true })
        : null),
    ]);
    const writer = db.bulkWriter();
    drivers.docs.forEach((driver) => writer.update(driver.ref, { driverStatus: 'suspended', isOnline: false, isAvailable: false, updatedAt: timestamp() }));
    await writer.close();
  } else {
    // Restoring a TODA never restores individually suspended drivers.
    const geofenceRef = db.collection('geofences').doc(todaId);
    await Promise.all([
      ref.update({ isActive: true, updatedAt: timestamp() }),
      geofenceRef.get().then((geofence) => geofence.exists
        ? geofenceRef.set({
          isActive: true,
          updatedAt: timestamp(),
        }, { merge: true })
        : null),
    ]);
  }
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: developer,
    action: request.data.isActive ? 'restore_toda' : 'suspend_toda',
    targetType: 'toda',
    targetId: todaId,
  });
  await invalidateGoPolicyCache('toda_status_changed');
  return { updated: true };
});

exports.adminAttachTodaDocuments = onCall({ region: 'asia-southeast1' }, async (request) => {
  await requireDeveloperAdmin(request);
  const todaId = requiredString(request.data?.todaId, 'TODA ID');
  const documents = request.data?.documents;
  if (!validTodaDocuments(todaId, documents)) throw new HttpsError('invalid-argument', 'All TODA documents must use their secure TODA document location.');
  await db.collection('todaApplications').doc(todaId).set({ todaId, documents, updatedAt: timestamp() }, { merge: true });
  return { updated: true };
});

// A pending TODA applicant can upload their own legal evidence, but cannot
// inspect other TODAs or change approval state.
exports.attachTodaRegistrationDocuments = onCall({ region: 'asia-southeast1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in before uploading TODA documents.');
  const todaId = requiredString(request.data?.todaId, 'TODA ID');
  const documents = request.data?.documents;
  const applicationRef = db.collection('todaApplications').doc(todaId);
  const application = await applicationRef.get();
  if (!application.exists || application.data().adminUid !== request.auth.uid || application.data().status !== 'pending') {
    throw new HttpsError('permission-denied', 'Only the pending TODA applicant can attach these documents.');
  }
  if (!validTodaDocuments(todaId, documents)) throw new HttpsError('invalid-argument', 'Upload all required TODA evidence files.');
  await applicationRef.update({ documents, updatedAt: timestamp() });
  return { updated: true };
});

exports.adminUpdateFare = onCall({ region: 'asia-southeast1' }, async (request) => {
  const developer = await requireDeveloperAdmin(request);
  const fare = request.data?.fare || {};
  const values = {
    baseFare: validCurrency(fare.baseFare, 'Base fare', 0, 9999),
    includedMeters: validPositiveInteger(fare.includedMeters, 'Included meters', 1, 9999),
    distanceStepMeters: validPositiveInteger(fare.distanceStepMeters, 'Distance step meters', 1, 9999),
    distanceStepPrice: validCurrency(fare.distanceStepPrice, 'Distance step price', 0, 999),
    additionalPassengerFee: validCurrency(fare.additionalPassengerFee, 'Additional passenger fee', 0, 9999),
    baggageFee: validCurrency(fare.baggageFee, 'Large baggage fee', 0, 9999),
    outsideTodaSurcharge: validCurrency(fare.outsideTodaSurcharge, 'Outside TODA surcharge', 0, 9999),
    currency: 'PHP',
  };
  const fareRef = db.collection('settings').doc('fare_config');
  const normalized = await db.runTransaction(async (transaction) => {
    const current = await transaction.get(fareRef);
    const version = Number.isInteger(current.data()?.version)
      ? current.data().version + 1
      : 1;
    const next = {
      ...values,
      version,
      updatedAt: timestamp(),
      updatedBy: developer.uid,
    };
    transaction.set(fareRef, next, { merge: true });
    return { ...values, version };
  });
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: developer,
    action: 'update_city_fare',
    targetType: 'settings',
    targetId: 'fare_config',
    details: {
      baseFare: normalized.baseFare,
      includedMeters: normalized.includedMeters,
      distanceStepMeters: normalized.distanceStepMeters,
      distanceStepPrice: normalized.distanceStepPrice,
      additionalPassengerFee: normalized.additionalPassengerFee,
      baggageFee: normalized.baggageFee,
      outsideTodaSurcharge: normalized.outsideTodaSurcharge,
      currency: normalized.currency,
    },
  });
  await invalidateGoPolicyCache('fare_updated');
  return { updated: true };
});

exports.adminGetTodaCommission = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    if (actor.role !== 'toda_admin' || !actor.todaId) {
      throw new HttpsError(
        'permission-denied',
        'TODA administrator access is required.',
      );
    }
    const toda = await db.collection('todas').doc(actor.todaId).get();
    if (!toda.exists) throw new HttpsError('not-found', 'TODA not found.');
    return {
      percent: Number(toda.data().driverCommissionPercent || 0),
      recommendedPercent: 10,
      maximumPercent: 30,
      updatedAt: adminDate(toda.data().commissionUpdatedAt),
    };
  },
);

exports.adminGetTodaCommissionReport = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    if (actor.role !== 'toda_admin' ||
        typeof actor.todaId !== 'string' ||
        actor.todaId.length === 0) {
      throw new HttpsError(
        'permission-denied',
        'TODA administrator access is required.',
      );
    }
    const scopedTodaId = actor.todaId;

    let range;
    let pageSize;
    let summaryOnly;
    try {
      range = commissionReportDateRange(
        request.data?.startDate,
        request.data?.endDate,
      );
      summaryOnly = commissionReportSummaryOnly(
        request.data?.summaryOnly,
      );
      pageSize = summaryOnly
        ? null
        : commissionReportPageSize(request.data?.pageSize);
    } catch (error) {
      throw new HttpsError(
        'invalid-argument',
        error instanceof Error
          ? error.message
          : 'Invalid commission report options.',
      );
    }

    const settlements = db.collection('settlements');
    const start = Timestamp.fromDate(range.start);
    const endExclusive = Timestamp.fromDate(range.endExclusive);
    const scopedRange = settlements
      .where('todaId', '==', scopedTodaId)
      .where('settlementTimestamp', '>=', start)
      .where('settlementTimestamp', '<', endExclusive)
      .orderBy('settlementTimestamp', 'desc');
    const loadSummary = () => Promise.all([
      scopedRange.aggregate({
        grossFare: AggregateField.sum('grossFare'),
        commissionAmount: AggregateField.sum('commissionAmount'),
        driverNetEarnings: AggregateField.sum('driverNetEarnings'),
        completedRides: AggregateField.count(),
      }).get(),
      scopedRange
        .where('status', '==', 'settled')
        .count()
        .get(),
      scopedRange
        .where('adjustmentStatus', '==', 'disputed')
        .count()
        .get(),
    ]);
    const toSummary = (snapshots) => commissionReportSummary({
      aggregate: snapshots[0].data(),
      settledSettlements: snapshots[1].data().count,
      disputedSettlements: snapshots[2].data().count,
    });

    if (summaryOnly) {
      return {
        summary: toSummary(await loadSummary()),
        items: [],
        nextCursor: null,
      };
    }

    let pageQuery = scopedRange;
    const cursor = request.data?.cursor;
    if (cursor != null && cursor !== '') {
      if (typeof cursor !== 'string' ||
          cursor.length > 128 ||
          !validBookingId(cursor)) {
        throw new HttpsError(
          'invalid-argument',
          'The commission report cursor is invalid.',
        );
      }
      const cursorDocument = await settlements.doc(cursor).get();
      if (!cursorDocument.exists ||
          !cursorBelongsToReport(
            cursorDocument.data(),
            scopedTodaId,
            range,
          )) {
        throw new HttpsError(
          'invalid-argument',
          'The commission report cursor is invalid.',
        );
      }
      pageQuery = pageQuery.startAfter(cursorDocument);
    }

    const [pageSnapshot, summarySnapshots] = await Promise.all([
      pageQuery.limit(pageSize + 1).get(),
      loadSummary(),
    ]);

    const page = pageSnapshot.docs.slice(0, pageSize);
    const bookings = page.length
      ? await db.getAll(...page.map((entry) =>
        db.collection('bookings').doc(entry.id)))
      : [];
    return {
      summary: toSummary(summarySnapshots),
      items: page.map((entry, index) => commissionReportItem(
        entry.id,
        entry.data(),
        bookings[index]?.data() || {},
      )),
      nextCursor: pageSnapshot.docs.length > pageSize
        ? page.at(-1)?.id || null
        : null,
    };
  },
);

exports.adminSetTodaCommission = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    if (actor.role !== 'toda_admin' || !actor.todaId) {
      throw new HttpsError(
        'permission-denied',
        'TODA administrator access is required.',
      );
    }
    const percent = validCurrency(
      request.data?.percent,
      'Commission percentage',
      0,
      30,
    );
    const todaRef = db.collection('todas').doc(actor.todaId);
    const toda = await todaRef.get();
    if (!toda.exists || toda.data().isActive === false) {
      throw new HttpsError(
        'failed-precondition',
        'An active TODA is required to change commission.',
      );
    }
    await todaRef.update({
      driverCommissionPercent: percent,
      commissionUpdatedAt: timestamp(),
      commissionUpdatedBy: actor.uid,
    });
    await adminAudit(db.collection('auditLogs').doc(), {
      actor,
      action: 'update_driver_commission',
      targetType: 'toda',
      targetId: actor.todaId,
      details: {
        previousPercent: Number(
          toda.data().driverCommissionPercent || 0,
        ),
        percent,
        appliesTo: 'future_booking_assignments',
      },
    });
    return {
      percent,
      recommendedPercent: 10,
      maximumPercent: 30,
      updatedAt: new Date().toISOString(),
    };
  },
);

exports.adminSetDriverStatus = onCall({ region: 'asia-southeast1' }, async (request) => {
  const profile = await requireAdmin(request);
  const uid = requiredString(request.data?.uid, 'Driver ID');
  const status = request.data?.status;
  if (!['approved', 'rejected', 'suspended'].includes(status)) {
    throw new HttpsError('invalid-argument', 'Unsupported driver status.');
  }
  if (status !== 'suspended' && profile.role !== 'toda_admin') {
    throw new HttpsError(
      'permission-denied',
      'Routine driver decisions belong to the assigned TODA administrator.',
    );
  }
  const driverRef = db.collection('drivers').doc(uid);
  const driver = await driverRef.get();
  if (!driver.exists) throw new HttpsError('not-found', 'Driver not found.');
  await assertTodaScope(profile, driver.data().todaId);
  let verifiedLicenseNumber = driver.data().licenseNumber;
  let verifiedLicenseExpiry = driver.data().licenseExpiry;
  const suppliedLicenseNumber = String(
    request.data?.licenseNumber || '',
  ).trim();
  const suppliedLicenseExpiry = snapshotDateMillis(
    request.data?.licenseExpiry,
  );
  if (suppliedLicenseNumber || suppliedLicenseExpiry != null) {
    if (!suppliedLicenseNumber || suppliedLicenseExpiry == null ||
        suppliedLicenseExpiry < Date.now()) {
      throw new HttpsError(
        'invalid-argument',
        'Enter the current licence number and a future expiry date.',
      );
    }
    verifiedLicenseNumber = suppliedLicenseNumber;
    verifiedLicenseExpiry = Timestamp.fromMillis(suppliedLicenseExpiry);
  }
  if (status === 'approved') {
    const [vehicle, applicant] = await Promise.all([
      db.collection('vehicles')
        .doc(driver.data().vehicleId || '_missing')
        .get(),
      db.collection('users').doc(uid).get(),
    ]);
    const licenseExpiry = snapshotDateMillis(verifiedLicenseExpiry);
    if (!verifiedLicenseNumber || licenseExpiry == null ||
        licenseExpiry < Date.now()) {
      throw new HttpsError(
        'failed-precondition',
        'A current driver license is required before approval.',
      );
    }
    if (!vehicle.exists || vehicle.data().isVerified !== true) {
      throw new HttpsError(
        'failed-precondition',
        'Verify the registered vehicle before approving this driver.',
      );
    }
    if (applicant.exists && applicant.data().dateOfBirth != null &&
        !isAtLeast18(applicant.data().dateOfBirth)) {
      throw new HttpsError(
        'failed-precondition',
        'The driver applicant must be at least 18 years old.',
      );
    }
  }
  if (status !== 'approved' && await activeDriverBooking(driver.data())) {
    throw new HttpsError(
      'failed-precondition',
      'This driver has an active ride. Apply the status change after it finishes.',
    );
  }
  const update = { driverStatus: status, updatedAt: timestamp() };
  if (status === 'approved') Object.assign(update, {
    approvedAt: timestamp(),
    approvedBy: profile.uid,
    licenseNumber: verifiedLicenseNumber,
    licenseExpiry: verifiedLicenseExpiry,
  });
  if (status === 'approved' && driver.data().driverStatus === 'pending') {
    Object.assign(update, {
      rating: 0,
      ratingCount: 0,
      completedTrips: 0,
      totalEarnings: 0,
      dispatchStats: driverDispatchStats({}),
    });
  }
  if (status !== 'approved') Object.assign(update, { isOnline: false, isAvailable: false });
  await driverRef.update(update);
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: profile,
    action: `${status}_driver`,
    targetType: 'driver',
    targetId: uid,
    details: { todaId: driver.data().todaId },
  });
  return { updated: true };
});

exports.adminSetVehicleVerification = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    if (actor.role !== 'toda_admin') {
      throw new HttpsError(
        'permission-denied',
        'Vehicle verification belongs to the assigned TODA administrator.',
      );
    }
    const driverId = requiredString(request.data?.driverId, 'Driver ID');
    if (typeof request.data?.isVerified !== 'boolean') {
      throw new HttpsError(
        'invalid-argument',
        'Vehicle verification status is required.',
      );
    }
    const driver = await db.collection('drivers').doc(driverId).get();
    if (!driver.exists) throw new HttpsError('not-found', 'Driver not found.');
    await assertTodaScope(actor, driver.data().todaId);
    if (!request.data.isVerified && await activeDriverBooking(driver.data())) {
      throw new HttpsError(
        'failed-precondition',
        'Vehicle verification cannot be removed during an active ride.',
      );
    }
    const vehicleRef = db.collection('vehicles')
      .doc(driver.data().vehicleId || '_missing');
    const vehicle = await vehicleRef.get();
    if (!vehicle.exists || vehicle.data().driverId !== driverId) {
      throw new HttpsError('not-found', 'Registered vehicle not found.');
    }
    await vehicleRef.update({
      isVerified: request.data.isVerified,
      verifiedBy: request.data.isVerified ? actor.uid : null,
      verifiedAt: request.data.isVerified ? timestamp() : null,
      updatedAt: timestamp(),
    });
    await adminAudit(db.collection('auditLogs').doc(), {
      actor,
      action: request.data.isVerified
        ? 'verify_driver_vehicle'
        : 'remove_vehicle_verification',
      targetType: 'vehicle',
      targetId: vehicle.id,
      details: { driverId, todaId: driver.data().todaId },
    });
    return { updated: true };
  },
);

exports.adminSetUserStatus = onCall({ region: 'asia-southeast1' }, async (request) => {
  const developer = await requireDeveloperAdmin(request);
  const uid = requiredString(request.data?.uid, 'User ID');
  const sourceReportId = typeof request.data?.sourceReportId === 'string'
    ? request.data.sourceReportId.trim()
    : '';
  if (uid === request.auth.uid) throw new HttpsError('failed-precondition', 'You cannot suspend your own account.');
  if (typeof request.data?.isActive !== 'boolean') throw new HttpsError('invalid-argument', 'Account status is required.');
  let sourceReport = null;
  if (sourceReportId) {
    sourceReport = await db.collection('reports').doc(sourceReportId).get();
    if (!sourceReport.exists ||
        sourceReport.data().reportedUserId !== uid) {
      throw new HttpsError(
        'failed-precondition',
        'The source report does not match the account being evaluated.',
      );
    }
  }
  const driverRef = db.collection('drivers').doc(uid);
  const driverSnapshot = await driverRef.get();
  const passengerLock = await db.collection('activePassengerBookings').doc(uid).get();
  if (!request.data.isActive &&
      ((driverSnapshot.exists && await activeDriverBooking(driverSnapshot.data())) ||
        passengerLock.exists)) {
    throw new HttpsError(
      'failed-precondition',
      'This account has an active ride. Suspend it after the ride finishes.',
    );
  }
  const userRef = db.collection('users').doc(uid);
  const userProfile = await userRef.get();
  if (!userProfile.exists) throw new HttpsError('not-found', 'User not found.');
  await userRef.set({ isActive: request.data.isActive, updatedAt: timestamp() }, { merge: true });
  if (['developer_admin', 'toda_admin'].includes(userProfile.data().role)) {
    const claims = request.data.isActive
      ? {
        adminRole: userProfile.data().role,
        ...(userProfile.data().role === 'toda_admin'
          ? { todaId: userProfile.data().todaId }
          : {}),
      }
      : null;
    await admin.auth().setCustomUserClaims(uid, claims);
    await admin.auth().revokeRefreshTokens(uid);
  }
  if (!request.data.isActive) {
    if (driverSnapshot.exists) {
      await driverRef.update({ driverStatus: 'suspended', isOnline: false, isAvailable: false, updatedAt: timestamp() });
    }
    if (sourceReport) {
      await sourceReport.ref.update({
        action: 'Reported account suspended pending evaluation.',
        suspensionBy: developer.uid,
        suspensionAt: timestamp(),
      });
    }
  } else if (sourceReport) {
    await sourceReport.ref.update({
      action: 'Reported account restored after evaluation.',
      restorationBy: developer.uid,
      restorationAt: timestamp(),
    });
  }
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: developer,
    action: request.data.isActive ? 'restore_user' : 'suspend_user',
    targetType: 'user',
    targetId: uid,
    details: sourceReportId ? { sourceReportId } : {},
  });
  return { updated: true };
});

exports.adminResolveReport = onCall({ region: 'asia-southeast1' }, async (request) => {
  const profile = await requireAdmin(request);
  const reportId = requiredString(request.data?.reportId, 'Report ID');
  const status = request.data?.status;
  if (!['resolved', 'dismissed'].includes(status)) throw new HttpsError('invalid-argument', 'Unsupported report status.');
  const reportRef = db.collection('reports').doc(reportId);
  const report = await reportRef.get();
  if (!report.exists) throw new HttpsError('not-found', 'Report not found.');
  await assertTodaScope(profile, report.data().todaId);
  await reportRef.update({ status, action: String(request.data?.action || '').slice(0, 1000), resolvedBy: profile.uid, resolvedAt: timestamp() });
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: profile,
    action: `${status}_report`,
    targetType: 'report',
    targetId: reportId,
  });
  return { updated: true };
});

exports.adminSubmitZoneRequest = onCall({ region: 'asia-southeast1' }, async (request) => {
  const profile = await requireAdmin(request);
  const todaId = requiredString(request.data?.todaId, 'TODA ID');
  await assertTodaScope(profile, todaId);
  let areas;
  try {
    areas = normalizeGeometry({
      areas: request.data?.areas,
      polygon: request.data?.polygon,
    });
  } catch (error) {
    logger.warn('Coverage request geometry was rejected.', {
      todaId,
      actorId: profile.uid,
      error: String(error?.message || error),
    });
    throw new HttpsError('invalid-argument', 'One to 20 polygons with 3 to 200 valid points each are required.');
  }
  const toda = await db.collection('todas').doc(todaId).get();
  if (!toda.exists || toda.data().isActive !== true) {
    throw new HttpsError(
      'failed-precondition',
      'Coverage can be requested only for an active TODA.',
    );
  }
  const geometry = firestoreGeometry(areas);
  const zone = await db.collection('zoneRequests').add({
    todaId,
    ...geometry,
    status: 'pending',
    revision: 1,
    notes: String(request.data?.notes || '').slice(0, 1000),
    requestedBy: profile.uid,
    createdAt: timestamp(),
    updatedAt: timestamp(),
  });
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: profile,
    action: 'submit_zone_request',
    targetType: 'zoneRequest',
    targetId: zone.id,
    details: { todaId, areaCount: areas.length },
  });
  return { zoneRequestId: zone.id };
});

exports.adminReviewZoneRequest = onCall({ region: 'asia-southeast1' }, async (request) => {
  const developer = await requireDeveloperAdmin(request);
  const id = requiredString(request.data?.zoneRequestId, 'Zone request ID');
  const status = request.data?.status;
  if (!['approved', 'declined'].includes(status)) throw new HttpsError('invalid-argument', 'Unsupported zone decision.');
  const ref = db.collection('zoneRequests').doc(id);
  const activeRefFor = (todaId) =>
    db.collection('geofences').doc(todaId);
  const auditRef = db.collection('auditLogs').doc();
  const result = await db.runTransaction(async (transaction) => {
    const requestSnapshot = await transaction.get(ref);
    if (!requestSnapshot.exists) {
      throw new HttpsError('not-found', 'Zone request not found.');
    }
    const zone = requestSnapshot.data();
    if (zone.status !== 'pending') {
      if (zone.status === status) {
        return {
          updated: false,
          idempotent: true,
          todaId: zone.todaId,
        };
      }
      throw new HttpsError(
        'failed-precondition',
        'Only a pending coverage request can be reviewed.',
      );
    }
    let activeSnapshot = null;
    let areas = null;
    if (status === 'approved') {
      try {
        areas = normalizeGeometry(zone);
      } catch (error) {
        logger.warn('Coverage approval geometry was rejected.', {
          zoneRequestId: id,
          todaId: zone.todaId,
          actorId: developer.uid,
          error: String(error?.message || error),
        });
        throw new HttpsError(
          'failed-precondition',
          'This request has invalid geometry. Edit it before approval.',
        );
      }
      const [activeCoverage, todaSnapshot] = await Promise.all([
        transaction.get(activeRefFor(zone.todaId)),
        transaction.get(db.collection('todas').doc(zone.todaId)),
      ]);
      if (!todaSnapshot.exists || todaSnapshot.data().isActive !== true) {
        throw new HttpsError(
          'failed-precondition',
          'Coverage can be approved only for an active TODA.',
        );
      }
      activeSnapshot = activeCoverage;
      const active = activeSnapshot.exists ? activeSnapshot.data() : {};
      const activeSourceCreatedAt = snapshotDateMillis(
        active.sourceRequestCreatedAt,
      );
      const requestCreatedAt = snapshotDateMillis(zone.createdAt);
      if (activeSourceCreatedAt != null &&
          requestCreatedAt != null &&
          activeSourceCreatedAt > requestCreatedAt) {
        throw new HttpsError(
          'failed-precondition',
          'A newer coverage request is already active for this TODA.',
        );
      }
    }
    const currentCoverageRevision = activeSnapshot?.exists
      ? Number(activeSnapshot.data().coverageRevision || 0)
      : 0;
    const safeCurrentCoverageRevision =
      Number.isInteger(currentCoverageRevision) &&
      currentCoverageRevision >= 0
        ? currentCoverageRevision
        : 0;
    const coverageRevision = status === 'approved'
      ? safeCurrentCoverageRevision + 1
      : null;
    transaction.update(ref, {
      status,
      reviewedBy: developer.uid,
      reviewedAt: timestamp(),
      approvedCoverageRevision: coverageRevision,
      updatedAt: timestamp(),
    });
    if (status === 'approved') {
      transaction.set(activeRefFor(zone.todaId), {
        todaId: zone.todaId,
        ...firestoreGeometry(areas),
        coverageRevision,
        isActive: true,
        sourceRequestId: id,
        sourceRequestRevision: Number(zone.revision || 1),
        sourceRequestCreatedAt: zone.createdAt || timestamp(),
        approvedAt: timestamp(),
        updatedBy: developer.uid,
        updatedAt: timestamp(),
      }, { merge: true });
    }
    transaction.create(auditRef, adminAuditData({
      actor: developer,
      action: `${status}_zone_request`,
      targetType: 'zoneRequest',
      targetId: id,
      details: {
        todaId: zone.todaId,
        coverageRevision,
        requestRevision: Number(zone.revision || 1),
      },
    }));
    return {
      updated: true,
      idempotent: false,
      todaId: zone.todaId,
      coverageRevision,
    };
  });
  if (status === 'approved' && result.updated) {
    await invalidateGoPolicyCache('coverage_approved');
  }
  return result;
});

exports.adminUpdateZoneRequest = onCall({ region: 'asia-southeast1' }, async (request) => {
  const profile = await requireAdmin(request);
  const id = requiredString(request.data?.zoneRequestId, 'Zone request ID');
  let areas;
  try {
    areas = normalizeGeometry({
      areas: request.data?.areas,
      polygon: request.data?.polygon,
    });
  } catch (error) {
    logger.warn('Coverage request update geometry was rejected.', {
      zoneRequestId: id,
      actorId: profile.uid,
      error: String(error?.message || error),
    });
    throw new HttpsError('invalid-argument', 'One to 20 polygons with 3 to 200 valid points each are required.');
  }
  const ref = db.collection('zoneRequests').doc(id);
  const auditRef = db.collection('auditLogs').doc();
  const result = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      throw new HttpsError('not-found', 'Zone request not found.');
    }
    const zone = snapshot.data();
    await assertTodaScope(profile, zone.todaId);
    if (zone.status !== 'pending') {
      throw new HttpsError(
        'failed-precondition',
        'Only a pending coverage request can be edited. Submit a new revision for an approved area.',
      );
    }
    const revision = Number(zone.revision || 1) + 1;
    transaction.update(ref, {
      ...firestoreGeometry(areas),
      revision,
      notes: String(request.data?.notes || '').slice(0, 1000),
      updatedBy: profile.uid,
      updatedAt: timestamp(),
    });
    transaction.create(auditRef, adminAuditData({
      actor: profile,
      action: 'update_zone_request_geometry',
      targetType: 'zoneRequest',
      targetId: id,
      details: {
        todaId: zone.todaId,
        areaCount: areas.length,
        revision,
      },
    }));
    return { updated: true, revision };
  });
  return result;
});

// Route restrictions are centrally managed safety/operations constraints.
// They are read by both mobile apps to select a safe route alternative.
exports.adminCreateRouteRestriction = onCall({ region: 'asia-southeast1' }, async (request) => {
  const developer = await requireDeveloperAdmin(request);
  const name = requiredString(request.data?.name, 'Restriction name');
  const type = request.data?.type;
  if (!['prohibited_highway', 'no_service_area', 'restricted_crossing'].includes(type)) {
    throw new HttpsError('invalid-argument', 'Unsupported restriction type.');
  }
  const geometryType = type === 'prohibited_highway' ? 'corridor' : 'polygon';
  if (request.data?.geometryType && request.data.geometryType !== geometryType) {
    throw new HttpsError(
      'invalid-argument',
      type === 'prohibited_highway'
        ? 'Highway groups require polyline corridor geometry.'
        : 'No-service and restricted-driving areas require polygon geometry.',
    );
  }
  let areas;
  try {
    areas = normalizeGeometry({
      areas: request.data?.areas,
      polygon: request.data?.polygon,
    }, { geometryType });
  } catch {
    throw new HttpsError(
      'invalid-argument',
      geometryType === 'corridor'
        ? 'A corridor needs 1 to 20 centreline segments of 2 to 200 points each.'
        : 'A polygon needs 3 to 200 points.',
    );
  }
  const bufferMeters = geometryType === 'corridor'
    ? validPositiveInteger(request.data?.bufferMeters, 'Corridor buffer', 5, 200)
    : 0;
  const minimumAlignedTravelMeters = geometryType === 'corridor'
    ? validPositiveInteger(
      request.data?.minimumAlignedTravelMeters ?? 80,
      'Minimum highway travel distance', 30, 1000,
    )
    : 0;
  const ref = await db.collection('routeRestrictions').add({
    name,
    type,
    geometryType,
    ...firestoreRestrictionGeometry(areas, geometryType),
    bufferMeters,
    ...(geometryType === 'corridor' ? {
      enforcementMode: 'aligned_travel',
      minimumAlignedTravelMeters,
    } : {}),
    isActive: true,
    notes: String(request.data?.notes || '').slice(0, 1000),
    createdBy: developer.uid, createdAt: timestamp(), updatedAt: timestamp(),
  });
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: developer,
    action: 'create_route_restriction',
    targetType: 'routeRestriction',
    targetId: ref.id,
    details: {
      type, geometryType, areaCount: areas.length, bufferMeters,
      minimumAlignedTravelMeters,
    },
  });
  await invalidateGoPolicyCache('restriction_created');
  return { restrictionId: ref.id };
});

exports.adminSetRouteRestrictionStatus = onCall({ region: 'asia-southeast1' }, async (request) => {
  const developer = await requireDeveloperAdmin(request);
  const restrictionId = requiredString(request.data?.restrictionId, 'Restriction ID');
  if (typeof request.data?.isActive !== 'boolean') throw new HttpsError('invalid-argument', 'Restriction status is required.');
  const ref = db.collection('routeRestrictions').doc(restrictionId);
  if (!(await ref.get()).exists) throw new HttpsError('not-found', 'Route restriction not found.');
  await ref.update({ isActive: request.data.isActive, updatedAt: timestamp() });
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: developer,
    action: request.data.isActive
      ? 'activate_route_restriction'
      : 'deactivate_route_restriction',
    targetType: 'routeRestriction',
    targetId: restrictionId,
  });
  await invalidateGoPolicyCache('restriction_status_changed');
  return { updated: true };
});

function driverViolationDocument(id, data) {
  const response = data.response || {};
  const delivery = data.delivery || {};
  return {
    ...data,
    violationId: data.violationId || id,
    enteredAt: adminDate(data.enteredAt),
    exitedAt: adminDate(data.exitedAt),
    occurredAt: adminDate(data.occurredAt),
    createdAt: adminDate(data.createdAt),
    updatedAt: adminDate(data.updatedAt),
    response: {
      ...response,
      lastActionAt: adminDate(response.lastActionAt),
      acknowledgedAt: adminDate(response.acknowledgedAt),
      respondingAt: adminDate(response.respondingAt),
      resolvedAt: adminDate(response.resolvedAt),
      dismissedAt: adminDate(response.dismissedAt),
    },
    delivery: {
      ...delivery,
      lastAttemptAt: adminDate(delivery.lastAttemptAt),
    },
  };
}

async function driverViolationAdminRecipientIds(ownerTodaId) {
  const [developers, todaUsers] = await Promise.all([
    db.collection('users')
      .where('role', '==', 'developer_admin')
      .limit(100)
      .get(),
    ownerTodaId
      ? db.collection('users').where('todaId', '==', ownerTodaId)
        .limit(100)
        .get()
      : Promise.resolve({ docs: [] }),
  ]);
  return [...new Set([...developers.docs, ...todaUsers.docs]
    .filter((entry) => {
      const data = entry.data();
      return data.isActive !== false &&
        (data.role === 'developer_admin' ||
          (data.role === 'toda_admin' &&
            data.todaId === ownerTodaId));
    })
    .map((entry) => entry.id))];
}

async function deliverDriverViolationPush({
  recipientIds,
  title,
  body,
  violationId,
  messageId = '',
  type = 'driver_violation',
}) {
  const uniqueRecipients = [...new Set(recipientIds)].filter(Boolean);
  const deliveries = await Promise.all(uniqueRecipients.map((recipientId) =>
    sendToUser(recipientId, title, body, {
      type,
      violationId,
      ...(messageId ? { messageId } : {}),
    }).catch((error) => {
      logger.error('Could not deliver driver violation notification.', {
        violationId,
        messageId,
        recipientId,
        error,
      });
      return { attempted: 0, succeeded: 0 };
    })));
  return {
    recipientCount: uniqueRecipients.length,
    attemptedCount: deliveries.reduce(
      (sum, delivery) => sum + Number(delivery.attempted || 0),
      0,
    ),
    successCount: deliveries.reduce(
      (sum, delivery) => sum + Number(delivery.succeeded || 0),
      0,
    ),
  };
}

async function activeDriverIdentityForUid(uid) {
  const [user, driver] = await Promise.all([
    db.collection('users').doc(uid).get(),
    db.collection('drivers').doc(uid).get(),
  ]);
  if (!user.exists || user.data().role !== 'driver' ||
      user.data().isActive === false || !driver.exists ||
      driver.data().driverStatus !== 'approved') {
    throw new HttpsError(
      'permission-denied',
      'An active approved driver account is required.',
    );
  }
  return {
    uid,
    user: user.data(),
    driver: driver.data(),
  };
}

async function activeDriverIdentity(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in as a driver first.');
  }
  return activeDriverIdentityForUid(request.auth.uid);
}

function driverViolationActor(request, userData) {
  const actor = {
    uid: request.auth.uid,
    role: userData.role,
    todaId: userData.todaId || null,
    isActive: userData.isActive !== false,
  };
  if (['developer_admin', 'toda_admin'].includes(actor.role) &&
      !adminIdentityMatches(userData, request.auth.token)) {
    throw new HttpsError(
      'permission-denied',
      'Administrator permissions changed. Sign out and sign in again.',
    );
  }
  return actor;
}

function driverViolationSenderName(userData, actorRole) {
  const profileName = [
    userData.firstName,
    userData.middleName,
    userData.lastName,
  ]
    .filter((value) =>
      typeof value === 'string' && value.trim().length > 0)
    .map((value) => value.trim())
    .join(' ');
  if (profileName) return profileName;
  if (typeof userData.displayName === 'string' &&
      userData.displayName.trim().length > 0) {
    return userData.displayName.trim();
  }
  return actorRole === 'driver'
    ? 'Driver'
    : actorRole === 'toda_admin'
      ? 'TODA Administrator'
      : 'Developer Administrator';
}

function driverViolationRestrictionSnapshot(restriction) {
  const normalizedAreas = normalizeGeometry(restriction);
  const areas = normalizedAreas.map((points) => ({
    points: points.map((point) => ({
      latitude: point.latitude,
      longitude: point.longitude,
    })),
  }));
  const revision = Number(
    restriction.revision ?? restriction.geometryVersion ?? 0,
  );
  if (Buffer.byteLength(JSON.stringify(areas), 'utf8') > 700000) {
    throw new TypeError(
      'Restriction geometry is too large to preserve in a violation case.',
    );
  }
  return {
    id: restriction.id,
    name: restriction.name || 'Restricted area',
    type: restriction.type,
    revision: Number.isFinite(revision) ? revision : 0,
    geometryVersion: Number(restriction.geometryVersion || 1),
    areas,
    polygon: areas[0]?.points || [],
  };
}

// The driver supplies no polygon decision. Processing reads trusted account,
// booking, TODA, and restriction records and creates at most one case per
// observed enter/exit cycle.
async function processDriverRestrictionPosition(identity, rawLocation) {
  if (identity.driver.isOnline !== true) {
    throw new HttpsError(
      'failed-precondition',
      'Go online before checking restricted-area position.',
    );
  }
  let location;
  try {
    location = normalizeDriverLocation(rawLocation, {
      maximumAgeMs: driverLocationMaxAgeMs,
      maximumAccuracyMeters: 35,
      requireObservedAt: true,
      maximumObservedAgeMs: driverLocationMaxAgeMs,
    });
  } catch (error) {
    throw new HttpsError('failed-precondition', error.message);
  }
    const [restrictionDocuments, stateDocuments, todaDocument,
      bookingDocument] = await Promise.all([
      db.collection('routeRestrictions')
        .where('isActive', '==', true)
        .limit(200)
        .get(),
      db.collection('driverRestrictionStates')
        .doc(identity.uid)
        .collection('restrictions')
        .limit(200)
        .get(),
      identity.driver.todaId
        ? db.collection('todas').doc(identity.driver.todaId).get()
        : Promise.resolve(null),
      typeof identity.driver.currentBookingId === 'string' &&
        identity.driver.currentBookingId.length > 0
        ? db.collection('bookings')
          .doc(identity.driver.currentBookingId)
          .get()
        : Promise.resolve(null),
    ]);
    const restrictions = restrictionDocuments.docs
      .map((document) => ({ id: document.id, ...document.data() }))
      .filter((restriction) =>
        ['no_service_area', 'restricted_crossing']
          .includes(restriction.type) &&
        restriction.geometryType !== 'corridor');
    const insideRestrictions = restrictions.filter((restriction) =>
      recordContainsPoint(restriction, location));
    const insideIds = new Set(
      insideRestrictions.map((restriction) => restriction.id),
    );
    const stateById = new Map(
      stateDocuments.docs.map((document) => [
        document.id,
        { ref: document.ref, data: document.data() },
      ]),
    );
    const driverName = [
      identity.user.firstName,
      identity.user.middleName,
      identity.user.lastName,
    ].filter((value) =>
      typeof value === 'string' && value.trim().length > 0).join(' ') ||
      'Driver';
    const ownerTodaId = identity.driver.todaId || null;
    const ownerTodaName = todaDocument?.exists
      ? todaDocument.data().name || null
      : null;
    const bookingId = bookingDocument?.exists
      ? bookingDocument.id
      : null;
    const bookingStatus = bookingDocument?.exists
      ? bookingDocument.data().status || null
      : null;
    const created = [];
    const exited = [];
    const pending = [];
    const observationNow = Date.now();

    for (const restriction of restrictions) {
      const isInside = insideIds.has(restriction.id);
      const preloadedState = stateById.get(restriction.id);
      // Most drivers are outside almost every restriction. Avoid starting a
      // Firestore transaction unless the point is inside or state already
      // exists from an earlier candidate/entry.
      if (!isInside && !preloadedState) continue;
      const stateRef = db.collection('driverRestrictionStates')
        .doc(identity.uid)
        .collection('restrictions')
        .doc(restriction.id);
      const proposedViolationId = `violation_${randomUUID()
        .replaceAll('-', '')}`;
      const violationRef = db.collection('driverViolations')
        .doc(proposedViolationId);
      const transactionResult = await db.runTransaction(
        async (transaction) => {
          const currentState = await transaction.get(stateRef);
          const state = currentState.exists ? currentState.data() : {};
          if (!currentState.exists && !isInside) {
            return { transition: 'outside', violationId: null };
          }
          const stableOutsideState = !isInside &&
            state.inside !== true &&
            !state.activeViolationId &&
            Number(state.candidateInsideSamples || 0) <= 0 &&
            Number(state.candidateOutsideSamples || 0) <= 0 &&
            Number(state.reentryAllowedAtMillis || 0) <= observationNow;
          if (stableOutsideState) {
            transaction.delete(stateRef);
            return { transition: 'outside', violationId: null };
          }
          const decision = nextRestrictionObservation(state, {
            inside: isInside,
            observedAt: location.observedAt,
            now: observationNow,
          });
          if (decision.transition === 'ignored') {
            return {
              transition: decision.transition,
              violationId: null,
            };
          }
          const restrictionSnapshot =
            driverViolationRestrictionSnapshot(restriction);
          const stateUpdate = {
            schemaVersion: 1,
            driverId: identity.uid,
            restrictionId: restriction.id,
            restrictionType: restriction.type,
            ...decision.updates,
            lastObservedAt: timestamp(),
            updatedAt: timestamp(),
          };
          if (decision.transition === 'enter') {
            transaction.create(violationRef, {
              schemaVersion: 1,
              violationId: proposedViolationId,
              eventClass: DRIVER_VIOLATION_EVENT_CLASS.restrictedAreaEntry,
              status: DRIVER_VIOLATION_STATUS.open,
              driverId: identity.uid,
              driverName,
              ownerTodaId,
              ownerTodaName,
              bookingId,
              bookingStatus,
              context: driverViolationContext(bookingId, bookingStatus),
              restrictionId: restriction.id,
              restrictionName: restrictionSnapshot.name,
              restrictionType: restriction.type,
              restrictionRevision: restrictionSnapshot.revision,
              restrictionSnapshot,
              eventLocation: {
                latitude: location.latitude,
                longitude: location.longitude,
                accuracy: location.accuracy,
                bearing: location.bearing,
                speed: location.speed,
                timestamp: location.timestamp,
                observedAt: location.observedAt,
              },
              evidence: {
                ...(decision.evidence || {}),
                publishTimestamp: location.timestamp,
                clock: 'gps_observed_at',
                policy: 'two_distinct_fresh_gps_inside_samples',
              },
              source: 'driver_reported_gps_server_polygon_match',
              confidence:
                'two_fresh_driver_reported_gps_fixes_server_geometry_match',
              enteredAt: timestamp(),
              exitedAt: null,
              occurredAt: timestamp(),
              response: {
                status: DRIVER_VIOLATION_STATUS.open,
                lastAction: null,
                lastActionBy: null,
                lastActionAt: null,
                note: null,
              },
              delivery: {
                status: 'pending',
                recipientCount: 0,
                attemptedCount: 0,
                successCount: 0,
                lastAttemptAt: null,
              },
              driverDelivery: {
                status: 'pending',
                recipientCount: 1,
                attemptedCount: 0,
                successCount: 0,
                lastAttemptAt: null,
              },
              messageCount: 0,
              createdAt: timestamp(),
              updatedAt: timestamp(),
            });
            stateUpdate.activeViolationId = proposedViolationId;
            stateUpdate.enteredAt = timestamp();
            stateUpdate.exitedAt = null;
            transaction.create(db.collection('auditLogs').doc(), {
              type: 'driver_restriction_event',
              actorId: identity.uid,
              actorRole: 'driver',
              actorTodaId: ownerTodaId,
              action: 'operational_restricted_area_entry_match',
              targetType: 'driverViolation',
              targetId: proposedViolationId,
              details: {
                restrictionId: restriction.id,
                bookingId,
                source: 'backend_polygon_match',
                evidenceSampleCount: decision.evidence?.sampleCount || 2,
              },
              createdAt: timestamp(),
            });
          } else if (decision.transition === 'exit') {
            const activeViolationId = state.activeViolationId || null;
            stateUpdate.activeViolationId = null;
            stateUpdate.exitedAt = timestamp();
            if (activeViolationId) {
              transaction.set(
                db.collection('driverViolations').doc(activeViolationId),
                {
                  exitedAt: timestamp(),
                  exitEvidence: {
                    policy: 'two_distinct_fresh_gps_outside_samples',
                    clock: 'gps_observed_at',
                    confirmingObservedAt: location.observedAt,
                    publishTimestamp: location.timestamp,
                  },
                  updatedAt: timestamp(),
                },
                { merge: true },
              );
            }
          }
          transaction.set(stateRef, stateUpdate, { merge: true });
          return {
            transition: decision.transition,
            violationId: decision.transition === 'enter'
              ? proposedViolationId
              : decision.transition === 'exit'
                ? state.activeViolationId || null
                : null,
          };
        },
      );
      if (transactionResult.transition === 'enter' &&
          transactionResult.violationId) {
        created.push(transactionResult.violationId);
      } else if (transactionResult.transition === 'exit' &&
          transactionResult.violationId) {
        exited.push(transactionResult.violationId);
      } else if ([
        'candidate_entry',
        'candidate_exit',
        'reentry_cooldown',
      ].includes(transactionResult.transition)) {
        pending.push(restriction.id);
      }
    }

    // A disabled/deleted restriction is treated as outside for any retained
    // server state, but still requires two distinct observations before the
    // active case receives an exitedAt timestamp.
    const activeRestrictionIds = new Set(
      restrictions.map((restriction) => restriction.id),
    );
    const inactiveStates = [...stateById.entries()].filter(
      ([restrictionId, state]) =>
        !activeRestrictionIds.has(restrictionId) &&
        (state.data.inside === true ||
          Number(state.data.candidateInsideSamples || 0) > 0),
    );
    for (const [restrictionId, stateEntry] of inactiveStates) {
      const stateRef = stateEntry.ref;
      const result = await db.runTransaction(async (transaction) => {
        const currentState = await transaction.get(stateRef);
        if (!currentState.exists) {
          return { transition: 'ignored', violationId: null };
        }
        const state = currentState.data();
        const decision = nextRestrictionObservation(state, {
          inside: false,
          observedAt: location.observedAt,
          now: observationNow,
        });
        if (decision.transition === 'ignored') {
          return { transition: 'ignored', violationId: null };
        }
        const activeViolationId = state.activeViolationId || null;
        transaction.set(stateRef, {
          ...decision.updates,
          ...(decision.transition === 'exit'
            ? {
              activeViolationId: null,
              exitedAt: timestamp(),
            }
            : {}),
          lastObservedAt: timestamp(),
          updatedAt: timestamp(),
        }, { merge: true });
        if (decision.transition === 'exit' && activeViolationId) {
          transaction.set(
            db.collection('driverViolations').doc(activeViolationId),
            {
              exitedAt: timestamp(),
              exitEvidence: {
                policy: 'two_distinct_fresh_gps_outside_samples',
                clock: 'gps_observed_at',
                confirmingObservedAt: location.observedAt,
                publishTimestamp: location.timestamp,
                restrictionInactive: true,
              },
              updatedAt: timestamp(),
            },
            { merge: true },
          );
        }
        return {
          transition: decision.transition,
          violationId: decision.transition === 'exit'
            ? activeViolationId
            : null,
        };
      });
      if (result.transition === 'exit' && result.violationId) {
        exited.push(result.violationId);
      } else if (result.transition === 'candidate_exit') {
        pending.push(restrictionId);
      }
    }

    const adminRecipientIds = created.length > 0
      ? await driverViolationAdminRecipientIds(ownerTodaId)
      : [];
    for (const violationId of created) {
      const [delivery, driverDelivery] = await Promise.all([
        deliverDriverViolationPush({
          recipientIds: adminRecipientIds,
          title: 'Restricted-area entry detected',
          body: `${driverName} entered a mapped e-trike restricted area.`,
          violationId,
        }),
        // This server-originated alert is a safety fallback when the driver's
        // local restriction cache has not yet received an admin activation.
        deliverDriverViolationPush({
          recipientIds: [identity.uid],
          title: 'Restricted e-trike area entered',
          body: 'Leave the restricted area using the nearest permitted street.',
          violationId,
          type: 'driver_violation',
        }),
      ]);
      await db.collection('driverViolations').doc(violationId).set({
        delivery: {
          status: delivery.successCount > 0
            ? 'delivered'
            : delivery.attemptedCount > 0
              ? 'delivery_failed'
              : 'no_registered_admin_device',
          ...delivery,
          lastAttemptAt: timestamp(),
        },
        driverDelivery: {
          status: driverDelivery.successCount > 0
            ? 'delivered'
            : driverDelivery.attemptedCount > 0
              ? 'delivery_failed'
              : 'no_registered_driver_device',
          ...driverDelivery,
          lastAttemptAt: timestamp(),
        },
        updatedAt: timestamp(),
      }, { merge: true });
    }
    return {
      activeRestrictionIds: insideRestrictions.map(
        (restriction) => restriction.id,
      ),
      createdViolationIds: created,
      exitedViolationIds: exited,
      pendingRestrictionIds: [...new Set(pending)],
      locationTimestamp: location.timestamp,
      locationObservedAt: location.observedAt,
      evidenceClock: 'gps_observed_at',
    };
}

// The callable gives the signed-in driver immediate UI feedback. The RTDB
// trigger below is the authoritative fallback, so a modified client cannot
// suppress monitoring merely by omitting this callable.
exports.driverReportRestrictionPosition = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const identity = await activeDriverIdentity(request);
    const locationSnapshot = await realtime
      .ref(`driver_locations/${identity.uid}`)
      .get();
    return processDriverRestrictionPosition(
      identity,
      locationSnapshot.exists() ? locationSnapshot.val() : null,
    );
  },
);

exports.monitorDriverRestrictionPosition = onValueWritten(
  {
    ref: '/driver_locations/{driverId}',
    // The isolated demo emulator creates RTDB in us-central1; production
    // VolTrike RTDB is in asia-southeast1.
    region: functionsEmulator ? 'us-central1' : 'asia-southeast1',
    retry: false,
  },
  async (event) => {
    if (!event.data.after.exists()) return;
    const rawLocation = event.data.after.val();
    // Legacy APKs remain dispatch-visible during rollout but cannot create
    // confirmed cases until they provide a true GPS observation timestamp.
    if (rawLocation?.online !== true ||
        !Number.isFinite(Number(rawLocation?.observedAt))) {
      return;
    }
    const previousObservedAt = Number(
      event.data.before.exists()
        ? event.data.before.val()?.observedAt
        : null,
    );
    if (Number.isFinite(previousObservedAt) &&
        previousObservedAt === Number(rawLocation.observedAt)) {
      return;
    }
    try {
      const identity = await activeDriverIdentityForUid(
        event.params.driverId,
      );
      await processDriverRestrictionPosition(identity, rawLocation);
    } catch (error) {
      if (error instanceof HttpsError &&
          ['failed-precondition', 'permission-denied']
            .includes(error.code)) {
        logger.info('Ignored ineligible restriction position publication.', {
          driverId: event.params.driverId,
          reason: error.message,
        });
        return;
      }
      logger.error('Restriction position trigger failed.', {
        driverId: event.params.driverId,
        error,
      });
      throw error;
    }
  },
);

// Maintains a compact RTDB spatial read model without reading Firestore on
// every GPS heartbeat. Node performs final driver/TODA/vehicle validation.
exports.indexDriverDispatchLocation = onValueWritten(
  {
    ref: '/driver_locations/{driverId}',
    region: functionsEmulator ? 'us-central1' : 'asia-southeast1',
    retry: false,
  },
  async (event) => {
    // Warm the index while dispatch cutover remains off. This permits a safe
    // deploy/warm/enable sequence without sending bookings to an empty index.
    if (!goService.configured()) return;
    const driverId = event.params.driverId;
    const before = event.data.before.exists() ? event.data.before.val() : null;
    const after = event.data.after.exists() ? event.data.after.val() : null;
    const updates = dispatchIndexUpdates({ driverId, before, after });
    if (Object.keys(updates).length > 0) {
      await realtime.ref().update(updates);
    }
  },
);

exports.adminListDriverViolations = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const requestedLimit = adminPageSize(request.data?.limit);
    let query = db.collection('driverViolations');
    if (actor.role === 'toda_admin') {
      query = query.where('ownerTodaId', '==', actor.todaId);
    }
    const statusFilter = typeof request.data?.status === 'string'
      ? request.data.status
      : '';
    const eventClassFilter = typeof request.data?.eventClass === 'string'
      ? request.data.eventClass
      : '';
    if (statusFilter &&
        !Object.values(DRIVER_VIOLATION_STATUS).includes(statusFilter)) {
      throw new HttpsError(
        'invalid-argument',
        'The driver violation status filter is invalid.',
      );
    }
    if (eventClassFilter &&
        !Object.values(DRIVER_VIOLATION_EVENT_CLASS)
          .includes(eventClassFilter)) {
      throw new HttpsError(
        'invalid-argument',
        'The driver violation event filter is invalid.',
      );
    }
    if (statusFilter) {
      query = query.where('status', '==', statusFilter);
    }
    if (eventClassFilter) {
      query = query.where('eventClass', '==', eventClassFilter);
    }
    query = query.orderBy('occurredAt', 'desc');
    const cursor = typeof request.data?.cursor === 'string'
      ? request.data.cursor.trim()
      : '';
    if (cursor) {
      if (!validDriverViolationIdentifier(cursor)) {
        throw new HttpsError(
          'invalid-argument',
          'The driver violation cursor is invalid.',
        );
      }
      const cursorDocument = await db.collection('driverViolations')
        .doc(cursor)
        .get();
      if (!cursorDocument.exists ||
          !actorCanAccessDriverViolation(actor, cursorDocument.data())) {
        throw new HttpsError(
          'invalid-argument',
          'The driver violation cursor is unavailable in this scope.',
        );
      }
      query = query.startAfter(cursorDocument);
    }
    const snapshot = await query.limit(requestedLimit + 1).get();
    const pageDocuments = snapshot.docs.slice(0, requestedLimit);
    const items = pageDocuments
      .map((document) =>
        driverViolationDocument(document.id, document.data()));
    const nextCursor = snapshot.size > requestedLimit &&
        pageDocuments.length > 0
      ? pageDocuments[pageDocuments.length - 1].id
      : null;
    return { items, nextCursor };
  },
);

exports.adminGetDriverViolation = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const violationId = request.data?.violationId;
    if (!validDriverViolationIdentifier(violationId)) {
      throw new HttpsError(
        'invalid-argument',
        'A valid driver violation ID is required.',
      );
    }
    const violation = await db.collection('driverViolations')
      .doc(violationId)
      .get();
    if (!violation.exists) {
      throw new HttpsError(
        'not-found',
        'Driver violation case not found.',
      );
    }
    if (!actorCanAccessDriverViolation(actor, violation.data())) {
      throw new HttpsError(
        'permission-denied',
        'This driver violation is outside your TODA.',
      );
    }
    return {
      item: driverViolationDocument(violation.id, violation.data()),
    };
  },
);

exports.listMyDriverViolations = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const identity = await activeDriverIdentity(request);
    const requestedLimit = adminPageSize(request.data?.limit);
    const includeClosed = request.data?.includeClosed === true;
    const snapshot = await db.collection('driverViolations')
      .where('driverId', '==', identity.uid)
      .orderBy('occurredAt', 'desc')
      .limit(100)
      .get();
    const items = snapshot.docs
      .filter((document) => includeClosed || ![
        DRIVER_VIOLATION_STATUS.resolved,
        DRIVER_VIOLATION_STATUS.dismissed,
      ].includes(document.data().status))
      .slice(0, requestedLimit)
      .map((document) =>
        driverViolationDocument(document.id, document.data()));
    return { items };
  },
);

exports.adminUpdateDriverViolation = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const violationId = request.data?.violationId;
    if (!validDriverViolationIdentifier(violationId)) {
      throw new HttpsError(
        'invalid-argument',
        'A valid driver violation ID is required.',
      );
    }
    const action = requiredString(
      request.data?.action,
      'Driver violation action',
    );
    const note = typeof request.data?.note === 'string'
      ? request.data.note.trim().slice(0, 1000)
      : '';
    if (['resolve', 'dismiss'].includes(action) && note.length < 5) {
      throw new HttpsError(
        'invalid-argument',
        'A resolution or dismissal note of at least five characters is required.',
      );
    }
    const violationRef = db.collection('driverViolations').doc(violationId);
    const result = await db.runTransaction(async (transaction) => {
      const violation = await transaction.get(violationRef);
      if (!violation.exists) {
        throw new HttpsError(
          'not-found',
          'Driver violation case not found.',
        );
      }
      const data = violation.data();
      if (!actorCanAccessDriverViolation(actor, data)) {
        throw new HttpsError(
          'permission-denied',
          'This driver violation is outside your TODA.',
        );
      }
      let nextStatus;
      try {
        nextStatus = nextDriverViolationStatus(data.status, action);
      } catch (error) {
        throw new HttpsError('failed-precondition', error.message);
      }
      const canonicalAction = action === 'investigate'
        ? 'respond'
        : action;
      const response = {
        ...(data.response || {}),
        status: nextStatus,
        lastAction: canonicalAction,
        lastActionBy: actor.uid,
        lastActionRole: actor.role,
        lastActionAt: timestamp(),
        note: note || data.response?.note || null,
      };
      if (canonicalAction === 'acknowledge') {
        response.acknowledgedAt = timestamp();
        response.acknowledgedBy = actor.uid;
      } else if (canonicalAction === 'respond') {
        response.respondingAt = timestamp();
        response.respondingBy = actor.uid;
      } else if (canonicalAction === 'resolve') {
        response.resolvedAt = timestamp();
        response.resolvedBy = actor.uid;
      } else {
        response.dismissedAt = timestamp();
        response.dismissedBy = actor.uid;
      }
      transaction.update(violationRef, {
        status: nextStatus,
        response,
        updatedAt: timestamp(),
      });
      transaction.create(db.collection('auditLogs').doc(), {
        type: 'admin_action',
        actorId: actor.uid,
        actorRole: actor.role,
        actorTodaId: actor.todaId || null,
        action: `driver_violation_${canonicalAction}`,
        targetType: 'driverViolation',
        targetId: violationId,
        details: {
          driverId: data.driverId,
          ownerTodaId: data.ownerTodaId,
          note,
        },
        createdAt: timestamp(),
      });
      return {
        status: nextStatus,
        driverId: data.driverId,
      };
    });
    await deliverDriverViolationPush({
      recipientIds: [result.driverId],
      title: result.status === DRIVER_VIOLATION_STATUS.resolved
        ? 'Restricted-area case resolved'
        : result.status === DRIVER_VIOLATION_STATUS.dismissed
          ? 'Restricted-area case dismissed'
          : 'Restricted-area case updated',
      body: note || 'An administrator updated your restricted-area case.',
      violationId,
    });
    return { violationId, status: result.status };
  },
);

exports.sendDriverViolationMessage = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before messaging.');
    }
    const violationId = request.data?.violationId;
    const messageId = request.data?.messageId;
    if (!validDriverViolationIdentifier(violationId) ||
        !validDriverViolationIdentifier(messageId)) {
      throw new HttpsError(
        'invalid-argument',
        'Valid violation and message IDs are required.',
      );
    }
    const body = requiredString(
      request.data?.message ?? request.data?.body,
      'Message',
    ).slice(0, 2000);
    const user = await db.collection('users').doc(request.auth.uid).get();
    if (!user.exists || user.data().isActive === false) {
      throw new HttpsError(
        'permission-denied',
        'An active account is required.',
      );
    }
    const actor = driverViolationActor(request, user.data());
    const senderName = driverViolationSenderName(user.data(), actor.role);
    const violationRef = db.collection('driverViolations').doc(violationId);
    const messageRef = violationRef.collection('messages').doc(messageId);
    const result = await db.runTransaction(async (transaction) => {
      const [violation, existingMessage] = await Promise.all([
        transaction.get(violationRef),
        transaction.get(messageRef),
      ]);
      if (!violation.exists ||
          !actorCanAccessDriverViolation(actor, violation.data())) {
        throw new HttpsError(
          'permission-denied',
          'You cannot access this driver violation case.',
        );
      }
      if (existingMessage.exists) {
        if (existingMessage.data().senderId === actor.uid) {
          return {
            idempotent: true,
            driverId: violation.data().driverId,
            ownerTodaId: violation.data().ownerTodaId,
          };
        }
        throw new HttpsError(
          'already-exists',
          'This message ID is already in use.',
        );
      }
      transaction.create(messageRef, {
        schemaVersion: 1,
        messageId,
        violationId,
        senderId: actor.uid,
        senderRole: actor.role,
        senderName,
        senderTodaId: actor.todaId || null,
        body,
        seenBy: [actor.uid],
        delivery: {
          status: 'pending',
          recipientCount: 0,
          attemptedCount: 0,
          successCount: 0,
        },
        sentAt: timestamp(),
        createdAt: timestamp(),
      });
      transaction.update(violationRef, {
        lastMessage: body.slice(0, 240),
        lastMessageAt: timestamp(),
        lastMessageBy: actor.uid,
        messageCount: FieldValue.increment(1),
        updatedAt: timestamp(),
      });
      return {
        idempotent: false,
        driverId: violation.data().driverId,
        ownerTodaId: violation.data().ownerTodaId,
      };
    });
    if (!result.idempotent) {
      const adminIds = await driverViolationAdminRecipientIds(
        result.ownerTodaId,
      );
      const recipients = new Set([result.driverId, ...adminIds]);
      recipients.delete(actor.uid);
      const delivery = await deliverDriverViolationPush({
        recipientIds: [...recipients],
        title: 'New restricted-area case message',
        // Avoid exposing full case text on a lock screen or overflowing FCM's
        // payload budget. Authorized members fetch it from the case thread.
        body: 'Open VolTrike to read the new case message.',
        violationId,
        messageId,
        type: 'driver_violation_message',
      });
      await messageRef.set({
        delivery: {
          status: delivery.successCount > 0
            ? 'delivered'
            : delivery.attemptedCount > 0
              ? 'delivery_failed'
              : 'no_registered_recipient_device',
          ...delivery,
          lastAttemptAt: timestamp(),
        },
      }, { merge: true });
    }
    return { violationId, messageId, idempotent: result.idempotent };
  },
);

exports.markDriverViolationMessagesRead = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before messaging.');
    }
    const violationId = request.data?.violationId;
    if (!validDriverViolationIdentifier(violationId)) {
      throw new HttpsError(
        'invalid-argument',
        'A valid driver violation ID is required.',
      );
    }
    const [user, violation] = await Promise.all([
      db.collection('users').doc(request.auth.uid).get(),
      db.collection('driverViolations').doc(violationId).get(),
    ]);
    if (!user.exists || !violation.exists) {
      throw new HttpsError('not-found', 'Driver violation case not found.');
    }
    const actor = driverViolationActor(request, user.data());
    if (!actorCanAccessDriverViolation(actor, violation.data())) {
      throw new HttpsError(
        'permission-denied',
        'You cannot access this driver violation case.',
      );
    }
    const messages = await violation.ref.collection('messages')
      .orderBy('sentAt', 'desc')
      .limit(100)
      .get();
    if (!messages.empty) {
      const batch = db.batch();
      messages.docs.forEach((message) => {
        if (!(message.data().seenBy || []).includes(actor.uid)) {
          batch.update(message.ref, {
            seenBy: FieldValue.arrayUnion(actor.uid),
          });
        }
      });
      await batch.commit();
    }
    return { markedRead: messages.size };
  },
);

function adminPageSize(value) {
  return Number.isInteger(value) && value >= 1 && value <= 100 ? value : 25;
}

function adminString(value) {
  return typeof value === 'string' ? value.trim().toLowerCase().slice(0, 100) : '';
}

function adminDate(value) {
  return value?.toDate?.()?.toISOString?.() || value || null;
}

exports.getSystemDiagnostics = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in to run diagnostics.');
    }
    return {
      compatible: true,
      functionsProtocolVersion: 4,
      minimumClientProtocolVersion: 3,
      bookingSchemaVersion: 2,
      firestoreRulesVersion: 4,
      realtimeRulesVersion: 4,
      storageRulesVersion: 2,
      region: 'asia-southeast1',
      projectId: process.env.GCLOUD_PROJECT || null,
      checkedAt: new Date().toISOString(),
    };
  },
);

exports.getDriverEarningsSummary = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in to view earnings.');
    }
    const driverId = request.auth.uid;
    const driver = await db.collection('drivers').doc(driverId).get();
    if (!driver.exists || driver.data().driverStatus !== 'approved') {
      throw new HttpsError(
        'failed-precondition',
        'An approved driver profile is required.',
      );
    }
    const periods = driverEarningsPeriodStarts();
    const completed = db.collection('bookings')
      .where('driverId', '==', driverId)
      .where('status', '==', BOOKING_STATUS.completed);
    const aggregate = (query) => query.aggregate({
      total: AggregateField.sum('driverNetEarnings'),
      count: AggregateField.count(),
    }).get();
    const [all, today, week, month] = await Promise.all([
      aggregate(completed),
      aggregate(completed.where(
        'completedAt',
        '>=',
        Timestamp.fromDate(periods.day),
      )),
      aggregate(completed.where(
        'completedAt',
        '>=',
        Timestamp.fromDate(periods.week),
      )),
      aggregate(completed.where(
        'completedAt',
        '>=',
        Timestamp.fromDate(periods.month),
      )),
    ]);
    const money = (snapshot) => {
      const value = Number(snapshot.data().total || 0);
      return Number.isFinite(value) ? Math.round(value * 100) / 100 : 0;
    };
    const completedTrips = Number(all.data().count || 0);
    const total = money(all);
    return {
      today: money(today),
      week: money(week),
      month: money(month),
      total,
      completedTrips,
      averageNetEarnings: completedTrips > 0
        ? Math.round((total / completedTrips) * 100) / 100
        : 0,
      timeZone: 'Asia/Manila',
    };
  },
);

exports.adminGetMetrics = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const scoped = (collectionName) => actor.role === 'toda_admin'
      ? db.collection(collectionName).where('todaId', '==', actor.todaId)
      : db.collection(collectionName);
    const drivers = scoped('drivers');
    const bookings = scoped('bookings');
    const reports = scoped('reports');
    const zones = scoped('zoneRequests');
    const safetyIncidents = scoped('safetyIncidents');
    const openReportsQuery = actor.role === 'toda_admin'
      ? reports
        .where('status', '==', 'open')
        .where('reviewAudience', 'array-contains', 'toda_admin')
      : reports.where('status', '==', 'open');
    const [driverCount, openReports, pendingZones, completedTrips,
      bookingCount, openSafetyIncidents] =
      await Promise.all([
      drivers.count().get(),
      openReportsQuery.count().get(),
      zones.where('status', '==', 'pending').count().get(),
      bookings.where('status', '==', BOOKING_STATUS.completed).count().get(),
      bookings.count().get(),
      safetyIncidents.where('status', '==', 'open').count().get(),
    ]);
    return {
      drivers: driverCount.data().count,
      reports: openReports.data().count,
      zones: pendingZones.data().count,
      trips: completedTrips.data().count,
      bookings: bookingCount.data().count,
      safetyIncidents: openSafetyIncidents.data().count,
      scope: actor.role === 'toda_admin' ? actor.todaId : 'platform',
    };
  },
);

exports.adminListDrivers = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const pageSize = adminPageSize(request.data?.pageSize);
    const search = adminString(request.data?.search);
    let query = db.collection('drivers').orderBy(FieldPath.documentId());
    if (actor.role === 'toda_admin') {
      query = db.collection('drivers')
        .where('todaId', '==', actor.todaId)
        .orderBy(FieldPath.documentId());
    }
    const cursor = request.data?.cursor;
    if (typeof cursor === 'string' && cursor.length > 0) {
      query = query.startAfter(cursor);
    }
    if (!search) query = query.limit(pageSize + 1);
    const snapshot = await query.get();
    const candidates = search ? snapshot.docs : snapshot.docs.slice(0, pageSize);
    const [profiles, vehicles] = candidates.length
      ? await Promise.all([
        db.getAll(...candidates.map((entry) => db.collection('users').doc(entry.id))),
        db.getAll(...candidates.map((entry) => db.collection('vehicles')
          .doc(entry.data().vehicleId || '_missing'))),
      ])
      : [[], []];
    let items = candidates.map((entry, index) => {
      const driver = entry.data();
      const profile = profiles[index]?.data() || {};
      return {
        uid: entry.id,
        ...driver,
        licenseExpiry: adminDate(driver.licenseExpiry),
        applicant: {
          firstName: profile.firstName || '',
          middleName: profile.middleName || '',
          lastName: profile.lastName || '',
          email: profile.email || '',
          phoneNumber: profile.phoneNumber || '',
          dateOfBirth: adminDate(profile.dateOfBirth),
          profileImage: profile.profileImage || '',
        },
        vehicle: vehicles[index]?.exists
          ? {
            id: vehicles[index].id,
            ...vehicles[index].data(),
          }
          : null,
      };
    });
    if (search) {
      items = items.filter((item) => [
        item.uid,
        item.todaId,
        item.licenseNumber,
        item.applicant.firstName,
        item.applicant.middleName,
        item.applicant.lastName,
        item.applicant.email,
        item.applicant.phoneNumber,
      ].some((value) => String(value || '').toLowerCase().includes(search)));
      items = items.slice(0, pageSize);
    }
    return {
      items,
      nextCursor: !search && snapshot.docs.length > pageSize
        ? candidates.at(-1)?.id || null
        : null,
    };
  },
);

exports.adminListRatings = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    if (actor.role !== 'toda_admin') {
      throw new HttpsError(
        'permission-denied',
        'Driver ratings are managed by the assigned TODA administrator.',
      );
    }
    const pageSize = adminPageSize(request.data?.pageSize);
    const ratings = db.collection('ratings');
    let query = ratings
      .where('todaId', '==', actor.todaId)
      .orderBy('createdAt', 'desc');
    const cursor = request.data?.cursor;
    if (typeof cursor === 'string' && cursor.length > 0) {
      const cursorDocument = await ratings.doc(cursor).get();
      if (cursorDocument.exists) {
        query = query.startAfter(cursorDocument);
      }
    }
    const snapshot = await query.limit(pageSize + 1).get();
    const page = snapshot.docs.slice(0, pageSize);
    const items = page.map((entry) => {
      const rating = entry.data();
      return {
        id: entry.id,
        ...rating,
        createdAt: adminDate(rating.createdAt),
      };
    });
    return {
      items,
      nextCursor: snapshot.docs.length > pageSize
        ? page.at(-1)?.id || null
        : null,
    };
  },
);

exports.adminListReports = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const pageSize = adminPageSize(request.data?.pageSize);
    const search = adminString(request.data?.search);
    let query = db.collection('reports').orderBy(FieldPath.documentId());
    if (actor.role === 'toda_admin') {
      query = db.collection('reports')
        .where('todaId', '==', actor.todaId)
        .orderBy(FieldPath.documentId());
    }
    const cursor = request.data?.cursor;
    if (typeof cursor === 'string' && cursor.length > 0) {
      query = query.startAfter(cursor);
    }
    // TODA visibility also depends on the report audience. Fetch the TODA
    // scope first so passenger-account reports intended for developer review
    // cannot leak merely because they share a booking's TODA ID.
    if (!search && actor.role !== 'toda_admin') {
      query = query.limit(pageSize + 1);
    }
    const snapshot = await query.get();
    const visible = actor.role === 'toda_admin'
      ? snapshot.docs.filter((entry) => {
        const audience = entry.data().reviewAudience;
        return !Array.isArray(audience) || audience.includes('toda_admin');
      })
      : snapshot.docs;
    const candidates = visible.slice(0, pageSize);
    const userIds = [...new Set(candidates.flatMap((entry) => [
      entry.data().reporterId,
      entry.data().reportedUserId,
    ]).filter(Boolean))];
    const profiles = userIds.length
      ? await db.getAll(...userIds.map((uid) => db.collection('users').doc(uid)))
      : [];
    const profileById = new Map(
      profiles.map((profile) => [profile.id, profile.data() || {}]),
    );
    let items = candidates.map((entry) => {
      const report = entry.data();
      return {
        id: entry.id,
        ...report,
        createdAt: adminDate(report.createdAt),
        reporter: profileById.get(report.reporterId) || null,
        reportedUser: profileById.get(report.reportedUserId) || null,
      };
    });
    if (search) {
      items = items.filter((item) => [
        item.id,
        item.bookingId,
        item.category,
        item.reporterName,
        item.reportedUserName,
        item.status,
      ].some((value) => String(value || '').toLowerCase().includes(search)));
      items = items.slice(0, pageSize);
    }
    return {
      items,
      nextCursor: !search && visible.length > pageSize
        ? candidates.at(-1)?.id || null
        : null,
    };
  },
);

exports.adminListBookings = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const pageSize = adminPageSize(request.data?.pageSize);
    const search = adminString(request.data?.search);
    let query = db.collection('bookings').orderBy(FieldPath.documentId());
    if (actor.role === 'toda_admin') {
      query = db.collection('bookings')
        .where('todaId', '==', actor.todaId)
        .orderBy(FieldPath.documentId());
    }
    const cursor = request.data?.cursor;
    if (typeof cursor === 'string' && cursor.length > 0) {
      query = query.startAfter(cursor);
    }
    if (!search) query = query.limit(pageSize + 1);
    const snapshot = await query.get();
    const candidates = search ? snapshot.docs : snapshot.docs.slice(0, pageSize);
    const settlements = candidates.length
      ? await db.getAll(
        ...candidates.map((entry) => db.collection('settlements').doc(entry.id)),
      )
      : [];
    let items = candidates.map((entry, index) => {
      const booking = entry.data();
      const settlement = settlements[index]?.data() || null;
      return {
        bookingId: entry.id,
        schemaVersion: booking.schemaVersion || 0,
        status: booking.status,
        passengerName: booking.passengerName || 'Passenger',
        driverName: booking.driverName || null,
        driverId: booking.driverId || null,
        plateNumber: booking.plateNumber || null,
        todaId: booking.todaId || null,
        todaName: booking.todaName || null,
        pickupAddress: booking.pickupAddress,
        destinationAddress: booking.destinationAddress,
        amountDue: Number(booking.amountDue ?? booking.estimatedFare ?? 0),
        paymentMethod: booking.paymentMethod || 'cash',
        settlementStatus: booking.settlementStatus || 'not_recorded',
        adjustmentStatus: settlement?.adjustmentStatus || 'none',
        disputeReason: settlement?.disputeReason || null,
        receiptNumber: booking.receiptNumber || null,
        cancellationCode: booking.cancellationCode || null,
        createdAt: adminDate(booking.createdAt),
        updatedAt: adminDate(booking.updatedAt),
        settlement,
      };
    });
    if (search) {
      items = items.filter((item) => [
        item.bookingId,
        item.passengerName,
        item.driverName,
        item.driverId,
        item.plateNumber,
        item.receiptNumber,
        item.status,
      ].some((value) => String(value || '').toLowerCase().includes(search)));
      items = items.slice(0, pageSize);
    }
    return {
      items,
      nextCursor: !search && snapshot.docs.length > pageSize
        ? candidates.at(-1)?.id || null
        : null,
    };
  },
);

exports.adminListSafetyIncidents = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const pageSize = adminPageSize(request.data?.pageSize);
    const incidents = db.collection('safetyIncidents');
    let query = incidents.orderBy(FieldPath.documentId());
    if (actor.role === 'toda_admin') {
      query = incidents
        .where('todaId', '==', actor.todaId)
        .orderBy(FieldPath.documentId());
    }
    const cursor = request.data?.cursor;
    if (typeof cursor === 'string' && cursor.length > 0) {
      query = query.startAfter(cursor);
    }
    const snapshot = await query.limit(pageSize + 1).get();
    const page = snapshot.docs.slice(0, pageSize);
    const driverIds = [...new Set(page
      .map((entry) => entry.data().driverId)
      .filter((value) => typeof value === 'string' && value.length > 0))];
    const liveLocations = new Map(await Promise.all(driverIds.map(async (id) => {
      const location = await realtime.ref(`driver_locations/${id}`).get();
      return [id, location.exists() ? location.val() : null];
    })));
    const now = Date.now();
    return {
      items: page.map((entry) => {
        const incident = entry.data();
        const live = liveLocations.get(incident.driverId);
        const liveTimestamp = Number(live?.timestamp || live?.updatedAt);
        const liveLocation = live &&
          live.online === true &&
          Number.isFinite(Number(live.latitude)) &&
          Number.isFinite(Number(live.longitude)) &&
          Number.isFinite(Number(live.accuracy)) &&
          Number(live.accuracy) >= 0 &&
          Number(live.accuracy) <= 100 &&
          Number.isFinite(liveTimestamp) &&
          now - liveTimestamp <= driverLocationMaxAgeMs &&
          liveTimestamp <= now + 10000
          ? {
            latitude: Number(live.latitude),
            longitude: Number(live.longitude),
            accuracy: Number(live.accuracy || 0),
            bearing: Number(live.bearing || 0),
            speed: Number(live.speed || 0),
            timestamp: liveTimestamp,
            online: live.online === true,
          }
          : null;
        return {
          id: entry.id,
          ...incident,
          responseStatus: normalizedResponseStatus(incident),
          driverLocation: liveLocation || incident.driverLocation || null,
          locationSource: liveLocation ? 'live_driver_location' : 'sos_snapshot',
          createdAt: adminDate(incident.createdAt),
          updatedAt: adminDate(incident.updatedAt),
          acknowledgedAt: adminDate(incident.acknowledgedAt),
          respondingAt: adminDate(incident.respondingAt),
          resolvedAt: adminDate(incident.resolvedAt),
          deliveredAt: adminDate(incident.deliveredAt),
          escalatedAt: adminDate(incident.escalatedAt),
        };
      }),
      nextCursor: snapshot.docs.length > pageSize
        ? page.at(-1)?.id || null
        : null,
    };
  },
);

exports.adminUpdateSafetyIncidentResponse = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const incidentId = requiredString(request.data?.incidentId, 'Incident ID');
    const action = requiredString(request.data?.action, 'Response action');
    if (!['acknowledge', 'responding', 'resolve'].includes(action)) {
      throw new HttpsError(
        'invalid-argument',
        'Choose acknowledge, responding, or resolve.',
      );
    }
    const note = String(request.data?.note || '').trim().slice(0, 1000);
    if (action === 'resolve' && note.length === 0) {
      throw new HttpsError(
        'invalid-argument',
        'Add a short resolution note before closing an SOS.',
      );
    }
    const incidentRef = db.collection('safetyIncidents').doc(incidentId);
    const result = await db.runTransaction(async (transaction) => {
      const incident = await transaction.get(incidentRef);
      if (!incident.exists) {
        throw new HttpsError('not-found', 'Safety incident not found.');
      }
      const data = incident.data();
      await assertTodaScope(actor, data.todaId);
      if (data.status === 'accidental') {
        throw new HttpsError(
          'failed-precondition',
          'Accidental presses do not require an emergency response.',
        );
      }
      const current = normalizedResponseStatus(data);
      const next = nextAdminResponseStatus(current, action);
      if (!next) {
        throw new HttpsError(
          'failed-precondition',
          'This SOS is already resolved.',
        );
      }
      const update = {
        responseStatus: next,
        lastResponseNote: note || null,
        lastRespondedBy: actor.uid,
        updatedAt: timestamp(),
      };
      if (action === 'acknowledge' && current === 'reported') {
        update.acknowledgedAt = timestamp();
        update.acknowledgedBy = actor.uid;
      }
      if (action === 'responding') {
        update.respondingAt = timestamp();
        update.respondingBy = actor.uid;
      }
      if (action === 'resolve') {
        update.status = 'resolved';
        update.resolvedAt = timestamp();
        update.resolvedBy = actor.uid;
        update.resolutionNote = note;
      }
      transaction.update(incidentRef, update);
      transaction.create(db.collection('auditLogs').doc(), {
        type: 'admin_action',
        actorId: actor.uid,
        actorRole: actor.role,
        actorTodaId: actor.todaId || null,
        action: `safety_incident_${action}`,
        targetType: 'safety_incident',
        targetId: incidentId,
        details: { note },
        createdAt: timestamp(),
      });
      return {
        responseStatus: next,
        reportedBy: data.reportedBy,
        reporterRole: data.reporterRole,
        bookingId: data.bookingId,
      };
    });
    const messages = {
      acknowledge: [
        'Your SOS was acknowledged',
        'An administrator has seen your SOS and is reviewing it.',
      ],
      responding: [
        'Safety response started',
        'An administrator marked your SOS as actively being handled.',
      ],
      resolve: [
        'Safety incident resolved',
        'An administrator recorded a resolution. Reopen the SOS if you still need help.',
      ],
    };
    const message = messages[action];
    if (result.reportedBy && message) {
      await sendToUser(
        result.reportedBy,
        message[0],
        message[1],
        {
          type: 'safety_incident',
          bookingId: result.bookingId,
          target: result.reporterRole,
          incidentId,
        },
      );
    }
    return { responseStatus: result.responseStatus };
  },
);

exports.adminListLiveDrivers = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    let query = db.collection('drivers')
      .where('driverStatus', '==', 'approved')
      .where('isOnline', '==', true)
      .limit(200);
    if (actor.role === 'toda_admin') {
      query = db.collection('drivers')
        .where('todaId', '==', actor.todaId)
        .where('driverStatus', '==', 'approved')
        .where('isOnline', '==', true)
        .limit(200);
    }
    let drivers;
    let locationMap;
    if (actor.role === 'toda_admin') {
      drivers = await query.get();
      const locationSnapshots = await Promise.all(
        drivers.docs.map((entry) =>
          realtime.ref(`driver_locations/${entry.id}`).get()),
      );
      locationMap = Object.fromEntries(drivers.docs.map((entry, index) => [
        entry.id,
        locationSnapshots[index].exists()
          ? locationSnapshots[index].val()
          : null,
      ]));
    } else {
      const [driverSnapshot, locations] = await Promise.all([
        query.get(),
        realtime.ref('driver_locations').get(),
      ]);
      drivers = driverSnapshot;
      locationMap = locations.val() || {};
    }
    const now = Date.now();
    const candidates = drivers.docs.filter((entry) => {
      const location = locationMap[entry.id];
      return location &&
        location.online === true &&
        Number.isFinite(Number(location.latitude)) &&
        Number.isFinite(Number(location.longitude)) &&
        Number.isFinite(Number(location.accuracy)) &&
        Number(location.accuracy) >= 0 &&
        Number(location.accuracy) <= 100 &&
        Number.isFinite(Number(location.timestamp)) &&
        now - Number(location.timestamp) <= driverLocationMaxAgeMs &&
        Number(location.timestamp) <= now + 10000;
    });
    if (candidates.length === 0) return { items: [] };
    const [profiles, vehicles] = await Promise.all([
      db.getAll(
        ...candidates.map((entry) => db.collection('users').doc(entry.id)),
      ),
      db.getAll(
        ...candidates.map((entry) => db.collection('vehicles')
          .doc(entry.data().vehicleId || '_missing')),
      ),
    ]);
    const bookingIds = [...new Set(candidates
      .map((entry) => entry.data().currentBookingId)
      .filter((value) => typeof value === 'string' && value.length > 0))];
    const bookingSnapshots = bookingIds.length > 0
      ? await db.getAll(
        ...bookingIds.map((id) => db.collection('bookings').doc(id)),
      )
      : [];
    const bookingById = new Map(
      bookingSnapshots.map((entry) => [entry.id, entry.data() || {}]),
    );
    return {
      items: candidates.map((entry, index) => {
        const driver = entry.data();
        const profile = profiles[index]?.data() || {};
        const vehicle = vehicles[index]?.data() || {};
        const location = locationMap[entry.id];
        const bookingId = driver.currentBookingId || null;
        const booking = bookingId ? bookingById.get(bookingId) : null;
        return {
          uid: entry.id,
          name: [
            profile.firstName,
            profile.middleName,
            profile.lastName,
          ].filter(Boolean).join(' ') || 'Driver',
          todaId: driver.todaId || '',
          latitude: Number(location.latitude),
          longitude: Number(location.longitude),
          accuracy: Number(location.accuracy || 0),
          timestamp: Number(location.timestamp),
          bookingId,
          bookingStatus: booking?.status || (
            driver.isAvailable === true ? 'available' : 'online'
          ),
          vehicleType: vehicle.vehicleType || vehicle.type ||
            vehicle.vehicleNumber || null,
          plateNumber: vehicle.plateNumber || null,
        };
      }),
    };
  },
);

exports.adminCancelBookingForSafety = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const incidentId = requiredString(request.data?.incidentId, 'Incident ID');
    const incidentRef = db.collection('safetyIncidents').doc(incidentId);
    const result = await db.runTransaction(async (transaction) => {
      const incident = await transaction.get(incidentRef);
      if (!incident.exists) {
        throw new HttpsError('not-found', 'Safety incident not found.');
      }
      const incidentData = incident.data();
      await assertTodaScope(actor, incidentData.todaId);
      if (incidentData.status !== 'open') {
        throw new HttpsError(
          'failed-precondition',
          'This safety incident is no longer open.',
        );
      }
      const createdAt = snapshotDateMillis(incidentData.createdAt);
      if (createdAt == null ||
          Date.now() - createdAt < SOS_UNRESPONSIVE_MS) {
        throw new HttpsError(
          'failed-precondition',
          'Wait five minutes and attempt contact before cancelling the ride.',
        );
      }
      const bookingRef = db.collection('bookings').doc(
        incidentData.bookingId,
      );
      const booking = await transaction.get(bookingRef);
      if (!booking.exists) {
        throw new HttpsError('not-found', 'Booking not found.');
      }
      const data = booking.data();
      if (data.status === BOOKING_STATUS.passengerOnBoard ||
          data.status === BOOKING_STATUS.paymentConfirmation) {
        throw new HttpsError(
          'failed-precondition',
          'Do not remotely cancel an onboard ride. Contact 911 and continue monitoring.',
        );
      }
      if (![BOOKING_STATUS.pending, BOOKING_STATUS.driverAssigned,
        BOOKING_STATUS.driverArriving].includes(data.status)) {
        throw new HttpsError(
          'failed-precondition',
          'This booking has already closed or changed state.',
        );
      }
      const driverRef = data.driverId
        ? db.collection('drivers').doc(data.driverId)
        : null;
      const passengerLockRef = db.collection('activePassengerBookings')
        .doc(data.passengerId);
      const [driver, passengerLock] = await Promise.all([
        driverRef ? transaction.get(driverRef) : Promise.resolve(null),
        transaction.get(passengerLockRef),
      ]);
      transaction.update(bookingRef, {
        status: BOOKING_STATUS.cancelled,
        cancelledAt: timestamp(),
        cancelledBy: actor.uid,
        cancellationCode: 'admin_safety_unresponsive',
        cancellationDetail:
          'Cancelled by an administrator after an open SOS remained unresponsive for at least five minutes.',
        updatedAt: timestamp(),
      });
      if (driverRef && driver?.exists &&
          driver.data().currentBookingId === booking.id) {
        transaction.update(driverRef, {
          currentBookingId: null,
          isAvailable: driver.data().isOnline === true &&
            driver.data().driverStatus === 'approved',
          updatedAt: timestamp(),
        });
      }
      if (passengerLock.exists &&
          passengerLock.data().bookingId === booking.id) {
        transaction.delete(passengerLockRef);
      }
      transaction.update(incidentRef, {
        bookingStatus: BOOKING_STATUS.cancelled,
        bookingSafetyAction: 'admin_cancelled_unresponsive',
        bookingCancelledForSafety: true,
        cancelledBookingAt: timestamp(),
        cancelledBookingBy: actor.uid,
        updatedAt: timestamp(),
      });
      transaction.create(db.collection('auditLogs').doc(), {
        type: 'admin_action',
        actorId: actor.uid,
        actorRole: actor.role,
        actorTodaId: actor.todaId || null,
        action: 'cancel_booking_after_sos_timeout',
        targetType: 'booking',
        targetId: booking.id,
        details: { incidentId },
        createdAt: timestamp(),
      });
      return {
        bookingId: booking.id,
        passengerId: data.passengerId,
        driverId: data.driverId || null,
      };
    });
    await expireBookingOffers(result.bookingId, 'closed');
    if (result.driverId) {
      await realtime
        .ref(`driver_tracking_access/${result.passengerId}/${result.driverId}`)
        .remove();
    }
    return { cancelled: true };
  },
);

// Keeps dispatch eligibility and the driver's online state under one trusted
// backend decision. Client profile writes cannot modify these fields.
exports.setDriverOnlineStatus = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in as a driver first.');
    }
    if (typeof request.data?.isOnline !== 'boolean') {
      throw new HttpsError('invalid-argument', 'Online status is required.');
    }

    const uid = request.auth.uid;
    const isOnline = request.data.isOnline;
    const userRef = db.collection('users').doc(uid);
    const driverRef = db.collection('drivers').doc(uid);
    const auditRef = db.collection('auditLogs').doc();

    const result = await db.runTransaction(async (transaction) => {
      const [user, driver] = await Promise.all([
        transaction.get(userRef),
        transaction.get(driverRef),
      ]);
      if (!user.exists || user.data().role !== 'driver' ||
          user.data().isActive === false || !driver.exists) {
        throw new HttpsError(
          'failed-precondition',
          'An active driver profile is required.',
        );
      }

      const driverData = driver.data();
      if (driverData.driverStatus !== 'approved') {
        throw new HttpsError(
          'failed-precondition',
          'Driver approval is required before going online.',
        );
      }
      if (!isOnline && typeof driverData.currentBookingId === 'string' &&
          driverData.currentBookingId.length > 0) {
        throw new HttpsError(
          'failed-precondition',
          'Complete or cancel the active trip before going offline.',
        );
      }

      const todaRef = db.collection('todas').doc(driverData.todaId || '_missing');
      const vehicleRef = db.collection('vehicles').doc(
        driverData.vehicleId || '_missing',
      );
      const [toda, vehicle] = await Promise.all([
        transaction.get(todaRef),
        transaction.get(vehicleRef),
      ]);
      if (isOnline && (!toda.exists || toda.data().isActive === false)) {
        throw new HttpsError(
          'failed-precondition',
          'Your TODA is not currently active.',
        );
      }
      if (isOnline && !vehicle.exists) {
        throw new HttpsError(
          'failed-precondition',
          'A registered vehicle is required before going online.',
        );
      }
      if (isOnline && vehicle.data().isVerified !== true) {
        throw new HttpsError(
          'failed-precondition',
          'Your vehicle verification is not active.',
        );
      }
      const licenseExpiry = snapshotDateMillis(driverData.licenseExpiry);
      if (isOnline &&
          (typeof driverData.licenseNumber !== 'string' ||
            driverData.licenseNumber.trim().length === 0 ||
            licenseExpiry == null ||
            licenseExpiry < Date.now())) {
        throw new HttpsError(
          'failed-precondition',
          'A current driver license is required before going online.',
        );
      }

      const hasBooking = typeof driverData.currentBookingId === 'string' &&
        driverData.currentBookingId.length > 0;
      const isAvailable = isOnline && !hasBooking;
      transaction.update(driverRef, {
        isOnline,
        isAvailable,
        updatedAt: timestamp(),
      });
      transaction.create(auditRef, {
        type: 'driver_availability',
        action: isOnline ? 'go_online' : 'go_offline',
        actorId: uid,
        driverId: uid,
        todaId: driverData.todaId || null,
        isOnline,
        isAvailable,
        createdAt: timestamp(),
      });
      return { isOnline, isAvailable };
    });

    if (!isOnline) {
      await Promise.all([
        realtime.ref(`driver_locations/${uid}`).remove(),
        realtime.ref(`driver_presence/${uid}`).set({
          online: false,
          updatedAt: ServerValue.TIMESTAMP,
        }),
      ]);
    }
    return result;
  },
);

function goQuoteInput({
  actorId,
  pickup,
  destination,
  additionalPassengers,
  baggageCount,
  issueToken = false,
}) {
  return {
    actorId,
    pickup,
    destination,
    additionalPassengers,
    baggageCount,
    issueToken,
  };
}

function goQuoteHttpsError(error) {
  if (!(error instanceof GoServiceError)) {
    return new HttpsError(
      'unavailable',
      'The route and fare service is temporarily unavailable.',
    );
  }
  const code = {
    invalid_argument: 'invalid-argument',
    failed_precondition: 'failed-precondition',
    unauthenticated: 'unauthenticated',
    permission_denied: 'permission-denied',
    unavailable: 'unavailable',
  }[error.code] || 'internal';
  return new HttpsError(code, error.message);
}

function normalizedGoBookingQuote(raw) {
  const quote = raw?.quote;
  const coverage = quote?.coverage;
  const distance = Number(quote?.distanceMeters);
  if (!quote || !coverage || !Number.isInteger(distance) || distance <= 0 ||
      typeof quote.authoritativeRoutePolyline !== 'string' ||
      quote.authoritativeRoutePolyline.length === 0 ||
      !Array.isArray(coverage.primaryTodaIds) ||
      !Array.isArray(coverage.secondaryTodaIds) ||
      !Array.isArray(coverage.eligibleTodaIds)) {
    throw new GoServiceError(
      'internal',
      'Go service returned an incomplete booking quote.',
      500,
    );
  }
  const pricing = fareSnapshot(quote.fareSnapshot);
  const fareBreakdown = calculateFareBreakdown({
    config: pricing,
    distanceMeters: distance,
    additionalPassengers: Number(quote.fareBreakdown?.additionalPassengers),
    baggageCount: Number(quote.fareBreakdown?.baggageCount),
    isOutsideToda: coverage.isOutsideToda === true,
  });
  if (Math.abs(fareBreakdown.total - Number(quote.estimatedFare)) > 0.001 ||
      Math.abs(fareBreakdown.total - Number(quote.fareBreakdown?.total)) >
        0.001) {
    throw new GoServiceError(
      'internal',
      'Go and Node fare calculations did not match.',
      500,
    );
  }
  return {
    coverage: {
      configured: coverage.configured === true,
      serviceable: coverage.serviceable !== false,
      isOutsideToda: coverage.isOutsideToda === true,
      coverageClass: String(coverage.coverageClass || 'unconfigured_fallback'),
      pickupTodaIds: coverage.pickupTodaIds || [],
      destinationTodaIds: coverage.destinationTodaIds || [],
      sharedTodaIds: coverage.sharedTodaIds || [],
      primaryTodaIds: coverage.primaryTodaIds,
      secondaryTodaIds: coverage.secondaryTodaIds,
      allowAnyActiveToda: coverage.allowAnyActiveToda === true,
      eligibleTodaIds: coverage.eligibleTodaIds,
      serviceTodaId: coverage.serviceTodaId || null,
      geofenceRevisions: coverage.geofenceRevisions || {},
    },
    route: {
      distanceMeters: distance,
      duration: String(quote.estimatedDuration || ''),
      encodedPolyline: quote.authoritativeRoutePolyline,
      restrictionIdsChecked: quote.routeRestrictionIdsChecked || [],
      avoidedRestrictionIds: quote.avoidedRouteRestrictionIds || [],
      avoidedRestrictionNames: quote.avoidedRouteRestrictionNames || [],
      highwayRouteAdvisory: quote.highwayRouteAdvisory || null,
    },
    pricing,
    fareBreakdown,
    distanceMeters: distance,
    estimatedFare: fareBreakdown.total,
    policyRevision: String(quote.policyRevision || ''),
    quoteExpiresAt: quote.expiresAt || null,
  };
}

async function authoritativeGoBookingQuote({
  actorId,
  pickup,
  destination,
  additionalPassengers,
  baggageCount,
  quoteToken,
  issueToken = false,
}) {
  const input = goQuoteInput({
    actorId,
    pickup,
    destination,
    additionalPassengers,
    baggageCount,
    issueToken,
  });
  const response = quoteToken
    ? await goService.consumeQuote({ ...input, quoteToken })
    : await goService.computeQuote(input);
  return {
    ...normalizedGoBookingQuote(response),
    quoteToken: typeof response?.quoteToken === 'string'
      ? response.quoteToken
      : '',
  };
}

exports.createBookingQuote = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before requesting a fare.');
    }
    if (!goService.quotesEnabled()) {
      throw new HttpsError(
        'failed-precondition',
        'The Go quote bridge is not enabled.',
      );
    }
    const pickup = parseCoordinate(request.data?.pickup, 'Pickup');
    const destination = parseCoordinate(request.data?.destination, 'Destination');
    const additionalPassengers = validNonNegativeInteger(
      request.data?.additionalPassengers,
      'Additional passengers',
      3,
    );
    const baggageCount = validNonNegativeInteger(
      request.data?.baggageCount,
      'Baggage count',
      1,
    );
    try {
      const result = await authoritativeGoBookingQuote({
        actorId: request.auth.uid,
        pickup,
        destination,
        additionalPassengers,
        baggageCount,
        issueToken: true,
      });
      return {
        distanceMeters: result.distanceMeters,
        estimatedFare: result.estimatedFare,
        estimatedDuration: result.route.duration,
        authoritativeRoutePolyline: result.route.encodedPolyline,
        fareSnapshot: result.pricing,
        fareVersion: result.pricing.version,
        fareBreakdown: result.fareBreakdown,
        isOutsideToda: result.coverage.isOutsideToda,
        coverageClass: result.coverage.coverageClass,
        primaryTodaIds: result.coverage.primaryTodaIds,
        secondaryTodaIds: result.coverage.secondaryTodaIds,
        allowAnyActiveToda: result.coverage.allowAnyActiveToda,
        eligibleTodaIds: result.coverage.eligibleTodaIds,
        avoidedRouteRestrictionIds: result.route.avoidedRestrictionIds,
        avoidedRouteRestrictionNames: result.route.avoidedRestrictionNames,
        highwayRouteAdvisory: result.route.highwayRouteAdvisory,
        quoteToken: result.quoteToken,
        quoteExpiresAt: result.quoteExpiresAt,
      };
    } catch (error) {
      throw goQuoteHttpsError(error);
    }
  },
);

// Creates the durable booking, passenger display snapshot, active-booking
// lock, pickup secret, idempotency record, and audit event together.
exports.createBookingLifecycle = onCall(
  {
    region: 'asia-southeast1',
    secrets: [googleRoutesApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before booking a ride.');
    }
    const { bookingId, operationId } = lifecycleIdentity(request.data);
    const pickup = parseCoordinate(request.data?.pickup, 'Pickup');
    const destination = parseCoordinate(request.data?.destination, 'Destination');
    const pickupAddress = requiredString(request.data?.pickupAddress, 'Pickup address');
    const destinationAddress = requiredString(
      request.data?.destinationAddress,
      'Destination address',
    );
    const clientDistanceMeters = validNonNegativeInteger(
      request.data?.distanceMeters,
      'Distance',
      100000,
    );
    const clientEstimatedFare = validCurrency(
      request.data?.estimatedFare,
      'Estimated fare',
      0,
      100000,
    );
    const additionalPassengers = validNonNegativeInteger(
      request.data?.additionalPassengers,
      'Additional passengers',
      3,
    );
    const baggageCount = validNonNegativeInteger(
      request.data?.baggageCount,
      'Baggage count',
      1,
    );
    const clientIsOutsideToda =
      typeof request.data?.isOutsideToda === 'boolean'
        ? request.data.isOutsideToda
        : null;

    const uid = request.auth.uid;
    const userRef = db.collection('users').doc(uid);
    const bookingRef = db.collection('bookings').doc(bookingId);
    const lockRef = db.collection('activePassengerBookings').doc(uid);
    const operationRef = operationReference(bookingId, uid, operationId);
    const auditRef = auditReference(bookingId, uid, operationId);

    // Avoid a second Google call for ordinary retries while retaining the
    // transaction below as the final race-safe idempotency boundary.
    const [existingOperation, existingBooking] = await Promise.all([
      operationRef.get(),
      bookingRef.get(),
    ]);
    if (existingOperation.exists ||
        (existingBooking.exists &&
          existingBooking.data().passengerId === uid)) {
      return {
        bookingId,
        idempotent: true,
        distanceMeters: existingBooking.data()?.distanceMeters ?? null,
        estimatedFare: existingBooking.data()?.estimatedFare ?? null,
        authoritativeRoutePolyline:
          existingBooking.data()?.authoritativeRoutePolyline ?? null,
        fareSnapshot: existingBooking.data()?.fareSnapshot ?? null,
        fareVersion:
          existingBooking.data()?.fareVersion ??
          existingBooking.data()?.fareSnapshot?.version ??
          null,
        fareBreakdown: existingBooking.data()?.fareBreakdown ?? null,
        isOutsideToda: existingBooking.data()?.isOutsideToda ?? null,
        coverageClass:
          existingBooking.data()?.coverageDecision?.coverageClass ?? null,
        coveragePolicyVersion:
          existingBooking.data()?.coveragePolicyVersion ?? null,
        routePolicyVersion:
          existingBooking.data()?.routePolicyVersion ?? null,
        primaryTodaIds:
          existingBooking.data()?.primaryTodaIds ?? [],
        secondaryTodaIds:
          existingBooking.data()?.secondaryTodaIds ?? [],
        allowAnyActiveToda:
          existingBooking.data()?.allowAnyActiveToda === true,
        eligibleTodaIds:
          existingBooking.data()?.eligibleTodaIds ?? [],
        avoidedRouteRestrictionIds:
          existingBooking.data()?.avoidedRouteRestrictionIds ?? [],
        avoidedRouteRestrictionNames:
          existingBooking.data()?.avoidedRouteRestrictionNames ?? [],
        highwayRouteAdvisory:
          existingBooking.data()?.highwayRouteAdvisory ?? null,
        searchExpiresAt: snapshotDateMillis(
          existingBooking.data()?.searchExpiresAt,
        ) == null
          ? null
          : new Date(snapshotDateMillis(
            existingBooking.data()?.searchExpiresAt,
          )).toISOString(),
      };
    }

    let authoritative = null;
    const suppliedQuoteToken = typeof request.data?.quoteToken === 'string'
      ? request.data.quoteToken.trim()
      : '';
    if (goService.quotesEnabled()) {
      try {
        authoritative = await authoritativeGoBookingQuote({
          actorId: uid,
          pickup,
          destination,
          additionalPassengers,
          baggageCount,
          quoteToken: suppliedQuoteToken,
        });
      } catch (error) {
        if (suppliedQuoteToken) throw goQuoteHttpsError(error);
        logger.warn('Go booking quote failed; using the Node safety path.', {
          bookingId,
          error: error?.message || String(error),
        });
      }
    }
    if (!authoritative) {
      const [fareDocument, geofenceDocuments, restrictionDocuments] =
        await Promise.all([
        db.collection('settings').doc('fare_config').get(),
        db.collection('geofences').limit(500).get(),
        db.collection('routeRestrictions')
          .where('isActive', '==', true)
          .limit(200)
          .get(),
      ]);
      const geofences = geofenceDocuments.docs.map((document) => ({
        id: document.id,
        ...document.data(),
      }));
      const restrictions = restrictionDocuments.docs.map((document) => ({
        id: document.id,
        ...document.data(),
      })).filter((restriction) =>
        restriction.isActive !== false &&
        ((['no_service_area', 'restricted_crossing'].includes(restriction.type) &&
          restriction.geometryType !== 'corridor') ||
         (restriction.type === 'prohibited_highway' &&
          restriction.geometryType === 'corridor')));
      const coverage = classifyTripCoverage(
        geofences,
        pickup,
        destination,
      );
      const route = await trustedRoute(pickup, destination, restrictions);
      const pricing = fareSnapshot(
        fareDocument.exists ? fareDocument.data() : null,
      );
      const distanceMeters = route.distanceMeters;
      const fareBreakdown = calculateFareBreakdown({
        config: pricing,
        distanceMeters,
        additionalPassengers,
        baggageCount,
        isOutsideToda: coverage.isOutsideToda,
      });
      authoritative = {
        coverage,
        route,
        pricing,
        distanceMeters,
        fareBreakdown,
        estimatedFare: fareBreakdown.total,
      };
    }
    const {
      coverage,
      route,
      pricing,
      distanceMeters,
      fareBreakdown,
      estimatedFare,
    } = authoritative;
    const searchExpiresAt = Timestamp.fromMillis(
      Date.now() + bookingSearchDurationMs,
    );

    const result = await db.runTransaction(async (transaction) => {
      const [user, booking, lock, operation] = await Promise.all([
        transaction.get(userRef),
        transaction.get(bookingRef),
        transaction.get(lockRef),
        transaction.get(operationRef),
      ]);
      if (operation.exists) {
        return { idempotent: true };
      }
      if (!user.exists || user.data().isActive === false ||
          user.data().role !== 'passenger') {
        throw new HttpsError(
          'failed-precondition',
          'An active passenger profile is required.',
        );
      }
      if (booking.exists) {
        if (booking.data().passengerId === uid) {
          return { idempotent: true };
        }
        throw new HttpsError('already-exists', 'This booking ID is already in use.');
      }
      if (lock.exists && lock.data().bookingId !== bookingId) {
        throw new HttpsError(
          'failed-precondition',
          'Complete or cancel the active booking before creating another.',
        );
      }
      const profile = user.data();
      const passengerName = [
        profile.firstName,
        profile.middleName,
        profile.lastName,
      ].filter((value) => typeof value === 'string' && value.trim()).join(' ');
      const bookingData = {
        schemaVersion: 2,
        passengerId: uid,
        passengerName: passengerName || request.auth.token.name ||
          request.auth.token.email || 'Passenger',
        passengerPhone: typeof profile.phoneNumber === 'string'
          ? profile.phoneNumber
          : '',
        passengerPhotoUrl: typeof profile.profileImage === 'string'
          ? profile.profileImage
          : '',
        driverId: null,
        driverName: null,
        driverPhotoUrl: null,
        driverRating: null,
        vehicleNumber: null,
        plateNumber: null,
        todaId: null,
        todaName: null,
        pickup,
        destination,
        pickupAddress,
        destinationAddress,
        distanceMeters,
        estimatedFare,
        paymentMethod: 'cash',
        amountDue: estimatedFare,
        passengerPaidAt: null,
        driverReceivedAt: null,
        settlementStatus: 'awaiting_confirmation',
        receiptNumber: null,
        estimatedDuration: route.duration,
        authoritativeRoutePolyline: route.encodedPolyline,
        routeRestrictionIdsChecked: route.restrictionIdsChecked,
        avoidedRouteRestrictionIds: route.avoidedRestrictionIds,
        avoidedRouteRestrictionNames: route.avoidedRestrictionNames,
        highwayRouteAdvisory: route.highwayRouteAdvisory,
        routePolicyVersion: 4,
        fareSnapshot: pricing,
        fareBreakdown,
        clientEstimate: {
          distanceMeters: clientDistanceMeters,
          estimatedFare: clientEstimatedFare,
          isOutsideToda: clientIsOutsideToda,
        },
        additionalPassengers,
        baggageCount,
        isOutsideToda: coverage.isOutsideToda,
        coverageDecision: {
          version: 3,
          configured: coverage.configured,
          coverageClass: coverage.coverageClass,
          pickupTodaIds: coverage.pickupTodaIds,
          destinationTodaIds: coverage.destinationTodaIds,
          sharedTodaIds: coverage.sharedTodaIds,
          primaryTodaIds: coverage.primaryTodaIds,
          secondaryTodaIds: coverage.secondaryTodaIds,
          allowAnyActiveToda: coverage.allowAnyActiveToda,
          eligibleTodaIds: coverage.eligibleTodaIds,
          serviceTodaId: coverage.serviceTodaId,
          geofenceRevisions: coverage.geofenceRevisions,
        },
        coveragePolicyVersion: 3,
        primaryTodaIds: coverage.primaryTodaIds,
        secondaryTodaIds: coverage.secondaryTodaIds,
        allowAnyActiveToda: coverage.allowAnyActiveToda,
        eligibleTodaIds: coverage.eligibleTodaIds,
        serviceTodaId: coverage.serviceTodaId,
        geofenceRevisions: coverage.geofenceRevisions,
        searchExpiresAt,
        queueEnteredAt: timestamp(),
        status: BOOKING_STATUS.pending,
        createdAt: timestamp(),
        updatedAt: timestamp(),
        completedAt: null,
        cancelledAt: null,
        cancelledBy: null,
        cancellationCode: null,
      };
      transaction.create(bookingRef, bookingData);
      transaction.set(lockRef, {
        bookingId,
        createdAt: timestamp(),
        updatedAt: timestamp(),
      });
      transaction.create(operationRef, {
        bookingId,
        operationId,
        actorId: uid,
        action: 'create',
        resultStatus: BOOKING_STATUS.pending,
        createdAt: timestamp(),
      });
      transaction.create(auditRef, {
        type: 'booking_lifecycle',
        action: 'create',
        bookingId,
        actorId: uid,
        actorRole: 'passenger',
        fromStatus: null,
        toStatus: BOOKING_STATUS.pending,
        createdAt: timestamp(),
      });
      return { idempotent: false };
    });

    return {
      bookingId,
      distanceMeters,
      estimatedFare,
      authoritativeRoutePolyline: route.encodedPolyline,
      fareSnapshot: pricing,
      fareVersion: pricing.version,
      fareBreakdown,
      isOutsideToda: coverage.isOutsideToda,
      coverageClass: coverage.coverageClass,
      coveragePolicyVersion: 3,
      routePolicyVersion: 4,
      primaryTodaIds: coverage.primaryTodaIds,
      secondaryTodaIds: coverage.secondaryTodaIds,
      allowAnyActiveToda: coverage.allowAnyActiveToda,
      eligibleTodaIds: coverage.eligibleTodaIds,
      avoidedRouteRestrictionIds: route.avoidedRestrictionIds,
      avoidedRouteRestrictionNames: route.avoidedRestrictionNames,
      highwayRouteAdvisory: route.highwayRouteAdvisory,
      searchExpiresAt: searchExpiresAt.toDate().toISOString(),
      ...result,
    };
  },
);

function bookingAllowsDriverToda(booking, todaId) {
  return bookingDriverServicePriority(booking, todaId) != null;
}

function validDriverAwardCandidate({
  booking,
  claim,
  user,
  driver,
  offer,
  vehicle,
  toda,
  offerRound,
  now,
}) {
  const licenseExpiry = snapshotDateMillis(driver?.licenseExpiry);
  return user?.isActive !== false &&
    user?.role === 'driver' &&
    driver?.driverStatus === 'approved' &&
    driver?.isOnline === true &&
    driver?.isAvailable === true &&
    driver?.currentBookingId == null &&
    bookingAllowsDriverToda(booking, driver?.todaId) &&
    offer?.status === 'offered' &&
    Number(offer?.offerRound) === offerRound &&
    (snapshotDateMillis(offer?.expiresAt) ?? 0) >
      (snapshotDateMillis(claim?.acceptedAt) ?? now) &&
    vehicle?.isVerified === true &&
    vehicleCanServeBooking(vehicle, booking) &&
    toda?.isActive === true &&
    typeof driver?.licenseNumber === 'string' &&
    driver.licenseNumber.trim().length > 0 &&
    licenseExpiry != null &&
    licenseExpiry >= now;
}

// Drivers submit an accept intent during a short server-owned arbitration
// window. The transaction awards by service tier, 100 m proximity band,
// trusted daily workload, smoothed reliability/quality, exact distance,
// acceptance time, and finally driver ID. This preserves fast simultaneous
// offers while keeping the result deterministic and auditable.
exports.acceptBookingLifecycle = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before accepting a ride.');
    }
    const { bookingId, operationId } = lifecycleIdentity(request.data);
    const uid = request.auth.uid;
    const bookingRef = db.collection('bookings').doc(bookingId);
    const userRef = db.collection('users').doc(uid);
    const driverRef = db.collection('drivers').doc(uid);
    const offerRef = driverRef.collection('bookingOffers').doc(bookingId);
    const operationRef = operationReference(bookingId, uid, operationId);
    const claimRef = bookingRef.collection('acceptClaims').doc(uid);
    const registered = await db.runTransaction(async (transaction) => {
      const [booking, user, driver, offer, operation, existingClaim] =
        await Promise.all([
        transaction.get(bookingRef),
        transaction.get(userRef),
        transaction.get(driverRef),
        transaction.get(offerRef),
        transaction.get(operationRef),
        transaction.get(claimRef),
      ]);
      if (!booking.exists) {
        throw new HttpsError('not-found', 'Booking not found.');
      }
      const bookingData = booking.data();
      if (bookingData.driverId === uid &&
          bookingData.status === BOOKING_STATUS.driverAssigned) {
        return {
          alreadyAssigned: true,
          idempotent: true,
          passengerId: bookingData.passengerId,
          winnerDriverId: uid,
        };
      }
      if (operation.exists || bookingData.status !== BOOKING_STATUS.pending ||
          bookingData.driverId != null) {
        throw new HttpsError(
          'failed-precondition',
          'This booking has already changed.',
        );
      }
      if (!user.exists || user.data().isActive === false ||
          user.data().role !== 'driver') {
        throw new HttpsError('failed-precondition', 'An active driver profile is required.');
      }
      if (!driver.exists || driver.data().driverStatus !== 'approved' ||
          driver.data().isOnline !== true ||
          driver.data().isAvailable !== true ||
          driver.data().currentBookingId != null) {
        throw new HttpsError('failed-precondition', 'You are not available for this booking.');
      }
      if (!offer.exists || offer.data().status !== 'offered' ||
          (snapshotDateMillis(offer.data().expiresAt) ?? 0) <= Date.now()) {
        throw new HttpsError('failed-precondition', 'This booking offer has expired.');
      }
      const offerRound = Number(bookingData.offerRound || 0);
      if (Number(offer.data().offerRound) !== offerRound) {
        throw new HttpsError(
          'failed-precondition',
          'This booking offer is no longer in the active round.',
        );
      }
      const vehicleRef = db.collection('vehicles').doc(driver.data().vehicleId);
      const todaRef = db.collection('todas').doc(driver.data().todaId);
      const [vehicle, toda] = await Promise.all([
        transaction.get(vehicleRef),
        transaction.get(todaRef),
      ]);
      if (!vehicle.exists) {
        throw new HttpsError('failed-precondition', 'Driver vehicle record is missing.');
      }
      if (vehicle.data().isVerified !== true) {
        throw new HttpsError('failed-precondition', 'Driver vehicle is not verified.');
      }
      if (!vehicleCanServeBooking(vehicle.data(), bookingData)) {
        throw new HttpsError(
          'failed-precondition',
          'This vehicle does not have the required passenger capacity.',
        );
      }
      if (!toda.exists || toda.data().isActive !== true) {
        throw new HttpsError('failed-precondition', 'The assigned TODA is not active.');
      }
      if (!bookingAllowsDriverToda(bookingData, driver.data().todaId)) {
        throw new HttpsError(
          'permission-denied',
          'This booking belongs to another TODA coverage area.',
        );
      }
      const licenseExpiry = snapshotDateMillis(driver.data().licenseExpiry);
      if (typeof driver.data().licenseNumber !== 'string' ||
          driver.data().licenseNumber.trim().length === 0 ||
          licenseExpiry == null ||
          licenseExpiry < Date.now()) {
        throw new HttpsError(
          'failed-precondition',
          'A current driver license is required.',
        );
      }
      const now = Date.now();
      const searchExpiresAt = snapshotDateMillis(
        bookingData.searchExpiresAt,
      );
      if (searchExpiresAt != null && searchExpiresAt <= now) {
        throw new HttpsError(
          'failed-precondition',
          'The passenger search has expired.',
        );
      }
      const existingClaimData = existingClaim.exists
        ? existingClaim.data()
        : null;
      if (existingClaimData?.status === 'submitted' &&
          Number(existingClaimData.offerRound) === offerRound) {
        return {
          alreadyAssigned: false,
          idempotent: true,
          passengerId: bookingData.passengerId,
          windowEndsAt:
            snapshotDateMillis(bookingData.awardWindowEndsAt) ?? now,
        };
      }
      const existingWindowEnd =
        Number(bookingData.awardWindowRound) === offerRound
          ? snapshotDateMillis(bookingData.awardWindowEndsAt)
          : null;
      if (existingWindowEnd != null && existingWindowEnd <= now) {
        throw new HttpsError(
          'failed-precondition',
          'The acceptance window for this offer has closed.',
        );
      }
      const offerExpiresAt =
        snapshotDateMillis(offer.data().expiresAt) ?? now;
      const latestEnd = Math.min(
        offerExpiresAt - acceptanceFinalizationGraceMs,
        searchExpiresAt == null
          ? Number.POSITIVE_INFINITY
          : searchExpiresAt - acceptanceFinalizationGraceMs,
      );
      const windowEndsAt = Math.min(
        existingWindowEnd != null
          ? existingWindowEnd
          : now + acceptanceWindowMs,
        latestEnd,
      );
      if (windowEndsAt <= now) {
        throw new HttpsError(
          'failed-precondition',
          'This booking offer has expired.',
        );
      }
      if (existingWindowEnd == null) {
        transaction.update(bookingRef, {
          awardWindowRound: offerRound,
          awardWindowEndsAt: Timestamp.fromMillis(windowEndsAt),
          updatedAt: timestamp(),
        });
      }
      const offerScore = dispatchScoreSnapshot(offer.data());
      transaction.set(claimRef, {
        bookingId,
        driverId: uid,
        operationId,
        offerRound,
        todaId: driver.data().todaId,
        servicePriority: offerScore.servicePriority,
        distanceMeters: offerScore.distanceMeters,
        dailyAwards: offerScore.dailyAwards,
        reliabilityScore: offerScore.reliabilityScore,
        qualityScore: offerScore.qualityScore,
        dispatchScore: offerScore,
        dispatchPolicyVersion:
          Number(offer.data().dispatchPolicyVersion || 3),
        acceptedAt: Timestamp.fromMillis(now),
        status: 'submitted',
        createdAt: timestamp(),
        updatedAt: timestamp(),
      });
      transaction.set(offerRef, {
        claimStatus: 'submitted',
        claimSubmittedAt: Timestamp.fromMillis(now),
        updatedAt: timestamp(),
      }, { merge: true });
      return {
        alreadyAssigned: false,
        idempotent: false,
        passengerId: bookingData.passengerId,
        windowEndsAt,
      };
    });

    let result = registered;
    if (!registered.alreadyAssigned) {
      const waitMilliseconds = Math.max(
        0,
        Number(registered.windowEndsAt) - Date.now() + 75,
      );
      if (waitMilliseconds > 0) {
        await new Promise((resolve) =>
          setTimeout(resolve, waitMilliseconds));
      }
      result = await db.runTransaction(async (transaction) => {
        const booking = await transaction.get(bookingRef);
        if (!booking.exists) {
          throw new HttpsError('not-found', 'Booking not found.');
        }
        const bookingData = booking.data();
        if (bookingData.status === BOOKING_STATUS.driverAssigned &&
            typeof bookingData.driverId === 'string') {
          return {
            idempotent: true,
            passengerId: bookingData.passengerId,
            winnerDriverId: bookingData.driverId,
          };
        }
        if (bookingData.status !== BOOKING_STATUS.pending ||
            bookingData.driverId != null) {
          throw new HttpsError(
            'failed-precondition',
            'This booking has already changed.',
          );
        }
        const offerRound = Number(bookingData.offerRound || 0);
        const windowEndsAt =
          snapshotDateMillis(bookingData.awardWindowEndsAt) ?? 0;
        if (Number(bookingData.awardWindowRound) !== offerRound ||
            windowEndsAt <= 0) {
          throw new HttpsError(
            'aborted',
            'The acceptance window is no longer active.',
          );
        }
        if (Date.now() < windowEndsAt) {
          throw new HttpsError(
            'aborted',
            'The acceptance window is still collecting driver responses.',
          );
        }
        const claimSnapshot = await transaction.get(
          bookingRef.collection('acceptClaims'),
        );
        const claims = claimSnapshot.docs
          .map((document) => ({ ref: document.ref, ...document.data() }))
          .filter((claim) =>
            claim.status === 'submitted' &&
            Number(claim.offerRound) === offerRound &&
            (snapshotDateMillis(claim.acceptedAt) ??
              Number.POSITIVE_INFINITY) <= windowEndsAt)
          .sort(compareDispatchClaims);
        const baseCandidates = await Promise.all(claims.map(async (claim) => {
          const candidateDriverRef =
            db.collection('drivers').doc(claim.driverId);
          const [candidateUser, candidateDriver, candidateOffer,
            candidateOperation] = await Promise.all([
            transaction.get(db.collection('users').doc(claim.driverId)),
            transaction.get(candidateDriverRef),
            transaction.get(
              candidateDriverRef.collection('bookingOffers').doc(bookingId),
            ),
            transaction.get(operationReference(
              bookingId,
              claim.driverId,
              claim.operationId,
            )),
          ]);
          return {
            claim,
            user: candidateUser.exists ? candidateUser.data() : null,
            driverRef: candidateDriver.ref,
            driver: candidateDriver.exists ? candidateDriver.data() : null,
            offerRef: candidateOffer.ref,
            offer: candidateOffer.exists ? candidateOffer.data() : null,
            operationExists: candidateOperation.exists,
          };
        }));
        const candidatesWithIdentity = baseCandidates.filter((candidate) =>
          !candidate.operationExists &&
          typeof candidate.driver?.vehicleId === 'string' &&
          typeof candidate.driver?.todaId === 'string');
        const completeCandidates = await Promise.all(
          candidatesWithIdentity.map(async (candidate) => {
            const [vehicle, toda] = await Promise.all([
              transaction.get(
                db.collection('vehicles').doc(candidate.driver.vehicleId),
              ),
              transaction.get(
                db.collection('todas').doc(candidate.driver.todaId),
              ),
            ]);
            return {
              ...candidate,
              vehicle: vehicle.exists ? vehicle.data() : null,
              toda: toda.exists ? toda.data() : null,
            };
          }),
        );
        const now = Date.now();
        const winner = completeCandidates.find((candidate) =>
          validDriverAwardCandidate({
            booking: bookingData,
            claim: candidate.claim,
            user: candidate.user,
            driver: candidate.driver,
            offer: candidate.offer,
            vehicle: candidate.vehicle,
            toda: candidate.toda,
            offerRound,
            now,
          }));
        if (!winner) {
          transaction.update(bookingRef, {
            awardWindowEndsAt: null,
            awardWindowRound: null,
            updatedAt: timestamp(),
          });
          claims.forEach((claim) => transaction.set(claim.ref, {
            status: 'ineligible',
            resolvedAt: timestamp(),
            updatedAt: timestamp(),
          }, { merge: true }));
          return {
            idempotent: false,
            passengerId: bookingData.passengerId,
            winnerDriverId: null,
          };
        }
        const profile = winner.user;
        const driverName = [
          profile.firstName,
          profile.middleName,
          profile.lastName,
        ].filter((value) =>
          typeof value === 'string' && value.trim()).join(' ');
        const commissionPercent = normalizedCommissionPercent(
          winner.toda.driverCommissionPercent,
        );
        const winnerId = winner.claim.driverId;
        const winningDispatchScore =
          dispatchScoreSnapshot(winner.claim);
        transaction.update(bookingRef, {
          driverId: winnerId,
          driverName: driverName || profile.email || 'Driver',
          driverPhotoUrl:
            profile.profileImage || winner.driver.profilePhotoUrl || '',
          driverRating: Number(winner.driver.rating || 0),
          vehicleNumber:
            winner.vehicle.vehicleNumber || winner.vehicle.model || '',
          plateNumber: winner.vehicle.plateNumber || '',
          todaId: winner.driver.todaId,
          driverTodaId: winner.driver.todaId,
          todaName: winner.toda.name || '',
          commissionPercent,
          awardPolicyVersion: 3,
          winningDispatchScore,
          winningServicePriority:
            winningDispatchScore.servicePriority,
          winningOfferDistanceMeters:
            Number(winner.claim.distanceMeters || 0),
          winningZoneRevision:
            Number(winner.offer.zoneRevision || 0),
          winningClaimAcceptedAt: winner.claim.acceptedAt,
          awardWindowEndsAt: null,
          awardWindowRound: null,
          status: BOOKING_STATUS.driverAssigned,
          assignedAt: timestamp(),
          updatedAt: timestamp(),
        });
        transaction.update(winner.driverRef, {
          currentBookingId: bookingId,
          isAvailable: false,
          dispatchStats:
            nextDriverDispatchStats(winner.driver, 'assigned', now),
          updatedAt: timestamp(),
        });
        transaction.set(winner.offerRef, {
          status: 'accepted',
          claimStatus: 'awarded',
          acceptedAt: winner.claim.acceptedAt,
          awardedAt: timestamp(),
          updatedAt: timestamp(),
        }, { merge: true });
        transaction.create(operationReference(
          bookingId,
          winnerId,
          winner.claim.operationId,
        ), {
          bookingId,
          operationId: winner.claim.operationId,
          actorId: winnerId,
          action: 'accept',
          resultStatus: BOOKING_STATUS.driverAssigned,
          awardPolicyVersion: 3,
          dispatchScore: winningDispatchScore,
          createdAt: timestamp(),
        });
        transaction.create(auditReference(
          bookingId,
          winnerId,
          winner.claim.operationId,
        ), {
          type: 'booking_lifecycle',
          action: 'accept',
          bookingId,
          actorId: winnerId,
          actorRole: 'driver',
          fromStatus: BOOKING_STATUS.pending,
          toStatus: BOOKING_STATUS.driverAssigned,
          awardPolicyVersion: 3,
          distanceMeters: Number(winner.claim.distanceMeters || 0),
          servicePriority: winningDispatchScore.servicePriority,
          dispatchScore: winningDispatchScore,
          createdAt: timestamp(),
        });
        claims.forEach((claim) => transaction.set(claim.ref, {
          status: claim.driverId === winnerId ? 'awarded' : 'lost',
          winnerDriverId: winnerId,
          resolvedAt: timestamp(),
          updatedAt: timestamp(),
        }, { merge: true }));
        return {
          idempotent: false,
          passengerId: bookingData.passengerId,
          winnerDriverId: winnerId,
        };
      });
    }
    if (!result.winnerDriverId) {
      throw new HttpsError(
        'failed-precondition',
        'No accepted driver remained eligible for this booking.',
      );
    }
    await realtime
      .ref(
        `driver_tracking_access/${result.passengerId}/` +
        result.winnerDriverId,
      )
      .set({
        bookingId,
        grantedAt: ServerValue.TIMESTAMP,
      });
    await expireBookingOffers(bookingId, 'closed');
    if (result.winnerDriverId !== uid) {
      throw new HttpsError(
        'aborted',
        'A higher-ranked eligible driver accepted during the same award window.',
      );
    }
    return {
      bookingId,
      status: BOOKING_STATUS.driverAssigned,
      idempotent: result.idempotent,
    };
  },
);

exports.confirmCashPayment = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'Sign in before confirming a cash payment.',
      );
    }
    const { bookingId, operationId } = lifecycleIdentity(request.data);
    const confirmation = request.data?.confirmation;
    if (confirmation !== 'received') {
      throw new HttpsError(
        'invalid-argument',
        'A valid cash confirmation is required.',
      );
    }
    const uid = request.auth.uid;
    const bookingRef = db.collection('bookings').doc(bookingId);
    const settlementRef = db.collection('settlements').doc(bookingId);
    const operationRef = operationReference(bookingId, uid, operationId);
    const auditRef = auditReference(bookingId, uid, operationId);
    const result = await db.runTransaction(async (transaction) => {
      const [booking, operation] = await Promise.all([
        transaction.get(bookingRef),
        transaction.get(operationRef),
      ]);
      if (operation.exists) return { idempotent: true };
      if (!booking.exists) throw new HttpsError('not-found', 'Booking not found.');
      const data = booking.data();
      const isDriver = data.driverId === uid;
      if (confirmation !== 'received' || !isDriver) {
        throw new HttpsError(
          'permission-denied',
          'Only the assigned driver can confirm cash received.',
        );
      }
      if (data.status !== BOOKING_STATUS.paymentConfirmation) {
        throw new HttpsError(
          'failed-precondition',
          'Cash can be confirmed only after drop-off.',
        );
      }
      const targetField = 'driverReceivedAt';
      if (data[targetField] != null) return { idempotent: true };

      const settled = false;
      const receiptNumber = settled
        ? `VT-${bookingId.replace(/[^a-zA-Z0-9]/g, '').slice(0, 10).toUpperCase()}`
        : null;
      transaction.update(bookingRef, {
        [targetField]: timestamp(),
        settlementStatus: settled ? 'confirmed' : 'awaiting_confirmation',
        receiptNumber: settled ? receiptNumber : data.receiptNumber || null,
        updatedAt: timestamp(),
      });
      transaction.set(settlementRef, {
        bookingId,
        passengerId: data.passengerId,
        driverId: data.driverId,
        todaId: data.todaId || null,
        paymentMethod: 'cash',
        amountDue: Number(data.amountDue ?? data.estimatedFare ?? 0),
        currency: 'PHP',
        [targetField]: timestamp(),
        status: settled ? 'confirmed' : 'awaiting_confirmation',
        receiptNumber,
        adjustmentStatus: 'none',
        updatedAt: timestamp(),
        createdAt: timestamp(),
      }, { merge: true });
      transaction.create(operationRef, {
        bookingId,
        operationId,
        actorId: uid,
        action: `confirm_cash_${confirmation}`,
        resultStatus: data.status,
        createdAt: timestamp(),
      });
      transaction.create(auditRef, {
        type: 'cash_settlement',
        action: `confirm_${confirmation}`,
        bookingId,
        actorId: uid,
        actorRole: 'driver',
        amountDue: Number(data.amountDue ?? data.estimatedFare ?? 0),
        createdAt: timestamp(),
      });
      return { idempotent: false, settled, receiptNumber };
    });
    return { bookingId, ...result };
  },
);

// Advances or terminates a ride. Terminal transitions release the driver and
// passenger active-booking lock in the same transaction.
exports.acknowledgeDriverReceipt = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before closing a receipt.');
    }
    const bookingId = request.data?.bookingId;
    if (!validBookingId(bookingId)) {
      throw new HttpsError('invalid-argument', 'A valid booking ID is required.');
    }
    const driverRef = db.collection('drivers').doc(request.auth.uid);
    await db.runTransaction(async (transaction) => {
      const driver = await transaction.get(driverRef);
      if (!driver.exists) {
        throw new HttpsError('not-found', 'Driver profile not found.');
      }
      if (driver.data().pendingReceiptBookingId == null) return;
      if (driver.data().pendingReceiptBookingId !== bookingId) {
        throw new HttpsError('failed-precondition', 'A newer receipt is pending.');
      }
      transaction.update(driverRef, {
        pendingReceiptBookingId: null,
        updatedAt: timestamp(),
      });
    });
    return { bookingId, acknowledged: true };
  },
);

exports.declineBookingOfferLifecycle = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before declining a ride.');
    }
    const { bookingId, operationId } = lifecycleIdentity(request.data);
    const driverId = request.auth.uid;
    const bookingRef = db.collection('bookings').doc(bookingId);
    const offerRef = db.doc(`drivers/${driverId}/bookingOffers/${bookingId}`);
    const claimRef = bookingRef.collection('acceptClaims').doc(driverId);
    const operationRef = operationReference(bookingId, driverId, operationId);
    const auditRef = auditReference(bookingId, driverId, operationId);

    const result = await db.runTransaction(async (transaction) => {
      const [booking, offer, operation, claim] = await Promise.all([
        transaction.get(bookingRef),
        transaction.get(offerRef),
        transaction.get(operationRef),
        transaction.get(claimRef),
      ]);
      if (operation.exists) return { idempotent: true };
      if (!booking.exists || booking.data().status !== BOOKING_STATUS.pending) {
        throw new HttpsError('failed-precondition', 'This offer is no longer active.');
      }
      if (!offer.exists || !['offered', 'declined'].includes(offer.data().status)) {
        throw new HttpsError('failed-precondition', 'No active offer was found.');
      }
      const currentOfferDriverIds =
        Array.isArray(booking.data().currentOfferDriverIds)
          ? booking.data().currentOfferDriverIds
          : [];
      const peerOfferSnapshots = await Promise.all(
        currentOfferDriverIds
          .filter((peerId) => peerId !== driverId)
          .map((peerId) => transaction.get(
            db.doc(`drivers/${peerId}/bookingOffers/${bookingId}`),
          )),
      );
      const now = Date.now();
      const anotherOfferIsActive = peerOfferSnapshots.some((peer) =>
        peer.exists &&
        peer.data().status === 'offered' &&
        (snapshotDateMillis(peer.data().expiresAt) ?? 0) > now);
      transaction.set(offerRef, {
        status: 'declined',
        declinedAt: timestamp(),
        updatedAt: timestamp(),
      }, { merge: true });
      if (claim.exists && claim.data().status === 'submitted') {
        transaction.set(claimRef, {
          status: 'withdrawn',
          resolvedAt: timestamp(),
          updatedAt: timestamp(),
        }, { merge: true });
      }
      transaction.set(bookingRef, {
        ...(anotherOfferIsActive
          ? {}
          : { nextDispatchAt: Timestamp.fromMillis(now - 1000) }),
        updatedAt: timestamp(),
      }, { merge: true });
      transaction.create(operationRef, {
        bookingId,
        operationId,
        actorId: driverId,
        action: 'declineOffer',
        terminal: false,
        resultStatus: BOOKING_STATUS.pending,
        passengerId: booking.data().passengerId,
        driverId,
        createdAt: timestamp(),
      });
      transaction.create(auditRef, {
        type: 'booking_offer',
        action: 'decline',
        bookingId,
        actorId: driverId,
        actorRole: 'driver',
        createdAt: timestamp(),
      });
      return {
        idempotent: false,
        shouldRedispatch: !anotherOfferIsActive,
      };
    });
    if (!result.idempotent && result.shouldRedispatch) {
      await dispatchNextOfferBatch(bookingId);
    }
    return { bookingId, idempotent: result.idempotent };
  },
);

exports.transitionBookingLifecycle = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before updating a ride.');
    }
    const { bookingId, operationId } = lifecycleIdentity(request.data);
    const action = request.data?.action;
    if (!['arrived', 'start', 'dropOff', 'complete', 'cancel', 'noShow'].includes(action)) {
      throw new HttpsError('invalid-argument', 'Unsupported booking action.');
    }
    const uid = request.auth.uid;
    const bookingRef = db.collection('bookings').doc(bookingId);
    const operationRef = operationReference(bookingId, uid, operationId);
    const auditRef = auditReference(bookingId, uid, operationId);

    const result = await db.runTransaction(async (transaction) => {
      const [booking, operation] = await Promise.all([
        transaction.get(bookingRef),
        transaction.get(operationRef),
      ]);
      if (operation.exists) {
        return {
          idempotent: true,
          status: operation.data().resultStatus,
          terminal: operation.data().terminal === true,
          passengerId: operation.data().passengerId || null,
          driverId: operation.data().driverId || null,
        };
      }
      if (!booking.exists) {
        throw new HttpsError('not-found', 'Booking not found.');
      }
      const data = booking.data();
      const isPassenger = data.passengerId === uid;
      const isDriver = data.driverId === uid;
      if (!isPassenger && !isDriver) {
        throw new HttpsError('permission-denied', 'You are not part of this booking.');
      }

      let nextStatus;
      let expectedStatuses;
      let actorRole;
      let cancellationCode = null;
      if (action === 'arrived') {
        nextStatus = BOOKING_STATUS.driverArriving;
        expectedStatuses = [BOOKING_STATUS.driverAssigned];
        actorRole = 'driver';
      } else if (action === 'start') {
        nextStatus = BOOKING_STATUS.passengerOnBoard;
        expectedStatuses = [BOOKING_STATUS.driverArriving];
        actorRole = 'driver';
      } else if (action === 'complete') {
        nextStatus = BOOKING_STATUS.completed;
        expectedStatuses = [BOOKING_STATUS.paymentConfirmation];
        actorRole = 'driver';
      } else if (action === 'dropOff') {
        nextStatus = BOOKING_STATUS.paymentConfirmation;
        expectedStatuses = [BOOKING_STATUS.passengerOnBoard];
        actorRole = 'driver';
      } else {
        nextStatus = BOOKING_STATUS.cancelled;
        actorRole = isDriver ? 'driver' : 'passenger';
        const requestedCancellationCode = action === 'noShow'
          ? (isDriver ? 'passenger_no_show' : 'driver_no_show')
          : requiredString(
            request.data?.reasonCode || 'cancelled',
            'Cancellation reason',
          );
        expectedStatuses = cancellationExpectedStatuses({
          isDriver,
          cancellationCode: requestedCancellationCode,
        });
        cancellationCode = requestedCancellationCode;
      }
      if (data.status === nextStatus) {
        const sameTerminalActor = nextStatus !== BOOKING_STATUS.cancelled ||
          data.cancelledBy === uid;
        if (sameTerminalActor) {
          return {
            idempotent: true,
            status: nextStatus,
            terminal: nextStatus === BOOKING_STATUS.completed ||
              nextStatus === BOOKING_STATUS.cancelled,
            passengerId: data.passengerId,
            driverId: data.driverId || null,
          };
        }
      }
      if (actorRole === 'driver' && !isDriver) {
        throw new HttpsError('permission-denied', 'Only the assigned driver can perform this action.');
      }
      if (!expectedStatuses.includes(data.status)) {
        throw new HttpsError('failed-precondition', 'This ride has already changed state.');
      }
      if (cancellationCode === 'search_timeout') {
        const searchExpiresAt = snapshotDateMillis(data.searchExpiresAt);
        if (searchExpiresAt != null && Date.now() < searchExpiresAt) {
          throw new HttpsError(
            'failed-precondition',
            'The driver search is still active.',
          );
        }
        const awardWindowEndsAt = snapshotDateMillis(
          data.awardWindowEndsAt,
        );
        if (Number(data.awardWindowRound) ===
              Number(data.offerRound || 0) &&
            awardWindowEndsAt != null &&
            Date.now() <
              awardWindowEndsAt + acceptanceFinalizationGraceMs) {
          throw new HttpsError(
            'aborted',
            'A driver response is being finalized. Refresh the booking.',
          );
        }
      }

      const terminal = nextStatus === BOOKING_STATUS.completed ||
        nextStatus === BOOKING_STATUS.cancelled;
      let driverRef = null;
      let driver = null;
      if (terminal && data.driverId) {
        driverRef = db.collection('drivers').doc(data.driverId);
        driver = await transaction.get(driverRef);
      }
      const passengerLockRef = db.collection('activePassengerBookings').doc(data.passengerId);
      const passengerRef = db.collection('passengers').doc(data.passengerId);
      const settlementRef = db.collection('settlements').doc(bookingId);
      const [passengerLock, passenger, settlement] = terminal
        ? await Promise.all([
          transaction.get(passengerLockRef),
          transaction.get(passengerRef),
          transaction.get(settlementRef),
        ])
        : [null, null, null];

      const lifecycleUpdate = {
        status: nextStatus,
        updatedAt: timestamp(),
      };
      if (action === 'arrived') lifecycleUpdate.arrivedAt = timestamp();
      if (action === 'start') lifecycleUpdate.startedAt = timestamp();
      if (action === 'dropOff') lifecycleUpdate.droppedOffAt = timestamp();
      if (action === 'complete') {
        let settlementBreakdown;
        try {
          settlementBreakdown = calculateSettlementBreakdown({
            grossFare: data.amountDue ?? data.estimatedFare,
            commissionPercent: data.commissionPercent,
          });
        } catch (error) {
          logger.error('Refusing an invalid booking settlement.', {
            bookingId,
            error: error instanceof Error ? error.message : String(error),
          });
          throw new HttpsError(
            'failed-precondition',
            'This booking has invalid settlement amounts.',
          );
        }
        const receiptNumber = data.receiptNumber ||
          `VT-${bookingId.replace(/[^a-zA-Z0-9]/g, '').slice(0, 10).toUpperCase()}`;
        lifecycleUpdate.completedAt = timestamp();
        lifecycleUpdate.driverReceivedAt = data.driverReceivedAt || timestamp();
        lifecycleUpdate.cashConfirmedByDriverAt = timestamp();
        lifecycleUpdate.settlementStatus = 'settled';
        lifecycleUpdate.settlementTimestamp = timestamp();
        lifecycleUpdate.receiptNumber = receiptNumber;
        lifecycleUpdate.grossFare = settlementBreakdown.grossFare;
        lifecycleUpdate.commissionPercent =
          settlementBreakdown.commissionPercent;
        lifecycleUpdate.commissionAmount =
          settlementBreakdown.commissionAmount;
        lifecycleUpdate.driverNetEarnings =
          settlementBreakdown.driverNetEarnings;
      }
      if (nextStatus === BOOKING_STATUS.cancelled) {
        lifecycleUpdate.cancelledAt = timestamp();
        lifecycleUpdate.cancelledBy = uid;
        lifecycleUpdate.cancellationCode = cancellationCode;
        lifecycleUpdate.cancellationDetail = String(
          request.data?.reasonDetail || '',
        ).trim().slice(0, 500);
      }
      const driverFaultCancellation =
        cancellationCode === 'driver_no_show' ||
        (isDriver && cancellationCode != null &&
          cancellationCode !== 'passenger_no_show');
      const driverStatsOutcome = action === 'complete'
        ? 'completed'
        : nextStatus === BOOKING_STATUS.cancelled
          ? (driverFaultCancellation
            ? 'driver_fault_cancelled'
            : 'cancelled')
          : null;
      transaction.update(bookingRef, lifecycleUpdate);
      if (driverRef && driver?.exists &&
          driver.data().currentBookingId === bookingId) {
        const driverUpdate = {
          currentBookingId: null,
          isAvailable: driver.data().isOnline === true &&
            driver.data().driverStatus === 'approved',
          updatedAt: timestamp(),
        };
        if (driverStatsOutcome != null) {
          driverUpdate.dispatchStats = nextDriverDispatchStats(
            driver.data(),
            driverStatsOutcome,
          );
        }
        if (action === 'complete') {
          driverUpdate.pendingReceiptBookingId = bookingId;
          driverUpdate.completedTrips = FieldValue.increment(1);
          driverUpdate.totalEarnings = FieldValue.increment(
            lifecycleUpdate.driverNetEarnings,
          );
        }
        transaction.update(driverRef, driverUpdate);
      } else if (driverRef && driver?.exists &&
          driverStatsOutcome != null) {
        const driverUpdate = {
          dispatchStats: nextDriverDispatchStats(
            driver.data(),
            driverStatsOutcome,
          ),
          updatedAt: timestamp(),
        };
        if (action === 'complete') {
          driverUpdate.pendingReceiptBookingId = bookingId;
          driverUpdate.completedTrips = FieldValue.increment(1);
          driverUpdate.totalEarnings = FieldValue.increment(
            lifecycleUpdate.driverNetEarnings,
          );
        }
        transaction.update(driverRef, driverUpdate);
      }
      if (action === 'complete' && passenger?.exists) {
        transaction.update(passengerRef, {
          totalTrips: FieldValue.increment(1),
          updatedAt: timestamp(),
        });
      }
      if (action === 'complete') {
        const receiptNumber = data.receiptNumber ||
          `VT-${bookingId.replace(/[^a-zA-Z0-9]/g, '').slice(0, 10).toUpperCase()}`;
        transaction.set(settlementRef, {
          bookingId,
          passengerId: data.passengerId,
          driverId: data.driverId,
          todaId: data.todaId || null,
          paymentMethod: 'cash',
          amountDue: lifecycleUpdate.grossFare,
          grossFare: lifecycleUpdate.grossFare,
          commissionPercent: lifecycleUpdate.commissionPercent,
          commissionAmount: lifecycleUpdate.commissionAmount,
          driverNetEarnings: lifecycleUpdate.driverNetEarnings,
          currency: 'PHP',
          status: 'settled',
          driverReceivedAt: data.driverReceivedAt || timestamp(),
          cashConfirmedByDriverAt: timestamp(),
          receiptNumber,
          settlementTimestamp: timestamp(),
          adjustmentStatus: settlement?.data()?.adjustmentStatus || 'none',
          updatedAt: timestamp(),
        }, { merge: true });
      }
      if (passengerLock?.exists &&
          passengerLock.data().bookingId === bookingId) {
        transaction.delete(passengerLockRef);
      }
      transaction.create(operationRef, {
        bookingId,
        operationId,
        actorId: uid,
        action,
        terminal,
        resultStatus: nextStatus,
        passengerId: data.passengerId,
        driverId: data.driverId || null,
        createdAt: timestamp(),
      });
      transaction.create(auditRef, {
        type: 'booking_lifecycle',
        action,
        bookingId,
        actorId: uid,
        actorRole,
        fromStatus: data.status,
        toStatus: nextStatus,
        cancellationCode,
        paymentMethod: action === 'complete' ? 'cash' : null,
        amountDue: action === 'complete'
          ? lifecycleUpdate.grossFare
          : null,
        createdAt: timestamp(),
      });
      return {
        idempotent: false,
        status: nextStatus,
        terminal,
        passengerId: data.passengerId,
        driverId: data.driverId || null,
      };
    });
    if (result.terminal) {
      await expireBookingOffers(bookingId, 'closed');
      if (result.passengerId && result.driverId) {
        await realtime
          .ref(`driver_tracking_access/${result.passengerId}/${result.driverId}`)
          .remove();
      }
    }
    return {
      bookingId,
      idempotent: result.idempotent,
      status: result.status,
      terminal: result.terminal,
    };
  },
);

exports.createRideReport = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before submitting a report.');
    }
    const reportId = request.data?.reportId;
    const bookingId = request.data?.bookingId;
    if (!validOperationId(reportId) || !validBookingId(bookingId)) {
      throw new HttpsError('invalid-argument', 'Valid report and booking IDs are required.');
    }
    const category = requiredString(request.data?.category, 'Report category').slice(0, 100);
    const details = requiredString(
      request.data?.details,
      'Report details',
    ).slice(0, 2000);
    if (details.length < 5) {
      throw new HttpsError(
        'invalid-argument',
        'Report details must contain at least five characters.',
      );
    }
    const uid = request.auth.uid;
    const reportingUser = await db.collection('users').doc(uid).get();
    if (!reportingUser.exists || reportingUser.data().isActive === false) {
      throw new HttpsError(
        'permission-denied',
        'An active account is required to submit a report.',
      );
    }
    const booking = await db.collection('bookings').doc(bookingId).get();
    if (!booking.exists) throw new HttpsError('not-found', 'Booking not found.');
    const bookingData = booking.data();
    if (![bookingData.passengerId, bookingData.driverId].includes(uid)) {
      throw new HttpsError('permission-denied', 'You are not part of this booking.');
    }
    const reportedUserId = uid === bookingData.passengerId
      ? bookingData.driverId
      : bookingData.passengerId;
    if (!reportedUserId) {
      throw new HttpsError('failed-precondition', 'The booking has no other participant to report.');
    }
    const reporterRole = uid === bookingData.passengerId
      ? 'passenger'
      : 'driver';
    const reportedRole = reportedUserId === bookingData.driverId
      ? 'driver'
      : 'passenger';
    let todaId = bookingData.todaId || null;
    if (bookingData.driverId) {
      const driver = await db.collection('drivers').doc(bookingData.driverId).get();
      todaId = driver.exists ? driver.data().todaId || null : null;
    }
    const reportRef = db.collection('reports').doc(reportId);
    const existing = await reportRef.get();
    if (existing.exists) {
      if (existing.data().reporterId === uid &&
          existing.data().bookingId === bookingId) {
        return { reportId, idempotent: true };
      }
      throw new HttpsError('already-exists', 'This report ID is already in use.');
    }
    await reportRef.create({
      reportId,
      bookingId,
      reporterId: uid,
      reportedUserId,
      todaId,
      reporterRole,
      reportedRole,
      reviewAudience: reportedRole === 'driver'
        ? ['developer_admin', 'toda_admin']
        : ['developer_admin'],
      category,
      details,
      status: 'open',
      reporterName: uid === bookingData.passengerId
        ? bookingData.passengerName || 'Passenger'
        : bookingData.driverName || 'Driver',
      reportedUserName: uid === bookingData.passengerId
        ? bookingData.driverName || 'Driver'
        : bookingData.passengerName || 'Passenger',
      createdAt: timestamp(),
    });
    return { reportId, idempotent: false };
  },
);

// Records an in-app SOS with trusted ride, participant, TODA, and latest
// backend driver-location snapshots. One reporter gets one durable incident
// per booking, so retries and repeated taps cannot create duplicate alerts.
// It does not claim to contact emergency services; that external integration
// remains an explicit development stub.
exports.createSafetyIncident = onCall(
  {
    region: 'asia-southeast1',
    secrets: [brevoSmtpKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before using ride SOS.');
    }
    const bookingId = request.data?.bookingId;
    if (!validBookingId(bookingId)) {
      throw new HttpsError(
        'invalid-argument',
        'A valid booking ID is required.',
      );
    }
    const booking = await db.collection('bookings').doc(bookingId).get();
    if (!booking.exists) throw new HttpsError('not-found', 'Booking not found.');
    const data = booking.data();
    if (![data.passengerId, data.driverId].includes(request.auth.uid)) {
      throw new HttpsError('permission-denied', 'You are not part of this ride.');
    }
    const sosStatuses = [
      BOOKING_STATUS.driverAssigned,
      BOOKING_STATUS.driverArriving,
      BOOKING_STATUS.passengerOnBoard,
      BOOKING_STATUS.paymentConfirmation,
    ];
    if (!sosStatuses.includes(data.status)) {
      throw new HttpsError(
        'failed-precondition',
        'SOS is available after a driver is assigned and before the ride closes.',
      );
    }
    const acknowledgement = request.data?.acknowledgement === 'accidental'
      ? 'accidental'
      : 'needs_review';

    const incidentId = `sos_${createHash('sha256')
      .update(`${bookingId}:${request.auth.uid}`)
      .digest('hex')
      .slice(0, 40)}`;
    const incidentRef = db.collection('safetyIncidents').doc(incidentId);

    let todaId = data.todaId || null;
    let todaName = data.todaName || null;
    let driverLocation = null;
    if (data.driverId) {
      const [driver, location] = await Promise.all([
        db.collection('drivers').doc(data.driverId).get(),
        realtime.ref(`driver_locations/${data.driverId}`).get(),
      ]);
      todaId = todaId || (driver.exists ? driver.data().todaId || null : null);
      const locationData = location.exists() ? location.val() : null;
      try {
        driverLocation = normalizeDriverLocation(locationData, {
          maximumAgeMs: driverLocationMaxAgeMs,
        });
      } catch {
        driverLocation = null;
      }
    }
    if (todaId && !todaName) {
      const toda = await db.collection('todas').doc(todaId).get();
      todaName = toda.exists ? toda.data().name || null : null;
    }
    const reporterRole = data.passengerId === request.auth.uid
      ? 'passenger'
      : 'driver';
    const result = await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(incidentRef);
      if (existing.exists) {
        if (existing.data().bookingId === bookingId &&
            existing.data().reportedBy === request.auth.uid) {
          if (acknowledgement === 'needs_review' &&
              (existing.data().acknowledgement === 'accidental' ||
                ['resolved', 'reporter_safe'].includes(
                  existing.data().status,
                ))) {
            transaction.update(incidentRef, {
              acknowledgement,
              status: 'open',
              responseStatus: SAFETY_RESPONSE_STATUS.reported,
              escalationLevel: 0,
              escalatedAt: timestamp(),
              updatedAt: timestamp(),
            });
            return { idempotent: false, escalated: true };
          }
          return { idempotent: true, escalated: false };
        }
        throw new HttpsError(
          'already-exists',
          'This incident ID is already used.',
        );
      }
      transaction.create(incidentRef, {
        schemaVersion: 3,
        incidentId,
        bookingId,
        category: 'sos',
        reportedBy: request.auth.uid,
        reporterRole,
        passengerId: data.passengerId,
        passengerName: data.passengerName || null,
        driverId: data.driverId || null,
        driverName: data.driverName || null,
        todaId,
        todaName,
        bookingStatus: data.status,
        pickup: data.pickup,
        pickupAddress: data.pickupAddress || null,
        destination: data.destination,
        destinationAddress: data.destinationAddress || null,
        driverLocation,
        acknowledgement,
        status: acknowledgement === 'accidental' ? 'accidental' : 'open',
        responseStatus: acknowledgement === 'accidental'
          ? SAFETY_RESPONSE_STATUS.resolved
          : SAFETY_RESPONSE_STATUS.reported,
        deliveryStatus: acknowledgement === 'accidental'
          ? 'not_required'
          : 'pending',
        escalationLevel: 0,
        emergencyDispatch: 'manual_911_call_available',
        requiresManualEmergencyContact: true,
        createdAt: timestamp(),
        updatedAt: timestamp(),
      });
      transaction.create(db.collection('auditLogs').doc(), {
        type: 'admin_action',
        actorId: request.auth.uid,
        actorRole: reporterRole,
        actorTodaId: todaId,
        action: 'create_sos_incident',
        targetType: 'booking',
        targetId: bookingId,
        details: { incidentId },
        createdAt: timestamp(),
      });
      return { idempotent: false, escalated: false };
    });
    let delivery = null;
    if (acknowledgement === 'needs_review' &&
        (!result.idempotent || result.escalated)) {
      delivery = await notifySafetyAdmins({
        incidentId,
        bookingId,
        todaId,
        title: `Urgent SOS from a ${reporterRole}`,
        body: `Booking ${bookingId} needs acknowledgement. Open Safety Incidents and verify the location.`,
        stage: result.escalated ? 'reopened' : 'initial',
        incident: {
          reporterRole,
          todaName,
          bookingStatus: data.status,
          pickupAddress: data.pickupAddress,
          destinationAddress: data.destinationAddress,
        },
      });
      await incidentRef.set({
        deliveryStatus: delivery.succeeded > 0
          ? 'delivered'
          : delivery.attempted > 0
            ? 'delivery_failed'
            : 'no_registered_admin_device',
        deliveryRecipientCount: delivery.recipients,
        deliveryAttemptCount: delivery.attempted,
        deliverySuccessCount: delivery.succeeded,
        ...(delivery.succeeded > 0 ? { deliveredAt: timestamp() } : {}),
        lastAlertAt: timestamp(),
        updatedAt: timestamp(),
      }, { merge: true });
    }
    return {
      incidentId,
      idempotent: result.idempotent,
      acknowledgement,
      escalated: result.escalated,
      deliveryStatus: delivery?.succeeded > 0
        ? 'delivered'
        : delivery?.attempted > 0
          ? 'delivery_failed'
          : delivery
            ? 'no_registered_admin_device'
            : null,
      emergencyDispatch: 'manual_911_call_available',
    };
  },
);

function safetyIncidentId(bookingId, userId) {
  return `sos_${createHash('sha256')
    .update(`${bookingId}:${userId}`)
    .digest('hex')
    .slice(0, 40)}`;
}

exports.getMySafetyIncident = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in to view your SOS.');
    }
    const bookingId = request.data?.bookingId;
    if (!validBookingId(bookingId)) {
      throw new HttpsError('invalid-argument', 'A valid booking ID is required.');
    }
    const booking = await db.collection('bookings').doc(bookingId).get();
    if (!booking.exists ||
        ![booking.data().passengerId, booking.data().driverId]
          .includes(request.auth.uid)) {
      throw new HttpsError(
        'permission-denied',
        'You are not part of this ride.',
      );
    }
    const incident = await db.collection('safetyIncidents')
      .doc(safetyIncidentId(bookingId, request.auth.uid))
      .get();
    if (!incident.exists) return { incident: null };
    const data = incident.data();
    return {
      incident: {
        incidentId: incident.id,
        status: data.status,
        responseStatus: normalizedResponseStatus(data),
        deliveryStatus: data.deliveryStatus || null,
        escalationLevel: Number(data.escalationLevel || 0),
        updatedAt: adminDate(data.updatedAt),
      },
    };
  },
);

exports.updateMySafetyIncident = onCall(
  {
    region: 'asia-southeast1',
    secrets: [brevoSmtpKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in to update your SOS.');
    }
    const bookingId = request.data?.bookingId;
    if (!validBookingId(bookingId)) {
      throw new HttpsError('invalid-argument', 'A valid booking ID is required.');
    }
    const action = requiredString(request.data?.action, 'Safety update');
    if (!['safe', 'still_need_help', 'emergency_call_attempted']
      .includes(action)) {
      throw new HttpsError(
        'invalid-argument',
        'Choose safe, still need help, or emergency call attempted.',
      );
    }
    const incidentId = safetyIncidentId(bookingId, request.auth.uid);
    const incidentRef = db.collection('safetyIncidents').doc(incidentId);
    const result = await db.runTransaction(async (transaction) => {
      const incident = await transaction.get(incidentRef);
      if (!incident.exists ||
          incident.data().reportedBy !== request.auth.uid) {
        throw new HttpsError('not-found', 'Your SOS incident was not found.');
      }
      const data = incident.data();
      const update = { updatedAt: timestamp() };
      if (action === 'safe') {
        update.status = 'reporter_safe';
        update.responseStatus = SAFETY_RESPONSE_STATUS.resolved;
        update.reporterMarkedSafeAt = timestamp();
        update.resolvedAt = timestamp();
        update.resolvedBy = request.auth.uid;
        update.resolutionNote = 'SOS reporter marked themselves safe.';
      } else if (action === 'still_need_help') {
        update.status = 'open';
        update.responseStatus = SAFETY_RESPONSE_STATUS.reported;
        update.acknowledgement = 'needs_review';
        update.escalationLevel = Math.max(
          Number(data.escalationLevel || 0),
          2,
        );
        update.reporterRequestedMoreHelpAt = timestamp();
      } else {
        update.emergencyCallAttemptedAt = timestamp();
        update.emergencyCallAttemptedBy = request.auth.uid;
      }
      transaction.update(incidentRef, update);
      transaction.create(db.collection('auditLogs').doc(), {
        type: 'safety_action',
        actorId: request.auth.uid,
        actorRole: data.reporterRole,
        actorTodaId: data.todaId || null,
        action: `reporter_${action}`,
        targetType: 'safety_incident',
        targetId: incidentId,
        details: { bookingId },
        createdAt: timestamp(),
      });
      return {
        todaId: data.todaId || null,
        reporterRole: data.reporterRole,
        incident: {
          reporterRole: data.reporterRole,
          todaName: data.todaName || null,
          bookingStatus: data.bookingStatus || null,
          pickupAddress: data.pickupAddress || null,
          destinationAddress: data.destinationAddress || null,
        },
      };
    });
    if (action === 'still_need_help') {
      await notifySafetyAdmins({
        incidentId,
        bookingId,
        todaId: result.todaId,
        title: `SOS escalation: ${result.reporterRole} still needs help`,
        body: `Booking ${bookingId} was escalated by the reporter. Acknowledge it immediately.`,
        escalationLevel: 2,
        stage: 'reporter_still_needs_help',
        incident: result.incident,
      });
    } else if (action === 'safe') {
      await notifySafetyAdmins({
        incidentId,
        bookingId,
        todaId: result.todaId,
        title: 'SOS reporter marked safe',
        body: `The ${result.reporterRole} for booking ${bookingId} marked themselves safe. Verify and record any follow-up notes.`,
        stage: 'reporter_marked_safe',
        incident: result.incident,
      });
    }
    return {
      incidentId,
      status: action === 'safe' ? 'reporter_safe' : 'open',
      responseStatus: action === 'safe' ? 'resolved' : 'reported',
    };
  },
);

exports.escalateUnacknowledgedSafetyIncidents = onSchedule(
  {
    region: 'asia-southeast1',
    schedule: 'every 1 minutes',
    secrets: [brevoSmtpKey],
  },
  async () => {
    const open = await db.collection('safetyIncidents')
      .where('status', '==', 'open')
      .limit(200)
      .get();
    let escalated = 0;
    await Promise.all(open.docs.map(async (entry) => {
      const data = entry.data();
      const createdAtMs = snapshotDateMillis(data.createdAt);
      const currentLevel = Number(data.escalationLevel || 0);
      const targetLevel = safetyEscalationLevel({
        createdAtMs,
        responseStatus: normalizedResponseStatus(data),
        currentLevel,
      });
      if (targetLevel <= currentLevel) return;
      const claimed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(entry.ref);
        if (!current.exists || current.data().status !== 'open' ||
            normalizedResponseStatus(current.data()) !==
              SAFETY_RESPONSE_STATUS.reported ||
            Number(current.data().escalationLevel || 0) >= targetLevel) {
          return false;
        }
        transaction.update(entry.ref, {
          escalationLevel: targetLevel,
          escalatedAt: timestamp(),
          updatedAt: timestamp(),
        });
        return true;
      });
      if (!claimed) return;
      escalated += 1;
      const threshold = targetLevel >= 2 ? 'five minutes' : 'two minutes';
      const delivery = await notifySafetyAdmins({
        incidentId: entry.id,
        bookingId: data.bookingId,
        todaId: data.todaId || null,
        title: 'Unacknowledged VolTrike SOS',
        body: `Booking ${data.bookingId} has not been acknowledged for ${threshold}.`,
        escalationLevel: targetLevel,
        stage: `unacknowledged_${targetLevel}`,
        incident: data,
      });
      await entry.ref.set({
        lastAlertAt: timestamp(),
        deliveryStatus: delivery.succeeded > 0
          ? 'delivered'
          : delivery.attempted > 0
            ? 'delivery_failed'
            : 'no_registered_admin_device',
        deliveryRecipientCount: delivery.recipients,
        deliveryAttemptCount: delivery.attempted,
        deliverySuccessCount: delivery.succeeded,
        ...(delivery.succeeded > 0 ? { deliveredAt: timestamp() } : {}),
        updatedAt: timestamp(),
      }, { merge: true });
    }));
    logger.info('Unacknowledged SOS escalation check completed', {
      open: open.size,
      escalated,
      acknowledgementWindowMs: SOS_ACKNOWLEDGEMENT_MS,
    });
  },
);

exports.getShareTripInformation = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before sharing a trip.');
    }
    const bookingId = request.data?.bookingId;
    if (!validBookingId(bookingId)) {
      throw new HttpsError('invalid-argument', 'A valid booking ID is required.');
    }
    const booking = await db.collection('bookings').doc(bookingId).get();
    if (!booking.exists) throw new HttpsError('not-found', 'Booking not found.');
    const data = booking.data();
    if (![data.passengerId, data.driverId].includes(request.auth.uid)) {
      throw new HttpsError('permission-denied', 'You are not part of this ride.');
    }
    return {
      bookingReference: bookingId,
      status: data.status,
      passengerName: data.passengerName || 'Passenger',
      driverName: data.driverName || null,
      vehicleNumber: data.vehicleNumber || null,
      plateNumber: data.plateNumber || null,
      todaName: data.todaName || null,
      pickupAddress: data.pickupAddress,
      destinationAddress: data.destinationAddress,
      updatedAt: data.updatedAt?.toDate?.()?.toISOString?.() || null,
    };
  },
);

exports.submitDriverRating = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before rating a ride.');
    }
    const bookingId = request.data?.bookingId;
    if (!validBookingId(bookingId)) {
      throw new HttpsError('invalid-argument', 'A valid booking ID is required.');
    }
    const rating = request.data?.rating;
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      throw new HttpsError(
        'invalid-argument',
        'Rating must be a whole number from 1 to 5.',
      );
    }
    const comment = String(request.data?.comment || '').trim().slice(0, 1000);
    const passengerId = request.auth.uid;
    const ratingId = `${bookingId}_${passengerId}`;
    const bookingRef = db.collection('bookings').doc(bookingId);
    const ratingRef = db.collection('ratings').doc(ratingId);

    const result = await db.runTransaction(async (transaction) => {
      const [booking, existing] = await Promise.all([
        transaction.get(bookingRef),
        transaction.get(ratingRef),
      ]);
      if (existing.exists) {
        if (existing.data().passengerId === passengerId) {
          return { idempotent: true };
        }
        throw new HttpsError('already-exists', 'This rating already exists.');
      }
      if (!booking.exists || booking.data().passengerId !== passengerId) {
        throw new HttpsError(
          'permission-denied',
          'Only the ride passenger can rate this booking.',
        );
      }
      const data = booking.data();
      if (data.status !== BOOKING_STATUS.completed || !data.driverId) {
        throw new HttpsError(
          'failed-precondition',
          'Only a completed ride can be rated.',
        );
      }
      const driverRef = db.collection('drivers').doc(data.driverId);
      const driver = await transaction.get(driverRef);
      if (!driver.exists) {
        throw new HttpsError('not-found', 'Driver profile not found.');
      }
      const ratingCount = Number(driver.data().ratingCount || 0);
      const previousAverage = Number(driver.data().rating || 0);
      const nextAggregate = nextRatingAggregate(
        previousAverage,
        ratingCount,
        rating,
      );
      transaction.create(ratingRef, {
        ratingId,
        bookingId,
        driverId: data.driverId,
        passengerId,
        todaId: data.todaId || driver.data().todaId || null,
        todaName: data.todaName || null,
        driverName: data.driverName || null,
        passengerName: data.passengerName || null,
        rating,
        comment,
        createdAt: timestamp(),
      });
      transaction.update(driverRef, {
        rating: nextAggregate.rating,
        ratingCount: nextAggregate.ratingCount,
        updatedAt: timestamp(),
      });
      transaction.create(db.collection('auditLogs').doc(), {
        type: 'rating',
        action: 'submit_driver_rating',
        bookingId,
        actorId: passengerId,
        driverId: data.driverId,
        rating,
        createdAt: timestamp(),
      });
      return { idempotent: false, ...nextAggregate };
    });
    return { ratingId, ...result };
  },
);

exports.submitSettlementDispute = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'Sign in before disputing a settlement.',
      );
    }
    const bookingId = request.data?.bookingId;
    if (!validBookingId(bookingId)) {
      throw new HttpsError('invalid-argument', 'A valid booking ID is required.');
    }
    const reason = requiredString(request.data?.reason, 'Dispute reason')
      .slice(0, 1000);
    const booking = await db.collection('bookings').doc(bookingId).get();
    if (!booking.exists) throw new HttpsError('not-found', 'Booking not found.');
    const data = booking.data();
    if (![data.passengerId, data.driverId].includes(request.auth.uid)) {
      throw new HttpsError('permission-denied', 'You are not part of this ride.');
    }
    if (data.status !== BOOKING_STATUS.completed) {
      throw new HttpsError(
        'failed-precondition',
        'Only a completed trip settlement can be disputed.',
      );
    }
    const settlementRef = db.collection('settlements').doc(bookingId);
    await settlementRef.set({
      adjustmentStatus: 'disputed',
      disputeReason: reason,
      disputedBy: request.auth.uid,
      disputedAt: timestamp(),
      updatedAt: timestamp(),
    }, { merge: true });
    await adminAudit(db.collection('auditLogs').doc(), {
      actor: {
        uid: request.auth.uid,
        role: data.passengerId === request.auth.uid ? 'passenger' : 'driver',
        todaId: data.todaId || null,
      },
      action: 'dispute_cash_settlement',
      targetType: 'settlement',
      targetId: bookingId,
    });
    return { updated: true };
  },
);

exports.adminResolveSettlementDispute = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const actor = await requireAdmin(request);
    const bookingId = requiredString(request.data?.bookingId, 'Booking ID');
    const resolution = requiredString(request.data?.resolution, 'Resolution')
      .slice(0, 1000);
    const settlementRef = db.collection('settlements').doc(bookingId);
    const settlement = await settlementRef.get();
    if (!settlement.exists) {
      throw new HttpsError('not-found', 'Settlement not found.');
    }
    await assertTodaScope(actor, settlement.data().todaId);
    if (settlement.data().adjustmentStatus !== 'disputed') {
      throw new HttpsError(
        'failed-precondition',
        'This settlement does not have an open dispute.',
      );
    }
    await settlementRef.update({
      adjustmentStatus: 'resolved',
      disputeResolution: resolution,
      disputeResolvedBy: actor.uid,
      disputeResolvedAt: timestamp(),
      updatedAt: timestamp(),
    });
    await adminAudit(db.collection('auditLogs').doc(), {
      actor,
      action: 'resolve_cash_settlement_dispute',
      targetType: 'settlement',
      targetId: bookingId,
    });
    return { updated: true };
  },
);

// Legacy reports are enriched defensively. New reports receive trusted TODA
// scope synchronously in createRideReport.
exports.enrichReportToda = onDocumentCreated('reports/{reportId}', async (event) => {
  const report = event.data.data();
  const booking = await db.collection('bookings').doc(report.bookingId).get();
  if (!booking.exists) return;
  const bookingData = booking.data();
  const driverId = bookingData.driverId || null;
  let todaId = bookingData.todaId || null;
  if (driverId && !todaId) {
    const driver = await db.collection('drivers').doc(driverId).get();
    todaId = driver.exists ? driver.data().todaId || null : null;
  }
  const reporterRole = report.reporterId === bookingData.passengerId
    ? 'passenger'
    : 'driver';
  const reportedRole = report.reportedUserId === driverId
    ? 'driver'
    : 'passenger';
  await event.data.ref.set({
    todaId,
    reporterRole,
    reportedRole,
    reviewAudience: reportedRole === 'driver'
      ? ['developer_admin', 'toda_admin']
      : ['developer_admin'],
  }, { merge: true });
});

const liveKitRoomCleanupTimeoutMs = 1_200;

function configuredLiveKitServerUrl() {
  const value = liveKitUrl.value();
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : null;
}

function requireLiveKitServerUrl() {
  const serverUrl = configuredLiveKitServerUrl();
  if (serverUrl == null) {
    throw new HttpsError(
      'failed-precondition',
      'Voice calling is not configured.',
    );
  }
  return serverUrl;
}

function callResult(data, { idempotent = false } = {}) {
  return {
    bookingId: data.bookingId,
    callId: data.callId,
    status: data.status,
    callerId: data.callerId,
    recipientId: data.recipientId,
    expiresAtMillis: callTimestampMillis(data.expiresAt),
    endsAtMillis: callTimestampMillis(data.endsAt),
    serverUrl: typeof data.serverUrl === 'string' &&
      data.serverUrl.trim().length > 0
      ? data.serverUrl.trim()
      : configuredLiveKitServerUrl(),
    idempotent,
  };
}

function logBookingCallLatency(operation, startedAt, context, stages = {}) {
  logger.info('Booking call stage latency', {
    operation,
    ...context,
    ...stages,
    totalMs: Date.now() - startedAt,
  });
}

function requireCallIdentity(data) {
  const bookingId = requiredString(data?.bookingId, 'Booking ID');
  const callId = requiredString(data?.callId, 'Call ID');
  if (!validBookingId(bookingId) || !validOperationId(callId)) {
    throw new HttpsError(
      'invalid-argument',
      'Valid booking and call IDs are required.',
    );
  }
  return { bookingId, callId };
}

function requireCallParticipant(booking, uid) {
  const role = participantRole(booking, uid);
  if (!role) {
    throw new HttpsError(
      'permission-denied',
      'You are not part of this booking.',
    );
  }
  return role;
}

async function deleteLiveKitRoom(roomName, context = {}) {
  if (typeof roomName !== 'string' || roomName.length === 0) return;
  try {
    const url = requireLiveKitServerUrl();
    const { RoomServiceClient } = require('livekit-server-sdk');
    const serviceUrl = url.replace(/^wss:/, 'https:').replace(/^ws:/, 'http:');
    const rooms = new RoomServiceClient(
      serviceUrl,
      liveKitApiKey.value(),
      liveKitApiSecret.value(),
    );
    await rooms.deleteRoom(roomName);
  } catch (error) {
    // LiveKit removes empty rooms automatically. Clients still receive the
    // terminal Firestore state when cleanup is slow or the room is absent.
    logger.info('LiveKit room cleanup did not delete the room', {
      ...context,
      roomName,
      error: String(error),
    });
  }
}

async function deleteLiveKitRoomBounded(roomName, context = {}) {
  const startedAt = Date.now();
  let timeout;
  const cleanup = deleteLiveKitRoom(roomName, context).then(() => true);
  const completed = await Promise.race([
    cleanup,
    new Promise((resolve) => {
      timeout = setTimeout(
        () => resolve(false),
        liveKitRoomCleanupTimeoutMs,
      );
    }),
  ]);
  if (timeout != null) clearTimeout(timeout);
  if (!completed) {
    logger.warn('LiveKit room cleanup exceeded the response budget', {
      ...context,
      roomName,
      cleanupBudgetMs: liveKitRoomCleanupTimeoutMs,
    });
  }
  return {
    completed,
    durationMs: Date.now() - startedAt,
  };
}

async function createLiveKitParticipantCredentials({
  call,
  participantId,
  nowMillis = Date.now(),
}) {
  const remainingSeconds = remainingCallSeconds(call, nowMillis);
  if (remainingSeconds == null) {
    throw new HttpsError(
      'failed-precondition',
      'The call must be accepted and active before joining.',
    );
  }
  if (typeof call.roomName !== 'string' || call.roomName.length === 0) {
    throw new HttpsError(
      'failed-precondition',
      'The active call room is unavailable.',
    );
  }
  const serverUrl = requireLiveKitServerUrl();
  const endsAtMillis = callTimestampMillis(call.endsAt);
  const { AccessToken } = require('livekit-server-sdk');
  const accessToken = new AccessToken(
    liveKitApiKey.value(),
    liveKitApiSecret.value(),
    {
      identity: participantId,
      ttl: `${remainingSeconds}s`,
    },
  );
  accessToken.addGrant({
    roomJoin: true,
    room: call.roomName,
    canPublish: true,
    canSubscribe: true,
  });
  return {
    serverUrl,
    token: await accessToken.toJwt(),
    roomName: call.roomName,
    callId: call.callId,
    endsAtMillis,
  };
}

// Creates a durable invitation without credentials. The accepted response can
// issue the recipient token directly; the separate token callable remains the
// caller and reconnect path.
exports.startBookingCall = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const operationStartedAt = Date.now();
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'Sign in before starting a call.',
      );
    }
    const bookingId = requiredString(request.data?.bookingId, 'Booking ID');
    if (!validBookingId(bookingId)) {
      throw new HttpsError('invalid-argument', 'A valid booking ID is required.');
    }
    const serverUrl = requireLiveKitServerUrl();

    const uid = request.auth.uid;
    const bookingRef = db.collection('bookings').doc(bookingId);
    const callRef = db.collection('bookingCalls').doc(bookingId);
    const now = Timestamp.now();
    const proposedCallId = `call_${randomUUID().replace(/-/g, '')}`;
    const result = await db.runTransaction(async (transaction) => {
      const [bookingSnapshot, callSnapshot] = await Promise.all([
        transaction.get(bookingRef),
        transaction.get(callRef),
      ]);
      if (!bookingSnapshot.exists) {
        throw new HttpsError('not-found', 'Booking not found.');
      }
      const booking = bookingSnapshot.data();
      requireCallParticipant(booking, uid);
      if (!callAllowedForBookingStatus(booking.status)) {
        throw new HttpsError(
          'failed-precondition',
          'Voice calls are unavailable at this ride stage.',
        );
      }
      const recipientId = recipientFor(booking, uid);
      if (!recipientId) {
        throw new HttpsError(
          'failed-precondition',
          'The other ride participant is unavailable.',
        );
      }

      if (callSnapshot.exists) {
        const existing = callSnapshot.data();
        const effectiveStatus = effectiveCallStatus(existing, now.toMillis());
        const currentSchema =
          validOperationId(existing.callId) &&
          typeof existing.roomName === 'string' &&
          existing.roomName.length > 0;
        if (currentSchema &&
            effectiveStatus === CALL_STATUS.ringing &&
            existing.callerId === uid &&
            existing.recipientId === recipientId) {
          transaction.set(callRef, {
            schemaVersion: 3,
            serverUrl,
          }, { merge: true });
          return {
            data: {
              ...existing,
              schemaVersion: 3,
              serverUrl,
            },
            idempotent: true,
            notify: false,
          };
        }
        if (currentSchema &&
            (effectiveStatus === CALL_STATUS.ringing ||
              effectiveStatus === CALL_STATUS.accepted)) {
          throw new HttpsError(
            'already-exists',
            'A ride call is already active.',
          );
        }
      }

      const data = {
        schemaVersion: 3,
        bookingId,
        callId: proposedCallId,
        roomName: `voltrike_${proposedCallId}`,
        serverUrl,
        callerId: uid,
        recipientId,
        status: CALL_STATUS.ringing,
        createdAt: now,
        updatedAt: now,
        expiresAt: Timestamp.fromMillis(
          now.toMillis() + CALL_INVITATION_MS,
        ),
        acceptedAt: null,
        acceptedBy: null,
        endsAt: null,
        endedAt: null,
        endedBy: null,
      };
      transaction.set(callRef, data);
      return { data, idempotent: false, notify: true };
    });
    const transactionMs = Date.now() - operationStartedAt;

    const notificationStartedAt = Date.now();
    if (result.notify) {
      try {
        await sendToUser(
          result.data.recipientId,
          'Incoming ride call',
          'Your ride participant is calling you.',
          {
            bookingId,
            callId: result.data.callId,
            type: 'incoming_call',
            expiresAtMillis: result.data.expiresAt.toMillis(),
            serverUrl,
          },
        );
      } catch (error) {
        // The Firestore listener is the durable discovery path. A temporary
        // FCM failure must not make the already-created invitation look lost
        // to the caller.
        logger.error('Could not send incoming call notification', {
          bookingId,
          callId: result.data.callId,
          error: String(error),
        });
      }
    }
    const notificationMs = Date.now() - notificationStartedAt;
    logBookingCallLatency(
      'start',
      operationStartedAt,
      {
        bookingId,
        callId: result.data.callId,
        idempotent: result.idempotent,
      },
      { transactionMs, notificationMs },
    );
    return callResult(result.data, { idempotent: result.idempotent });
  },
);

// Only the intended recipient can accept or decline. Either participant may
// mark a genuinely elapsed invitation expired, which gives clients an exact
// timeout while the scheduled cleanup remains a backend fallback.
exports.respondBookingCall = onCall(
  {
    region: 'asia-southeast1',
    secrets: [liveKitApiKey, liveKitApiSecret],
  },
  async (request) => {
    const operationStartedAt = Date.now();
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before responding.');
    }
    const { bookingId, callId } = requireCallIdentity(request.data);
    const response = requiredString(request.data?.response, 'Response');
    if (![
      CALL_STATUS.accepted,
      CALL_STATUS.declined,
      CALL_STATUS.expired,
    ].includes(response)) {
      throw new HttpsError('invalid-argument', 'Unsupported call response.');
    }
    const acceptanceServerUrl = response === CALL_STATUS.accepted
      ? configuredLiveKitServerUrl()
      : null;

    const uid = request.auth.uid;
    const bookingRef = db.collection('bookings').doc(bookingId);
    const callRef = db.collection('bookingCalls').doc(bookingId);
    const now = Timestamp.now();
    const result = await db.runTransaction(async (transaction) => {
      const [bookingSnapshot, callSnapshot] = await Promise.all([
        transaction.get(bookingRef),
        transaction.get(callRef),
      ]);
      if (!bookingSnapshot.exists || !callSnapshot.exists) {
        throw new HttpsError('not-found', 'The call invitation is unavailable.');
      }
      const booking = bookingSnapshot.data();
      requireCallParticipant(booking, uid);
      const call = callSnapshot.data();
      if (call.callId !== callId) {
        throw new HttpsError(
          'failed-precondition',
          'This call invitation is no longer current.',
        );
      }

      const effectiveStatus = effectiveCallStatus(call, now.toMillis());
      if (terminalCallStatus(effectiveStatus)) {
        if (effectiveStatus === CALL_STATUS.expired &&
            call.status !== CALL_STATUS.expired) {
          const expired = {
            ...call,
            status: CALL_STATUS.expired,
            expiredAt: now,
            updatedAt: now,
          };
          transaction.set(callRef, {
            status: CALL_STATUS.expired,
            expiredAt: now,
            updatedAt: now,
          }, { merge: true });
          return { data: expired, idempotent: false };
        }
        return {
          data: { ...call, status: effectiveStatus },
          idempotent: true,
        };
      }
      if (call.status === CALL_STATUS.accepted) {
        if (response === CALL_STATUS.accepted &&
            call.acceptedBy === uid) {
          if (acceptanceServerUrl == null) {
            throw new HttpsError(
              'failed-precondition',
              'Voice calling is not configured.',
            );
          }
          transaction.set(callRef, {
            schemaVersion: 3,
            serverUrl: acceptanceServerUrl,
          }, { merge: true });
          return {
            data: {
              ...call,
              schemaVersion: 3,
              serverUrl: acceptanceServerUrl,
            },
            idempotent: true,
          };
        }
        throw new HttpsError(
          'failed-precondition',
          'This call has already been accepted.',
        );
      }
      if (call.status !== CALL_STATUS.ringing) {
        throw new HttpsError(
          'failed-precondition',
          'This call can no longer be answered.',
        );
      }

      if (response === CALL_STATUS.expired) {
        const expiresAt = callTimestampMillis(call.expiresAt);
        if (expiresAt == null || expiresAt > now.toMillis()) {
          throw new HttpsError(
            'failed-precondition',
            'This call invitation has not expired.',
          );
        }
        const expired = {
          ...call,
          status: CALL_STATUS.expired,
          expiredAt: now,
          updatedAt: now,
        };
        transaction.set(callRef, {
          status: CALL_STATUS.expired,
          expiredAt: now,
          updatedAt: now,
        }, { merge: true });
        return { data: expired, idempotent: false };
      }

      if (uid !== call.recipientId) {
        throw new HttpsError(
          'permission-denied',
          'Only the called participant can answer this invitation.',
        );
      }
      if (response === CALL_STATUS.declined) {
        const declined = {
          ...call,
          status: CALL_STATUS.declined,
          respondedBy: uid,
          respondedAt: now,
          updatedAt: now,
        };
        transaction.set(callRef, {
          status: CALL_STATUS.declined,
          respondedBy: uid,
          respondedAt: now,
          updatedAt: now,
        }, { merge: true });
        return { data: declined, idempotent: false };
      }

      if (!callAllowedForBookingStatus(booking.status)) {
        throw new HttpsError(
          'failed-precondition',
          'Voice calls are unavailable at this ride stage.',
        );
      }
      if (acceptanceServerUrl == null) {
        throw new HttpsError(
          'failed-precondition',
          'Voice calling is not configured.',
        );
      }
      const accepted = {
        ...call,
        schemaVersion: 3,
        serverUrl: acceptanceServerUrl,
        status: CALL_STATUS.accepted,
        acceptedBy: uid,
        acceptedAt: now,
        endsAt: Timestamp.fromMillis(now.toMillis() + CALL_DURATION_MS),
        updatedAt: now,
      };
      transaction.set(callRef, {
        schemaVersion: 3,
        serverUrl: acceptanceServerUrl,
        status: CALL_STATUS.accepted,
        acceptedBy: uid,
        acceptedAt: accepted.acceptedAt,
        endsAt: accepted.endsAt,
        updatedAt: now,
      }, { merge: true });
      return { data: accepted, idempotent: false };
    });
    const transactionMs = Date.now() - operationStartedAt;
    const responseData = callResult(result.data, {
      idempotent: result.idempotent,
    });
    let credentialMs = 0;
    if (result.data.status === CALL_STATUS.accepted &&
        result.data.acceptedBy === uid) {
      const credentialStartedAt = Date.now();
      const credentials = await createLiveKitParticipantCredentials({
        call: result.data,
        participantId: uid,
      });
      credentialMs = Date.now() - credentialStartedAt;
      Object.assign(responseData, credentials);
    }
    logBookingCallLatency(
      'respond',
      operationStartedAt,
      {
        bookingId,
        callId,
        response,
        resultingStatus: result.data.status,
        idempotent: result.idempotent,
      },
      { transactionMs, credentialMs },
    );
    return responseData;
  },
);

// Issues a short-lived participant token only for the current accepted call.
exports.createBookingCallToken = onCall(
  {
    region: 'asia-southeast1',
    secrets: [liveKitApiKey, liveKitApiSecret],
  },
  async (request) => {
    const operationStartedAt = Date.now();
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'Sign in before joining a call.',
      );
    }
    const { bookingId, callId } = requireCallIdentity(request.data);
    const [bookingSnapshot, callSnapshot] = await Promise.all([
      db.collection('bookings').doc(bookingId).get(),
      db.collection('bookingCalls').doc(bookingId).get(),
    ]);
    const readMs = Date.now() - operationStartedAt;
    if (!bookingSnapshot.exists || !callSnapshot.exists) {
      throw new HttpsError('not-found', 'The active call is unavailable.');
    }
    const booking = bookingSnapshot.data();
    requireCallParticipant(booking, request.auth.uid);
    const call = callSnapshot.data();
    const nowMillis = Date.now();
    if (call.callId !== callId ||
        effectiveCallStatus(call, nowMillis) !== CALL_STATUS.accepted) {
      throw new HttpsError(
        'failed-precondition',
        'The call must be accepted before joining.',
      );
    }
    const credentialStartedAt = Date.now();
    const credentials = await createLiveKitParticipantCredentials({
      call,
      participantId: request.auth.uid,
      nowMillis,
    });
    logBookingCallLatency(
      'create-token',
      operationStartedAt,
      { bookingId, callId },
      {
        readMs,
        credentialMs: Date.now() - credentialStartedAt,
      },
    );
    return credentials;
  },
);

// Either participant can deliberately end only the current call attempt.
exports.endBookingCall = onCall(
  {
    region: 'asia-southeast1',
    secrets: [liveKitApiKey, liveKitApiSecret],
  },
  async (request) => {
    const operationStartedAt = Date.now();
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before ending a call.');
    }
    const { bookingId, callId } = requireCallIdentity(request.data);
    const [bookingSnapshot, callSnapshot] = await Promise.all([
      db.collection('bookings').doc(bookingId).get(),
      db.collection('bookingCalls').doc(bookingId).get(),
    ]);
    const readMs = Date.now() - operationStartedAt;
    if (!bookingSnapshot.exists || !callSnapshot.exists) {
      throw new HttpsError('not-found', 'The active call is unavailable.');
    }
    const booking = bookingSnapshot.data();
    requireCallParticipant(booking, request.auth.uid);
    const call = callSnapshot.data();
    if (call.callId !== callId) {
      throw new HttpsError(
        'failed-precondition',
        'This call is no longer current.',
      );
    }
    if (terminalCallStatus(call.status)) {
      logBookingCallLatency(
        'end',
        operationStartedAt,
        { bookingId, callId, idempotent: true },
        { readMs, transactionMs: 0, cleanupMs: 0 },
      );
      return callResult(call, { idempotent: true });
    }

    const now = Timestamp.now();
    const transactionStartedAt = Date.now();
    const result = await db.runTransaction(async (transaction) => {
      const currentSnapshot = await transaction.get(
        db.collection('bookingCalls').doc(bookingId),
      );
      if (!currentSnapshot.exists ||
          currentSnapshot.data().callId !== callId) {
        throw new HttpsError(
          'failed-precondition',
          'This call is no longer current.',
        );
      }
      const current = currentSnapshot.data();
      if (terminalCallStatus(current.status)) {
        return { data: current, idempotent: true };
      }
      const ended = {
        ...current,
        status: CALL_STATUS.ended,
        endedBy: request.auth.uid,
        endedAt: now,
        updatedAt: now,
      };
      transaction.set(currentSnapshot.ref, {
        status: CALL_STATUS.ended,
        endedBy: request.auth.uid,
        endedAt: now,
        updatedAt: now,
      }, { merge: true });
      return { data: ended, idempotent: false };
    });
    const transactionMs = Date.now() - transactionStartedAt;
    let cleanupMs = 0;
    let cleanupCompleted = true;
    if (!result.idempotent) {
      const cleanup = await deleteLiveKitRoomBounded(
        result.data.roomName,
        { bookingId, callId, source: 'participant-end' },
      );
      cleanupMs = cleanup.durationMs;
      cleanupCompleted = cleanup.completed;
    }
    logBookingCallLatency(
      'end',
      operationStartedAt,
      {
        bookingId,
        callId,
        idempotent: result.idempotent,
        cleanupCompleted,
      },
      { readMs, transactionMs, cleanupMs },
    );
    return callResult(result.data, { idempotent: result.idempotent });
  },
);

// Exact expiry is enforced when a client responds or requests a token. This
// scheduled job provides durable cleanup when both apps are offline.
exports.expireBookingCalls = onSchedule(
  {
    schedule: 'every 1 minutes',
    region: 'asia-southeast1',
    secrets: [liveKitApiKey, liveKitApiSecret],
  },
  async () => {
    const now = Timestamp.now();
    const [ringing, accepted] = await Promise.all([
      db.collection('bookingCalls')
        .where('status', '==', CALL_STATUS.ringing)
        .where('expiresAt', '<=', now)
        .limit(100)
        .get(),
      db.collection('bookingCalls')
        .where('status', '==', CALL_STATUS.accepted)
        .where('endsAt', '<=', now)
        .limit(100)
        .get(),
    ]);

    await Promise.all(ringing.docs.map((entry) =>
      db.runTransaction(async (transaction) => {
        const current = await transaction.get(entry.ref);
        if (!current.exists ||
            current.data().callId !== entry.data().callId ||
            effectiveCallStatus(current.data(), now.toMillis()) !==
              CALL_STATUS.expired) {
          return;
        }
        transaction.set(entry.ref, {
          status: CALL_STATUS.expired,
          expiredAt: now,
          updatedAt: now,
        }, { merge: true });
      }),
    ));
    const acceptedResults = await Promise.all(accepted.docs.map(
      async (entry) => {
        const queriedCallId = entry.data().callId;
        const transition = await db.runTransaction(async (transaction) => {
          const current = await transaction.get(entry.ref);
          const currentCall = current.exists ? current.data() : null;
          if (!current.exists ||
              !acceptedCallNeedsScheduledEnd(
                currentCall,
                queriedCallId,
                now.toMillis(),
              )) {
            return { transitioned: false };
          }
          const ended = {
            ...currentCall,
            status: CALL_STATUS.ended,
            endedBy: 'system',
            endedAt: now,
            updatedAt: now,
          };
          transaction.set(entry.ref, {
            status: CALL_STATUS.ended,
            endedBy: 'system',
            endedAt: now,
            updatedAt: now,
          }, { merge: true });
          return {
            transitioned: true,
            data: ended,
          };
        });
        if (!transition.transitioned) return transition;

        // The durable terminal state is committed before the optional room
        // cleanup. A slow LiveKit API can no longer leave Firestore accepted.
        const cleanup = await deleteLiveKitRoomBounded(
          transition.data.roomName,
          {
            bookingId: transition.data.bookingId,
            callId: transition.data.callId,
            source: 'scheduled-expiry',
          },
        );
        return {
          ...transition,
          cleanupCompleted: cleanup.completed,
          cleanupMs: cleanup.durationMs,
        };
      },
    ));
    const acceptedTransitioned = acceptedResults.filter(
      (result) => result.transitioned,
    );
    const acceptedCleanupTimedOut = acceptedTransitioned.filter(
      (result) => result.cleanupCompleted === false,
    );
    logger.info('Expired booking calls cleaned up', {
      ringing: ringing.size,
      accepted: accepted.size,
      acceptedTransitioned: acceptedTransitioned.length,
      acceptedCleanupTimedOut: acceptedCleanupTimedOut.length,
    });
  },
);

// Drivers receive only their own offer documents. Candidate proximity comes
// from fresh RTDB coordinates, never from Google Places.
exports.dispatchBookingOffers = onDocumentCreated('bookings/{bookingId}', async (event) => {
  await dispatchNextOfferBatch(event.params.bookingId);
});

async function expirePendingBookingSearch(bookingId) {
  const bookingRef = db.collection('bookings').doc(bookingId);
  const expired = await db.runTransaction(async (transaction) => {
    const booking = await transaction.get(bookingRef);
    if (!booking.exists ||
        booking.data().status !== BOOKING_STATUS.pending) {
      return false;
    }
    const data = booking.data();
    const createdAt = snapshotDateMillis(data.createdAt);
    const searchExpiresAt = snapshotDateMillis(data.searchExpiresAt) ??
      (createdAt == null ? null : createdAt + bookingSearchDurationMs);
    if (searchExpiresAt == null || searchExpiresAt > Date.now()) return false;
    const awardWindowEndsAt = snapshotDateMillis(data.awardWindowEndsAt);
    if (Number(data.awardWindowRound) === Number(data.offerRound || 0) &&
        awardWindowEndsAt != null &&
        Date.now() <
          awardWindowEndsAt + acceptanceFinalizationGraceMs) {
      return false;
    }
    const passengerLockRef = db.collection('activePassengerBookings')
      .doc(data.passengerId);
    const passengerLock = await transaction.get(passengerLockRef);
    transaction.update(bookingRef, {
      status: BOOKING_STATUS.cancelled,
      cancelledAt: timestamp(),
      cancelledBy: 'system',
      cancellationCode: 'search_timeout',
      cancellationDetail:
        'No eligible driver was awarded before the search deadline.',
      updatedAt: timestamp(),
    });
    if (passengerLock.exists &&
        passengerLock.data().bookingId === bookingId) {
      transaction.delete(passengerLockRef);
    }
    transaction.set(db.collection('auditLogs')
      .doc(`booking_timeout_${bookingId}`), {
      type: 'booking_lifecycle',
      action: 'search_timeout',
      bookingId,
      actorId: 'system',
      actorRole: 'system',
      fromStatus: BOOKING_STATUS.pending,
      toStatus: BOOKING_STATUS.cancelled,
      cancellationCode: 'search_timeout',
      createdAt: timestamp(),
    });
    return true;
  });
  if (expired) await expireBookingOffers(bookingId, 'closed');
  return expired;
}

// Pending bookings receive the next nearest unoffered batch after the prior
// offer window. The same pass also provides a backend timeout when the
// passenger app is offline, so its active-booking lock cannot persist forever.
exports.redispatchPendingBookings = onSchedule(
  { region: 'asia-southeast1', schedule: 'every 1 minutes' },
  async () => {
    const pending = await db.collection('bookings')
      .where('status', '==', BOOKING_STATUS.pending)
      .limit(50)
      .get();
    await Promise.all(pending.docs.map(async (booking) => {
      if (await expirePendingBookingSearch(booking.id)) return;
      await dispatchNextOfferBatch(booking.id);
    }));
  },
);

exports.notifyBookingLifecycle = onDocumentUpdated('bookings/{bookingId}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status) return;
  const bookingId = event.params.bookingId;
  const passenger = after.passengerId;
  const driver = after.driverId;
  const passengerMessages = {
    driverAssigned: ['Driver assigned', 'Your driver accepted the booking.'],
    driverArriving: ['Driver arrived', 'Your driver has arrived at pickup.'],
    passengerOnBoard: ['Trip started', 'You are on the way to your destination.'],
    paymentConfirmation: ['Payment confirmation', 'Waiting for the driver to confirm cash received.'],
    completed: ['Trip completed', 'Your receipt is ready.'],
    cancelled: ['Booking cancelled', 'Your booking was cancelled.'],
  };
  const driverMessages = {
    passengerOnBoard: ['Trip started', 'Navigate to the destination.'],
    paymentConfirmation: ['Confirm cash received', 'Confirm cash to complete the trip.'],
    completed: ['Trip completed', 'Your earnings receipt is ready.'],
  };
  const cancellationCode = String(after.cancellationCode || '');
  if (after.status === BOOKING_STATUS.cancelled) {
    const noShow = cancellationCode === 'passenger_no_show';
    const byPassenger = cancellationCode.includes('passenger');
    passengerMessages.cancelled = noShow
      ? ['Passenger no-show', 'This booking was closed as a passenger no-show.']
      : byPassenger
        ? ['Cancelled by passenger', 'You cancelled this booking.']
        : ['Cancelled by driver', 'Your driver cancelled this booking.'];
    driverMessages.cancelled = noShow
      ? ['Passenger no-show', 'The no-show booking was closed.']
      : byPassenger
        ? ['Cancelled by passenger', 'The passenger cancelled the trip.']
        : ['Cancelled by driver', 'You cancelled the trip.'];
  }
  const passengerMessage = passengerMessages[after.status];
  const driverMessage = driverMessages[after.status];
  const tasks = [];
  if (passenger && passengerMessage) tasks.push(sendToUser(passenger, passengerMessage[0], passengerMessage[1], { bookingId, target: 'passenger', type: after.status }));
  if (driver && driverMessage) tasks.push(sendToUser(driver, driverMessage[0], driverMessage[1], { bookingId, target: 'driver', type: after.status }));
  await Promise.all(tasks);
});
