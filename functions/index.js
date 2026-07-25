const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');
const { defineSecret, defineString } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { AccessToken, RoomServiceClient } = require('livekit-server-sdk');

admin.initializeApp();
const db = admin.firestore();
const liveKitApiKey = defineSecret('LIVEKIT_API_KEY');
const liveKitApiSecret = defineSecret('LIVEKIT_API_SECRET');
const liveKitUrl = defineString('LIVEKIT_URL');
const adminBootstrapCode = defineSecret('ADMIN_BOOTSTRAP_CODE');
const psgcRegions = require('./data/regionJson/regions.json');
const psgcCities = require('./data/regionJson/cities-municipalities.json');
const psgcBarangays = require('./data/regionJson/barangays.json');
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

function timestamp() {
  return admin.firestore.FieldValue.serverTimestamp();
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

function slugify(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60);
}

function selectedPsgcLocation(data) {
  const regionCode = requiredString(data.regionCode, 'Region');
  const cityCode = requiredString(data.cityCode, 'City or municipality');
  const barangayCode = requiredString(data.barangayCode, 'Barangay');
  const region = psgcRegions.find((item) => item.code === regionCode);
  const city = psgcCities.find((item) => item.code === cityCode && item.regionCode === regionCode);
  const barangay = psgcBarangays.find((item) => item.code === barangayCode &&
    item.regionCode === regionCode &&
    (item.cityCode === cityCode || item.municipalityCode === cityCode));
  if (!region || !city || !barangay) {
    throw new HttpsError('invalid-argument', 'Select a valid region, city or municipality, and barangay from the official list.');
  }
  return { region, city, barangay };
}

async function assertTodaScope(profile, todaId) {
  if (profile.role === 'developer_admin') return;
  if (profile.todaId !== todaId) {
    throw new HttpsError('permission-denied', 'This record is outside of your TODA.');
  }
}

async function sendToUser(userId, title, body, data) {
  const devices = await db.collection('users').doc(userId).collection('devices').get();
  const deviceTokens = devices.docs
    .map((doc) => ({ doc, token: doc.data().token }))
    .filter((entry) => typeof entry.token === 'string' && entry.token.length > 0);
  const tokens = deviceTokens.map((entry) => entry.token);
  if (tokens.length === 0) return;
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
    android: { priority: 'high' },
  });
  await Promise.all(response.responses.map((result, index) => {
    if (!result.success && ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(result.error?.code)) {
      return deviceTokens[index].doc.ref.delete();
    }
    return null;
  }));
}

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
  const registration = data.registration || {};
  const normalizedRegistration = {
    secCertificateNumber: requiredString(registration.secCertificateNumber, 'SEC certificate number'),
    spResolutionNumber: requiredString(registration.spResolutionNumber, 'SP resolution number'),
    mayorsPermitNumber: requiredString(registration.mayorsPermitNumber, "Mayor's permit number"),
    barangayClearanceNumber: requiredString(registration.barangayClearanceNumber, 'Barangay clearance number'),
    presidentName: requiredString(registration.presidentName, "President's name"),
    presidentLicenseNumber: requiredString(registration.presidentLicenseNumber, "President's driver license"),
    presidentTin: requiredString(registration.presidentTin, "President's TIN"),
  };
  const id = `${slugify(name)}-${Date.now().toString(36)}`;
  await db.collection('todas').doc(id).set({
    id, name, barangayCode, regionCode: '06', provinceCode: 'NEG', cityCode: 'BACOLOD',
    isActive: true, adminUid: null, registration: normalizedRegistration,
    createdAt: timestamp(), updatedAt: timestamp(),
  });
  return { todaId: id };
});

