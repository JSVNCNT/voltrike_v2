import { FormEvent, lazy, Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import { createUserWithEmailAndPassword, onAuthStateChanged, signInWithEmailAndPassword, signOut, type User } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from './firebase';
import { adminApi } from './admin-api';
import { loadPhilippineLocations, type Barangay, type City, type Region } from './data/locations';
import { bacolodBarangays } from './data/bacolodBarangays';
import type { AdminSession, Driver, FareConfig, Point, Report, RouteRestriction, Toda, TodaRegistration, ZoneRequest } from './types';
import './registration.css';
import './driver-review.css';

// Mapbox is substantial; only load it when an administrator opens Coverage.
const PolygonEditor = lazy(() => import('./components/PolygonEditor').then((module) => ({ default: module.PolygonEditor })));

type Page = 'overview' | 'todas' | 'fares' | 'drivers' | 'reports' | 'coverage' | 'route_rules';
const initialFare: FareConfig = { baseFare: 20, includedMeters: 1000, distanceStepMeters: 500, distanceStepPrice: 5, additionalPassengerFee: 40, baggageFee: 20, outsideTodaSurcharge: 20 };
const registrationFields: Array<[keyof TodaRegistration, string]> = [
  ['secCertificateNumber', 'SEC registration certificate number'], ['spResolutionNumber', 'SP resolution number'], ['mayorsPermitNumber', "Bacolod Mayor's permit / BPLO license number"], ['barangayClearanceNumber', 'Barangay clearance and endorsement number'], ['presidentName', "TODA President's full name"], ['presidentLicenseNumber', "President's professional driver license number"], ['presidentTin', "President's TIN"],
];

function peso(value: number) { return new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' }).format(value || 0); }
function label(text: string) { return text.replace(/([A-Z])/g, ' $1').replace(/^./, (value) => value.toUpperCase()); }

export default function App() {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<AdminSession | null>(null);
  const [page, setPage] = useState<Page>('overview');
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');

  const loadSession = useCallback(async (signedIn: User | null) => {
    setUser(signedIn);
    if (!signedIn) { setSession(null); setLoading(false); return; }
    const snapshot = await getDoc(doc(db, 'users', signedIn.uid));
    const data = snapshot.data();
    if (data && (data.role === 'developer_admin' || data.role === 'toda_admin') && data.isActive !== false) {
      setSession({ uid: signedIn.uid, email: signedIn.email, role: data.role, todaId: data.todaId || null, displayName: `${data.firstName || ''} ${data.lastName || ''}`.trim() || signedIn.email || 'Administrator' });
    } else setSession(null);
    setLoading(false);
  }, []);

  useEffect(() => onAuthStateChanged(auth, loadSession), [loadSession]);
  if (loading) return <main className="centered">Loading VolTrike Admin…</main>;
  if (!user) return <Login onMessage={setMessage} message={message} />;
  if (!session) return <AccountGate user={user} reload={() => loadSession(auth.currentUser)} onMessage={setMessage} message={message} />;

  const isDeveloper = session.role === 'developer_admin';
  const visiblePages: Array<[Page, string]> = isDeveloper
    ? [['overview', 'Overview'], ['todas', 'TODAs'], ['fares', 'City fares'], ['drivers', 'Drivers'], ['reports', 'Reports'], ['coverage', 'Coverage areas'], ['route_rules', 'Route restrictions']]
    : [['overview', 'Overview'], ['drivers', 'My drivers'], ['reports', 'TODA reports'], ['coverage', 'Zone request']];
  return <div className="shell">
    <aside className="sidebar"><div className="brand"><img src="/images/logo.png" onError={(event) => { event.currentTarget.style.display = 'none'; }} /><span>VolTrike<br /><b>Admin</b></span></div><div className="role-pill">{isDeveloper ? 'Developer Admin' : 'TODA Admin'}</div>
      <nav>{visiblePages.map(([key, text]) => <button className={page === key ? 'nav-active' : ''} key={key} onClick={() => setPage(key)}>{text}</button>)}</nav>
      <div className="sidebar-footer"><span>{session.displayName}</span><button onClick={() => signOut(auth)}>Sign out</button></div>
    </aside>
    <main className="content"><header><div><p className="eyebrow">Bacolod City TNVS operations</p><h1>{visiblePages.find(([key]) => key === page)?.[1]}</h1></div><div className="status">● Secure Firebase session</div></header>
      {message && <div className="notice">{message}<button onClick={() => setMessage('')}>×</button></div>}
      {page === 'overview' && <Overview session={session} />}
      {page === 'todas' && isDeveloper && <Todas onMessage={setMessage} />}
      {page === 'fares' && isDeveloper && <Fares onMessage={setMessage} />}
      {page === 'drivers' && <DriversPage todaId={isDeveloper ? undefined : session.todaId!} onMessage={setMessage} />}
      {page === 'reports' && <ReportsPage todaId={isDeveloper ? undefined : session.todaId!} onMessage={setMessage} />}
      {page === 'coverage' && <CoveragePage session={session} onMessage={setMessage} />}
      {page === 'route_rules' && isDeveloper && <RouteRestrictionsPage onMessage={setMessage} />}
    </main>
  </div>;
}

function LegacyLogin({ message, onMessage }: { message: string; onMessage: (value: string) => void }) {
  const [email, setEmail] = useState(''); const [password, setPassword] = useState(''); const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); try { await signInWithEmailAndPassword(auth, email.trim(), password); } catch { onMessage('Unable to sign in. Check the email and password.'); } finally { setBusy(false); } }
  return <main className="auth"><section><img src="/logo.png" className="auth-logo" /><p className="eyebrow">VolTrike operations</p><h1>Admin Portal</h1><p>Authorized Bacolod TODA and developer operations only.</p>{message && <div className="notice">{message}</div>}<form onSubmit={submit}><input type="email" placeholder="Email address" value={email} onChange={(e) => setEmail(e.target.value)} required /><input type="password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} required /><button className="primary" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button></form></section></main>;
}

