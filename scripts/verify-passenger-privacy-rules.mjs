import assert from 'node:assert/strict';

// Run only against the disposable local Firestore emulator started with the
// repository's firestore.rules. No production credentials or data are used.
const host = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8181';
assert.match(host, /^(127\.0\.0\.1|localhost):\d+$/);
const project = 'demo-voltrike-policy';
const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
const prefix = `rules-${Date.now()}`;
const passenger = `${prefix}-passenger`;
const system = `${prefix}-system`;
const toda = `${prefix}-toda`;
const driver = `${prefix}-driver`;

function token(uid, claims = {}) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({
    iss: `https://securetoken.google.com/${project}`, aud: project,
    sub: uid, user_id: uid, iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 3600,
    firebase: { sign_in_provider: 'custom' }, ...claims,
  })}.`;
}

function fields(record) {
  return Object.fromEntries(Object.entries(record).map(([key, value]) => [key,
    typeof value === 'boolean' ? { booleanValue: value } : { stringValue: value },
  ]));
}

async function seed(path, record) {
  const response = await fetch(`${base}/${path}`, {
    method: 'PATCH', headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: fields(record) }),
  });
  assert.equal(response.status, 200, await response.text());
}

for (const [uid, role, extra] of [
  [passenger, 'passenger', {}], [system, 'developer_admin', {}],
  [toda, 'toda_admin', { todaId: prefix }], [driver, 'driver', { todaId: prefix }],
]) await seed(`users/${uid}`, { role, isActive: true, ...extra });

await seed(`passengers/${passenger}`, { privateName: 'Passenger identity' });
await seed(`passengerBookingPolicies/${passenger}`, { passengerId: passenger });
await seed(`passengerCancellationEvents/${prefix}`, { passengerId: passenger, bookingId: prefix });
await seed(`reports/${prefix}`, { reporterId: passenger, todaId: prefix, details: 'Private report' });
await seed(`safetyIncidents/${prefix}`, { passengerId: passenger, driverId: driver, todaId: prefix });
await seed(`bookings/${prefix}`, { passengerId: passenger, driverId: driver, todaId: prefix });
await seed(`settlements/${prefix}`, { passengerId: passenger, driverId: driver, todaId: prefix });
await seed(`drivers/${driver}/bookingOffers/${prefix}`, { todaId: prefix, passengerName: 'Private Passenger' });

const identities = {
  passenger: token(passenger), driver: token(driver),
  system: token(system, { adminRole: 'developer_admin' }),
  toda: token(toda, { adminRole: 'toda_admin', todaId: prefix }),
};

let checks = 0;
async function expectRead(path, identity, allowed) {
  const response = await fetch(`${base}/${path}`, { headers: { Authorization: `Bearer ${identities[identity]}` } });
  assert.equal(response.status, allowed ? 200 : 403, `${identity} reading ${path}: ${await response.text()}`);
  checks += 1;
}

for (const identity of ['system', 'toda']) {
  for (const path of [
    `users/${passenger}`, `passengers/${passenger}`, `passengerBookingPolicies/${passenger}`,
    `passengerCancellationEvents/${prefix}`, `reports/${prefix}`, `safetyIncidents/${prefix}`,
    `settlements/${prefix}`, `drivers/${driver}/bookingOffers/${prefix}`,
  ]) await expectRead(path, identity, false);
}
for (const path of [
  `users/${passenger}`, `passengers/${passenger}`, `passengerBookingPolicies/${passenger}`,
  `passengerCancellationEvents/${prefix}`, `reports/${prefix}`, `safetyIncidents/${prefix}`, `settlements/${prefix}`,
]) await expectRead(path, 'passenger', true);
await expectRead(`users/${system}`, 'system', true);
await expectRead(`users/${toda}`, 'toda', true);
await expectRead(`users/${driver}`, 'toda', true);
await expectRead(`safetyIncidents/${prefix}`, 'driver', true);
await expectRead(`settlements/${prefix}`, 'driver', true);
await expectRead(`drivers/${driver}/bookingOffers/${prefix}`, 'driver', true);

for (const path of [`passengerBookingPolicies/${passenger}`, `passengerCancellationEvents/${prefix}`]) {
  const response = await fetch(`${base}/${path}`, {
    method: 'PATCH', headers: { Authorization: `Bearer ${identities.passenger}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: fields({ passengerId: passenger, overwritten: true }) }),
  });
  assert.equal(response.status, 403, `passenger overwrote policy: ${await response.text()}`);
  checks += 1;
}
console.log(`Passed ${checks} passenger privacy and policy access-rule checks.`);