// TODA administrators create their own pending application. No privileged
// claim is issued until a developer administrator explicitly approves it.
exports.registerToda = onCall({ region: 'asia-southeast1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in before registering a TODA.');
  const data = request.data || {};
  const name = requiredString(data.name, 'TODA name');
  const { region, city, barangay } = selectedPsgcLocation(data);
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
  const uid = toda.data().adminUid;
  if (status === 'approved') {
    await admin.auth().setCustomUserClaims(uid, { adminRole: 'toda_admin', todaId });
    const batch = db.batch();
    batch.update(todaRef, { status: 'approved', isActive: true, approvedBy: developer.uid, approvedAt: timestamp(), updatedAt: timestamp() });
    batch.set(db.collection('users').doc(uid), { role: 'toda_admin', todaId, isActive: true, todaApplicationStatus: 'approved', updatedAt: timestamp() }, { merge: true });
    await batch.commit();
  } else {
    await admin.auth().setCustomUserClaims(uid, null);
    const batch = db.batch();
    batch.update(todaRef, { status: 'declined', isActive: false, reviewedBy: developer.uid, reviewedAt: timestamp(), updatedAt: timestamp() });
    batch.set(db.collection('users').doc(uid), { role: 'toda_admin_pending', todaId, todaApplicationStatus: 'declined', updatedAt: timestamp() }, { merge: true });
    await batch.commit();
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
  await admin.auth().setCustomUserClaims(uid, { adminRole: 'toda_admin', todaId });
  const batch = db.batch();
  batch.set(db.collection('users').doc(uid), {
    uid, email: user.email || '', role: 'toda_admin', todaId, isActive: true,
    updatedAt: timestamp(),
  }, { merge: true });
  batch.update(toda.ref, { adminUid: uid, updatedAt: timestamp() });
  const driver = db.collection('drivers').doc(uid);
  if ((await driver.get()).exists) {
    batch.update(driver, { driverStatus: 'suspended', isOnline: false, isAvailable: false, updatedAt: timestamp() });
  }
  await batch.commit();
  logger.info('TODA administrator assigned', { uid, todaId, by: developer.uid });
  return { assigned: true };
});

exports.adminSetTodaStatus = onCall({ region: 'asia-southeast1' }, async (request) => {
  await requireDeveloperAdmin(request);
  const todaId = requiredString(request.data?.todaId, 'TODA ID');
  if (typeof request.data?.isActive !== 'boolean') {
    throw new HttpsError('invalid-argument', 'TODA status is required.');
  }
  const ref = db.collection('todas').doc(todaId);
  if (!(await ref.get()).exists) throw new HttpsError('not-found', 'TODA not found.');
  await ref.update({ isActive: request.data.isActive, updatedAt: timestamp() });
  if (!request.data.isActive) {
    const drivers = await db.collection('drivers').where('todaId', '==', todaId).get();
    const writer = db.bulkWriter();
    drivers.docs.forEach((driver) => writer.update(driver.ref, { driverStatus: 'suspended', isOnline: false, isAvailable: false, updatedAt: timestamp() }));
    await writer.close();
  }
  return { updated: true };
});

exports.adminAttachTodaDocuments = onCall({ region: 'asia-southeast1' }, async (request) => {
  await requireDeveloperAdmin(request);
  const todaId = requiredString(request.data?.todaId, 'TODA ID');
  const documents = request.data?.documents;
  if (!documents || typeof documents !== 'object' || Array.isArray(documents)) {
    throw new HttpsError('invalid-argument', 'TODA documents are required.');
  }
  const expectedPrefix = `toda_documents/${todaId}/`;
  for (const value of Object.values(documents)) {
    if (typeof value !== 'string' || !value.includes(encodeURIComponent(expectedPrefix))) {
      throw new HttpsError('invalid-argument', 'Invalid TODA document location.');
    }
  }
  await db.collection('todas').doc(todaId).update({ documents, updatedAt: timestamp() });
  return { updated: true };
});

exports.adminUpdateFare = onCall({ region: 'asia-southeast1' }, async (request) => {
  const developer = await requireDeveloperAdmin(request);
  const fare = request.data?.fare || {};
  const normalized = {
    baseFare: validCurrency(fare.baseFare, 'Base fare', 0, 9999),
    includedMeters: validPositiveInteger(fare.includedMeters, 'Included meters', 1, 9999),
    distanceStepMeters: validPositiveInteger(fare.distanceStepMeters, 'Distance step meters', 1, 9999),
    distanceStepPrice: validCurrency(fare.distanceStepPrice, 'Distance step price', 0, 999),
    additionalPassengerFee: validCurrency(fare.additionalPassengerFee, 'Additional passenger fee', 0, 9999),
    baggageFee: validCurrency(fare.baggageFee, 'Large baggage fee', 0, 9999),
    outsideTodaSurcharge: validCurrency(fare.outsideTodaSurcharge, 'Outside TODA surcharge', 0, 9999),
    currency: 'PHP', updatedAt: timestamp(), updatedBy: developer.uid,
  };
  await db.collection('settings').doc('fare_config').set(normalized, { merge: true });
  return { updated: true };
});