function Login({ message, onMessage }: { message: string; onMessage: (value: string) => void }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [registering, setRegistering] = useState(false);
  async function submit(event: FormEvent) {
    event.preventDefault(); setBusy(true);
    try { await signInWithEmailAndPassword(auth, email.trim(), password); }
    catch { onMessage('Unable to sign in. Check the email and password.'); }
    finally { setBusy(false); }
  }
  if (registering) return <TodaSignUp onBack={() => setRegistering(false)} onMessage={onMessage} />;
  return <main className="auth"><section><img src="/images/logo.png" className="auth-logo" /><p className="eyebrow">VolTrike operations</p><h1>Admin Portal</h1><p>Authorized TODA and developer operations only.</p>{message && <div className="notice">{message}</div>}<form onSubmit={submit}><input type="email" placeholder="Email address" value={email} onChange={(event) => setEmail(event.target.value)} required /><input type="password" placeholder="Password" value={password} onChange={(event) => setPassword(event.target.value)} required /><button className="primary" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button><button type="button" onClick={() => { onMessage(''); setRegistering(true); }}>Register a TODA</button></form></section></main>;
}

function TodaSignUp({ onBack, onMessage }: { onBack: () => void; onMessage: (value: string) => void }) {
  const [regions, setRegions] = useState<Region[]>([]); const [cities, setCities] = useState<City[]>([]); const [barangays, setBarangays] = useState<Barangay[]>([]);
  const [regionCode, setRegionCode] = useState(''); const [cityCode, setCityCode] = useState(''); const [barangayCode, setBarangayCode] = useState('');
  const [name, setName] = useState(''); const [email, setEmail] = useState(''); const [password, setPassword] = useState(''); const [busy, setBusy] = useState(false); const [loadError, setLoadError] = useState('');
  useEffect(() => { loadPhilippineLocations().then(({ regions: nextRegions, cities: nextCities, barangays: nextBarangays }) => { setRegions(nextRegions); setCities(nextCities); setBarangays(nextBarangays); }).catch((error) => setLoadError(error instanceof Error ? error.message : 'Unable to load locations.')); }, []);
  const cityOptions = useMemo(() => cities.filter((city) => city.regionCode === regionCode), [cities, regionCode]);
  const barangayOptions = useMemo(() => barangays.filter((barangay) => barangay.regionCode === regionCode && (barangay.cityCode === cityCode || barangay.municipalityCode === cityCode)), [barangays, cityCode, regionCode]);
  async function submit(event: FormEvent) {
    event.preventDefault(); setBusy(true);
    try {
      await createUserWithEmailAndPassword(auth, email.trim(), password);
      const region = regions.find((item) => item.code === regionCode); const city = cities.find((item) => item.code === cityCode); const barangay = barangays.find((item) => item.code === barangayCode);
      if (!region || !city || !barangay) throw new Error('Select a region, city/municipality, and barangay.');
      await adminApi.registerToda({ name, regionCode, regionName: region.name, cityCode, cityName: city.name, barangayCode, barangayName: barangay.name });
      await signOut(auth); onMessage('TODA application submitted. A developer administrator must approve it before you can sign in.'); onBack();
    } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to submit TODA registration.'); }
    finally { setBusy(false); }
  }
  return <main className="auth"><section className="auth-wide"><p className="eyebrow">TODA onboarding</p><h1>Register a TODA</h1><p>For testing, legal documents are not required. Select locations only from the official PSGC list.</p>{loadError && <div className="notice">{loadError}</div>}<form onSubmit={submit}><input value={name} onChange={(event) => setName(event.target.value)} placeholder="TODA name" required /><input type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="Administrator email" required /><input type="password" minLength={6} value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Password (at least 6 characters)" required /><select value={regionCode} onChange={(event) => { setRegionCode(event.target.value); setCityCode(''); setBarangayCode(''); }} required><option value="">Select region</option>{regions.map((region) => <option key={region.code} value={region.code}>{region.name}</option>)}</select><select value={cityCode} onChange={(event) => { setCityCode(event.target.value); setBarangayCode(''); }} disabled={!regionCode} required><option value="">Select city / municipality</option>{cityOptions.map((city) => <option key={city.code} value={city.code}>{city.name}</option>)}</select><select value={barangayCode} onChange={(event) => setBarangayCode(event.target.value)} disabled={!cityCode} required><option value="">Select barangay</option>{barangayOptions.map((barangay) => <option key={barangay.code} value={barangay.code}>{barangay.name}</option>)}</select><button className="primary" disabled={busy || Boolean(loadError)}>{busy ? 'Submitting…' : 'Submit TODA registration'}</button><button type="button" onClick={onBack}>Back to sign in</button></form></section></main>;
}

