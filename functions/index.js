const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { createHash } = require('node:crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { logger } = require('firebase-functions');
const { defineSecret, defineString } = require('firebase-functions/params');
const admin = require('firebase-admin');
const {
  FieldPath,
  FieldValue,
  Timestamp,
  AggregateField,
} = require('firebase-admin/firestore');
const { ServerValue } = require('firebase-admin/database');
const {
  BOOKING_STATUS,
  distanceMeters,
  nextRatingAggregate,
  normalizeCoordinate,
  validBookingId,
  validOperationId,
} = require('./booking-lifecycle');
const {
  adminIdentityMatches,
  canManageToda,
} = require('./admin-policy');
const {
  calculateFare,
  fareSnapshot,
} = require('./fare-policy');
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

async function trustedRoute(pickup, destination) {
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
    return {
      distanceMeters: routeDistanceMeters,
      duration: `${Math.max(60, Math.round(routeDistanceMeters / 6))}s`,
    };
  }
  const response = await fetch(
    'https://routes.googleapis.com/directions/v2:computeRoutes',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': googleRoutesApiKey.value(),
        'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration',
      },
      body: JSON.stringify({
        origin: {
          location: {
            latLng: {
              latitude: pickup.latitude,
              longitude: pickup.longitude,
            },
          },
        },
        destination: {
          location: {
            latLng: {
              latitude: destination.latitude,
              longitude: destination.longitude,
            },
          },
        },
        travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_AWARE',
        computeAlternativeRoutes: false,
        languageCode: 'en-PH',
        units: 'METRIC',
      }),
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
  const route = payload.routes?.[0];
  if (!Number.isInteger(route?.distanceMeters) || route.distanceMeters <= 0) {
    throw new HttpsError(
      'failed-precondition',
      'No valid driving route is available for these locations.',
    );
  }
  return {
    distanceMeters: route.distanceMeters,
    duration: typeof route.duration === 'string' ? route.duration : null,
  };
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
// Thirty seconds was too short once notification delivery, app rendering,
// and a driver's decision time were included. Keep the offer authoritative
// on the backend, but provide a practical response window.
const offerDurationMs = 120000;

async function rankedDispatchDrivers(booking) {
  const pickup = normalizeCoordinate(booking.pickup, 'Pickup');
  const [drivers, locations] = await Promise.all([
    db.collection('drivers')
      .where('driverStatus', '==', 'approved')
      .where('isOnline', '==', true)
      .where('isAvailable', '==', true)
      .limit(100)
      .get(),
    realtime.ref('driver_locations').get(),
  ]);
  const locationMap = locations.val() || {};
  const now = Date.now();
  const excluded = new Set(
    Array.isArray(booking.offeredDriverIds) ? booking.offeredDriverIds : [],
  );
  const nearby = drivers.docs.map((driver) => {
    const location = locationMap[driver.id];
    if (!location || location.online !== true ||
        !Number.isFinite(Number(location.timestamp)) ||
        now - Number(location.timestamp) > driverLocationMaxAgeMs ||
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
    return proximity <= dispatchRadiusMeters
      ? { driver, distanceMeters: Math.round(proximity) }
      : null;
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
      typeof driver.data().licenseNumber === 'string' &&
      driver.data().licenseNumber.trim().length > 0 &&
      licenseExpiry != null &&
      licenseExpiry >= now;
  });
  eligible.sort((a, b) => a.distanceMeters - b.distanceMeters);
  return eligible;
}

async function dispatchNextOfferBatch(bookingId) {
  const bookingRef = db.collection('bookings').doc(bookingId);
  const claimedBooking = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists || snapshot.data().status !== BOOKING_STATUS.pending) {
      return null;
    }
    const current = snapshot.data();
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

  const candidates = (await rankedDispatchDrivers(booking))
    .slice(0, dispatchBatchSize);
  const previousDrivers = Array.isArray(booking.offeredDriverIds)
    ? booking.offeredDriverIds
    : [];
  const batch = db.batch();
  previousDrivers.forEach((driverId) => {
    batch.set(
      db.doc(`drivers/${driverId}/bookingOffers/${bookingId}`),
      { status: 'expired', updatedAt: timestamp() },
      { merge: true },
    );
  });
  const expiresAt = Timestamp.fromMillis(
    Date.now() + offerDurationMs,
  );
  candidates.forEach(({ driver, distanceMeters: proximity }) => {
    batch.set(db.doc(`drivers/${driver.id}/bookingOffers/${bookingId}`), {
      bookingId,
      driverId: driver.id,
      todaId: driver.data().todaId,
      distanceMeters: proximity,
      status: 'offered',
      createdAt: timestamp(),
      updatedAt: timestamp(),
      expiresAt,
    });
  });
  const bookingUpdate = {
    offerRound: Number(booking.offerRound || 0) + 1,
    lastOfferAt: timestamp(),
    nextDispatchAt: Timestamp.fromMillis(
      Date.now() + offerDurationMs,
    ),
    updatedAt: timestamp(),
  };
  if (candidates.length > 0) {
    bookingUpdate.offeredDriverIds = FieldValue.arrayUnion(
      ...candidates.map(({ driver }) => driver.id),
    );
  }
  batch.set(
    bookingRef,
    bookingUpdate,
    { merge: true },
  );
  await batch.commit();
  await Promise.all(candidates.map(({ driver, distanceMeters: proximity }) =>
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
    count: candidates.length,
    radiusMeters: dispatchRadiusMeters,
    offerRound: Number(booking.offerRound || 0) + 1,
  });
  return candidates.length;
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
  return ref.set({
    type: 'admin_action',
    actorId: actor.uid,
    actorRole: actor.role,
    actorTodaId: actor.todaId || null,
    action,
    targetType,
    targetId,
    details,
    createdAt: timestamp(),
  });
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
  if (tokens.length === 0) return;
  const type = data.type;
  const channelId = type === 'chat_message'
    ? 'chat_messages'
    : type === 'incoming_call'
      ? 'incoming_calls'
      : 'booking_updates';
  const sound = type === 'chat_message'
    ? 'chat_ringtone'
    : type === 'incoming_call'
      ? 'inside_chat_screen_ringtone'
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
    await ref.update({ isActive: false, updatedAt: timestamp() });
    const writer = db.bulkWriter();
    drivers.docs.forEach((driver) => writer.update(driver.ref, { driverStatus: 'suspended', isOnline: false, isAvailable: false, updatedAt: timestamp() }));
    await writer.close();
  } else {
    // Restoring a TODA never restores individually suspended drivers.
    await ref.update({ isActive: true, updatedAt: timestamp() });
  }
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: developer,
    action: request.data.isActive ? 'restore_toda' : 'suspend_toda',
    targetType: 'toda',
    targetId: todaId,
  });
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
  return { updated: true };
});

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
  if (status === 'approved') {
    const vehicle = await db.collection('vehicles')
      .doc(driver.data().vehicleId || '_missing')
      .get();
    const licenseExpiry = snapshotDateMillis(driver.data().licenseExpiry);
    if (!driver.data().licenseNumber || licenseExpiry == null ||
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
  }
  if (status !== 'approved' && await activeDriverBooking(driver.data())) {
    throw new HttpsError(
      'failed-precondition',
      'This driver has an active ride. Apply the status change after it finishes.',
    );
  }
  const update = { driverStatus: status, updatedAt: timestamp() };
  if (status === 'approved') Object.assign(update, { approvedAt: timestamp(), approvedBy: profile.uid });
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
  const areas = Array.isArray(request.data?.areas) ? request.data.areas : [request.data?.polygon];
  const validArea = (area) => Array.isArray(area) && area.length >= 3 && area.length <= 200 &&
      area.every((point) => Array.isArray(point) && point.length === 2 && point.every(Number.isFinite));
  if (areas.length === 0 || areas.length > 20 || !areas.every(validArea)) {
    throw new HttpsError('invalid-argument', 'One to 20 polygons with 3 to 200 valid points each are required.');
  }
  const zone = await db.collection('zoneRequests').add({ todaId, polygon: areas[0], areas, status: 'pending', notes: String(request.data?.notes || '').slice(0, 1000), requestedBy: profile.uid, createdAt: timestamp(), updatedAt: timestamp() });
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
  const requestSnapshot = await ref.get();
  if (!requestSnapshot.exists) throw new HttpsError('not-found', 'Zone request not found.');
  const zone = requestSnapshot.data();
  const batch = db.batch();
  batch.update(ref, { status, reviewedBy: developer.uid, reviewedAt: timestamp(), updatedAt: timestamp() });
  if (status === 'approved') {
    const areas = Array.isArray(zone.areas) ? zone.areas : [zone.polygon];
    batch.set(db.collection('geofences').doc(zone.todaId), { todaId: zone.todaId, polygon: areas[0], areas, sourceRequestId: id, updatedBy: developer.uid, updatedAt: timestamp() }, { merge: true });
  }
  await batch.commit();
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: developer,
    action: `${status}_zone_request`,
    targetType: 'zoneRequest',
    targetId: id,
    details: { todaId: zone.todaId },
  });
  return { updated: true };
});