exports.adminSetDriverStatus = onCall({ region: 'asia-southeast1' }, async (request) => {
  const profile = await requireAdmin(request);
  const uid = requiredString(request.data?.uid, 'Driver ID');
  const status = request.data?.status;
  if (!['approved', 'rejected', 'suspended'].includes(status)) {
    throw new HttpsError('invalid-argument', 'Unsupported driver status.');
  }
  const driverRef = db.collection('drivers').doc(uid);
  const driver = await driverRef.get();
  if (!driver.exists) throw new HttpsError('not-found', 'Driver not found.');
  await assertTodaScope(profile, driver.data().todaId);
  const update = { driverStatus: status, updatedAt: timestamp() };
  if (status === 'approved') Object.assign(update, { approvedAt: timestamp(), approvedBy: profile.uid });
  if (status !== 'approved') Object.assign(update, { isOnline: false, isAvailable: false });
  await driverRef.update(update);
  return { updated: true };
});

exports.adminSetUserStatus = onCall({ region: 'asia-southeast1' }, async (request) => {
  await requireDeveloperAdmin(request);
  const uid = requiredString(request.data?.uid, 'User ID');
  if (uid === request.auth.uid) throw new HttpsError('failed-precondition', 'You cannot suspend your own account.');
  if (typeof request.data?.isActive !== 'boolean') throw new HttpsError('invalid-argument', 'Account status is required.');
  await db.collection('users').doc(uid).set({ isActive: request.data.isActive, updatedAt: timestamp() }, { merge: true });
  if (!request.data.isActive) {
    const driverRef = db.collection('drivers').doc(uid);
    if ((await driverRef.get()).exists) {
      await driverRef.update({ driverStatus: 'suspended', isOnline: false, isAvailable: false, updatedAt: timestamp() });
    }
  }
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
  return { updated: true };
});

exports.adminSubmitZoneRequest = onCall({ region: 'asia-southeast1' }, async (request) => {
  const profile = await requireAdmin(request);
  const todaId = requiredString(request.data?.todaId, 'TODA ID');
  await assertTodaScope(profile, todaId);
  const polygon = request.data?.polygon;
  if (!Array.isArray(polygon) || polygon.length < 3 || polygon.length > 200 || !polygon.every((point) => Array.isArray(point) && point.length === 2 && point.every(Number.isFinite))) {
    throw new HttpsError('invalid-argument', 'A polygon with 3 to 200 valid points is required.');
  }
  const zone = await db.collection('zoneRequests').add({ todaId, polygon, status: 'pending', notes: String(request.data?.notes || '').slice(0, 1000), requestedBy: profile.uid, createdAt: timestamp(), updatedAt: timestamp() });
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
    batch.set(db.collection('geofences').doc(zone.todaId), { todaId: zone.todaId, polygon: zone.polygon, sourceRequestId: id, updatedBy: developer.uid, updatedAt: timestamp() }, { merge: true });
  }
  await batch.commit();
  return { updated: true };
});

exports.adminUpdateZoneRequest = onCall({ region: 'asia-southeast1' }, async (request) => {
  await requireDeveloperAdmin(request);
  const id = requiredString(request.data?.zoneRequestId, 'Zone request ID');
  const polygon = request.data?.polygon;
  if (!Array.isArray(polygon) || polygon.length < 3 || polygon.length > 200 || !polygon.every((point) => Array.isArray(point) && point.length === 2 && point.every(Number.isFinite))) {
    throw new HttpsError('invalid-argument', 'A polygon with 3 to 200 valid points is required.');
  }
  const ref = db.collection('zoneRequests').doc(id);
  if (!(await ref.get()).exists) throw new HttpsError('not-found', 'Zone request not found.');
  await ref.update({ polygon, notes: String(request.data?.notes || '').slice(0, 1000), updatedAt: timestamp() });
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
  const minimumPoints = geometryType === 'corridor' ? 2 : 3;
  if (!Array.isArray(coordinates) || coordinates.length < minimumPoints || coordinates.length > 200 ||
      !coordinates.every((point) => Array.isArray(point) && point.length === 2 && point.every(Number.isFinite))) {
    throw new HttpsError('invalid-argument', geometryType === 'corridor' ? 'A corridor needs 2 to 200 centreline points.' : 'A polygon needs 3 to 200 points.');
  }
  const bufferMeters = geometryType === 'corridor'
    ? validPositiveInteger(request.data?.bufferMeters, 'Corridor buffer', 5, 200)
    : 0;
  const ref = await db.collection('routeRestrictions').add({
    name, type, geometryType, polygon: coordinates, coordinates, bufferMeters, isActive: true,
    notes: String(request.data?.notes || '').slice(0, 1000),
    createdBy: developer.uid, createdAt: timestamp(), updatedAt: timestamp(),
  });
  return { restrictionId: ref.id };
});

