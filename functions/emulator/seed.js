'use strict';

const {
  admin,
  auth,
  db,
  projectId,
  realtime,
} = require('./emulator-admin');
const {
  FieldValue,
  Timestamp,
} = require('firebase-admin/firestore');

const password = 'VolTrike123!';
const todaId = 'test-toda-bacolod';
const secondaryTodaId = 'test-toda-east';
const accounts = Object.freeze({
  passenger: {
    uid: 'passenger-test-001',
    email: 'passenger@voltrike.test',
    firstName: 'Paolo',
    lastName: 'Passenger',
    role: 'passenger',
  },
  driver: {
    uid: 'driver-test-001',
    email: 'driver@voltrike.test',
    firstName: 'Dario',
    lastName: 'Driver',
    role: 'driver',
    todaId,
  },
  secondDriver: {
    uid: 'driver-test-002',
    email: 'driver2@voltrike.test',
    firstName: 'Diego',
    lastName: 'Driver',
    role: 'driver',
    todaId: secondaryTodaId,
  },
  developer: {
    uid: 'developer-admin-test-001',
    email: 'developer@voltrike.test',
    firstName: 'Devon',
    lastName: 'Administrator',
    role: 'developer_admin',
  },
  todaAdmin: {
    uid: 'toda-admin-test-001',
    email: 'toda.admin@voltrike.test',
    firstName: 'Toni',
    lastName: 'TODA Administrator',
    role: 'toda_admin',
    todaId,
  },
});

async function clearLocalFirestore() {
  const response = await fetch(
    `http://127.0.0.1:8080/emulator/v1/projects/${projectId}` +
      '/databases/(default)/documents',
    { method: 'DELETE' },
  );
  if (!response.ok) {
    throw new Error(
      `Unable to clear local Firestore (${response.status}): ` +
        await response.text(),
    );
  }
}

async function upsertAuthUser(account) {
  try {
    await auth.getUser(account.uid);
    await auth.updateUser(account.uid, {
      email: account.email,
      emailVerified: true,
      password,
      displayName: `${account.firstName} ${account.lastName}`,
      disabled: false,
    });
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    await auth.createUser({
      uid: account.uid,
      email: account.email,
      emailVerified: true,
      password,
      displayName: `${account.firstName} ${account.lastName}`,
    });
  }
  const claims = account.role === 'developer_admin'
    ? { adminRole: 'developer_admin' }
    : account.role === 'toda_admin'
      ? { adminRole: 'toda_admin', todaId }
      : {};
  await auth.setCustomUserClaims(account.uid, claims);
}

function userProfile(account) {
  return {
    uid: account.uid,
    email: account.email,
    firstName: account.firstName,
    middleName: '',
    lastName: account.lastName,
    phoneNumber: '+639170000000',
    role: account.role,
    todaId: account.todaId || null,
    profileImage: '',
    dateOfBirth: Timestamp.fromDate(
      new Date('1990-01-15T00:00:00.000Z'),
    ),
    emailVerified: true,
    isActive: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function seedDriver(account, vehicleNumber, plateNumber) {
  const vehicleId = `vehicle-${account.uid}`;
  const batch = db.batch();
  batch.set(db.collection('drivers').doc(account.uid), {
    uid: account.uid,
    todaId: account.todaId,
    vehicleId,
    licenseNumber: `N01-TEST-${account.uid.slice(-3)}`,
    licenseExpiry: Timestamp.fromDate(
      new Date('2035-12-31T00:00:00.000Z'),
    ),
    profilePhotoUrl: '',
    driverStatus: 'approved',
    isOnline: false,
    isAvailable: false,
    currentBookingId: null,
    rating: 4.9,
    ratingCount: 12,
    completedTrips: 24,
    totalEarnings: 3200,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  batch.set(db.collection('vehicles').doc(vehicleId), {
    id: vehicleId,
    driverId: account.uid,
    vehicleNumber,
    plateNumber,
    make: 'VolTrike',
    model: 'Electric Tricycle',
    vehicleType: 'electric_tuktuk',
    capacity: 4,
    color: 'Teal',
    isVerified: true,
    verifiedBy: accounts.developer.uid,
    verifiedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await batch.commit();
}

async function main() {
  await clearLocalFirestore();
  await realtime.ref().remove();

  for (const account of Object.values(accounts)) {
    await upsertAuthUser(account);
  }

  const batch = db.batch();
  for (const account of Object.values(accounts)) {
    batch.set(
      db.collection('users').doc(account.uid),
      userProfile(account),
      { merge: true },
    );
  }
  batch.set(db.collection('passengers').doc(accounts.passenger.uid), {
    uid: accounts.passenger.uid,
    totalTrips: 0,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  batch.set(db.collection('todas').doc(todaId), {
    id: todaId,
    name: 'VolTrike Test TODA',
    barangayCode: '064501032',
    cityCode: 'BACOLOD',
    provinceCode: 'NEG',
    regionCode: '06',
    adminUid: accounts.todaAdmin.uid,
    status: 'approved',
    isActive: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  batch.set(db.collection('todas').doc(secondaryTodaId), {
    id: secondaryTodaId,
    name: 'VolTrike East Test TODA',
    barangayCode: '064501033',
    cityCode: 'BACOLOD',
    provinceCode: 'NEG',
    regionCode: '06',
    adminUid: null,
    status: 'approved',
    isActive: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  batch.set(db.collection('settings').doc('fare_config'), {
    baseFare: 20,
    includedMeters: 1000,
    distanceStepMeters: 500,
    distanceStepPrice: 5,
    additionalPassengerFee: 40,
    baggageFee: 20,
    outsideTodaSurcharge: 20,
    currency: 'PHP',
    version: 1,
    updatedBy: accounts.developer.uid,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await batch.commit();

  await Promise.all([
    seedDriver(accounts.driver, 'VT-001', 'TEST-001'),
    seedDriver(accounts.secondDriver, 'VT-002', 'TEST-002'),
    realtime.ref('driver_locations').remove(),
    realtime.ref('driver_presence').remove(),
    realtime.ref('driver_tracking_access').remove(),
  ]);

  console.log(`Seeded isolated Firebase project ${projectId}.`);
  console.log('Local accounts use password VolTrike123!:');
  for (const [name, account] of Object.entries(accounts)) {
    console.log(`- ${name}: ${account.email} (${account.uid})`);
  }
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);
