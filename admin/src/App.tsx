import { FormEvent, lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createUserWithEmailAndPassword, onAuthStateChanged, signInWithEmailAndPassword, signOut, type User } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from './firebase';
import { adminApi } from './admin-api';
import { loadPhilippineLocations, type Barangay, type City, type Region } from './data/locations';
import { bacolodBarangays } from './data/bacolodBarangays';
import type { AdminSession, BookingOperation, Driver, DriverRatingRecord, FareConfig, LiveDriver, Point, Report, RouteRestriction, SafetyIncident, Toda, TodaRegistration, ZoneRequest } from './types';
import './registration.css';
import './driver-review.css';

// Mapbox is substantial; load it only when an administrator opens a map page.
const PolygonEditor = lazy(() => import('./components/PolygonEditor').then((module) => ({ default: module.PolygonEditor })));
const AdminLocationMap = lazy(() => import('./components/AdminLocationMap').then((module) => ({ default: module.AdminLocationMap })));

type Page = 'overview' | 'todas' | 'fares' | 'drivers' | 'live_drivers' | 'commission' | 'ratings' | 'operations' | 'safety' | 'reports' | 'coverage' | 'route_rules';
const initialFare: FareConfig = { baseFare: 20, includedMeters: 1000, distanceStepMeters: 500, distanceStepPrice: 5, additionalPassengerFee: 40, baggageFee: 20, outsideTodaSurcharge: 20 };
const registrationFields: Array<[keyof TodaRegistration, string]> = [
  ['secCertificateNumber', 'SEC registration certificate number'], ['spResolutionNumber', 'SP resolution number'], ['mayorsPermitNumber', "Bacolod Mayor's permit / BPLO license number"], ['barangayClearanceNumber', 'Barangay clearance and endorsement number'], ['presidentName', "TODA President's full name"], ['presidentLicenseNumber', "President's professional driver license number"], ['presidentTin', "President's TIN"],
];
const todaEvidenceFields = [
  ['secCertificate', 'SEC registration certificate'],
  ['spResolution', 'Sangguniang Panlungsod resolution'],
  ['mayorsPermit', "Bacolod Mayor's permit / BPLO license"],
  ['barangayClearance', 'Barangay clearance and endorsement'],
  ['presidentLicense', "TODA President's professional driver license"],
] as const;

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
    const [snapshot, token] = await Promise.all([
      getDoc(doc(db, 'users', signedIn.uid)),
      signedIn.getIdTokenResult(true),
    ]);
    const data = snapshot.data();
    const claimRole = token.claims.adminRole;
    const claimTodaId = token.claims.todaId;
    const roleMatches = claimRole === data?.role &&
      (data?.role !== 'toda_admin' || claimTodaId === data.todaId);
    if (data && roleMatches &&
        (data.role === 'developer_admin' || data.role === 'toda_admin') &&
        data.isActive !== false &&
        (data.requiresEmailVerification !== true || signedIn.emailVerified)) {
      setSession({ uid: signedIn.uid, email: signedIn.email, role: data.role, todaId: data.todaId || null, displayName: `${data.firstName || ''} ${data.lastName || ''}`.trim() || signedIn.email || 'Administrator' });
    } else {
      setSession(null);
      if (data && (data.role === 'developer_admin' || data.role === 'toda_admin') && !roleMatches) {
        setMessage('Administrator permissions changed. Sign out and sign in again to refresh access.');
      }
    }
    setLoading(false);
  }, []);

  useEffect(() => onAuthStateChanged(auth, loadSession), [loadSession]);
  if (loading) return <main className="centered">Loading VolTrike Admin…</main>;
  if (!user) return <Login onMessage={setMessage} message={message} />;
  if (!session) return <AccountGate user={user} reload={() => loadSession(auth.currentUser)} onMessage={setMessage} message={message} />;

  const isDeveloper = session.role === 'developer_admin';
  const visiblePages: Array<[Page, string]> = isDeveloper
    ? [['overview', 'Overview'], ['todas', 'TODAs'], ['fares', 'City fares'], ['drivers', 'Drivers'], ['live_drivers', 'Live drivers'], ['operations', 'Ride operations'], ['safety', 'Safety incidents'], ['reports', 'Reports'], ['coverage', 'Coverage areas'], ['route_rules', 'Route restrictions']]
    : [['overview', 'Overview'], ['drivers', 'My drivers'], ['live_drivers', 'Live drivers'], ['commission', 'Driver commission'], ['ratings', 'Driver ratings'], ['operations', 'TODA rides'], ['safety', 'TODA safety'], ['reports', 'TODA reports'], ['coverage', 'Zone request']];
  return <div className="shell">
    <aside className="sidebar"><div className="brand"><img src="/images/VolTrikeLogo-Light.png" alt="VolTrike" onError={(event) => { event.currentTarget.style.display = 'none'; }} /><span>VolTrike<br /><b>Admin</b></span></div><div className="role-pill">{isDeveloper ? 'Developer Admin' : 'TODA Admin'}</div>
      <nav aria-label="Admin sections">{visiblePages.map(([key, text]) => <button className={page === key ? 'nav-active' : ''} aria-current={page === key ? 'page' : undefined} key={key} onClick={() => setPage(key)}>{text}</button>)}</nav>
      <div className="sidebar-footer"><span>{session.displayName}</span><button onClick={() => signOut(auth)}>Sign out</button></div>
    </aside>
    <main className="content"><header><div><p className="eyebrow">Bacolod City TNVS operations</p><h1>{visiblePages.find(([key]) => key === page)?.[1]}</h1></div><div className="status">{isDeveloper ? 'Platform-wide access' : 'TODA-scoped access'}</div></header>
      {message && <div className="notice" role="status">{message}<button aria-label="Dismiss message" onClick={() => setMessage('')}>×</button></div>}
      {page === 'overview' && <Overview session={session} />}
      {page === 'todas' && isDeveloper && <Todas onMessage={setMessage} />}
      {page === 'fares' && isDeveloper && <Fares onMessage={setMessage} />}
      {page === 'drivers' && <DriversPage todaId={isDeveloper ? undefined : session.todaId!} onMessage={setMessage} />}
      {page === 'live_drivers' && <LiveDriversPage />}
      {page === 'commission' && !isDeveloper && <CommissionPage onMessage={setMessage} />}
      {page === 'ratings' && !isDeveloper && <RatingsPage />}
      {page === 'operations' && <OperationsPage session={session} />}
      {page === 'safety' && <SafetyIncidentsPage session={session} />}
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
  return <main className="auth"><section><img src="/images/VolTrikeLogo-Dark.png" className="auth-logo" alt="VolTrike" /><p className="eyebrow">VolTrike operations</p><h1>Admin Portal</h1><p>Authorized TODA and developer operations only.</p>{message && <div className="notice" role="alert">{message}</div>}<form onSubmit={submit}><label>Email address<input type="email" placeholder="admin@example.com" autoComplete="email" value={email} onChange={(event) => setEmail(event.target.value)} required /></label><label>Password<input type="password" placeholder="Enter your password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} required /></label><button className="primary" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button><button type="button" onClick={() => { onMessage(''); setRegistering(true); }}>Register a TODA</button></form></section></main>;
}