function AccountGate({ user, reload, onMessage, message }: { user: User; reload: () => Promise<void>; onMessage: (value: string) => void; message: string }) {
  const [applicationStatus, setApplicationStatus] = useState<string | null | undefined>(undefined);
  useEffect(() => { getDoc(doc(db, 'users', user.uid)).then((snapshot) => { const profile = snapshot.data(); setApplicationStatus(profile?.role === 'toda_admin_pending' ? profile.todaApplicationStatus || 'pending' : null); }); }, [user.uid]);
  if (applicationStatus === undefined) return <main className="centered">Checking administrator access…</main>;
  if (applicationStatus) return <main className="auth"><section><p className="eyebrow">TODA registration</p><h1>{applicationStatus === 'declined' ? 'Application declined' : 'Approval pending'}</h1><p>{applicationStatus === 'declined' ? 'Your TODA application was declined. Contact the developer administrator before submitting another application.' : 'Your TODA registration has been submitted. A developer administrator must approve it before TODA-admin access is enabled.'}</p>{message && <div className="notice">{message}</div>}<button className="primary" onClick={() => signOut(auth)}>Sign out</button></section></main>;
  return <Bootstrap user={user} reload={reload} onMessage={onMessage} message={message} />;
}

function Bootstrap({ user, reload, onMessage, message }: { user: User; reload: () => Promise<void>; onMessage: (value: string) => void; message: string }) {
  const [code, setCode] = useState(''); const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); try { await adminApi.bootstrap(code); await user.getIdToken(true); await reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Bootstrap failed.'); } finally { setBusy(false); } }
  return <main className="auth"><section><p className="eyebrow">First-time setup</p><h1>Create developer access</h1><p>Signed in as {user.email}. Enter the one-time bootstrap code stored in Firebase Secret Manager. This page works only while no developer admin exists.</p>{message && <div className="notice">{message}</div>}<form onSubmit={submit}><input type="password" placeholder="Bootstrap code" value={code} onChange={(e) => setCode(e.target.value)} required /><button className="primary" disabled={busy}>{busy ? 'Creating…' : 'Create developer admin'}</button><button type="button" onClick={() => signOut(auth)}>Use another account</button></form></section></main>;
}

function Overview({ session }: { session: AdminSession }) {
  const [stats, setStats] = useState({ drivers: 0, reports: 0, zones: 0, earnings: 0 });
  useEffect(() => { Promise.all([adminApi.drivers(session.role === 'toda_admin' ? session.todaId! : undefined), adminApi.reports(session.role === 'toda_admin' ? session.todaId! : undefined), adminApi.zones(session.role === 'toda_admin' ? session.todaId! : undefined)]).then(([drivers, reports, zones]) => setStats({ drivers: drivers.length, reports: reports.filter((r) => r.status === 'open').length, zones: zones.filter((z) => z.status === 'pending').length, earnings: drivers.reduce((total, driver) => total + (driver.totalEarnings || 0), 0) })); }, [session]);
  return <><div className="cards"><Metric label="Registered drivers" value={String(stats.drivers)} /><Metric label="Open reports" value={String(stats.reports)} warning /><Metric label="Pending zones" value={String(stats.zones)} /><Metric label="Recorded driver earnings" value={peso(stats.earnings)} /></div><section className="panel"><h2>Operational boundaries</h2><p>{session.role === 'developer_admin' ? 'You manage city fares, TODA registration, driver and passenger account actions, reports, and zone approval.' : 'You can manage only drivers, reports, earnings, and zone requests assigned to your TODA. City fares remain controlled by the developer administrator.'}</p></section></>;
}
function Metric({ label: title, value, warning }: { label: string; value: string; warning?: boolean }) { return <div className="metric"><p>{title}</p><strong className={warning ? 'warning' : ''}>{value}</strong></div>; }