exports.adminUpdateZoneRequest = onCall({ region: 'asia-southeast1' }, async (request) => {
  const developer = await requireDeveloperAdmin(request);
  const id = requiredString(request.data?.zoneRequestId, 'Zone request ID');
  const areas = Array.isArray(request.data?.areas) ? request.data.areas : [request.data?.polygon];
  const validArea = (area) => Array.isArray(area) && area.length >= 3 && area.length <= 200 &&
      area.every((point) => Array.isArray(point) && point.length === 2 && point.every(Number.isFinite));
  if (areas.length === 0 || areas.length > 20 || !areas.every(validArea)) {
    throw new HttpsError('invalid-argument', 'One to 20 polygons with 3 to 200 valid points each are required.');
  }
  const ref = db.collection('zoneRequests').doc(id);
  if (!(await ref.get()).exists) throw new HttpsError('not-found', 'Zone request not found.');
  await ref.update({ polygon: areas[0], areas, notes: String(request.data?.notes || '').slice(0, 1000), updatedAt: timestamp() });
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: developer,
    action: 'update_zone_request_geometry',
    targetType: 'zoneRequest',
    targetId: id,
    details: { areaCount: areas.length },
  });
  return { updated: true };
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
  const geometryType = request.data?.geometryType === 'corridor' ? 'corridor' : 'polygon';
  const coordinates = request.data?.polygon;
  const areas = geometryType === 'polygon' && Array.isArray(request.data?.areas)
    ? request.data.areas
    : [coordinates];
  const minimumPoints = geometryType === 'corridor' ? 2 : 3;
  const validArea = (area) => Array.isArray(area) && area.length >= minimumPoints &&
      area.length <= 200 && area.every((point) => Array.isArray(point) && point.length === 2 && point.every(Number.isFinite));
  if (!Array.isArray(areas) || areas.length === 0 || areas.length > 20 ||
      (geometryType === 'corridor' && areas.length !== 1) || !areas.every(validArea)) {
    throw new HttpsError('invalid-argument', geometryType === 'corridor' ? 'A corridor needs 2 to 200 centreline points.' : 'A polygon needs 3 to 200 points.');
  }
  const bufferMeters = geometryType === 'corridor'
    ? validPositiveInteger(request.data?.bufferMeters, 'Corridor buffer', 5, 200)
    : 0;
  const ref = await db.collection('routeRestrictions').add({
    name, type, geometryType, polygon: areas[0], coordinates: areas[0], areas, bufferMeters, isActive: true,
    notes: String(request.data?.notes || '').slice(0, 1000),
    createdBy: developer.uid, createdAt: timestamp(), updatedAt: timestamp(),
  });
  await adminAudit(db.collection('auditLogs').doc(), {
    actor: developer,
    action: 'create_route_restriction',
    targetType: 'routeRestriction',
    targetId: ref.id,
    details: { type, geometryType, areaCount: areas.length, bufferMeters },
  });
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
  return { updated: true };
});

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
      functionsProtocolVersion: 3,
      minimumClientProtocolVersion: 3,
      bookingSchemaVersion: 2,
      firestoreRulesVersion: 3,
      realtimeRulesVersion: 2,
      storageRulesVersion: 2,
      region: 'asia-southeast1',
      projectId: process.env.GCLOUD_PROJECT || null,
      checkedAt: new Date().toISOString(),
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
      driverEarnings, tripRevenue, bookingCount, openSafetyIncidents] =
      await Promise.all([
      drivers.count().get(),
      openReportsQuery.count().get(),
      zones.where('status', '==', 'pending').count().get(),
      bookings.where('status', '==', BOOKING_STATUS.completed).count().get(),
      drivers.aggregate({
        value: AggregateField.sum('totalEarnings'),
      }).get(),
      bookings.where('status', '==', BOOKING_STATUS.completed).aggregate({
        value: AggregateField.sum('amountDue'),
      }).get(),
      bookings.count().get(),
      safetyIncidents.where('status', '==', 'open').count().get(),
    ]);
    return {
      drivers: driverCount.data().count,
      reports: openReports.data().count,
      zones: pendingZones.data().count,
      trips: completedTrips.data().count,
      earnings: Number(driverEarnings.data().value || 0),
      tripRevenue: Number(tripRevenue.data().value || 0),
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
    return {
      items: page.map((entry) => ({
        id: entry.id,
        ...entry.data(),
        createdAt: adminDate(entry.data().createdAt),
      })),
      nextCursor: snapshot.docs.length > pageSize
        ? page.at(-1)?.id || null
        : null,
    };
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
      20,
    );
    const baggageCount = validNonNegativeInteger(
      request.data?.baggageCount,
      'Baggage count',
      20,
    );
    if (typeof request.data?.isOutsideToda !== 'boolean') {
      throw new HttpsError('invalid-argument', 'TODA boundary state is required.');
    }

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
      };
    }

    const [route, fareDocument] = await Promise.all([
      trustedRoute(pickup, destination),
      db.collection('settings').doc('fare_config').get(),
    ]);
    const pricing = fareSnapshot(
      fareDocument.exists ? fareDocument.data() : null,
    );
    const distanceMeters = route.distanceMeters;
    const estimatedFare = calculateFare({
      config: pricing,
      distanceMeters,
      additionalPassengers,
      baggageCount,
      isOutsideToda: request.data.isOutsideToda,
    });

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
        fareSnapshot: pricing,
        clientEstimate: {
          distanceMeters: clientDistanceMeters,
          estimatedFare: clientEstimatedFare,
        },
        additionalPassengers,
        baggageCount,
        isOutsideToda: request.data.isOutsideToda,
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
      fareVersion: pricing.version,
      ...result,
    };
  },
);