function TodaSignUp({ onBack, onMessage }: { onBack: () => void; onMessage: (value: string) => void }) {
  const [regions, setRegions] = useState<Region[]>([]); const [cities, setCities] = useState<City[]>([]); const [barangays, setBarangays] = useState<Barangay[]>([]);
  const [regionCode, setRegionCode] = useState(''); const [cityCode, setCityCode] = useState(''); const [barangayCode, setBarangayCode] = useState('');
  const [name, setName] = useState(''); const [email, setEmail] = useState(''); const [password, setPassword] = useState(''); const [busy, setBusy] = useState(false); const [loadError, setLoadError] = useState(''); const [step, setStep] = useState(1);
  const [registration, setRegistration] = useState<TodaRegistration>({ secCertificateNumber: '', spResolutionNumber: '', mayorsPermitNumber: '', barangayClearanceNumber: '', presidentName: '', presidentLicenseNumber: '', presidentTin: '' });
  const [documents, setDocuments] = useState<Record<string, File>>({});
  useEffect(() => { loadPhilippineLocations().then(({ regions: nextRegions, cities: nextCities, barangays: nextBarangays }) => { setRegions(nextRegions); setCities(nextCities); setBarangays(nextBarangays); }).catch((error) => setLoadError(error instanceof Error ? error.message : 'Unable to load locations.')); }, []);
  const cityOptions = useMemo(() => cities.filter((city) => city.regionCode === regionCode), [cities, regionCode]);
  const barangayOptions = useMemo(() => barangays.filter((barangay) => barangay.regionCode === regionCode && (barangay.cityCode === cityCode || barangay.municipalityCode === cityCode)), [barangays, cityCode, regionCode]);
  async function submit(event: FormEvent) {
    event.preventDefault(); setBusy(true);
    try {
      if (!todaEvidenceFields.every(([key]) => documents[key])) throw new Error('Upload all five required legal evidence files.');
      await createUserWithEmailAndPassword(auth, email.trim(), password);
      const region = regions.find((item) => item.code === regionCode); const city = cities.find((item) => item.code === cityCode); const barangay = barangays.find((item) => item.code === barangayCode);
      if (!region || !city || !barangay) throw new Error('Select a region, city/municipality, and barangay.');
      const result = await adminApi.registerToda({ name, regionCode, regionName: region.name, cityCode, cityName: city.name, barangayCode, barangayName: barangay.name, registration });
      await adminApi.uploadTodaRegistrationDocuments(result.todaId, documents);
      let verificationSent = true;
      try { await adminApi.requestBrandedVerificationEmail(); } catch { verificationSent = false; }
      await signOut(auth); onMessage(verificationSent ? 'TODA application submitted. Check your branded verification email while a Developer Admin reviews the application.' : 'TODA application submitted, but the verification email could not be delivered. Sign in later and request another verification email.'); onBack();
    } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to submit TODA registration.'); }
    finally { setBusy(false); }
  }
  if (step === 1) return <main className="auth"><section className="auth-wide"><p className="eyebrow">TODA onboarding · Step 1 of 2</p><h1>Organization and administrator</h1><p>Choose the official location. Legal details and evidence files are collected in Step 2.</p>{loadError && <div className="notice">{loadError}</div>}<form onSubmit={(event) => { event.preventDefault(); setStep(2); }}><input value={name} onChange={(event) => setName(event.target.value)} placeholder="TODA name" required /><input type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="Administrator email" required /><input type="password" minLength={6} value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Password (at least 6 characters)" required /><select value={regionCode} onChange={(event) => { setRegionCode(event.target.value); setCityCode(''); setBarangayCode(''); }} required><option value="">Select region</option>{regions.map((region) => <option key={region.code} value={region.code}>{region.name}</option>)}</select><select value={cityCode} onChange={(event) => { setCityCode(event.target.value); setBarangayCode(''); }} disabled={!regionCode} required><option value="">Select city / municipality</option>{cityOptions.map((city) => <option key={city.code} value={city.code}>{city.name}</option>)}</select><select value={barangayCode} onChange={(event) => setBarangayCode(event.target.value)} disabled={!cityCode} required><option value="">Select barangay</option>{barangayOptions.map((barangay) => <option key={barangay.code} value={barangay.code}>{barangay.name}</option>)}</select><button className="primary" disabled={Boolean(loadError)}>Continue to legal requirements</button><button type="button" onClick={onBack}>Back to sign in</button></form></section></main>;
  if (step === 2) return <main className="auth"><section className="auth-wide"><p className="eyebrow">TODA onboarding · Step 2 of 2</p><h1>Legal registration requirements</h1><p>Provide the legal identifiers and clear photo or PDF evidence. The verified administrator email from Step 1 receives required account and safety notifications. A Developer Admin reviews every item before approval.</p><form onSubmit={submit}>{registrationFields.map(([key, title]) => <input key={key} type="text" autoComplete="off" value={registration[key]} onChange={(event) => setRegistration({ ...registration, [key]: event.target.value })} placeholder={title} required />)}{todaEvidenceFields.map(([key, title]) => <label className="file-label" key={key}>{title}<input type="file" accept="image/*,application/pdf" onChange={(event) => { const file = event.target.files?.[0]; if (file) setDocuments({ ...documents, [key]: file }); }} required /><small>{documents[key]?.name || 'No file selected'}</small></label>)}<button className="primary" disabled={busy}>{busy ? 'Submitting…' : 'Submit TODA application'}</button><button type="button" onClick={() => setStep(1)} disabled={busy}>Back</button></form></section></main>;
  return <main className="auth"><section className="auth-wide"><p className="eyebrow">TODA onboarding</p><h1>Register a TODA</h1><p>For testing, legal documents are not required. Select locations only from the official PSGC list.</p>{loadError && <div className="notice">{loadError}</div>}<form onSubmit={submit}><input value={name} onChange={(event) => setName(event.target.value)} placeholder="TODA name" required /><input type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="Administrator email" required /><input type="password" minLength={6} value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Password (at least 6 characters)" required /><select value={regionCode} onChange={(event) => { setRegionCode(event.target.value); setCityCode(''); setBarangayCode(''); }} required><option value="">Select region</option>{regions.map((region) => <option key={region.code} value={region.code}>{region.name}</option>)}</select><select value={cityCode} onChange={(event) => { setCityCode(event.target.value); setBarangayCode(''); }} disabled={!regionCode} required><option value="">Select city / municipality</option>{cityOptions.map((city) => <option key={city.code} value={city.code}>{city.name}</option>)}</select><select value={barangayCode} onChange={(event) => setBarangayCode(event.target.value)} disabled={!cityCode} required><option value="">Select barangay</option>{barangayOptions.map((barangay) => <option key={barangay.code} value={barangay.code}>{barangay.name}</option>)}</select><button className="primary" disabled={busy || Boolean(loadError)}>{busy ? 'Submitting…' : 'Submit TODA registration'}</button><button type="button" onClick={onBack}>Back to sign in</button></form></section></main>;
}

function AccountGate({ user, reload, onMessage, message }: { user: User; reload: () => Promise<void>; onMessage: (value: string) => void; message: string }) {
  const [gate, setGate] = useState<{ applicationStatus: string | null; requiresEmailVerification: boolean } | undefined>(undefined);
  const [sendingVerification, setSendingVerification] = useState(false);
  useEffect(() => { getDoc(doc(db, 'users', user.uid)).then((snapshot) => { const profile = snapshot.data(); setGate({ applicationStatus: profile?.role === 'toda_admin_pending' ? profile.todaApplicationStatus || 'pending' : null, requiresEmailVerification: profile?.requiresEmailVerification === true }); }); }, [user.uid]);
  if (gate === undefined) return <main className="centered">Checking administrator access…</main>;
  if (gate.requiresEmailVerification && !user.emailVerified) return <main className="auth"><section><p className="eyebrow">Administrator verification</p><h1>Verify your email</h1><p>Open the branded VolTrike verification email sent to {user.email}. Verification is required for new TODA administrator accounts.</p>{message && <div className="notice">{message}</div>}<button className="primary" disabled={sendingVerification} onClick={async () => { setSendingVerification(true); try { await adminApi.requestBrandedVerificationEmail(); onMessage('Verification email sent. Check your inbox and spam folder.'); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to send verification email.'); } finally { setSendingVerification(false); } }}>{sendingVerification ? 'Sending…' : 'Resend verification email'}</button><button onClick={async () => { await user.reload(); await reload(); }}>I have verified my email</button><button onClick={() => signOut(auth)}>Sign out</button></section></main>;
  const applicationStatus = gate.applicationStatus;
  if (applicationStatus) return <main className="auth"><section><p className="eyebrow">TODA registration</p><h1>{applicationStatus === 'declined' ? 'Application declined' : 'Approval pending'}</h1><p>{applicationStatus === 'declined' ? 'Your TODA application was declined. Contact the developer administrator before submitting another application.' : 'Your TODA registration has been submitted. A developer administrator must approve it before TODA-admin access is enabled.'}</p>{message && <div className="notice">{message}</div>}<button className="primary" onClick={() => signOut(auth)}>Sign out</button></section></main>;
  return <Bootstrap user={user} reload={reload} onMessage={onMessage} message={message} />;
}

function Bootstrap({ user, reload, onMessage, message }: { user: User; reload: () => Promise<void>; onMessage: (value: string) => void; message: string }) {
  const [code, setCode] = useState(''); const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); try { await adminApi.bootstrap(code); await user.getIdToken(true); await reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Bootstrap failed.'); } finally { setBusy(false); } }
  return <main className="auth"><section><p className="eyebrow">First-time setup</p><h1>Create developer access</h1><p>Signed in as {user.email}. Enter the one-time bootstrap code stored in Firebase Secret Manager. This page works only while no developer admin exists.</p>{message && <div className="notice">{message}</div>}<form onSubmit={submit}><input type="password" placeholder="Bootstrap code" value={code} onChange={(e) => setCode(e.target.value)} required /><button className="primary" disabled={busy}>{busy ? 'Creating…' : 'Create developer admin'}</button><button type="button" onClick={() => signOut(auth)}>Use another account</button></form></section></main>;
}

function Overview({ session }: { session: AdminSession }) {
  const [stats, setStats] = useState({
    drivers: 0,
    reports: 0,
    zones: 0,
    trips: 0,
    bookings: 0,
    safetyIncidents: 0,
    scope: session.role === 'toda_admin' ? session.todaId || '' : 'platform',
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  useEffect(() => {
    const refresh = async () => {
      if (document.visibilityState !== 'visible') return;
      try {
        const next = await adminApi.metrics();
        setStats(next);
        setError('');
      } catch (reason) {
        setError(reason instanceof Error ? reason.message : 'Unable to load Firebase overview metrics.');
      } finally {
        setLoading(false);
      }
    };
    void refresh();
    const timer = window.setInterval(() => void refresh(), 15000);
    return () => window.clearInterval(timer);
  }, [session]);
  return <>{loading && <p className="muted">Loading Firebase overview…</p>}{error && <div className="notice">{error}</div>}<div className="cards"><Metric label="Registered drivers" value={String(stats.drivers)} /><Metric label="All bookings" value={String(stats.bookings)} /><Metric label="Completed rides" value={String(stats.trips)} /><Metric label="Open reports" value={String(stats.reports)} warning /><Metric label="Open safety incidents" value={String(stats.safetyIncidents)} warning /><Metric label="Pending zones" value={String(stats.zones)} /></div><section className="panel"><h2>Operational boundaries</h2><p>{session.role === 'developer_admin' ? 'These figures cover Firebase bookings, drivers, reports, SOS incidents, and zone requests across the platform.' : 'These figures are restricted by Firebase to bookings, drivers, reports, SOS incidents, and zones assigned to your authenticated TODA. City fares remain controlled by the developer administrator; commission is managed on its own audited page.'}</p></section></>;
}
function Metric({ label: title, value, warning }: { label: string; value: string; warning?: boolean }) { return <div className="metric"><p>{title}</p><strong className={warning ? 'warning' : ''}>{value}</strong></div>; }

function CommissionPage({ onMessage }: { onMessage: (value: string) => void }) {
  const [percent, setPercent] = useState(0);
  const [recommended, setRecommended] = useState(10);
  const [maximum, setMaximum] = useState(30);
  const [updatedAt, setUpdatedAt] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    void adminApi.todaCommission().then((value) => {
      setPercent(value.percent);
      setRecommended(value.recommendedPercent);
      setMaximum(value.maximumPercent);
      setUpdatedAt(value.updatedAt || null);
    });
  }, []);
  async function save(event: FormEvent) {
    event.preventDefault();
    if (!window.confirm(`Set the TODA commission to ${percent}% for future ride assignments? Existing and completed rides will not be changed.`)) return;
    setBusy(true);
    try {
      const value = await adminApi.setTodaCommission(percent);
      setPercent(value.percent);
      setUpdatedAt(value.updatedAt || null);
      onMessage('Driver commission saved. It applies only when a future booking is assigned.');
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to update commission.');
    } finally {
      setBusy(false);
    }
  }
  return <section className="panel wide">
    <h2>Driver commission</h2>
    <p className="muted">Set the percentage retained by your TODA from future completed rides. The percentage is snapshotted when a driver accepts a booking, so later changes cannot rewrite existing ride earnings.</p>
    <form className="commission-form" onSubmit={save}>
      <label>Commission percentage<input type="range" min="0" max={maximum} step="0.5" value={percent} onChange={(event) => setPercent(Number(event.target.value))} /></label>
      <label className="commission-number"><input type="number" min="0" max={maximum} step="0.5" value={percent} onChange={(event) => setPercent(Number(event.target.value))} /><span>%</span></label>
      <button type="button" onClick={() => setPercent(recommended)}>Use recommended {recommended}%</button>
      <button className="primary" disabled={busy}>{busy ? 'Saving…' : 'Save commission'}</button>
    </form>
    <div className="fare-summary">Guardrails: 0–{maximum}% only, explicit confirmation, an audit record for every change, and no retroactive recalculation. Example on a ₱100 fare: driver receives {peso(100 - percent)} and TODA commission is {peso(percent)}.</div>
    {updatedAt && <p className="muted">Last changed {new Date(updatedAt).toLocaleString('en-PH')}.</p>}
  </section>;
}

function LiveDriversPage() {
  const [drivers, setDrivers] = useState<LiveDriver[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [error, setError] = useState('');
  const refresh = useCallback(async () => {
    try {
      setDrivers(await adminApi.liveDrivers());
      setError('');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to load live drivers.');
    }
  }, []);
  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') void refresh();
    }, 5000);
    return () => window.clearInterval(timer);
  }, [refresh]);
  const points = drivers.map((driver) => ({
    id: driver.uid,
    latitude: driver.latitude,
    longitude: driver.longitude,
    title: driver.name,
    details: [
      `${driver.vehicleType || 'Vehicle'} · ${driver.plateNumber || 'No plate'}`,
      `Status: ${driver.bookingStatus.split('_').join(' ')}`,
      driver.bookingId ? `Booking: ${driver.bookingId}` : 'No active booking',
    ],
  }));
  return <div className="two-column live-layout">
    <section className="panel wide">
      <h2>Online driver map</h2>
      <p className="muted">Only approved drivers who are online and have a fresh location are shown. Select a driver to expand their marker and current booking status.</p>
      {error && <div className="notice">{error}</div>}
      <Suspense fallback={<div className="map-missing">Loading live-driver map…</div>}>
        <AdminLocationMap points={points} selectedId={selectedId} />
      </Suspense>
    </section>
    <section className="panel">
      <h2>Online now ({drivers.length})</h2>
      <div className="table">{drivers.map((driver) => <button className={selectedId === driver.uid ? 'live-driver selected' : 'live-driver'} onClick={() => setSelectedId(driver.uid)} key={driver.uid}>
        <b>{driver.name}</b>
        <small>{driver.vehicleType || 'Vehicle'} · {driver.plateNumber || 'No plate'}</small>
        <small>{driver.bookingStatus.split('_').join(' ')}{driver.bookingId ? ` · ${driver.bookingId}` : ''}</small>
      </button>)}{drivers.length === 0 && <p className="muted">No online driver has a fresh location.</p>}</div>
    </section>
  </div>;
}

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
  const evidence = (toda: Toda) => [
    ['SEC certificate', toda.documents?.secCertificate],
    ['SP resolution', toda.documents?.spResolution],
    ["Mayor's permit / BPLO license", toda.documents?.mayorsPermit],
    ['Barangay clearance', toda.documents?.barangayClearance],
    ["President's license", toda.documents?.presidentLicense],
  ].filter((entry): entry is [string, string] => Boolean(entry[1]));
  return <section className="panel wide"><h2>TODA applications and registrations</h2><p className="muted">Review the organization details, legal identifiers, verified administrator email, and secure evidence before approving a TODA administrator.</p><div className="table">{todas.map((toda) => <div className="row toda-row" key={toda.id}><span><b>{toda.name}</b><small>{location(toda)}</small><small>President: {toda.registration?.presidentName || 'Not supplied'} · License: {toda.registration?.presidentLicenseNumber || 'Not supplied'} · TIN: {toda.registration?.presidentTin || 'Not supplied'}</small><small>SEC: {toda.registration?.secCertificateNumber || 'Not supplied'} · SP: {toda.registration?.spResolutionNumber || 'Not supplied'} · BPLO: {toda.registration?.mayorsPermitNumber || 'Not supplied'} · Barangay: {toda.registration?.barangayClearanceNumber || 'Not supplied'}</small><details><summary>Legal evidence ({evidence(toda).length}/5)</summary><div className="document-links">{evidence(toda).map(([name, url]) => <a href={url} target="_blank" rel="noreferrer" key={name}>{name}</a>)}</div></details></span><span className={toda.status === 'pending' ? 'warning' : toda.isActive ? 'ok' : ''}>{toda.status || (toda.isActive ? 'approved' : 'suspended')}</span><span className="actions">{toda.status === 'pending' && <><button className="primary" onClick={() => review(toda, 'approved')}>Approve</button><button onClick={() => review(toda, 'declined')}>Decline</button></>}{toda.status !== 'pending' && <button onClick={() => toggleToda(toda)}>{toda.isActive ? 'Suspend' : 'Restore'}</button>}</span></div>)}{todas.length === 0 && <p className="muted">No TODA applications yet.</p>}</div></section>;
  return <section className="panel wide"><h2>TODA applications and registrations</h2><p className="muted">TODA administrators register through the sign-in page. Review their application here; testing applications do not require documents.</p><div className="table">{todas.map((toda) => <div className="row toda-row" key={toda.id}><span><b>{toda.name}</b><small>{location(toda)}</small></span><span className={toda.status === 'pending' ? 'warning' : toda.isActive ? 'ok' : ''}>{toda.status || (toda.isActive ? 'approved' : 'suspended')}</span><span className="actions">{toda.status === 'pending' && <><button className="primary" onClick={() => review(toda, 'approved')}>Approve</button><button onClick={() => review(toda, 'declined')}>Decline</button></>}{toda.status !== 'pending' && <button onClick={() => toggleToda(toda)}>{toda.isActive ? 'Suspend' : 'Restore'}</button>}</span></div>)}{todas.length === 0 && <p className="muted">No TODA applications yet.</p>}</div></section>;
}