function LegacyTodas({ onMessage }: { onMessage: (value: string) => void }) {
  const [todas, setTodas] = useState<Toda[]>([]); const [name, setName] = useState('Test TODA'); const [barangayCode, setBarangayCode] = useState('064501059'); const [registration, setRegistration] = useState<TodaRegistration>({ secCertificateNumber: '', spResolutionNumber: '', mayorsPermitNumber: '', barangayClearanceNumber: '', presidentName: '', presidentLicenseNumber: '', presidentTin: '' }); const [documents, setDocuments] = useState<Record<string, File>>({}); const [targetUid, setTargetUid] = useState(''); const [selectedToda, setSelectedToda] = useState('');
  const reload = useCallback(() => adminApi.todas().then((items) => { setTodas(items); if (!selectedToda && items[0]) setSelectedToda(items[0].id); }), [selectedToda]); useEffect(() => { reload(); }, [reload]);
  async function create(event: FormEvent) { event.preventDefault(); const requiredDocuments = ['secCertificate', 'spResolution', 'mayorsPermit', 'barangayClearance']; if (!requiredDocuments.every((key) => documents[key])) { onMessage('Upload the SEC certificate, SP resolution, Mayor’s permit, and Barangay clearance.'); return; } try { const result = await adminApi.createToda({ name, barangayCode, registration }); await adminApi.uploadTodaDocuments(result.todaId, documents); onMessage(`TODA registered with legal documents. ID: ${result.todaId}`); setDocuments({}); await reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to create TODA.'); } }
  async function assign(event: FormEvent) { event.preventDefault(); try { await adminApi.assignTodaAdmin(targetUid.trim(), selectedToda); onMessage('Account promoted to TODA admin. Its former driver profile is suspended. The user must sign out and sign in again.'); setTargetUid(''); await reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to assign TODA admin.'); } }
  async function toggleToda(toda: Toda) { if (!window.confirm(`${toda.isActive ? 'Suspend' : 'restore'} ${toda.name}?`)) return; try { await adminApi.setTodaStatus(toda.id, !toda.isActive); onMessage(`${toda.name} ${toda.isActive ? 'suspended' : 'restored'}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update TODA.'); } }
  return <div className="two-column"><section className="panel"><h2>Register TODA</h2><p className="muted">Collects official city-registration details and four legal evidence files. Only official Bacolod barangays are accepted.</p><form className="form-grid" onSubmit={create}><input value={name} onChange={(e) => setName(e.target.value)} placeholder="TODA name" required /><select value={barangayCode} onChange={(e) => setBarangayCode(e.target.value)} required>{bacolodBarangays.map(([code, barangay]) => <option key={code} value={code}>{barangay} — {code}</option>)}</select>{registrationFields.map(([key, title]) => <input key={key} value={registration[key]} onChange={(e) => setRegistration({ ...registration, [key]: e.target.value })} placeholder={title} required />)}{[['secCertificate', 'SEC certificate'], ['spResolution', 'SP resolution'], ['mayorsPermit', "Mayor's permit / BPLO license"], ['barangayClearance', 'Barangay clearance']].map(([key, title]) => <label className="file-label" key={key}>{title}<input type="file" accept="image/*,application/pdf" onChange={(event) => { const file = event.target.files?.[0]; if (file) setDocuments({ ...documents, [key]: file }); }} required /></label>)}<button className="primary">Create TODA</button></form></section><section className="panel"><h2>Test TODA administrator</h2><p className="muted">Enter the Firebase Authentication UID of the existing test-driver account. Promotion intentionally suspends its driving profile.</p><form className="form-grid" onSubmit={assign}><select value={selectedToda} onChange={(e) => setSelectedToda(e.target.value)} required><option value="">Select TODA</option>{todas.map((toda) => <option key={toda.id} value={toda.id}>{toda.name} — {toda.barangayCode}</option>)}</select><input value={targetUid} onChange={(e) => setTargetUid(e.target.value)} placeholder="Existing driver Firebase UID" required /><button className="primary">Make TODA admin</button></form><h3>Registered TODAs</h3><div className="table">{todas.map((toda) => <div className="row" key={toda.id}><b>{toda.name}</b><span>{toda.barangayCode}</span><span className={toda.isActive ? 'ok' : 'warning'}>{toda.isActive ? 'Active' : 'Suspended'}</span><button onClick={() => toggleToda(toda)}>{toda.isActive ? 'Suspend' : 'Restore'}</button></div>)}</div></section></div>;
}

function Todas({ onMessage }: { onMessage: (value: string) => void }) {
  const [todas, setTodas] = useState<Toda[]>([]);
  const reload = useCallback(() => adminApi.todas().then(setTodas), []);
  useEffect(() => { reload(); }, [reload]);
  async function review(toda: Toda, status: 'approved' | 'declined') {
    if (!window.confirm(`${status === 'approved' ? 'Approve' : 'Decline'} ${toda.name}?`)) return;
    try { await adminApi.reviewTodaRegistration(toda.id, status); onMessage(`${toda.name} ${status}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to review TODA registration.'); }
  }
  async function toggleToda(toda: Toda) {
    try { await adminApi.setTodaStatus(toda.id, !toda.isActive); onMessage(`${toda.name} ${toda.isActive ? 'suspended' : 'restored'}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update TODA.'); }
  }
  const location = (toda: Toda) => [toda.barangayName, toda.cityName, toda.regionName].filter(Boolean).join(', ') || toda.barangayCode;
  return <section className="panel wide"><h2>TODA applications and registrations</h2><p className="muted">TODA administrators register through the sign-in page. Review their application here; testing applications do not require documents.</p><div className="table">{todas.map((toda) => <div className="row toda-row" key={toda.id}><span><b>{toda.name}</b><small>{location(toda)}</small></span><span className={toda.status === 'pending' ? 'warning' : toda.isActive ? 'ok' : ''}>{toda.status || (toda.isActive ? 'approved' : 'suspended')}</span><span className="actions">{toda.status === 'pending' && <><button className="primary" onClick={() => review(toda, 'approved')}>Approve</button><button onClick={() => review(toda, 'declined')}>Decline</button></>}{toda.status !== 'pending' && <button onClick={() => toggleToda(toda)}>{toda.isActive ? 'Suspend' : 'Restore'}</button>}</span></div>)}{todas.length === 0 && <p className="muted">No TODA applications yet.</p>}</div></section>;
}

function Fares({ onMessage }: { onMessage: (value: string) => void }) {
  const [fare, setFare] = useState<FareConfig>(initialFare); useEffect(() => { adminApi.fare().then(setFare); }, []);
  async function submit(event: FormEvent) { event.preventDefault(); try { await adminApi.updateFare(fare); onMessage('City fare configuration saved in Philippine pesos. New passenger estimates will use it.'); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update fares.'); } }
  return <section className="panel wide"><h2>City-controlled passenger fares</h2><p className="muted">TODA administrators can view the city fares but cannot change them. All amounts are PHP.</p><form className="form-grid fare-grid" onSubmit={submit}>{(Object.keys(fare) as Array<keyof FareConfig>).map((key) => <label key={key}>{label(key)}<input type="number" min={key === 'baseFare' || key.includes('Meters') ? 1 : 0} max="9999" value={fare[key]} onChange={(e) => setFare({ ...fare, [key]: Number(e.target.value) })} required /></label>)}<button className="primary">Save city fare</button></form><div className="fare-summary">Example: base {peso(fare.baseFare)} includes {fare.includedMeters} m; then {peso(fare.distanceStepPrice)} every {fare.distanceStepMeters} m. Additional passenger, large baggage, and out-of-TODA fees are applied exactly once.</div></section>;
}

function LegacyDriversPage({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [drivers, setDrivers] = useState<Driver[]>([]); const reload = useCallback(() => adminApi.drivers(todaId).then(setDrivers), [todaId]); useEffect(() => { reload(); }, [reload]);
  async function update(uid: string, status: string) { try { await adminApi.setDriverStatus(uid, status); onMessage(`Driver ${status}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update driver.'); } }
  return <section className="panel wide"><h2>{todaId ? 'Drivers registered in this TODA' : 'All registered drivers'}</h2><div className="table">{drivers.map((driver) => <div className="row driver" key={driver.uid}><span><b>{driver.uid}</b><small>TODA: {driver.todaId}</small></span><span>{driver.driverStatus}</span><span>★ {driver.rating || 0} · {driver.completedTrips || 0} trips<br /><small>{peso(driver.totalEarnings || 0)} earnings</small></span><span className="actions"><button onClick={() => update(driver.uid, 'approved')}>Approve</button><button onClick={() => update(driver.uid, 'suspended')}>Suspend</button><button onClick={() => update(driver.uid, 'rejected')}>Reject</button></span></div>)}{drivers.length === 0 && <p className="muted">No drivers are available in this scope.</p>}</div></section>;
}

function LegacyDriversPageV2({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const reload = useCallback(() => adminApi.drivers(todaId).then(setDrivers), [todaId]);
  useEffect(() => { reload(); }, [reload]);
  async function update(uid: string, status: 'approved' | 'suspended' | 'rejected') {
    try { await adminApi.setDriverStatus(uid, status); onMessage(`Driver ${status}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update driver.'); }
  }
  const documentLinks = (driver: Driver) => [
    ['Profile photo', driver.profilePhotoUrl], ['License front', driver.driverLicenseFrontUrl],
    ['License back', driver.driverLicenseBackUrl], ['Government ID', driver.governmentIdUrl],
    ['OR document', driver.orDocumentUrl], ['CR document', driver.crDocumentUrl],
    ['Vehicle photo', driver.vehiclePhotoUrl],
  ].filter((entry): entry is [string, string] => Boolean(entry[1]));
  return <section className="panel wide"><h2>{todaId ? 'Driver applications assigned to this TODA' : 'All driver registrations'}</h2><p className="muted">Pending drivers selected their TODA during Flutter registration. Review the profile and uploaded documents before approval.</p><div className="table">{drivers.map((driver) => <div className="row driver" key={driver.uid}><span><b>{driver.uid}</b><small>TODA: {driver.todaId}</small><small>License: {driver.licenseNumber || 'Not provided'}{driver.licenseExpiry ? ` · expires ${driver.licenseExpiry}` : ''}</small><details><summary>Registration documents ({documentLinks(driver).length})</summary><div className="document-links">{documentLinks(driver).map(([name, url]) => <a href={url} target="_blank" rel="noreferrer" key={name}>{name}</a>)}</div></details></span><span className={driver.driverStatus === 'pending' ? 'warning' : driver.driverStatus === 'approved' ? 'ok' : ''}>{driver.driverStatus}</span><span>★ {driver.rating || 0} · {driver.completedTrips || 0} trips<br /><small>{peso(driver.totalEarnings || 0)} earnings</small></span><span className="actions">{driver.driverStatus === 'pending' && <><button className="primary" onClick={() => update(driver.uid, 'approved')}>Approve</button><button onClick={() => update(driver.uid, 'rejected')}>Reject</button></>}{driver.driverStatus === 'approved' && <button onClick={() => update(driver.uid, 'suspended')}>Suspend</button>}{driver.driverStatus === 'suspended' && <button className="primary" onClick={() => update(driver.uid, 'approved')}>Restore</button>}</span></div>)}{drivers.length === 0 && <p className="muted">No driver applications are available in this scope.</p>}</div></section>;
}

function DriversPage({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const reload = useCallback(() => adminApi.drivers(todaId).then(setDrivers), [todaId]);
  useEffect(() => { reload(); }, [reload]);
  async function update(uid: string, status: 'approved' | 'suspended' | 'rejected') {
    try { await adminApi.setDriverStatus(uid, status); onMessage(`Driver ${status}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update driver.'); }
  }
  const fullName = (driver: Driver) => [driver.applicant?.firstName, driver.applicant?.middleName, driver.applicant?.lastName].filter(Boolean).join(' ') || 'Unnamed applicant';
  const documentLinks = (driver: Driver) => [['Profile photo', driver.profilePhotoUrl], ['License front', driver.driverLicenseFrontUrl], ['License back', driver.driverLicenseBackUrl], ['Government ID', driver.governmentIdUrl], ['OR document', driver.orDocumentUrl], ['CR document', driver.crDocumentUrl], ['Vehicle photo', driver.vehiclePhotoUrl]].filter((entry): entry is [string, string] => Boolean(entry[1]));
  return <section className="panel wide"><h2>{todaId ? 'Driver applications assigned to this TODA' : 'All driver registrations'}</h2><p className="muted">Review verified applicant identity, contact details, license, and documents before deciding an application.</p><div className="table">{drivers.map((driver) => <div className="row driver" key={driver.uid}><span className="applicant"><b>{fullName(driver)}</b><small>{driver.applicant?.email || 'Email not available'} · {driver.applicant?.phoneNumber || 'Phone not available'}</small><small>Date of birth: {driver.applicant?.dateOfBirth ? new Date(driver.applicant.dateOfBirth).toLocaleDateString('en-PH') : 'Not supplied (legacy registration)'}</small><small>TODA: {driver.todaId} · License: {driver.licenseNumber || 'Not provided'}</small><details><summary>Registration documents ({documentLinks(driver).length})</summary><div className="document-links">{documentLinks(driver).map(([name, url]) => <a href={url} target="_blank" rel="noreferrer" key={name}>{name}</a>)}</div></details><small className="technical-id">Firebase UID: {driver.uid}</small></span><span className={driver.driverStatus === 'pending' ? 'warning' : driver.driverStatus === 'approved' ? 'ok' : ''}>{driver.driverStatus}</span><span>★ {driver.rating || 0} · {driver.completedTrips || 0} trips<br /><small>{peso(driver.totalEarnings || 0)} earnings</small></span><span className="actions">{driver.driverStatus === 'pending' && <><button className="primary" onClick={() => update(driver.uid, 'approved')}>Approve</button><button onClick={() => update(driver.uid, 'rejected')}>Reject</button></>}{driver.driverStatus === 'approved' && <button onClick={() => update(driver.uid, 'suspended')}>Suspend</button>}{driver.driverStatus === 'suspended' && <button className="primary" onClick={() => update(driver.uid, 'approved')}>Restore</button>}</span></div>)}{drivers.length === 0 && <p className="muted">No driver applications are available in this scope.</p>}</div></section>;
}

function LegacyReportsPage({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [reports, setReports] = useState<Report[]>([]); const reload = useCallback(() => adminApi.reports(todaId).then(setReports), [todaId]); useEffect(() => { reload(); }, [reload]);
  async function action(id: string, status: string) { const note = window.prompt('Action note (optional):') ?? ''; try { await adminApi.resolveReport(id, status, note); onMessage(`Report ${status}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update report.'); } }
  async function suspendReportedUser(uid: string) { if (!window.confirm('Suspend this reported account? This prevents it from using VolTrike.')) return; try { await adminApi.setUserStatus(uid, false); onMessage('Reported account suspended.'); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to suspend account.'); } }
  return <section className="panel wide"><h2>Ride reports</h2><div className="table">{reports.map((report) => <div className="row report" key={report.id}><span><b>{report.category}</b><small>Booking {report.bookingId}</small><small>Reported user: {report.reportedUserId}</small></span><span>{report.details || 'No details provided.'}</span><span className={report.status === 'open' ? 'warning' : 'ok'}>{report.status}</span>{report.status === 'open' && <span className="actions"><button onClick={() => action(report.id, 'resolved')}>Resolve</button><button onClick={() => action(report.id, 'dismissed')}>Dismiss</button>{!todaId && <button onClick={() => suspendReportedUser(report.reportedUserId)}>Suspend user</button>}</span>}</div>)}{reports.length === 0 && <p className="muted">No reports are available in this scope.</p>}</div></section>;
}

function ReportsPage({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [reports, setReports] = useState<Report[]>([]);
  const reload = useCallback(() => adminApi.reports(todaId).then(setReports), [todaId]);
  useEffect(() => { reload(); }, [reload]);
  async function action(id: string, status: string) {
    const note = window.prompt('Action note (optional):') ?? '';
    try { await adminApi.resolveReport(id, status, note); onMessage(`Report ${status}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update report.'); }
  }
  async function suspendReportedUser(uid: string) {
    if (!window.confirm('Suspend this reported account? This prevents it from using VolTrike.')) return;
    try { await adminApi.setUserStatus(uid, false); onMessage('Reported account suspended.'); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to suspend account.'); }
  }
  const name = (person: Report['reporter'] | undefined, fallback: string) => [person?.firstName, person?.middleName, person?.lastName].filter(Boolean).join(' ') || fallback;
  const contact = (person: Report['reporter'] | undefined) => [person?.email, person?.phoneNumber].filter(Boolean).join(' · ');
  return <section className="panel wide"><h2>{todaId ? 'Reports involving this TODA' : 'All passenger and driver reports'}</h2><p className="muted">Developer Admin can identify both parties. TODA Admin sees only the identities within its authorized driver scope.</p><div className="table">{reports.map((report) => <div className="row report report-card" key={report.id}><span><b>{report.category}</b><small>Booking {report.bookingId}</small><small className={report.status === 'open' ? 'warning' : 'ok'}>{report.status}</small></span><span className="report-parties"><b>Reported by: {name(report.reporter, 'Passenger identity restricted')}</b><small>{contact(report.reporter) || (report.reporter ? 'No contact details' : 'Restricted outside TODA scope')}</small><b>Reported account: {name(report.reportedUser, 'Driver or passenger identity restricted')}</b><small>{contact(report.reportedUser) || (report.reportedUser ? 'No contact details' : 'Restricted outside TODA scope')}</small></span><span>{report.details || 'No details provided.'}{report.action && <small>Action: {report.action}</small>}</span>{report.status === 'open' && <span className="actions"><button onClick={() => action(report.id, 'resolved')}>Resolve</button><button onClick={() => action(report.id, 'dismissed')}>Dismiss</button>{!todaId && <button onClick={() => suspendReportedUser(report.reportedUserId)}>Suspend reported account</button>}</span>}</div>)}{reports.length === 0 && <p className="muted">No reports are available in this scope.</p>}</div></section>;
}

function LegacyRouteRestrictionsPage({ onMessage }: { onMessage: (value: string) => void }) {
  const [restrictions, setRestrictions] = useState<RouteRestriction[]>([]);
  const [name, setName] = useState(''); const [type, setType] = useState<RouteRestriction['type']>('prohibited_highway'); const [notes, setNotes] = useState(''); const [points, setPoints] = useState<Point[]>([]);
  const reload = useCallback(() => adminApi.routeRestrictions().then(setRestrictions), []);
  useEffect(() => { reload(); }, [reload]);
  async function create() {
    try { await adminApi.createRouteRestriction(name.trim(), type, points, notes); setName(''); setNotes(''); setPoints([]); onMessage('Route restriction saved. Mobile route selection will avoid it after the next refresh.'); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Enter a name and a three- or four-point area.'); }
  }
  async function toggle(item: RouteRestriction) {
    try { await adminApi.setRouteRestrictionStatus(item.id, !item.isActive); onMessage(`${item.name} ${item.isActive ? 'disabled' : 'enabled'}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update restriction.'); }
  }
  return <><section className="panel wide"><h2>Developer-only route restrictions</h2><p className="muted">Draw a maximum four-point red boundary for a prohibited highway segment, unavailable service area, or restricted crossing. Passenger and driver route selection will choose a safe Google Routes alternative when one is available.</p><div className="form-grid"><input value={name} onChange={(event) => setName(event.target.value)} placeholder="Restriction name, e.g. Circumferential Road highway segment" required /><select value={type} onChange={(event) => setType(event.target.value as RouteRestriction['type'])}><option value="prohibited_highway">Prohibited highway</option><option value="no_service_area">No-service area</option><option value="restricted_crossing">Restricted crossing</option></select></div><PolygonEditor points={points} onChange={setPoints} onFinish={create} maxPoints={4} /><div className="map-actions"><span>{points.length}/4 points</span><button onClick={() => setPoints(points.slice(0, -1))} disabled={!points.length}>Undo point</button><button onClick={() => setPoints([])} disabled={!points.length}>Clear</button><button className="primary" onClick={create} disabled={points.length < 3 || !name.trim()}>Save restriction</button></div><textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Operational reason and driver guidance" /></section><section className="panel wide"><h2>Active and archived restrictions</h2><div className="table">{restrictions.map((item) => <div className="row" key={item.id}><span><b>{item.name}</b><small>{item.type.replace(/_/g, ' ')} · {item.polygon.length} points</small></span><span>{item.notes || 'No guidance'}</span><span className={item.isActive ? 'warning' : 'ok'}>{item.isActive ? 'active' : 'disabled'}</span><span className="actions"><button onClick={() => toggle(item)}>{item.isActive ? 'Disable' : 'Enable'}</button></span></div>)}{restrictions.length === 0 && <p className="muted">No route restrictions configured.</p>}</div></section></>;
}

function RouteRestrictionsPage({ onMessage }: { onMessage: (value: string) => void }) {
  const [restrictions, setRestrictions] = useState<RouteRestriction[]>([]);
  const [name, setName] = useState('');
  const [type, setType] = useState<RouteRestriction['type']>('prohibited_highway');
  const [geometryType, setGeometryType] = useState<'polygon' | 'corridor'>('corridor');
  const [bufferMeters, setBufferMeters] = useState(30);
  const [notes, setNotes] = useState('');
  const [points, setPoints] = useState<Point[]>([]);
  const reload = useCallback(() => adminApi.routeRestrictions().then(setRestrictions), []);
  useEffect(() => { reload(); }, [reload]);
  const minimumPoints = geometryType === 'corridor' ? 2 : 3;
  async function create() {
    try {
      await adminApi.createRouteRestriction(name.trim(), type, geometryType, points, bufferMeters, notes);
      setName(''); setNotes(''); setPoints([]); onMessage('Route restriction saved. Mobile route selection will avoid it after the next refresh.'); reload();
    } catch (error) { onMessage(error instanceof Error ? error.message : `Enter a name and at least ${minimumPoints} points.`); }
  }
  async function toggle(item: RouteRestriction) {
    try { await adminApi.setRouteRestrictionStatus(item.id, !item.isActive); onMessage(`${item.name} ${item.isActive ? 'disabled' : 'enabled'}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update restriction.'); }
  }
  function changeType(next: RouteRestriction['type']) {
    setType(next); setGeometryType(next === 'prohibited_highway' ? 'corridor' : 'polygon'); setPoints([]);
  }
  return <><section className="panel wide"><h2>Highways and prohibited areas</h2><p className="muted">Use a red corridor for a curved or straight highway: click along its centreline, then set the blocked width. Use a polygon for no-service areas and restricted crossings.</p><div className="form-grid"><input value={name} onChange={(event) => setName(event.target.value)} placeholder="Restriction name, e.g. Circumferential Road" required /><select value={type} onChange={(event) => changeType(event.target.value as RouteRestriction['type'])}><option value="prohibited_highway">Prohibited highway corridor</option><option value="no_service_area">No-service polygon</option><option value="restricted_crossing">Restricted crossing polygon</option></select>{geometryType === 'corridor' && <label>Highway buffer (metres)<input type="number" min="5" max="200" value={bufferMeters} onChange={(event) => setBufferMeters(Number(event.target.value))} /></label>}</div><PolygonEditor points={points} onChange={setPoints} onFinish={create} geometryMode={geometryType === 'corridor' ? 'polyline' : 'polygon'} /><div className="map-actions"><span>{points.length} points · {geometryType === 'corridor' ? `${bufferMeters} m red corridor` : 'red prohibited polygon'}</span><button onClick={() => setPoints(points.slice(0, -1))} disabled={!points.length}>Undo point</button><button onClick={() => setPoints([])} disabled={!points.length}>Clear</button><button className="primary" onClick={create} disabled={points.length < minimumPoints || !name.trim()}>Save restriction</button></div><textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Operational reason and driver guidance" /></section><section className="panel wide"><h2>Active and archived restrictions</h2><div className="table">{restrictions.map((item) => <div className="row" key={item.id}><span><b>{item.name}</b><small>{item.type.replace(/_/g, ' ')} · {item.geometryType === 'corridor' ? `${item.polygon.length} centreline points · ${item.bufferMeters || 0} m buffer` : `${item.polygon.length} polygon points`}</small></span><span>{item.notes || 'No guidance'}</span><span className={item.isActive ? 'warning' : 'ok'}>{item.isActive ? 'active' : 'disabled'}</span><span className="actions"><button onClick={() => toggle(item)}>{item.isActive ? 'Disable' : 'Enable'}</button></span></div>)}{restrictions.length === 0 && <p className="muted">No route restrictions configured.</p>}</div></section></>;
}

function CoveragePage({ session, onMessage }: { session: AdminSession; onMessage: (value: string) => void }) {
  const [todas, setTodas] = useState<Toda[]>([]); const [todaId, setTodaId] = useState(session.todaId || ''); const [points, setPoints] = useState<Point[]>([]); const [notes, setNotes] = useState(''); const [zones, setZones] = useState<ZoneRequest[]>([]); const [editingZoneId, setEditingZoneId] = useState<string | null>(null);
  const reload = useCallback(async () => { const scope = session.role === 'developer_admin' ? undefined : session.todaId!; const [todoList, zoneList] = await Promise.all([adminApi.todas(), adminApi.zones(scope)]); setTodas(todoList); setZones(zoneList); if (!todaId && todoList[0]) setTodaId(todoList[0].id); }, [session, todaId]); useEffect(() => { reload(); }, [reload]);
  async function submit() { try { if (editingZoneId) { await adminApi.updateZone(editingZoneId, points, notes); onMessage('Zone request polygon updated. You can now approve or decline it.'); } else { await adminApi.submitZone(todaId, points, notes); onMessage('Polygon zone request submitted for developer review.'); } setPoints([]); setNotes(''); setEditingZoneId(null); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'A polygon needs at least three points.'); } }
  async function review(id: string, status: string) { try { await adminApi.reviewZone(id, status); onMessage(`Zone request ${status}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to review zone.'); } }
  const selectedName = useMemo(() => todas.find((toda) => toda.id === todaId)?.name || 'selected TODA', [todas, todaId]);
  return <><section className="panel wide"><h2>{session.role === 'developer_admin' ? 'Create or review coverage areas' : 'Request TODA coverage area'}</h2><p className="muted">Choose a TODA, then left-click the map to add points. Press <b>Enter</b> or use Finish polygon when at least three points have been added. The developer admin approves or declines the request.</p>{session.role === 'developer_admin' && <select value={todaId} onChange={(e) => setTodaId(e.target.value)}><option value="">Select TODA</option>{todas.map((toda) => <option key={toda.id} value={toda.id}>{toda.name}</option>)}</select>}<Suspense fallback={<div className="map-missing">Loading Mapbox coverage editor…</div>}><PolygonEditor points={points} onChange={setPoints} onFinish={submit} /></Suspense><div className="map-actions"><span>{points.length} points for {selectedName}</span><button onClick={() => setPoints(points.slice(0, -1))} disabled={!points.length}>Undo point</button><button onClick={() => { setPoints([]); setEditingZoneId(null); }} disabled={!points.length}>Clear</button><button className="primary" onClick={submit} disabled={points.length < 3 || !todaId}>{editingZoneId ? 'Save edited polygon' : 'Finish polygon & request review'}</button></div><textarea value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Route/terminal notes for the reviewer" /></section><section className="panel wide"><h2>{session.role === 'developer_admin' ? 'Pending zone requests' : 'My TODA zone requests'}</h2><div className="table">{zones.map((zone) => <div className="row" key={zone.id}><span><b>{zone.todaId}</b><small>{zone.polygon.length} polygon points</small></span><span>{zone.notes || 'No notes'}</span><span className={zone.status === 'pending' ? 'warning' : 'ok'}>{zone.status}</span>{session.role === 'developer_admin' && zone.status === 'pending' && <span className="actions"><button onClick={() => { setTodaId(zone.todaId); setPoints(zone.polygon); setNotes(zone.notes || ''); setEditingZoneId(zone.id); }}>Edit</button><button onClick={() => review(zone.id, 'approved')}>Approve</button><button onClick={() => review(zone.id, 'declined')}>Decline</button></span>}</div>)}</div></section></>;
}