// Accepts a dispatched offer using trusted user, driver, vehicle, and TODA
// snapshots. Booking assignment and driver reservation are one transaction.
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
    const auditRef = auditReference(bookingId, uid, operationId);

    const result = await db.runTransaction(async (transaction) => {
      const [booking, user, driver, offer, operation] = await Promise.all([
        transaction.get(bookingRef),
        transaction.get(userRef),
        transaction.get(driverRef),
        transaction.get(offerRef),
        transaction.get(operationRef),
      ]);
      if (operation.exists) {
        return { idempotent: true };
      }
      if (!booking.exists) {
        throw new HttpsError('not-found', 'Booking not found.');
      }
      const bookingData = booking.data();
      if (bookingData.driverId === uid &&
          bookingData.status === BOOKING_STATUS.driverAssigned) {
        return {
          idempotent: true,
          passengerId: bookingData.passengerId,
        };
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
      if (bookingData.status !== BOOKING_STATUS.pending ||
          bookingData.driverId != null) {
        throw new HttpsError('failed-precondition', 'This booking has already changed.');
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
      if (!toda.exists || toda.data().isActive !== true) {
        throw new HttpsError('failed-precondition', 'The assigned TODA is not active.');
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

      const profile = user.data();
      const driverName = [
        profile.firstName,
        profile.middleName,
        profile.lastName,
      ].filter((value) => typeof value === 'string' && value.trim()).join(' ');
      transaction.update(bookingRef, {
        driverId: uid,
        driverName: driverName || request.auth.token.name || 'Driver',
        driverPhotoUrl: profile.profileImage || driver.data().profilePhotoUrl || '',
        driverRating: Number(driver.data().rating || 0),
        vehicleNumber: vehicle.data().vehicleNumber || vehicle.data().model || '',
        plateNumber: vehicle.data().plateNumber || '',
        todaId: driver.data().todaId,
        todaName: toda.data().name || '',
        status: BOOKING_STATUS.driverAssigned,
        assignedAt: timestamp(),
        updatedAt: timestamp(),
      });
      transaction.update(driverRef, {
        currentBookingId: bookingId,
        isAvailable: false,
        updatedAt: timestamp(),
      });
      transaction.set(offerRef, {
        status: 'accepted',
        acceptedAt: timestamp(),
        updatedAt: timestamp(),
      }, { merge: true });
      transaction.create(operationRef, {
        bookingId,
        operationId,
        actorId: uid,
        action: 'accept',
        resultStatus: BOOKING_STATUS.driverAssigned,
        createdAt: timestamp(),
      });
      transaction.create(auditRef, {
        type: 'booking_lifecycle',
        action: 'accept',
        bookingId,
        actorId: uid,
        actorRole: 'driver',
        fromStatus: BOOKING_STATUS.pending,
        toStatus: BOOKING_STATUS.driverAssigned,
        createdAt: timestamp(),
      });
      return {
        idempotent: false,
        passengerId: bookingData.passengerId,
      };
    });
    await realtime
      .ref(`driver_tracking_access/${result.passengerId}/${uid}`)
      .set({
        bookingId,
        grantedAt: ServerValue.TIMESTAMP,
      });
    await expireBookingOffers(bookingId, 'closed');
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
    const operationRef = operationReference(bookingId, driverId, operationId);
    const auditRef = auditReference(bookingId, driverId, operationId);

    const result = await db.runTransaction(async (transaction) => {
      const [booking, offer, operation] = await Promise.all([
        transaction.get(bookingRef),
        transaction.get(offerRef),
        transaction.get(operationRef),
      ]);
      if (operation.exists) return { idempotent: true };
      if (!booking.exists || booking.data().status !== BOOKING_STATUS.pending) {
        throw new HttpsError('failed-precondition', 'This offer is no longer active.');
      }
      if (!offer.exists || !['offered', 'declined'].includes(offer.data().status)) {
        throw new HttpsError('failed-precondition', 'No active offer was found.');
      }
      transaction.set(offerRef, {
        status: 'declined',
        declinedAt: timestamp(),
        updatedAt: timestamp(),
      }, { merge: true });
      transaction.update(bookingRef, {
        nextDispatchAt: Timestamp.fromMillis(Date.now() - 1000),
        updatedAt: timestamp(),
      });
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
      return { idempotent: false };
    });
    if (!result.idempotent) await dispatchNextOfferBatch(bookingId);
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
        expectedStatuses = isDriver
          ? [BOOKING_STATUS.driverAssigned, BOOKING_STATUS.driverArriving]
          : [BOOKING_STATUS.pending, BOOKING_STATUS.driverAssigned, BOOKING_STATUS.driverArriving];
        cancellationCode = action === 'noShow'
          ? (isDriver ? 'passenger_no_show' : 'driver_no_show')
          : requiredString(request.data?.reasonCode || 'cancelled', 'Cancellation reason');
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
        const receiptNumber = data.receiptNumber ||
          `VT-${bookingId.replace(/[^a-zA-Z0-9]/g, '').slice(0, 10).toUpperCase()}`;
        lifecycleUpdate.completedAt = timestamp();
        lifecycleUpdate.driverReceivedAt = data.driverReceivedAt || timestamp();
        lifecycleUpdate.cashConfirmedByDriverAt = timestamp();
        lifecycleUpdate.settlementStatus = 'settled';
        lifecycleUpdate.settlementTimestamp = timestamp();
        lifecycleUpdate.receiptNumber = receiptNumber;
      }
      if (nextStatus === BOOKING_STATUS.cancelled) {
        lifecycleUpdate.cancelledAt = timestamp();
        lifecycleUpdate.cancelledBy = uid;
        lifecycleUpdate.cancellationCode = cancellationCode;
        lifecycleUpdate.cancellationDetail = String(
          request.data?.reasonDetail || '',
        ).trim().slice(0, 500);
      }
      transaction.update(bookingRef, lifecycleUpdate);
      if (driverRef && driver?.exists &&
          driver.data().currentBookingId === bookingId) {
        const driverUpdate = {
          currentBookingId: null,
          isAvailable: driver.data().isOnline === true &&
            driver.data().driverStatus === 'approved',
          updatedAt: timestamp(),
        };
        if (action === 'complete') {
          driverUpdate.pendingReceiptBookingId = bookingId;
          driverUpdate.completedTrips = FieldValue.increment(1);
          driverUpdate.totalEarnings = FieldValue.increment(
            Number(data.amountDue ?? data.estimatedFare ?? 0),
          );
        }
        transaction.update(driverRef, driverUpdate);
      } else if (driverRef && driver?.exists && action === 'complete') {
        transaction.update(driverRef, {
          pendingReceiptBookingId: bookingId,
          completedTrips: FieldValue.increment(1),
          totalEarnings: FieldValue.increment(
            Number(data.amountDue ?? data.estimatedFare ?? 0),
          ),
          updatedAt: timestamp(),
        });
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
          amountDue: Number(data.amountDue ?? data.estimatedFare ?? 0),
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
          ? Number(data.amountDue ?? data.estimatedFare ?? 0)
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
  { region: 'asia-southeast1' },
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
      if (locationData && typeof locationData === 'object') {
        driverLocation = {
          latitude: Number(locationData.latitude),
          longitude: Number(locationData.longitude),
          accuracy: Number(locationData.accuracy),
          bearing: Number(locationData.bearing || 0),
          speed: Number(locationData.speed || 0),
          timestamp: Number(locationData.timestamp || locationData.updatedAt),
          online: locationData.online === true,
        };
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
          return { idempotent: true };
        }
        throw new HttpsError(
          'already-exists',
          'This incident ID is already used.',
        );
      }
      transaction.create(incidentRef, {
        schemaVersion: 2,
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
        status: 'open',
        emergencyDispatch: 'development_placeholder',
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
      return { idempotent: false };
    });
    return {
      incidentId,
      idempotent: result.idempotent,
      emergencyDispatch: 'development_placeholder',
    };
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

// The Firebase-authenticated caller receives a short-lived LiveKit token only
// when they are the passenger or assigned driver for an active booking.
exports.createBookingCallToken = onCall(
  {
    region: 'asia-southeast1',
    secrets: [liveKitApiKey, liveKitApiSecret],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before starting a call.');
    }
    const { AccessToken } = require('livekit-server-sdk');
    const bookingId = request.data?.bookingId;
    if (typeof bookingId !== 'string' || bookingId.length === 0) {
      throw new HttpsError('invalid-argument', 'A booking ID is required.');
    }
    const bookingSnapshot = await db.collection('bookings').doc(bookingId).get();
    if (!bookingSnapshot.exists) {
      throw new HttpsError('not-found', 'Booking not found.');
    }
    const booking = bookingSnapshot.data();
    const activeStatuses = ['driverAssigned', 'driverArriving'];
    if (!activeStatuses.includes(booking.status)) {
      throw new HttpsError('failed-precondition', 'Voice calls are only available during an active ride.');
    }
    if (![booking.passengerId, booking.driverId].includes(request.auth.uid)) {
      throw new HttpsError('permission-denied', 'You are not part of this booking.');
    }
    const url = liveKitUrl.value();
    if (!url) {
      throw new HttpsError('failed-precondition', 'Voice calling is not configured.');
    }
    const roomName = `booking_${bookingId}`;
    const token = new AccessToken(liveKitApiKey.value(), liveKitApiSecret.value(), {
      identity: request.auth.uid,
      ttl: '2m',
    });
    token.addGrant({ roomJoin: true, room: roomName, canPublish: true, canSubscribe: true });
    const recipientId = booking.passengerId === request.auth.uid
      ? booking.driverId
      : booking.passengerId;
    const accepting = request.data?.accepting === true;
    const callRef = db.collection('bookingCalls').doc(bookingId);
    if (accepting) {
      await callRef.set({
        status: 'accepted',
        acceptedBy: request.auth.uid,
        acceptedAt: timestamp(),
        updatedAt: timestamp(),
      }, { merge: true });
    } else {
      await callRef.set({
        bookingId,
        callerId: request.auth.uid,
        recipientId,
        status: 'ringing',
        createdAt: timestamp(),
        updatedAt: timestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + 30000),
      });
    }
    if (recipientId && !accepting) {
      await sendToUser(
        recipientId,
        'Incoming ride call',
        'Your ride participant is calling you.',
        { bookingId, type: 'incoming_call' },
      );
    }
    return { serverUrl: url, token: await token.toJwt(), roomName };
  },
);