function Fares({ onMessage }: { onMessage: (value: string) => void }) {
  const [fare, setFare] = useState<FareConfig>(initialFare); useEffect(() => { adminApi.fare().then(setFare); }, []);
  async function submit(event: FormEvent) { event.preventDefault(); try { await adminApi.updateFare(fare); onMessage('City fare configuration saved in Philippine pesos. New passenger estimates will use it.'); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update fares.'); } }
  const fields: Array<[keyof FareConfig, string, string]> = [
    ['baseFare', 'Base fare', 'PHP'],
    ['includedMeters', 'Base fare distance', 'metres'],
    ['distanceStepPrice', 'Distance surcharge', 'PHP'],
    ['distanceStepMeters', 'Surcharge interval', 'metres'],
    ['additionalPassengerFee', 'Additional passenger fee', 'PHP each'],
    ['baggageFee', 'One-time baggage fee', 'PHP'],
    ['outsideTodaSurcharge', 'Outside TODA surcharge', 'PHP'],
  ];
  return <section className="panel wide"><h2>City-controlled passenger fares</h2><p className="muted">Amounts are stored in PHP. Update metadata is recorded by the backend automatically and is not editable.</p><form className="form-grid fare-grid" onSubmit={submit}>{fields.map(([key, title, unit]) => <label key={key}>{title}<span className="input-with-unit"><input type="number" min={key === 'baseFare' || key.includes('Meters') ? 1 : 0} max="9999" step="0.01" value={fare[key]} onChange={(e) => setFare({ ...fare, [key]: Number(e.target.value) })} required /><small>{unit}</small></span></label>)}<button className="primary">Save city fare</button></form><div className="fare-summary">Fare = {peso(fare.baseFare)} for the first {fare.includedMeters} m, plus {peso(fare.distanceStepPrice)} per started {fare.distanceStepMeters} m after that. Passenger, baggage, and boundary charges appear separately in the passenger breakdown.</div></section>;
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
  async function update(uid: string, status: 'approved' | 'suspended' | 'rejected', license?: { number: string; expiry: string }) {
    try { await adminApi.setDriverStatus(uid, status, license); onMessage(`Driver ${status}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update driver.'); }
  }
  async function verifyVehicle(driver: Driver, isVerified: boolean) {
    try { await adminApi.setVehicleVerification(driver.uid, isVerified); onMessage(`Vehicle ${isVerified ? 'verified' : 'verification removed'}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update vehicle verification.'); }
  }
  const documentLinks = (driver: Driver) => [
    ['Profile photo', driver.profilePhotoUrl], ['License front', driver.driverLicenseFrontUrl],
    ['License back', driver.driverLicenseBackUrl], ['Government ID', driver.governmentIdUrl],
    ['OR document', driver.orDocumentUrl], ['CR document', driver.crDocumentUrl],
    ['Vehicle photo', driver.vehiclePhotoUrl],
  ].filter((entry): entry is [string, string] => Boolean(entry[1]));
  return <section className="panel wide"><h2>{todaId ? 'Driver applications assigned to this TODA' : 'All driver registrations'}</h2><p className="muted">Pending drivers selected their TODA during Flutter registration. Review the profile and uploaded documents before approval.</p><div className="table">{drivers.map((driver) => <div className="row driver" key={driver.uid}><span><b>{driver.uid}</b><small>TODA: {driver.todaId}</small><small>License: {driver.licenseNumber || 'Not provided'}{driver.licenseExpiry ? ` · expires ${driver.licenseExpiry}` : ''}</small><details><summary>Registration documents ({documentLinks(driver).length})</summary><div className="document-links">{documentLinks(driver).map(([name, url]) => <a href={url} target="_blank" rel="noreferrer" key={name}>{name}</a>)}</div></details></span><span className={driver.driverStatus === 'pending' ? 'warning' : driver.driverStatus === 'approved' ? 'ok' : ''}>{driver.driverStatus}</span><span>★ {driver.rating || 0} · {driver.completedTrips || 0} trips<br /><small>{peso(driver.totalEarnings || 0)} earnings</small></span><span className="actions">{driver.driverStatus === 'pending' && <><button className="primary" onClick={() => update(driver.uid, 'approved')}>Approve</button><button onClick={() => update(driver.uid, 'rejected')}>Reject</button></>}{driver.driverStatus === 'approved' && <button onClick={() => update(driver.uid, 'suspended')}>Suspend</button>}{driver.driverStatus === 'suspended' && <button className="primary" onClick={() => update(driver.uid, 'approved')}>Restore</button>}</span></div>)}{drivers.length === 0 && <p className="muted">No driver applications are available in this scope.</p>}</div></section>;
}

function LegacyDriversPageV3({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const reload = useCallback(() => adminApi.drivers(todaId).then(setDrivers), [todaId]);
  useEffect(() => {
    reload();
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') reload();
    }, 5000);
    return () => window.clearInterval(timer);
  }, [reload]);
  async function update(uid: string, status: 'approved' | 'suspended' | 'rejected') {
    try { await adminApi.setDriverStatus(uid, status); onMessage(`Driver ${status}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update driver.'); }
  }
  async function verifyVehicle(driver: Driver, isVerified: boolean) {
    try { await adminApi.setVehicleVerification(driver.uid, isVerified); onMessage(`Vehicle ${isVerified ? 'verified' : 'verification removed'}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update vehicle verification.'); }
  }
  const fullName = (driver: Driver) => [driver.applicant?.firstName, driver.applicant?.middleName, driver.applicant?.lastName].filter(Boolean).join(' ') || 'Unnamed applicant';
  const documentLinks = (driver: Driver) => [['Profile photo', driver.profilePhotoUrl], ['License front', driver.driverLicenseFrontUrl], ['License back', driver.driverLicenseBackUrl], ['Government ID', driver.governmentIdUrl], ['OR document', driver.orDocumentUrl], ['CR document', driver.crDocumentUrl], ['Vehicle photo', driver.vehiclePhotoUrl]].filter((entry): entry is [string, string] => Boolean(entry[1]));
  return <section className="panel wide"><h2>{todaId ? 'Driver applications assigned to this TODA' : 'All driver registrations'}</h2><p className="muted">{todaId ? 'Review identity, vehicle, documents, and passenger feedback before a TODA decision.' : 'Developer oversight can suspend active accounts; routine approvals and driver ratings remain with each TODA.'}</p><div className="table">{drivers.map((driver) => <div className="row driver" key={driver.uid}><span className="applicant"><b>{fullName(driver)}</b><small>{driver.applicant?.email || 'Email not available'} · {driver.applicant?.phoneNumber || 'Phone not available'}</small><small>Date of birth: {driver.applicant?.dateOfBirth ? new Date(driver.applicant.dateOfBirth).toLocaleDateString('en-PH') : 'Not supplied (legacy registration)'}</small><small>TODA: {driver.todaId} · License: {driver.licenseNumber || 'Not provided'}</small><small>Vehicle: {driver.vehicle?.vehicleNumber || driver.vehicle?.model || 'Not registered'} · {driver.vehicle?.plateNumber || 'No plate'} · {driver.vehicle?.isVerified ? 'verified' : 'not verified'}</small><details><summary>Registration documents ({documentLinks(driver).length})</summary><div className="document-links">{documentLinks(driver).map(([name, url]) => <a href={url} target="_blank" rel="noreferrer" key={name}>{name}</a>)}</div></details><small className="technical-id">Firebase UID: {driver.uid}</small></span><span className={driver.driverStatus === 'pending' ? 'warning' : driver.driverStatus === 'approved' ? 'ok' : ''}>{driver.driverStatus}</span><span>{todaId && <>★ {driver.rating || 0} from {driver.ratingCount || 0} ratings<br /></>}<small>{driver.completedTrips || 0} trips · {peso(driver.totalEarnings || 0)} earnings</small></span><span className="actions">{todaId && driver.vehicle && <button onClick={() => verifyVehicle(driver, !driver.vehicle?.isVerified)}>{driver.vehicle.isVerified ? 'Remove vehicle verification' : 'Verify vehicle'}</button>}{todaId && driver.driverStatus === 'pending' && <><button className="primary" onClick={() => update(driver.uid, 'approved')} disabled={!driver.vehicle?.isVerified}>Approve</button><button onClick={() => update(driver.uid, 'rejected')}>Reject</button></>}{driver.driverStatus === 'approved' && <button onClick={() => update(driver.uid, 'suspended')}>Suspend</button>}{todaId && driver.driverStatus === 'suspended' && <button className="primary" onClick={() => update(driver.uid, 'approved')} disabled={!driver.vehicle?.isVerified}>Restore</button>}</span></div>)}{drivers.length === 0 && <p className="muted">No driver applications are available in this scope.</p>}</div></section>;
}

function DriversPage({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const reload = useCallback(() => adminApi.drivers(todaId).then(setDrivers), [todaId]);
  useEffect(() => {
    void reload();
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') void reload();
    }, 5000);
    return () => window.clearInterval(timer);
  }, [reload]);
  async function update(driver: Driver, status: 'approved' | 'suspended' | 'rejected', license?: { number: string; expiry: string }) {
    try {
      await adminApi.setDriverStatus(driver.uid, status, license);
      onMessage(`Driver ${status}.`);
      await reload();
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to update driver.');
    }
  }
  async function verifyVehicle(driver: Driver, isVerified: boolean) {
    try {
      await adminApi.setVehicleVerification(driver.uid, isVerified);
      onMessage(`Vehicle ${isVerified ? 'verified' : 'verification removed'}.`);
      await reload();
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to update vehicle verification.');
    }
  }
  const fullName = (driver: Driver) =>
    [driver.applicant?.firstName, driver.applicant?.middleName, driver.applicant?.lastName]
      .filter(Boolean).join(' ') || 'Unnamed applicant';
  const documentLinks = (driver: Driver) => [
    ['Profile photo', driver.profilePhotoUrl],
    ['Licence front', driver.driverLicenseFrontUrl],
    ['Licence back', driver.driverLicenseBackUrl],
    ['Government ID', driver.governmentIdUrl],
    ['OR document', driver.orDocumentUrl],
    ['CR document', driver.crDocumentUrl],
    ['Vehicle photo', driver.vehiclePhotoUrl],
  ].filter((entry): entry is [string, string] => Boolean(entry[1]));
  return <section className="panel wide">
    <h2>{todaId ? 'Driver applications assigned to this TODA' : 'All driver registrations'}</h2>
    <p className="muted">{todaId ? 'Review the camera-captured identity and vehicle documents. Record the licence details shown in the images before approval.' : 'Developer oversight can suspend active accounts; routine approval and licence verification remain with each TODA.'}</p>
    <div className="table">{drivers.map((driver) => <div className="row driver" key={driver.uid}>
      <span className="applicant">
        <b>{fullName(driver)}</b>
        <small>{driver.applicant?.email || 'Email unavailable'} · {driver.applicant?.phoneNumber || 'Phone unavailable'}</small>
        <small>Date of birth: {driver.applicant?.dateOfBirth ? new Date(driver.applicant.dateOfBirth).toLocaleDateString('en-PH') : 'Not supplied (legacy registration)'}</small>
        <small>TODA: {driver.todaId} · Licence: {driver.licenseNumber || 'Awaiting TODA verification'}</small>
        <small>Vehicle: {driver.vehicle?.vehicleNumber || driver.vehicle?.model || 'Not registered'} · {driver.vehicle?.plateNumber || 'No plate'} · {driver.vehicle?.isVerified ? 'verified' : 'not verified'}</small>
        <details><summary>Registration documents ({documentLinks(driver).length})</summary><div className="document-links">{documentLinks(driver).map(([name, url]) => <a href={url} target="_blank" rel="noreferrer" key={name}>{name}</a>)}</div></details>
        <small className="technical-id">Firebase UID: {driver.uid}</small>
      </span>
      <span className={driver.driverStatus === 'pending' ? 'warning' : driver.driverStatus === 'approved' ? 'ok' : ''}>{driver.driverStatus}</span>
      <span>{todaId && <>★ {driver.rating || 0} from {driver.ratingCount || 0} ratings<br /></>}<small>{driver.completedTrips || 0} trips · {peso(driver.totalEarnings || 0)} net earnings</small></span>
      <span className="actions">
        {todaId && driver.vehicle && <button onClick={() => verifyVehicle(driver, !driver.vehicle?.isVerified)}>{driver.vehicle.isVerified ? 'Remove vehicle verification' : 'Verify vehicle'}</button>}
        {todaId && (driver.driverStatus === 'pending' || driver.driverStatus === 'suspended') && <DriverReviewActions driver={driver} onApprove={(license) => update(driver, 'approved', license)} onReject={driver.driverStatus === 'pending' ? () => update(driver, 'rejected') : undefined} />}
        {driver.driverStatus === 'approved' && <button onClick={() => update(driver, 'suspended')}>Suspend</button>}
      </span>
    </div>)}{drivers.length === 0 && <p className="muted">No driver applications are available in this scope.</p>}</div>
  </section>;
}

function DriverReviewActions({ driver, onApprove, onReject }: {
  driver: Driver;
  onApprove: (license?: { number: string; expiry: string }) => void;
  onReject?: () => void;
}) {
  const [number, setNumber] = useState(driver.licenseNumber || '');
  const [expiry, setExpiry] = useState(driver.licenseExpiry ? driver.licenseExpiry.slice(0, 10) : '');
  const existingLicenseIsCurrent = Boolean(driver.licenseNumber && driver.licenseExpiry && new Date(driver.licenseExpiry).getTime() > Date.now());
  const suppliedLicenseIsComplete = Boolean(number.trim() && expiry && new Date(`${expiry}T23:59:59`).getTime() > Date.now());
  return <>
    {!existingLicenseIsCurrent && <div className="license-review">
      <label>Licence number<input value={number} onChange={(event) => setNumber(event.target.value)} placeholder="From licence image" /></label>
      <label>Licence expiry<input type="date" min={new Date().toISOString().slice(0, 10)} value={expiry} onChange={(event) => setExpiry(event.target.value)} /></label>
    </div>}
    <button className="primary" onClick={() => onApprove(existingLicenseIsCurrent ? undefined : { number: number.trim(), expiry })} disabled={!driver.vehicle?.isVerified || (!existingLicenseIsCurrent && !suppliedLicenseIsComplete)}>{driver.driverStatus === 'suspended' ? 'Restore' : 'Approve'}</button>
    {onReject && <button onClick={onReject}>Reject</button>}
  </>;
}

function RatingsPage() {
  const [ratings, setRatings] = useState<DriverRatingRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const reload = useCallback(() => {
    void adminApi.ratingPage().then((page) => {
      setRatings(page.items);
      setNextCursor(page.nextCursor);
    }).finally(() => setLoading(false));
  }, []);
  async function loadMore() {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const page = await adminApi.ratingPage(nextCursor);
      setRatings((current) => [
        ...current,
        ...page.items.filter((item) => !current.some((entry) => entry.id === item.id)),
      ]);
      setNextCursor(page.nextCursor);
    } finally {
      setLoadingMore(false);
    }
  }
  useEffect(() => {
    reload();
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') reload();
    }, 5000);
    return () => window.clearInterval(timer);
  }, [reload]);
  return <section className="panel wide"><h2>Passenger ratings</h2><p className="muted">Ratings are immutable trip records. TODA administrators see only feedback for drivers assigned to their TODA.</p>{loading && <p>Loading ratings…</p>}<div className="table">{ratings.map((rating) => <div className="row report" key={rating.id}><span><b>{rating.rating} ★ for {rating.driverName || 'Driver'}</b><small>Passenger: {rating.passengerName || 'Passenger'}</small><small>TODA: {rating.todaName || rating.todaId || 'Not recorded'}</small></span><span>{rating.comment || 'Passenger left a star rating without a comment.'}</span><span><small>{rating.createdAt ? new Date(rating.createdAt).toLocaleString('en-PH') : 'Date unavailable'}</small><br /><small className="technical-id">Booking: {rating.bookingId}</small></span></div>)}{!loading && ratings.length === 0 && <p className="muted">No ratings are available in this scope.</p>}{nextCursor && <button onClick={loadMore} disabled={loadingMore}>{loadingMore ? 'Loading…' : 'Load older ratings'}</button>}</div></section>;
}

function LegacyReportsPage({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [reports, setReports] = useState<Report[]>([]); const reload = useCallback(() => adminApi.reports(todaId).then(setReports), [todaId]); useEffect(() => { reload(); }, [reload]);
  async function action(id: string, status: string) { const note = window.prompt('Action note (optional):') ?? ''; try { await adminApi.resolveReport(id, status, note); onMessage(`Report ${status}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update report.'); } }
  async function suspendReportedUser(uid: string) { if (!window.confirm('Suspend this reported account? This prevents it from using VolTrike.')) return; try { await adminApi.setUserStatus(uid, false); onMessage('Reported account suspended.'); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to suspend account.'); } }
  return <section className="panel wide"><h2>Ride reports</h2><div className="table">{reports.map((report) => <div className="row report" key={report.id}><span><b>{report.category}</b><small>Booking {report.bookingId}</small><small>Reported user: {report.reportedUserId}</small></span><span>{report.details || 'No details provided.'}</span><span className={report.status === 'open' ? 'warning' : 'ok'}>{report.status}</span>{report.status === 'open' && <span className="actions"><button onClick={() => action(report.id, 'resolved')}>Resolve</button><button onClick={() => action(report.id, 'dismissed')}>Dismiss</button>{!todaId && <button onClick={() => suspendReportedUser(report.reportedUserId)}>Suspend user</button>}</span>}</div>)}{reports.length === 0 && <p className="muted">No reports are available in this scope.</p>}</div></section>;
}

function ReportsPage({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [reports, setReports] = useState<Report[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [loadingMore, setLoadingMore] = useState(false);
  const reload = useCallback(async () => {
    const page = await adminApi.reportPage(null, search);
    setReports(page.items);
    setNextCursor(page.nextCursor);
  }, [search]);
  useEffect(() => {
    void reload();
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') void reload();
    }, 5000);
    return () => window.clearInterval(timer);
  }, [reload]);
  async function loadMore() {
    if (!nextCursor) return;
    setLoadingMore(true);
    try {
      const page = await adminApi.reportPage(nextCursor, search);
      setReports((current) => [...current, ...page.items]);
      setNextCursor(page.nextCursor);
    } finally {
      setLoadingMore(false);
    }
  }
  async function action(id: string, status: string) {
    const note = window.prompt('Action note (optional):') ?? '';
    try { await adminApi.resolveReport(id, status, note); onMessage(`Report ${status}.`); await reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update report.'); }
  }
  async function suspendReportedUser(report: Report) {
    if (!window.confirm('Suspend this reported account? This prevents it from using VolTrike.')) return;
    try { await adminApi.setUserStatus(report.reportedUserId, false, report.id); onMessage('Reported account suspended for evaluation.'); await reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to suspend account.'); }
  }
  async function restoreReportedUser(report: Report) {
    if (!window.confirm('Restore this account after evaluation?')) return;
    try {
      await adminApi.setUserStatus(report.reportedUserId, true, report.id);
      onMessage(report.reportedRole === 'driver' ? 'User account restored. The driver still needs TODA approval before driving.' : 'Passenger account restored.');
      await reload();
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to restore account.');
    }
  }
  const name = (person: Report['reporter'] | undefined, fallback: string) => [person?.firstName, person?.middleName, person?.lastName].filter(Boolean).join(' ') || fallback;
  const contact = (person: Report['reporter'] | undefined) => [person?.email, person?.phoneNumber].filter(Boolean).join(' · ');
  return <section className="panel wide"><h2>{todaId ? 'Driver reports for this TODA' : 'All passenger and driver reports'}</h2><p className="muted">{todaId ? 'TODA administrators receive reports about their drivers. Passenger-account reports are evaluated by the Developer Admin.' : 'Developer Admin receives every report. Reports about drivers are also synchronized to the driver’s TODA.'}</p><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search reports" aria-label="Search reports" /><div className="table">{reports.map((report) => <div className="row report report-card" key={report.id}><span><b>{report.category}</b><small>Booking {report.bookingId}</small><small>{report.reportedRole ? `Reported ${report.reportedRole}` : 'Legacy report'}</small><small className={report.status === 'open' ? 'warning' : 'ok'}>{report.status}</small></span><span className="report-parties"><b>Reported by: {name(report.reporter, 'Passenger identity restricted')}</b><small>{contact(report.reporter) || (report.reporter ? 'No contact details' : 'Restricted outside TODA scope')}</small><b>Reported account: {name(report.reportedUser, 'Driver or passenger identity restricted')}</b><small>{contact(report.reportedUser) || (report.reportedUser ? 'No contact details' : 'Restricted outside TODA scope')}</small></span><span>{report.details || 'No details provided.'}{report.action && <small>Action: {report.action}</small>}</span>{report.status === 'open' && <span className="actions"><button onClick={() => action(report.id, 'resolved')}>Resolve</button><button onClick={() => action(report.id, 'dismissed')}>Dismiss</button>{!todaId && report.reportedUser?.isActive !== false && <button onClick={() => suspendReportedUser(report)}>Suspend reported account</button>}</span>}{!todaId && report.reportedUser?.isActive === false && <span className="actions"><button className="primary" onClick={() => restoreReportedUser(report)}>Restore after evaluation</button></span>}</div>)}{reports.length === 0 && <p className="muted">No reports are available in this scope.</p>}{nextCursor && <button onClick={loadMore} disabled={loadingMore}>{loadingMore ? 'Loading…' : 'Load older reports'}</button>}</div></section>;
}

function OperationsPage({ session }: { session: AdminSession }) {
  const [items, setItems] = useState<BookingOperation[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const load = useCallback(async (cursor?: string | null, append = false) => {
    setLoading(true);
    try {
      const page = await adminApi.bookingPage(cursor, search);
      setItems((current) => append ? [...current, ...page.items] : page.items);
      setNextCursor(page.nextCursor);
      setError('');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to load Firebase bookings.');
    } finally {
      setLoading(false);
    }
  }, [search]);

  useEffect(() => {
    void load();
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') void load();
    }, 5000);
    return () => window.clearInterval(timer);
  }, [load]);

  async function resolveDispute(booking: BookingOperation) {
    const resolution = window.prompt('Settlement dispute resolution:')?.trim();
    if (!resolution) return;
    await adminApi.resolveSettlementDispute(booking.bookingId, resolution);
    await load();
  }

  return <section className="panel wide">
    <h2>{session.role === 'developer_admin' ? 'All bookings and cash settlements' : 'TODA bookings and cash settlements'}</h2>
    <p className="muted">{session.role === 'developer_admin' ? 'Every Firebase booking is available here, including pending, active, completed, and cancelled rides.' : 'Firebase restricts this list to bookings assigned to a driver in your TODA.'} Search names, booking reference, driver ID, plate, receipt, or lifecycle status.</p>
    <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search ride operations" aria-label="Search ride operations" />
    {error && <div className="notice">{error}</div>}
    <div className="table">
      {items.map((booking) => <div className="row operation" key={booking.bookingId}>
        <span><b>{booking.passengerName}</b><small>{booking.pickupAddress} → {booking.destinationAddress}</small><small className="technical-id">Booking: {booking.bookingId}</small></span>
        <span><b>{booking.driverName || 'Searching for driver'}</b><small>{booking.plateNumber || 'No plate assigned'} · {booking.todaName || 'No TODA assigned'}</small></span>
        <span className={booking.status === 'cancelled' ? 'warning' : booking.status === 'completed' ? 'ok' : ''}>{booking.status}{booking.cancellationCode && <small>{booking.cancellationCode.split('_').join(' ')}</small>}</span>
        <span><b>{peso(booking.amountDue)}</b><small>{booking.paymentMethod} · {booking.settlementStatus.split('_').join(' ')}</small><small>Adjustment: {booking.adjustmentStatus.split('_').join(' ')}</small>{booking.receiptNumber && <small>Receipt: {booking.receiptNumber}</small>}{booking.adjustmentStatus === 'disputed' && <button onClick={() => resolveDispute(booking)}>Resolve dispute</button>}</span>
      </div>)}
      {loading && items.length === 0 && <p className="muted">Loading Firebase bookings…</p>}
      {!loading && !error && items.length === 0 && <p className="muted">No ride operations match this search.</p>}
    </div>
    <button onClick={() => load(nextCursor, true)} disabled={loading || !nextCursor}>{loading ? 'Loading…' : nextCursor ? 'Load next page' : 'End of results'}</button>
  </section>;
}

function LegacySafetyIncidentsPage({ session }: { session: AdminSession }) {
  const [incidents, setIncidents] = useState<SafetyIncident[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    try {
      const page = await adminApi.safetyIncidentPage();
      setIncidents(page.items);
      setNextCursor(page.nextCursor);
      setError('');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to load Firebase safety incidents.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') void refresh();
    }, 5000);
    return () => window.clearInterval(timer);
  }, [refresh]);

  async function loadMore() {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const page = await adminApi.safetyIncidentPage(nextCursor);
      setIncidents((current) => [
        ...current,
        ...page.items.filter((item) => !current.some((entry) => entry.id === item.id)),
      ]);
      setNextCursor(page.nextCursor);
      setError('');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to load more safety incidents.');
    } finally {
      setLoadingMore(false);
    }
  }

  const location = (incident: SafetyIncident) => {
    const point = incident.driverLocation;
    if (!point || !Number.isFinite(point.latitude) || !Number.isFinite(point.longitude)) return 'Driver location unavailable';
    const capturedAt = point.timestamp ? new Date(point.timestamp).toLocaleString('en-PH') : 'time unavailable';
    return `${point.latitude.toFixed(5)}, ${point.longitude.toFixed(5)} · ${capturedAt}`;
  };

  return <section className="panel wide">
    <h2>{session.role === 'developer_admin' ? 'All TNVS safety incidents' : 'TODA safety incidents'}</h2>
    <p className="muted">{session.role === 'developer_admin' ? 'This list receives every SOS created by a passenger or driver.' : 'Firebase restricts this list to SOS records linked to your TODA.'} Each record includes the trusted booking, participants, ride state, route, TODA, and latest backend driver-location snapshot. External emergency dispatch remains a development placeholder.</p>
    {error && <div className="notice">{error}</div>}
    <div className="table">
      {incidents.map((incident) => <div className="row report" key={incident.id}>
        <span><b>{incident.category.toUpperCase()} · {incident.status}</b><small>Booking {incident.bookingId}</small><small>{incident.createdAt ? new Date(incident.createdAt).toLocaleString('en-PH') : 'Date unavailable'}</small></span>
        <span><b>Reported by {incident.reporterRole}</b><small>Passenger: {incident.passengerName || incident.passengerId}</small><small>Driver: {incident.driverName || incident.driverId || 'Not assigned'}</small><small>TODA: {incident.todaName || incident.todaId || 'Not assigned'}</small></span>
        <span className="warning">{incident.bookingStatus}<small>{incident.pickupAddress || 'Pickup unavailable'} → {incident.destinationAddress || 'Destination unavailable'}</small></span>
        <span>{incident.requiresManualEmergencyContact ? 'Manual emergency contact required' : incident.emergencyDispatch}<small>{location(incident)}</small></span>
      </div>)}
      {loading && incidents.length === 0 && <p className="muted">Loading Firebase safety incidents…</p>}
      {!loading && !error && incidents.length === 0 && <p className="muted">No safety incidents in this scope.</p>}
    </div>
    {nextCursor && <button onClick={loadMore} disabled={loadingMore}>{loadingMore ? 'Loading…' : 'Load more incidents'}</button>}
  </section>;
}

function SafetyIncidentsPage({ session }: { session: AdminSession }) {
  const [incidents, setIncidents] = useState<SafetyIncident[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [browserAlertsEnabled, setBrowserAlertsEnabled] = useState(
    typeof Notification !== 'undefined' && Notification.permission === 'granted',
  );
  const knownUrgentIds = useRef<Set<string> | null>(null);
  const refresh = useCallback(async () => {
    try {
      const page = await adminApi.safetyIncidentPage();
      setIncidents(page.items);
      const urgent = page.items.filter((incident) =>
        incident.status === 'open' &&
        (incident.responseStatus || 'reported') === 'reported');
      const previous = knownUrgentIds.current;
      if (browserAlertsEnabled && previous) {
        urgent
          .filter((incident) => !previous.has(incident.id))
          .forEach((incident) => {
            const notification = new Notification(
              'VolTrike SOS requires acknowledgement',
              {
                body: `${incident.reporterRole} · Booking ${incident.bookingId}`,
                tag: incident.id,
                requireInteraction: true,
              },
            );
            notification.onclick = () => {
              window.focus();
              setSelectedId(incident.id);
              notification.close();
            };
            window.navigator.vibrate?.([250, 100, 250]);
          });
      }
      knownUrgentIds.current = new Set(urgent.map((incident) => incident.id));
      setError('');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to load safety incidents.');
    } finally {
      setLoading(false);
    }
  }, [browserAlertsEnabled]);
  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') void refresh();
    }, 5000);
    return () => window.clearInterval(timer);
  }, [refresh]);
  const mappable = incidents.filter((incident) =>
    Number.isFinite(incident.driverLocation?.latitude) &&
    Number.isFinite(incident.driverLocation?.longitude));
  const points = mappable.map((incident) => ({
    id: incident.id,
    latitude: incident.driverLocation!.latitude,
    longitude: incident.driverLocation!.longitude,
    title: `SOS · ${incident.driverName || incident.reporterRole}`,
    details: [
      `Booking: ${incident.bookingId}`,
      `Status: ${incident.bookingStatus.split('_').join(' ')}`,
      incident.todaName || incident.todaId || 'TODA unavailable',
    ],
    urgent: incident.status === 'open' &&
      (incident.responseStatus || 'reported') === 'reported',
  }));
  async function enableBrowserAlerts() {
    if (typeof Notification === 'undefined') {
      setError('This browser does not support system notifications. Keep the Safety Incidents page open.');
      return;
    }
    const permission = await Notification.requestPermission();
    const enabled = permission === 'granted';
    setBrowserAlertsEnabled(enabled);
    knownUrgentIds.current = enabled ? new Set() : null;
    if (!enabled) {
      setError('Browser notifications were not allowed. SOS records still update on this page every five seconds.');
      return;
    }
    setError('');
  }
  function contact911() {
    if (window.confirm('Call the Philippine Unified 911 emergency hotline now? This starts a phone call; it does not silently dispatch emergency services.')) {
      window.location.href = 'tel:911';
    }
  }
  async function cancelAfterTimeout(incident: SafetyIncident) {
    if (!window.confirm('Cancel this booking because the SOS initiator is still unresponsive after at least five minutes? This action is audited and cannot be used while the passenger is onboard.')) return;
    try {
      await adminApi.cancelBookingForSafety(incident.id);
      await refresh();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to cancel this booking.');
    }
  }
  async function updateResponse(
    incident: SafetyIncident,
    action: 'acknowledge' | 'responding' | 'resolve',
  ) {
    let note = '';
    if (action === 'responding') {
      note = window.prompt('Optional response note, for example “Calling passenger now”:') || '';
    }
    if (action === 'resolve') {
      const resolution = window.prompt('Required resolution note. Explain what was verified and how the incident ended:');
      if (!resolution?.trim()) return;
      note = resolution.trim();
    }
    try {
      await adminApi.updateSafetyIncidentResponse(incident.id, action, note);
      await refresh();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to update the SOS response.');
    }
  }
  const timeoutReached = (incident: SafetyIncident) =>
    Boolean(incident.createdAt &&
      Date.now() - new Date(incident.createdAt).getTime() >= 5 * 60 * 1000);
  return <>
    <section className="panel wide">
      <h2>{session.role === 'developer_admin' ? 'All TNVS safety incidents' : 'TODA safety incidents'}</h2>
      <p className="muted">A real SOS stays active until the reporter marks themselves safe or an administrator records a resolution. New incidents escalate when they remain unacknowledged; cancelling transportation never closes the emergency by itself.</p>
      <div className="safety-email-card">
        <div>
          <b>Administrator safety notifications</b>
          <small>Required transactional SOS email uses the verified administrator account. The dashboard and browser alerts remain the primary live monitoring tools.</small>
        </div>
        <label>Verified administrator email<input type="email" value={session.email || ''} readOnly aria-readonly="true" /></label>
      </div>
      <div className="safety-actions">
        <button className="danger-button" onClick={contact911}>Call Unified 911</button>
        <button onClick={enableBrowserAlerts}>
          {browserAlertsEnabled ? 'Browser SOS alerts enabled' : 'Enable browser SOS alerts'}
        </button>
        <span>For active danger, call first, acknowledge the record, attempt contact, and keep monitoring its latest available map location.</span>
      </div>
      {error && <div className="notice">{error}</div>}
      <Suspense fallback={<div className="map-missing">Loading incident map…</div>}>
        <AdminLocationMap points={points} selectedId={selectedId} />
      </Suspense>
    </section>
    <section className="panel wide">
      <div className="table">{incidents.map((incident) => <div className="row report" key={incident.id}>
        <span><b>{incident.category.toUpperCase()} · {(incident.responseStatus || incident.status).split('_').join(' ')}</b><small>{incident.createdAt ? new Date(incident.createdAt).toLocaleString('en-PH') : 'Date unavailable'}</small><small>Booking {incident.bookingId}</small><small>Alert: {(incident.deliveryStatus || 'legacy record').split('_').join(' ')} · escalation level {incident.escalationLevel || 0}</small></span>
        <span><b>Reported by {incident.reporterRole}</b><small>Passenger: {incident.passengerName || incident.passengerId}</small><small>Driver: {incident.driverName || incident.driverId || 'Not assigned'}</small><small>TODA: {incident.todaName || incident.todaId || 'Not assigned'}</small></span>
        <span className="warning">{incident.bookingStatus.split('_').join(' ')}<small>{incident.pickupAddress || 'Pickup unavailable'} → {incident.destinationAddress || 'Destination unavailable'}</small><small>{incident.locationSource === 'live_driver_location' ? 'Live driver location' : 'SOS location snapshot'}{incident.driverLocation?.timestamp ? ` · ${new Date(incident.driverLocation.timestamp).toLocaleTimeString('en-PH')}` : ''}</small>{incident.lastResponseNote && <small>Latest note: {incident.lastResponseNote}</small>}{incident.resolutionNote && <small>Resolution: {incident.resolutionNote}</small>}</span>
        <span className="actions">
          {incident.driverLocation && <button onClick={() => setSelectedId(incident.id)}>View location</button>}
          <button onClick={contact911}>Call 911</button>
          {!['accidental', 'resolved', 'reporter_safe'].includes(incident.status) && (incident.responseStatus || 'reported') === 'reported' && <button className="primary" onClick={() => updateResponse(incident, 'acknowledge')}>Acknowledge SOS</button>}
          {!['accidental', 'resolved', 'reporter_safe'].includes(incident.status) && !['responding', 'resolved'].includes(incident.responseStatus || 'reported') && <button onClick={() => updateResponse(incident, 'responding')}>Start response</button>}
          {!['accidental', 'resolved', 'reporter_safe'].includes(incident.status) && incident.responseStatus !== 'resolved' && <button onClick={() => updateResponse(incident, 'resolve')}>Resolve with note</button>}
          {incident.status === 'open' && incident.bookingStatus !== 'cancelled' && !incident.bookingCancelledForSafety && <button onClick={() => cancelAfterTimeout(incident)} disabled={!timeoutReached(incident) || ['passenger_on_board', 'payment_confirmation'].includes(incident.bookingStatus)}>Cancel after 5 min unresponsive</button>}
          {incident.status === 'open' && !timeoutReached(incident) && <small>Five-minute contact window still active.</small>}
        </span>
      </div>)}{loading && <p className="muted">Loading safety incidents…</p>}{!loading && incidents.length === 0 && <p className="muted">No safety incidents in this scope.</p>}</div>
    </section>
  </>;
}

function LegacyRouteRestrictionsPage({ onMessage }: { onMessage: (value: string) => void }) {
  const [restrictions, setRestrictions] = useState<RouteRestriction[]>([]);
  const [name, setName] = useState(''); const [type, setType] = useState<RouteRestriction['type']>('prohibited_highway'); const [notes, setNotes] = useState(''); const [points, setPoints] = useState<Point[]>([]);
  const reload = useCallback(() => adminApi.routeRestrictions().then(setRestrictions), []);
  useEffect(() => { reload(); }, [reload]);
  async function create() {
    try { await adminApi.createRouteRestriction(name.trim(), type, 'polygon', points, 0, notes); setName(''); setNotes(''); setPoints([]); onMessage('Route restriction saved. Mobile route selection will avoid it after the next refresh.'); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Enter a name and a three- or four-point area.'); }
  }
  async function toggle(item: RouteRestriction) {
    try { await adminApi.setRouteRestrictionStatus(item.id, !item.isActive); onMessage(`${item.name} ${item.isActive ? 'disabled' : 'enabled'}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update restriction.'); }
  }
  return <><section className="panel wide"><h2>Developer-only route restrictions</h2><p className="muted">Draw a maximum four-point red boundary for a prohibited highway segment, unavailable service area, or restricted crossing. Passenger and driver route selection will choose a safe Google Routes alternative when one is available.</p><div className="form-grid"><input value={name} onChange={(event) => setName(event.target.value)} placeholder="Restriction name, e.g. Circumferential Road highway segment" required /><select value={type} onChange={(event) => setType(event.target.value as RouteRestriction['type'])}><option value="prohibited_highway">Prohibited highway</option><option value="no_service_area">No-service area</option><option value="restricted_crossing">Restricted crossing</option></select></div><PolygonEditor points={points} onChange={setPoints} onFinish={create} maxPoints={4} /><div className="map-actions"><span>{points.length}/4 points</span><button onClick={() => setPoints(points.slice(0, -1))} disabled={!points.length}>Undo point</button><button onClick={() => setPoints([])} disabled={!points.length}>Clear</button><button className="primary" onClick={create} disabled={points.length < 3 || !name.trim()}>Save restriction</button></div><textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Operational reason and driver guidance" /></section><section className="panel wide"><h2>Active and archived restrictions</h2><div className="table">{restrictions.map((item) => <div className="row" key={item.id}><span><b>{item.name}</b><small>{item.type.replace(/_/g, ' ')} · {item.polygon.length} points</small></span><span>{item.notes || 'No guidance'}</span><span className={item.isActive ? 'warning' : 'ok'}>{item.isActive ? 'active' : 'disabled'}</span><span className="actions"><button onClick={() => toggle(item)}>{item.isActive ? 'Disable' : 'Enable'}</button></span></div>)}{restrictions.length === 0 && <p className="muted">No route restrictions configured.</p>}</div></section></>;
}

function LegacyRouteRestrictionsPageV2({ onMessage }: { onMessage: (value: string) => void }) {
  const [restrictions, setRestrictions] = useState<RouteRestriction[]>([]);
  const [name, setName] = useState('');
  const [type, setType] = useState<RouteRestriction['type']>('prohibited_highway');
  const [geometryType, setGeometryType] = useState<'polygon' | 'corridor'>('corridor');
  const [bufferMeters, setBufferMeters] = useState(30);
  const [notes, setNotes] = useState('');
  const [points, setPoints] = useState<Point[]>([]);
  const [completedAreas, setCompletedAreas] = useState<Point[][]>([]);
  const reload = useCallback(() => adminApi.routeRestrictions().then(setRestrictions), []);
  useEffect(() => { reload(); }, [reload]);
  const minimumPoints = geometryType === 'corridor' ? 2 : 3;
  const allAreas = geometryType === 'polygon'
    ? [...completedAreas, ...(points.length >= 3 ? [points] : [])]
    : [points];
  async function create() {
    try {
      await adminApi.createRouteRestriction(name.trim(), type, geometryType, allAreas[0], bufferMeters, notes, allAreas);
      setName(''); setNotes(''); setPoints([]); setCompletedAreas([]); onMessage('Route restriction saved. Mobile route selection will avoid it after the next refresh.'); reload();
    } catch (error) { onMessage(error instanceof Error ? error.message : `Enter a name and at least ${minimumPoints} points.`); }
  }
  async function toggle(item: RouteRestriction) {
    try { await adminApi.setRouteRestrictionStatus(item.id, !item.isActive); onMessage(`${item.name} ${item.isActive ? 'disabled' : 'enabled'}.`); reload(); }
    catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update restriction.'); }
  }
  function changeType(next: RouteRestriction['type']) {
    setType(next); setGeometryType(next === 'prohibited_highway' ? 'corridor' : 'polygon'); setPoints([]); setCompletedAreas([]);
  }
  return <><section className="panel wide"><h2>Highways and prohibited areas</h2><p className="muted">Use a red corridor for a curved or straight highway: click along its centreline, then set the blocked width. Use a polygon for no-service areas and restricted crossings.</p><div className="form-grid"><input value={name} onChange={(event) => setName(event.target.value)} placeholder="Restriction name, e.g. Circumferential Road" required /><select value={type} onChange={(event) => changeType(event.target.value as RouteRestriction['type'])}><option value="prohibited_highway">Prohibited highway corridor</option><option value="no_service_area">No-service polygon</option><option value="restricted_crossing">Restricted crossing polygon</option></select>{geometryType === 'corridor' && <label>Highway buffer (metres)<input type="number" min="5" max="200" value={bufferMeters} onChange={(event) => setBufferMeters(Number(event.target.value))} /></label>}</div><PolygonEditor points={points} onChange={setPoints} onFinish={create} geometryMode={geometryType === 'corridor' ? 'polyline' : 'polygon'} /><div className="map-actions"><span>{points.length} points · {geometryType === 'corridor' ? `${bufferMeters} m red corridor` : 'red prohibited polygon'}</span><button onClick={() => setPoints(points.slice(0, -1))} disabled={!points.length}>Undo point</button><button onClick={() => setPoints([])} disabled={!points.length}>Clear</button><button className="primary" onClick={create} disabled={points.length < minimumPoints || !name.trim()}>Save restriction</button></div><textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Operational reason and driver guidance" /></section><section className="panel wide"><h2>Active and archived restrictions</h2><div className="table">{restrictions.map((item) => <div className="row" key={item.id}><span><b>{item.name}</b><small>{item.type.replace(/_/g, ' ')} · {item.geometryType === 'corridor' ? `${item.polygon.length} centreline points · ${item.bufferMeters || 0} m buffer` : `${item.polygon.length} polygon points`}</small></span><span>{item.notes || 'No guidance'}</span><span className={item.isActive ? 'warning' : 'ok'}>{item.isActive ? 'active' : 'disabled'}</span><span className="actions"><button onClick={() => toggle(item)}>{item.isActive ? 'Disable' : 'Enable'}</button></span></div>)}{restrictions.length === 0 && <p className="muted">No route restrictions configured.</p>}</div></section></>;
}

function RouteRestrictionsPage({ onMessage }: { onMessage: (value: string) => void }) {
  const [restrictions, setRestrictions] = useState<RouteRestriction[]>([]); const [name, setName] = useState(''); const [type, setType] = useState<RouteRestriction['type']>('prohibited_highway'); const [geometryType, setGeometryType] = useState<'polygon' | 'corridor'>('corridor'); const [bufferMeters, setBufferMeters] = useState(30); const [notes, setNotes] = useState(''); const [points, setPoints] = useState<Point[]>([]); const [completedAreas, setCompletedAreas] = useState<Point[][]>([]);
  const reload = useCallback(() => adminApi.routeRestrictions().then(setRestrictions), []); useEffect(() => { reload(); }, [reload]);
  const allAreas = geometryType === 'polygon' ? [...completedAreas, ...(points.length >= 3 ? [points] : [])] : [points]; const minimumPoints = geometryType === 'corridor' ? 2 : 3;
  function addArea() { if (points.length >= 3) { setCompletedAreas([...completedAreas, points]); setPoints([]); } }
  async function create() { try { await adminApi.createRouteRestriction(name.trim(), type, geometryType, allAreas[0], bufferMeters, notes, allAreas); setName(''); setNotes(''); setPoints([]); setCompletedAreas([]); onMessage('Route restriction saved. Mobile route selection will avoid it after the next refresh.'); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to save restriction.'); } }
  async function toggle(item: RouteRestriction) { try { await adminApi.setRouteRestrictionStatus(item.id, !item.isActive); onMessage(`${item.name} ${item.isActive ? 'disabled' : 'enabled'}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update restriction.'); } }
  function changeType(next: RouteRestriction['type']) { setType(next); setGeometryType(next === 'prohibited_highway' ? 'corridor' : 'polygon'); setPoints([]); setCompletedAreas([]); }
  return <><section className="panel wide"><h2>Highways and prohibited areas</h2><p className="muted">A highway is one buffered red centreline. A no-service or crossing restriction may contain several disconnected red polygons.</p><div className="form-grid"><input value={name} onChange={(event) => setName(event.target.value)} placeholder="Restriction name" required /><select value={type} onChange={(event) => changeType(event.target.value as RouteRestriction['type'])}><option value="prohibited_highway">Prohibited highway corridor</option><option value="no_service_area">No-service MultiPolygon</option><option value="restricted_crossing">Restricted crossing MultiPolygon</option></select>{geometryType === 'corridor' && <label>Highway buffer (metres)<input type="number" min="5" max="200" value={bufferMeters} onChange={(event) => setBufferMeters(Number(event.target.value))} /></label>}</div><PolygonEditor points={points} completedAreas={geometryType === 'polygon' ? completedAreas : []} onChange={setPoints} onFinish={geometryType === 'polygon' ? addArea : create} geometryMode={geometryType === 'corridor' ? 'polyline' : 'polygon'} /><div className="map-actions"><span>{geometryType === 'polygon' ? `${allAreas.length} area(s) · current shape ${points.length} points` : `${points.length} centreline points · ${bufferMeters} m buffer`}</span><button onClick={() => setPoints(points.slice(0, -1))} disabled={!points.length}>Undo point</button>{geometryType === 'polygon' && <button onClick={addArea} disabled={points.length < 3 || completedAreas.length >= 19}>Add another area</button>}<button onClick={() => { setPoints([]); setCompletedAreas([]); }} disabled={!points.length && !completedAreas.length}>Clear all</button><button className="primary" onClick={create} disabled={allAreas.length === 0 || !name.trim()}>Save restriction</button></div><textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Operational reason and driver guidance" /></section><section className="panel wide"><h2>Active and archived restrictions</h2><div className="table">{restrictions.map((item) => <div className="row" key={item.id}><span><b>{item.name}</b><small>{item.type.replace(/_/g, ' ')} · {item.geometryType === 'corridor' ? `${item.polygon.length} centreline points · ${item.bufferMeters || 0} m buffer` : `${item.areas?.length || 1} polygon areas`}</small></span><span>{item.notes || 'No guidance'}</span><span className={item.isActive ? 'warning' : 'ok'}>{item.isActive ? 'active' : 'disabled'}</span><span className="actions"><button onClick={() => toggle(item)}>{item.isActive ? 'Disable' : 'Enable'}</button></span></div>)}</div></section></>;
}

function LegacyCoveragePage({ session, onMessage }: { session: AdminSession; onMessage: (value: string) => void }) {
  const [todas, setTodas] = useState<Toda[]>([]); const [todaId, setTodaId] = useState(session.todaId || ''); const [points, setPoints] = useState<Point[]>([]); const [notes, setNotes] = useState(''); const [zones, setZones] = useState<ZoneRequest[]>([]); const [editingZoneId, setEditingZoneId] = useState<string | null>(null);
  const reload = useCallback(async () => { const scope = session.role === 'developer_admin' ? undefined : session.todaId!; const [todoList, zoneList] = await Promise.all([adminApi.todas(), adminApi.zones(scope)]); setTodas(todoList); setZones(zoneList); if (!todaId && todoList[0]) setTodaId(todoList[0].id); }, [session, todaId]); useEffect(() => { reload(); }, [reload]);
  async function submit() { try { if (editingZoneId) { await adminApi.updateZone(editingZoneId, points, notes); onMessage('Zone request polygon updated. You can now approve or decline it.'); } else { await adminApi.submitZone(todaId, points, notes); onMessage('Polygon zone request submitted for developer review.'); } setPoints([]); setNotes(''); setEditingZoneId(null); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'A polygon needs at least three points.'); } }
  async function review(id: string, status: string) { try { await adminApi.reviewZone(id, status); onMessage(`Zone request ${status}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to review zone.'); } }
  const selectedName = useMemo(() => todas.find((toda) => toda.id === todaId)?.name || 'selected TODA', [todas, todaId]);
  return <><section className="panel wide"><h2>{session.role === 'developer_admin' ? 'Create or review coverage areas' : 'Request TODA coverage area'}</h2><p className="muted">Choose a TODA, then left-click the map to add points. Press <b>Enter</b> or use Finish polygon when at least three points have been added. The developer admin approves or declines the request.</p>{session.role === 'developer_admin' && <select value={todaId} onChange={(e) => setTodaId(e.target.value)}><option value="">Select TODA</option>{todas.map((toda) => <option key={toda.id} value={toda.id}>{toda.name}</option>)}</select>}<Suspense fallback={<div className="map-missing">Loading Mapbox coverage editor…</div>}><PolygonEditor points={points} onChange={setPoints} onFinish={submit} /></Suspense><div className="map-actions"><span>{points.length} points for {selectedName}</span><button onClick={() => setPoints(points.slice(0, -1))} disabled={!points.length}>Undo point</button><button onClick={() => { setPoints([]); setEditingZoneId(null); }} disabled={!points.length}>Clear</button><button className="primary" onClick={submit} disabled={points.length < 3 || !todaId}>{editingZoneId ? 'Save edited polygon' : 'Finish polygon & request review'}</button></div><textarea value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Route/terminal notes for the reviewer" /></section><section className="panel wide"><h2>{session.role === 'developer_admin' ? 'Pending zone requests' : 'My TODA zone requests'}</h2><div className="table">{zones.map((zone) => <div className="row" key={zone.id}><span><b>{zone.todaId}</b><small>{zone.polygon.length} polygon points</small></span><span>{zone.notes || 'No notes'}</span><span className={zone.status === 'pending' ? 'warning' : 'ok'}>{zone.status}</span>{session.role === 'developer_admin' && zone.status === 'pending' && <span className="actions"><button onClick={() => { setTodaId(zone.todaId); setPoints(zone.polygon); setNotes(zone.notes || ''); setEditingZoneId(zone.id); }}>Edit</button><button onClick={() => review(zone.id, 'approved')}>Approve</button><button onClick={() => review(zone.id, 'declined')}>Decline</button></span>}</div>)}</div></section></>;
}

function CoveragePage({ session, onMessage }: { session: AdminSession; onMessage: (value: string) => void }) {
  const [todas, setTodas] = useState<Toda[]>([]);
  const [todaId, setTodaId] = useState(session.todaId || '');
  const [points, setPoints] = useState<Point[]>([]);
  const [completedAreas, setCompletedAreas] = useState<Point[][]>([]);
  const [notes, setNotes] = useState('');
  const [zones, setZones] = useState<ZoneRequest[]>([]);
  const [editingZoneId, setEditingZoneId] = useState<string | null>(null);
  const reload = useCallback(async () => { const scope = session.role === 'developer_admin' ? undefined : session.todaId!; const [todoList, zoneList] = await Promise.all([adminApi.todas(), adminApi.zones(scope)]); setTodas(todoList); setZones(zoneList); if (!todaId && todoList[0]) setTodaId(todoList[0].id); }, [session, todaId]);
  useEffect(() => { reload(); }, [reload]);
  const areas = [...completedAreas, ...(points.length >= 3 ? [points] : [])];
  function addAnotherArea() { if (points.length >= 3) { setCompletedAreas([...completedAreas, points]); setPoints([]); } }
  async function submit() {
    if (areas.length === 0) { onMessage('Draw at least one polygon with three points.'); return; }
    try {
      if (editingZoneId) await adminApi.updateZone(editingZoneId, areas[0], notes, areas);
      else await adminApi.submitZone(todaId, areas[0], notes, areas);
      setPoints([]); setCompletedAreas([]); setNotes(''); setEditingZoneId(null); onMessage(editingZoneId ? 'Coverage request polygons updated.' : 'Coverage request submitted for developer review.'); reload();
    } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to save coverage polygons.'); }
  }
  async function review(id: string, status: string) { try { await adminApi.reviewZone(id, status); onMessage(`Zone request ${status}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to review zone.'); } }
  const selectedName = useMemo(() => todas.find((toda) => toda.id === todaId)?.name || 'selected TODA', [todas, todaId]);
  function editZone(zone: ZoneRequest) { const zoneAreas = zone.areas?.length ? zone.areas : [zone.polygon]; setTodaId(zone.todaId); setCompletedAreas(zoneAreas.slice(0, -1)); setPoints(zoneAreas[zoneAreas.length - 1] || []); setNotes(zone.notes || ''); setEditingZoneId(zone.id); }
  return <><section className="panel wide"><h2>{session.role === 'developer_admin' ? 'Create or review coverage areas' : 'Request TODA coverage area'}</h2><p className="muted">Create one or several disconnected operating polygons. Select Add another area after finishing each shape; the developer approves the complete TODA coverage request together.</p>{session.role === 'developer_admin' && <select value={todaId} onChange={(event) => setTodaId(event.target.value)}><option value="">Select TODA</option>{todas.map((toda) => <option key={toda.id} value={toda.id}>{toda.name}</option>)}</select>}<Suspense fallback={<div className="map-missing">Loading Mapbox coverage editor…</div>}><PolygonEditor points={points} completedAreas={completedAreas} onChange={setPoints} onFinish={addAnotherArea} /></Suspense><div className="map-actions"><span>{areas.length} area{areas.length === 1 ? '' : 's'} for {selectedName} · current shape: {points.length} points</span><button onClick={() => setPoints(points.slice(0, -1))} disabled={!points.length}>Undo point</button><button onClick={addAnotherArea} disabled={points.length < 3 || completedAreas.length >= 19}>Add another area</button><button onClick={() => { setPoints([]); setCompletedAreas([]); setEditingZoneId(null); }} disabled={!points.length && !completedAreas.length}>Clear all</button><button className="primary" onClick={submit} disabled={areas.length === 0 || !todaId}>{editingZoneId ? 'Save coverage polygons' : 'Submit coverage request'}</button></div><textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Route/terminal notes for the reviewer" /></section><section className="panel wide"><h2>{session.role === 'developer_admin' ? 'Pending zone requests' : 'My TODA zone requests'}</h2><div className="table">{zones.map((zone) => <div className="row" key={zone.id}><span><b>{zone.todaId}</b><small>{zone.areas?.length || 1} area{(zone.areas?.length || 1) === 1 ? '' : 's'} · {(zone.areas || [zone.polygon]).reduce((total, area) => total + area.length, 0)} points</small></span><span>{zone.notes || 'No notes'}</span><span className={zone.status === 'pending' ? 'warning' : 'ok'}>{zone.status}</span>{session.role === 'developer_admin' && zone.status === 'pending' && <span className="actions"><button onClick={() => editZone(zone)}>Edit</button><button onClick={() => review(zone.id, 'approved')}>Approve</button><button onClick={() => review(zone.id, 'declined')}>Decline</button></span>}</div>)}</div></section></>;
}