exports.adminSetRouteRestrictionStatus = onCall({ region: 'asia-southeast1' }, async (request) => {
  await requireDeveloperAdmin(request);
  const restrictionId = requiredString(request.data?.restrictionId, 'Restriction ID');
  if (typeof request.data?.isActive !== 'boolean') throw new HttpsError('invalid-argument', 'Restriction status is required.');
  const ref = db.collection('routeRestrictions').doc(restrictionId);
  if (!(await ref.get()).exists) throw new HttpsError('not-found', 'Route restriction not found.');
  await ref.update({ isActive: request.data.isActive, updatedAt: timestamp() });
  return { updated: true };
});

// Adds TODA scope to reports after creation. This supports efficient, scoped
// TODA-admin report lists without exposing unrelated passenger reports.
exports.enrichReportToda = onDocumentCreated('reports/{reportId}', async (event) => {
  const report = event.data.data();
  const booking = await db.collection('bookings').doc(report.bookingId).get();
  const driverId = booking.exists ? booking.data().driverId : null;
  if (!driverId) return;
  const driver = await db.collection('drivers').doc(driverId).get();
  if (driver.exists) await event.data.ref.set({ todaId: driver.data().todaId }, { merge: true });
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
    const bookingId = request.data?.bookingId;
    if (typeof bookingId !== 'string' || bookingId.length === 0) {
      throw new HttpsError('invalid-argument', 'A booking ID is required.');
    }
    const bookingSnapshot = await db.collection('bookings').doc(bookingId).get();
    if (!bookingSnapshot.exists) {
      throw new HttpsError('not-found', 'Booking not found.');
    }
    const booking = bookingSnapshot.data();
    const activeStatuses = ['driverAssigned', 'driverArriving', 'passengerOnBoard'];
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
    return { serverUrl: url, token: await token.toJwt(), roomName };
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
    return { ended: true };
  },
);

// Drivers receive only their own offer documents. Geo-ranking from RTDB is a
// later enhancement; this bounded dispatcher is intentionally server-owned.
exports.dispatchBookingOffers = onDocumentCreated('bookings/{bookingId}', async (event) => {
  const booking = event.data.data();
  if (!booking || booking.status !== 'pending') return;

  const drivers = await db.collection('drivers')
    .where('driverStatus', '==', 'approved')
    .where('isOnline', '==', true)
    .where('isAvailable', '==', true)
    .limit(10)
    .get();
  const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 30000);
  const batch = db.batch();
  drivers.docs.forEach((driver) => {
    batch.set(db.doc(`drivers/${driver.id}/bookingOffers/${event.params.bookingId}`), {
      bookingId: event.params.bookingId,
      status: 'offered',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
    });
  });
  await batch.commit();
  await Promise.all(drivers.docs.map((driver) => sendToUser(
    driver.id,
    'New VolTrike booking',
    'A nearby passenger is requesting a ride.',
    { bookingId: event.params.bookingId, target: 'driver', type: 'booking_offer' },
  )));
  logger.info('Booking offers dispatched', { bookingId: event.params.bookingId, count: drivers.size });
});

exports.notifyBookingLifecycle = onDocumentUpdated('bookings/{bookingId}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status) return;
  const bookingId = event.params.bookingId;
  const passenger = after.passengerId;
  const driver = after.driverId;
  const passengerMessages = {
    driverAssigned: ['Driver assigned', 'Your driver accepted the booking.'],
    driverArriving: ['Driver arriving', 'Your driver has arrived at pickup.'],
    passengerOnBoard: ['Trip started', 'You are on the way to your destination.'],
    completed: ['Trip completed', 'Your receipt is ready.'],
    cancelled: ['Booking cancelled', 'Your booking was cancelled.'],
  };
  const driverMessages = {
    passengerOnBoard: ['Trip started', 'Navigate to the destination.'],
    cancelled: ['Trip cancelled', 'The passenger cancelled the trip.'],
  };
  const passengerMessage = passengerMessages[after.status];
  const driverMessage = driverMessages[after.status];
  const tasks = [];
  if (passenger && passengerMessage) tasks.push(sendToUser(passenger, passengerMessage[0], passengerMessage[1], { bookingId, target: 'passenger', type: after.status }));
  if (driver && driverMessage) tasks.push(sendToUser(driver, driverMessage[0], driverMessage[1], { bookingId, target: 'driver', type: after.status }));
  await Promise.all(tasks);
});