exports.respondBookingCall = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before responding.');
    }
    const bookingId = requiredString(request.data?.bookingId, 'Booking ID');
    const response = requiredString(request.data?.response, 'Response');
    if (!['declined', 'expired'].includes(response)) {
      throw new HttpsError('invalid-argument', 'Unsupported call response.');
    }
    const [booking, call] = await Promise.all([
      db.collection('bookings').doc(bookingId).get(),
      db.collection('bookingCalls').doc(bookingId).get(),
    ]);
    if (!booking.exists ||
        ![booking.data().passengerId, booking.data().driverId]
          .includes(request.auth.uid)) {
      throw new HttpsError('permission-denied', 'You are not part of this call.');
    }
    if (call.exists && ['declined', 'ended'].includes(call.data().status)) {
      return { idempotent: true, status: call.data().status };
    }
    await db.collection('bookingCalls').doc(bookingId).set({
      status: response,
      respondedBy: request.auth.uid,
      respondedAt: timestamp(),
      updatedAt: timestamp(),
    }, { merge: true });
    return { idempotent: false, status: response };
  },
);

// Either participant can deliberately end an active booking call. Deleting the
// room disconnects both sides, and is also invoked by the two-minute UI timer.
exports.endBookingCall = onCall(
  {
    region: 'asia-southeast1',
    secrets: [liveKitApiKey, liveKitApiSecret],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before ending a call.');
    }
    const { RoomServiceClient } = require('livekit-server-sdk');
    const bookingId = request.data?.bookingId;
    if (typeof bookingId !== 'string' || bookingId.length === 0) {
      throw new HttpsError('invalid-argument', 'A booking ID is required.');
    }
    const bookingSnapshot = await db.collection('bookings').doc(bookingId).get();
    const booking = bookingSnapshot.data();
    if (!bookingSnapshot.exists || !booking ||
        ![booking.passengerId, booking.driverId].includes(request.auth.uid)) {
      throw new HttpsError('permission-denied', 'You are not part of this booking.');
    }
    const url = liveKitUrl.value();
    if (!url) {
      throw new HttpsError('failed-precondition', 'Voice calling is not configured.');
    }
    const roomName = `booking_${bookingId}`;
    const serviceUrl = url.replace(/^wss:/, 'https:').replace(/^ws:/, 'http:');
    const rooms = new RoomServiceClient(
      serviceUrl,
      liveKitApiKey.value(),
      liveKitApiSecret.value(),
    );
    try {
      await rooms.deleteRoom(roomName);
    } catch (error) {
      // A room may already be empty/deleted; ending a call remains idempotent.
      logger.info('LiveKit room already absent while ending call', {
        bookingId,
        error: String(error),
      });
    }
    await db.collection('bookingCalls').doc(bookingId).set({
      status: 'ended',
      endedBy: request.auth.uid,
      endedAt: timestamp(),
      updatedAt: timestamp(),
    }, { merge: true });
    return { ended: true };
  },
);

// Drivers receive only their own offer documents. Candidate proximity comes
// from fresh RTDB coordinates, never from Google Places.
exports.dispatchBookingOffers = onDocumentCreated('bookings/{bookingId}', async (event) => {
  await dispatchNextOfferBatch(event.params.bookingId);
});

// Pending bookings receive the next nearest unoffered batch after the prior
// 30-second offer window. The booking transaction remains authoritative, so
// concurrent schedule invocations cannot cause two drivers to claim a ride.
exports.redispatchPendingBookings = onSchedule(
  { region: 'asia-southeast1', schedule: 'every 1 minutes' },
  async () => {
    const pending = await db.collection('bookings')
      .where('status', '==', BOOKING_STATUS.pending)
      .limit(50)
      .get();
    await Promise.all(pending.docs.map((booking) =>
      dispatchNextOfferBatch(booking.id)));
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
