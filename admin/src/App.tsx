import { FormEvent, lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createUserWithEmailAndPassword, onAuthStateChanged, signInWithEmailAndPassword, signOut, type User } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from './firebase';
import { adminApi } from './admin-api';
import { loadPhilippineLocations, type Barangay, type City, type Region } from './data/locations';
import type { AdminSession, BookingOperation, Driver, DriverRatingRecord, FareConfig, LiveDriver, OverviewAnalytics, OverviewAnalyticsDay, Point, Report, RouteRestriction, SafetyIncident, Toda, TodaCommissionDriverSummary, TodaCommissionReportItem, TodaCommissionReportSummary, TodaRegistration, ZoneRequest } from './types';
import {
  enableAdminWebPush,
  listenForAdminPush,
  removeAdminWebPush,
  syncAdminWebPush,
  webPushSetupMessage,
  type AdminPushAlert,
  type WebPushResult,
} from './web-push';
import './registration.css';
import './driver-review.css';

// Mapbox is substantial; load it only when an administrator opens a map page.
const PolygonEditor = lazy(() => import('./components/PolygonEditor').then((module) => ({ default: module.PolygonEditor })));
const AdminLocationMap = lazy(() => import('./components/AdminLocationMap').then((module) => ({ default: module.AdminLocationMap })));
const ViolationsPage = lazy(() => import('./components/ViolationsPage').then((module) => ({ default: module.ViolationsPage })));
const ChatSafetyPage = lazy(() => import('./components/ChatSafetyPage').then((module) => ({ default: module.ChatSafetyPage })));

type Page = 'overview' | 'todas' | 'fares' | 'drivers' | 'live_drivers' | 'commission' | 'ratings' | 'operations' | 'safety' | 'violations' | 'reports' | 'coverage' | 'route_rules' | 'chat_safety';
const pages = new Set<Page>(['overview', 'todas', 'fares', 'drivers', 'live_drivers', 'commission', 'ratings', 'operations', 'safety', 'violations', 'reports', 'coverage', 'route_rules', 'chat_safety']);

function useRefreshOnVisible(
  refresh: () => void | Promise<void>,
  intervalMs?: number,
) {
  useEffect(() => {
    void refresh();
    const onVisible = () => {
      if (document.visibilityState === 'visible') void refresh();
    };
    const interval = intervalMs
      ? window.setInterval(onVisible, intervalMs)
      : undefined;
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('focus', onVisible);
    return () => {
      if (interval !== undefined) window.clearInterval(interval);
      document.removeEventListener('visibilitychange', onVisible);
      window.removeEventListener('focus', onVisible);
    };
  }, [intervalMs, refresh]);
}

function adminRoute(): { page: Page; violationId: string | null } {
  const parameters = new URLSearchParams(window.location.search);
  const violationId = parameters.get('case') || parameters.get('violation');
  const requestedPage = parameters.get('page');
  const page = violationId
    ? 'violations'
    : requestedPage && pages.has(requestedPage as Page)
      ? requestedPage as Page
      : 'overview';
  return { page, violationId };
}
const initialFare: FareConfig = { baseFare: 20, includedMeters: 1000, distanceStepMeters: 500, distanceStepPrice: 5, additionalPassengerFee: 40, baggageFee: 20, outsideTodaSurcharge: 20, additionalDropoffFee: 10 };
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
function dateInputValue(value: Date) {
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, '0');
  const day = String(value.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}
function currentMonthRange() {
  const now = new Date();
  return {
    startDate: dateInputValue(new Date(now.getFullYear(), now.getMonth(), 1)),
    endDate: dateInputValue(new Date(now.getFullYear(), now.getMonth() + 1, 0)),
  };
}
function currentDayRange() {
  const today = new Date();
  const value = dateInputValue(today);
  return { startDate: value, endDate: value };
}
function currentWeekRange() {
  const today = new Date();
  const mondayOffset = (today.getDay() + 6) % 7;
  const start = new Date(today.getFullYear(), today.getMonth(), today.getDate() - mondayOffset);
  const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6);
  return { startDate: dateInputValue(start), endDate: dateInputValue(end) };
}
const overviewMetricsRefreshMs = 15 * 1000;
const overviewCommissionRefreshMs = 5 * 60 * 1000;
const overviewAnalyticsRefreshMs = 15 * 60 * 1000;
function percentLabel(value: number) {
  return `${new Intl.NumberFormat('en-PH', { maximumFractionDigits: 2 }).format(value || 0)}%`;
}
function statusLabel(value: string | null | undefined) {
  return value?.trim() ? value.split('_').join(' ') : 'not recorded';
}

function geometrySummary(areas: Point[][]): string {
  const points = areas.flat().filter(([longitude, latitude]) =>
    Number.isFinite(longitude)
    && Number.isFinite(latitude)
    && Math.abs(longitude) <= 180
    && Math.abs(latitude) <= 90);
  if (points.length === 0) return 'No valid coordinates';

  const longitudes = points.map(([longitude]) => longitude);
  const latitudes = points.map(([, latitude]) => latitude);
  const longitudeRange = `${Math.min(...longitudes).toFixed(5)} to ${Math.max(...longitudes).toFixed(5)}`;
  const latitudeRange = `${Math.min(...latitudes).toFixed(5)} to ${Math.max(...latitudes).toFixed(5)}`;
  return `${areas.length} area${areas.length === 1 ? '' : 's'} | ${points.length} coordinate${points.length === 1 ? '' : 's'} | longitude ${longitudeRange} | latitude ${latitudeRange}`;
}

function zoneStatusLabel(status: ZoneRequest['status']): string {
  if (status === 'approved') return 'Approved coverage';
  if (status === 'declined') return 'Declined';
  return 'Pending System Admin review';
}

export default function App() {
  const initialRoute = useMemo(adminRoute, []);
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<AdminSession | null>(null);
  const [page, setPage] = useState<Page>(initialRoute.page);
  const [deepLinkedViolationId, setDeepLinkedViolationId] = useState<string | null>(
    initialRoute.violationId,
  );
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [pushAlert, setPushAlert] = useState<AdminPushAlert | null>(null);
  const [webPushResult, setWebPushResult] = useState<WebPushResult>({
    enabled: false,
    mode: 'local_only',
    message: webPushSetupMessage(),
  });

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
  useEffect(() => {
    const onPopState = () => {
      const route = adminRoute();
      setPage(route.page);
      setDeepLinkedViolationId(route.violationId);
    };
    window.addEventListener('popstate', onPopState);
    return () => window.removeEventListener('popstate', onPopState);
  }, []);
  useEffect(() => {
    if (!session) return;
    let active = true;
    let stopListening: () => void = () => undefined;
    void syncAdminWebPush(session.uid)
      .then((result) => {
        if (active) setWebPushResult(result);
      })
      .catch((reason) => {
        if (active) {
          setWebPushResult({
            enabled: false,
            mode: 'unavailable',
            message: reason instanceof Error
              ? reason.message
              : 'Unable to synchronize this browser for violation-case web push.',
          });
        }
      });
    void listenForAdminPush((alert) => {
      if (!active) return;
      setPushAlert(alert);
      window.navigator.vibrate?.([220, 100, 220]);
    }).then((unsubscribe) => {
      if (active) stopListening = unsubscribe;
      else unsubscribe();
    });
    return () => {
      active = false;
      stopListening();
    };
  }, [session]);
  if (loading) return <main className="centered">Loading VolTrike Admin…</main>;
  if (!user) return <Login onMessage={setMessage} message={message} />;
  if (!session) return <AccountGate user={user} reload={() => loadSession(auth.currentUser)} onMessage={setMessage} message={message} />;

  const sessionUid = session.uid;
  const isDeveloper = session.role === 'developer_admin';
  const visiblePages: Array<[Page, string]> = isDeveloper
    ? [['overview', 'Overview'], ['todas', 'TODAs'], ['fares', 'City fares'], ['drivers', 'Drivers'], ['live_drivers', 'Live drivers'], ['operations', 'Ride operations'], ['safety', 'Safety incidents'], ['violations', 'Violations'], ['chat_safety', 'Chat safety'], ['reports', 'Reports'], ['coverage', 'Coverage areas'], ['route_rules', 'Route restrictions']]
    : [['overview', 'Overview'], ['drivers', 'My drivers'], ['live_drivers', 'Live drivers'], ['commission', 'Driver commission'], ['ratings', 'Driver ratings'], ['operations', 'TODA rides'], ['safety', 'TODA safety'], ['violations', 'Violations'], ['chat_safety', 'Chat reports'], ['reports', 'TODA reports'], ['coverage', 'Zone request']];

  function navigate(nextPage: Page) {
    setPage(nextPage);
    setDeepLinkedViolationId(null);
    const url = new URL(window.location.href);
    url.searchParams.set('page', nextPage);
    url.searchParams.delete('case');
    url.searchParams.delete('violation');
    window.history.pushState({}, '', url);
  }

  function selectViolation(violationId: string | null) {
    setDeepLinkedViolationId(violationId);
    const url = new URL(window.location.href);
    url.searchParams.set('page', 'violations');
    url.searchParams.delete('violation');
    if (violationId) url.searchParams.set('case', violationId);
    else url.searchParams.delete('case');
    window.history.replaceState({}, '', url);
  }

  async function enableWebPush(): Promise<WebPushResult> {
    try {
      const result = await enableAdminWebPush(sessionUid);
      setWebPushResult(result);
      return result;
    } catch (reason) {
      const result: WebPushResult = {
        enabled: false,
        mode: 'unavailable',
        message: reason instanceof Error
          ? reason.message
          : 'Unable to register violation-case web push on this browser.',
      };
      setWebPushResult(result);
      return result;
    }
  }

  async function signOutAdmin() {
    await removeAdminWebPush(sessionUid).catch(() => undefined);
    await signOut(auth);
  }

  return <div className="shell">
    <aside className="sidebar"><div className="brand"><img src="/images/VolTrikeLogo-Light.png" alt="VolTrike" onError={(event) => { event.currentTarget.style.display = 'none'; }} /><span>VolTrike<br /><b>Admin</b></span></div><div className="role-pill">{isDeveloper ? 'System Admin' : 'TODA Admin'}</div>
      <nav aria-label="Admin sections">{visiblePages.map(([key, text]) => <button className={page === key ? 'nav-active' : ''} aria-current={page === key ? 'page' : undefined} key={key} onClick={() => navigate(key)}>{text}</button>)}</nav>
      <div className="sidebar-footer"><span>{isDeveloper ? 'System Admin' : session.displayName}</span><button onClick={signOutAdmin}>Sign out</button></div>
    </aside>
    <main className="content"><header><div><p className="eyebrow">{isDeveloper ? 'PLATFORM OPERATIONS' : 'TODA OPERATIONS'}</p><h1>{visiblePages.find(([key]) => key === page)?.[1]}</h1></div><div className="status">{isDeveloper ? 'Platform-wide access' : 'TODA-scoped access'}</div></header>
      {message && <div className="notice" role="status">{message}<button aria-label="Dismiss message" onClick={() => setMessage('')}>×</button></div>}
      {pushAlert && <div className="violation-alert-strip global-push-alert" role="alert"><span><b>{pushAlert.title}</b><br />{pushAlert.body}</span><span className="actions">{pushAlert.violationId && <button onClick={() => { setPage('violations'); selectViolation(pushAlert.violationId); setPushAlert(null); }}>Open case</button>}<button aria-label="Dismiss push alert" onClick={() => setPushAlert(null)}>×</button></span></div>}
      {page === 'overview' && <Overview session={session} />}
      {page === 'todas' && isDeveloper && <Todas onMessage={setMessage} />}
      {page === 'fares' && isDeveloper && <Fares onMessage={setMessage} />}
      {page === 'drivers' && <DriversPage todaId={isDeveloper ? undefined : session.todaId!} onMessage={setMessage} />}
      {page === 'live_drivers' && <LiveDriversPage />}
      {page === 'commission' && !isDeveloper && <CommissionPage onMessage={setMessage} />}
      {page === 'ratings' && !isDeveloper && <RatingsPage />}
      {page === 'operations' && <OperationsPage session={session} />}
      {page === 'safety' && <SafetyIncidentsPage session={session} />}
      {page === 'violations' && <Suspense fallback={<section className="panel wide">Loading violations…</section>}><ViolationsPage session={session} initialViolationId={deepLinkedViolationId} onSelectViolation={selectViolation} webPushResult={webPushResult} onEnableWebPush={enableWebPush} /></Suspense>}
      {page === 'chat_safety' && <Suspense fallback={<section className="panel wide">Loading chat safety…</section>}><ChatSafetyPage onMessage={setMessage} canManageRules={isDeveloper} /></Suspense>}
      {page === 'reports' && <ReportsPage todaId={isDeveloper ? undefined : session.todaId!} onMessage={setMessage} />}
      {page === 'coverage' && <CoveragePage session={session} onMessage={setMessage} />}
      {page === 'route_rules' && isDeveloper && <RouteRestrictionsPage onMessage={setMessage} />}
    </main>
  </div>;
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
  return <main className="auth"><section><img src="/images/VolTrikeLogo-Dark.png" className="auth-logo" alt="VolTrike" /><p className="eyebrow">VolTrike operations</p><h1>Admin Portal</h1><p>Authorized TODA and System Admin operations only.</p>{message && <div className="notice" role="alert">{message}</div>}<form onSubmit={submit}><label>Email address<input type="email" placeholder="admin@example.com" autoComplete="email" value={email} onChange={(event) => setEmail(event.target.value)} required /></label><label>Password<input type="password" placeholder="Enter your password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} required /></label><button className="primary" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button><button type="button" onClick={() => { onMessage(''); setRegistering(true); }}>Register a TODA</button></form></section></main>;
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
      await signOut(auth); onMessage(verificationSent ? 'TODA application submitted. Check your branded verification email while a System Admin reviews the application.' : 'TODA application submitted, but the verification email could not be delivered. Sign in later and request another verification email.'); onBack();
    } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to submit TODA registration.'); }
    finally { setBusy(false); }
  }
  if (step === 1) return <main className="auth"><section className="auth-wide"><p className="eyebrow">TODA onboarding · Step 1 of 2</p><h1>Organization and administrator</h1><p>Choose the official location. Legal details and evidence files are collected in Step 2.</p>{loadError && <div className="notice">{loadError}</div>}<form onSubmit={(event) => { event.preventDefault(); setStep(2); }}><input value={name} onChange={(event) => setName(event.target.value)} placeholder="TODA name" required /><input type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="Administrator email" required /><input type="password" minLength={6} value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Password (at least 6 characters)" required /><select value={regionCode} onChange={(event) => { setRegionCode(event.target.value); setCityCode(''); setBarangayCode(''); }} required><option value="">Select region</option>{regions.map((region) => <option key={region.code} value={region.code}>{region.name}</option>)}</select><select value={cityCode} onChange={(event) => { setCityCode(event.target.value); setBarangayCode(''); }} disabled={!regionCode} required><option value="">Select city / municipality</option>{cityOptions.map((city) => <option key={city.code} value={city.code}>{city.name}</option>)}</select><select value={barangayCode} onChange={(event) => setBarangayCode(event.target.value)} disabled={!cityCode} required><option value="">Select barangay</option>{barangayOptions.map((barangay) => <option key={barangay.code} value={barangay.code}>{barangay.name}</option>)}</select><button className="primary" disabled={Boolean(loadError)}>Continue to legal requirements</button><button type="button" onClick={onBack}>Back to sign in</button></form></section></main>;
  if (step === 2) return <main className="auth"><section className="auth-wide"><p className="eyebrow">TODA onboarding · Step 2 of 2</p><h1>Legal registration requirements</h1><p>Provide the legal identifiers and clear photo or PDF evidence. The verified administrator email from Step 1 receives required account and safety notifications. A System Admin reviews every item before approval.</p><form onSubmit={submit}>{registrationFields.map(([key, title]) => <input key={key} type="text" autoComplete="off" value={registration[key]} onChange={(event) => setRegistration({ ...registration, [key]: event.target.value })} placeholder={title} required />)}{todaEvidenceFields.map(([key, title]) => <label className="file-label" key={key}>{title}<input type="file" accept="image/*,application/pdf" onChange={(event) => { const file = event.target.files?.[0]; if (file) setDocuments({ ...documents, [key]: file }); }} required /><small>{documents[key]?.name || 'No file selected'}</small></label>)}<button className="primary" disabled={busy}>{busy ? 'Submitting…' : 'Submit TODA application'}</button><button type="button" onClick={() => setStep(1)} disabled={busy}>Back</button></form></section></main>;
  return <main className="auth"><section className="auth-wide"><p className="eyebrow">TODA onboarding</p><h1>Register a TODA</h1><p>For testing, legal documents are not required. Select locations only from the official PSGC list.</p>{loadError && <div className="notice">{loadError}</div>}<form onSubmit={submit}><input value={name} onChange={(event) => setName(event.target.value)} placeholder="TODA name" required /><input type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="Administrator email" required /><input type="password" minLength={6} value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Password (at least 6 characters)" required /><select value={regionCode} onChange={(event) => { setRegionCode(event.target.value); setCityCode(''); setBarangayCode(''); }} required><option value="">Select region</option>{regions.map((region) => <option key={region.code} value={region.code}>{region.name}</option>)}</select><select value={cityCode} onChange={(event) => { setCityCode(event.target.value); setBarangayCode(''); }} disabled={!regionCode} required><option value="">Select city / municipality</option>{cityOptions.map((city) => <option key={city.code} value={city.code}>{city.name}</option>)}</select><select value={barangayCode} onChange={(event) => setBarangayCode(event.target.value)} disabled={!cityCode} required><option value="">Select barangay</option>{barangayOptions.map((barangay) => <option key={barangay.code} value={barangay.code}>{barangay.name}</option>)}</select><button className="primary" disabled={busy || Boolean(loadError)}>{busy ? 'Submitting…' : 'Submit TODA registration'}</button><button type="button" onClick={onBack}>Back to sign in</button></form></section></main>;
}

function AccountGate({ user, reload, onMessage, message }: { user: User; reload: () => Promise<void>; onMessage: (value: string) => void; message: string }) {
  const [gate, setGate] = useState<{ applicationStatus: string | null; requiresEmailVerification: boolean } | undefined>(undefined);
  const [sendingVerification, setSendingVerification] = useState(false);
  useEffect(() => { getDoc(doc(db, 'users', user.uid)).then((snapshot) => { const profile = snapshot.data(); setGate({ applicationStatus: profile?.role === 'toda_admin_pending' ? profile.todaApplicationStatus || 'pending' : null, requiresEmailVerification: profile?.requiresEmailVerification === true }); }); }, [user.uid]);
  if (gate === undefined) return <main className="centered">Checking administrator access…</main>;
  if (gate.requiresEmailVerification && !user.emailVerified) return <main className="auth"><section><p className="eyebrow">Administrator verification</p><h1>Verify your email</h1><p>Open the branded VolTrike verification email sent to {user.email}. Verification is required for new TODA administrator accounts.</p>{message && <div className="notice">{message}</div>}<button className="primary" disabled={sendingVerification} onClick={async () => { setSendingVerification(true); try { await adminApi.requestBrandedVerificationEmail(); onMessage('Verification email sent. Check your inbox and spam folder.'); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to send verification email.'); } finally { setSendingVerification(false); } }}>{sendingVerification ? 'Sending…' : 'Resend verification email'}</button><button onClick={async () => { await user.reload(); await reload(); }}>I have verified my email</button><button onClick={() => signOut(auth)}>Sign out</button></section></main>;
  const applicationStatus = gate.applicationStatus;
  if (applicationStatus) return <main className="auth"><section><p className="eyebrow">TODA registration</p><h1>{applicationStatus === 'declined' ? 'Application declined' : 'Approval pending'}</h1><p>{applicationStatus === 'declined' ? 'Your TODA application was declined. Contact the system administrator before submitting another application.' : 'Your TODA registration has been submitted. A system administrator must approve it before TODA-admin access is enabled.'}</p>{message && <div className="notice">{message}</div>}<button className="primary" onClick={() => signOut(auth)}>Sign out</button></section></main>;
  return <Bootstrap user={user} reload={reload} onMessage={onMessage} message={message} />;
}

function Bootstrap({ user, reload, onMessage, message }: { user: User; reload: () => Promise<void>; onMessage: (value: string) => void; message: string }) {
  const [code, setCode] = useState(''); const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); try { await adminApi.bootstrap(code); await user.getIdToken(true); await reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Bootstrap failed.'); } finally { setBusy(false); } }
  return <main className="auth"><section><p className="eyebrow">First-time setup</p><h1>Create system admin access</h1><p>Signed in as {user.email}. Enter the one-time bootstrap code stored in Firebase Secret Manager. This page works only while no system admin exists.</p>{message && <div className="notice">{message}</div>}<form onSubmit={submit}><input type="password" placeholder="Bootstrap code" value={code} onChange={(e) => setCode(e.target.value)} required /><button className="primary" disabled={busy}>{busy ? 'Creating…' : 'Create system admin'}</button><button type="button" onClick={() => signOut(auth)}>Use another account</button></form></section></main>;
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
  const [commission, setCommission] = useState<{
    percent: number;
    summary: TodaCommissionReportSummary;
  } | null>(null);
  const [analytics, setAnalytics] = useState<OverviewAnalytics | null>(null);
  const [metricsLoading, setMetricsLoading] = useState(true);
  const [analyticsLoading, setAnalyticsLoading] = useState(true);
  const [commissionLoading, setCommissionLoading] = useState(
    session.role === 'toda_admin',
  );
  const [metricsError, setMetricsError] = useState('');
  const [commissionError, setCommissionError] = useState('');
  const [analyticsError, setAnalyticsError] = useState('');
  useEffect(() => {
    let active = true;
    let inFlight = false;
    let lastAttemptedAt = 0;
    setMetricsLoading(true);
    const refreshMetrics = async () => {
      const now = Date.now();
      if (!active ||
          inFlight ||
          now - lastAttemptedAt < overviewMetricsRefreshMs ||
          document.visibilityState !== 'visible') {
        return;
      }
      inFlight = true;
      lastAttemptedAt = now;
      try {
        const value = await adminApi.metrics();
        if (!active) return;
        setStats(value);
        setMetricsError('');
      } catch (reason) {
        if (!active) return;
        setMetricsError(reason instanceof Error
          ? reason.message
          : 'Unable to load Firebase overview metrics.');
      } finally {
        inFlight = false;
        if (active) setMetricsLoading(false);
      }
    };
    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') {
        void refreshMetrics();
      }
    };
    void refreshMetrics();
    const timer = window.setInterval(
      () => void refreshMetrics(),
      overviewMetricsRefreshMs,
    );
    document.addEventListener('visibilitychange', refreshWhenVisible);
    return () => {
      active = false;
      window.clearInterval(timer);
      document.removeEventListener(
        'visibilitychange',
        refreshWhenVisible,
      );
    };
  }, [session.role, session.todaId]);
  useEffect(() => {
    if (session.role !== 'toda_admin') {
      setCommissionLoading(false);
      setCommissionError('');
      return;
    }
    let active = true;
    let inFlight = false;
    let lastAttemptedAt = 0;
    setCommissionLoading(true);
    const refreshCommission = async () => {
      const now = Date.now();
      if (!active ||
          inFlight ||
          now - lastAttemptedAt < overviewCommissionRefreshMs ||
          document.visibilityState !== 'visible') {
        return;
      }
      inFlight = true;
      lastAttemptedAt = now;
      const range = currentMonthRange();
      try {
        const [configuration, report] = await Promise.all([
          adminApi.todaCommission(),
          adminApi.todaCommissionReport(
            range.startDate,
            range.endDate,
            { summaryOnly: true },
          ),
        ]);
        if (!active) return;
        setCommission({
          percent: configuration.percent,
          summary: report.summary,
        });
        setCommissionError('');
      } catch (reason) {
        if (!active) return;
        setCommissionError(reason instanceof Error
          ? reason.message
          : 'Unable to load this month\'s TODA commission totals.');
      } finally {
        inFlight = false;
        if (active) setCommissionLoading(false);
      }
    };
    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') {
        void refreshCommission();
      }
    };
    void refreshCommission();
    const timer = window.setInterval(
      () => void refreshCommission(),
      overviewCommissionRefreshMs,
    );
    document.addEventListener('visibilitychange', refreshWhenVisible);
    return () => {
      active = false;
      window.clearInterval(timer);
      document.removeEventListener(
        'visibilitychange',
        refreshWhenVisible,
      );
    };
  }, [session.role, session.todaId]);
  useEffect(() => {
    let active = true;
    let inFlight = false;
    let lastAttemptedAt = 0;
    setAnalyticsLoading(true);
    const refreshAnalytics = async () => {
      const now = Date.now();
      if (!active || inFlight || now - lastAttemptedAt < overviewAnalyticsRefreshMs || document.visibilityState !== 'visible') return;
      inFlight = true;
      lastAttemptedAt = now;
      try {
        const value = await adminApi.overviewAnalytics();
        if (!active) return;
        setAnalytics(value);
        setAnalyticsError('');
      } catch (reason) {
        if (!active) return;
        setAnalyticsError(reason instanceof Error ? reason.message : 'Unable to load overview analytics.');
      } finally {
        inFlight = false;
        if (active) setAnalyticsLoading(false);
      }
    };
    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') void refreshAnalytics();
    };
    void refreshAnalytics();
    const timer = window.setInterval(() => void refreshAnalytics(), overviewAnalyticsRefreshMs);
    document.addEventListener('visibilitychange', refreshWhenVisible);
    return () => {
      active = false;
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', refreshWhenVisible);
    };
  }, [session.role, session.todaId]);

  const isTodaAdmin = session.role === 'toda_admin';
  const loading = metricsLoading || commissionLoading || analyticsLoading;
  const error = [metricsError, commissionError, analyticsError].filter(Boolean).join(' ');
  const completionRate = stats.bookings > 0 ? Math.round((stats.trips / stats.bookings) * 100) : 0;
  const attentionItems = [
    { label: 'Open reports', value: stats.reports, tone: 'attention' as const },
    { label: 'Open safety incidents', value: stats.safetyIncidents, tone: 'danger' as const },
    { label: 'Pending zone requests', value: stats.zones, tone: 'governance' as const },
    ...(isTodaAdmin ? [{ label: 'Disputed settlements', value: commission?.summary.disputedSettlements || 0, tone: 'attention' as const }] : []),
  ];

  return <div className="overview-dashboard">
    <div className="overview-intro">
      <div>
        <h2>{isTodaAdmin ? 'TODA operating snapshot' : 'Platform operating snapshot'}</h2>
        <p className="muted">Live totals refresh every 15 seconds. Trend charts use real Firestore records for the latest 14 Manila calendar days.</p>
      </div>
      {analytics?.generatedAt && <span className="last-updated">Charts updated {new Date(analytics.generatedAt).toLocaleTimeString('en-PH')}</span>}
    </div>
    {loading && <p className="muted" role="status">Refreshing overview data…</p>}
    {error && <div className="notice">{error}</div>}
    {analytics?.truncated && <div className="notice">The 14-day chart reached its safe record limit. Values shown are real but partial; shorten the analytics window before operational use at this volume.</div>}

    <div className="cards overview-hero">
      {isTodaAdmin
        ? <>
          <Metric tone="operations" label="Completed rides this month" value={commission ? String(commission.summary.completedRides) : '—'} hint="Settled completed rides" />
          <Metric tone="finance" label="Gross fares this month" value={commission ? peso(commission.summary.grossFare) : '—'} hint="Passenger cash fares" />
          <Metric tone={commission?.summary.commissionDue ? 'attention' : 'finance'} label="Commission due" value={commission ? peso(commission.summary.commissionDue) : '—'} warning={Boolean(commission?.summary.commissionDue)} hint="Selected TODA only" />
          <Metric tone={stats.safetyIncidents ? 'danger' : 'operations'} label="Open safety incidents" value={String(stats.safetyIncidents)} warning={Boolean(stats.safetyIncidents)} hint="Requires operational review" />
        </>
        : <>
          <Metric tone="operations" label="All bookings" value={String(stats.bookings)} hint="Platform scope" />
          <Metric tone="operations" label="Completed rides" value={String(stats.trips)} hint={`${completionRate}% completion snapshot`} />
          <Metric tone="governance" label="Registered drivers" value={String(stats.drivers)} hint="All TODAs" />
          <Metric tone={stats.safetyIncidents ? 'danger' : 'operations'} label="Open safety incidents" value={String(stats.safetyIncidents)} warning={Boolean(stats.safetyIncidents)} hint="Requires operational review" />
        </>}
    </div>

    <div className="overview-charts">
      <DailyBarChart
        title="14-day ride activity"
        description="Booking requests are grouped by creation date; completed rides are grouped by settlement time."
        days={analytics?.days || []}
        series={[
          { key: 'bookings', label: 'Booking requests', tone: 'operations' },
          { key: 'completedRides', label: 'Completed rides', tone: 'governance' },
        ]}
        valueFormatter={(value) => String(value)}
      />
      {isTodaAdmin && <DailyBarChart
        title="14-day completed-fare distribution"
        description="Every bar comes from settled ride snapshots; driver net plus TODA commission equals the completed gross fare."
        days={analytics?.days || []}
        series={[
          { key: 'driverNetEarnings', label: 'Driver net', tone: 'finance' },
          { key: 'commissionAmount', label: 'TODA commission', tone: 'governance' },
        ]}
        valueFormatter={peso}
      />}
      <SnapshotBarChart title="Current operational workload" items={attentionItems} />
    </div>

    <section className="overview-section" aria-labelledby="additional-overview-title">
      <div className="overview-section-heading">
        <div><p className="eyebrow">Supporting totals</p><h2 id="additional-overview-title">Additional overview</h2></div>
      </div>
      <div className="cards overview-secondary">
        <Metric tone="governance" label="Registered drivers" value={String(stats.drivers)} />
        <Metric tone="operations" label="All bookings" value={String(stats.bookings)} />
        <Metric tone="operations" label="Completed rides" value={String(stats.trips)} hint={`${completionRate}% of all bookings`} />
        <Metric tone={stats.reports ? 'attention' : 'governance'} label="Open reports" value={String(stats.reports)} warning={Boolean(stats.reports)} />
        <Metric tone="governance" label="Pending zone requests" value={String(stats.zones)} />
        {isTodaAdmin && <>
          <Metric tone="finance" label="Current commission rate" value={commission ? percentLabel(commission.percent) : '—'} />
          <Metric tone="finance" label="Commission earned this month" value={commission ? peso(commission.summary.commissionAmount) : '—'} />
          <Metric tone="finance" label="Commission paid this month" value={commission ? peso(commission.summary.commissionSettled) : '—'} />
          <Metric tone="finance" label="Driver net this month" value={commission ? peso(commission.summary.driverNetEarnings) : '—'} />
        </>}
      </div>
    </section>

    <details className="panel overview-boundaries">
      <summary>How these figures are scoped</summary>
      <p>{session.role === 'developer_admin' ? 'These figures cover Firebase bookings, drivers, reports, SOS incidents, and zone requests across the platform.' : 'These figures and commission totals are restricted by Firebase to your authenticated TODA. Monthly earnings use each completed ride’s snapshotted commission rate; changing today’s rate never recalculates older rides. Marking commission paid records a separate TODA payout and never changes the passenger cash receipt.'}</p>
    </details>
  </div>;
}

type MetricTone = 'neutral' | 'operations' | 'finance' | 'governance' | 'attention' | 'danger';
type ChartTone = Exclude<MetricTone, 'neutral' | 'danger'> | 'danger';
type OverviewNumericKey = Exclude<keyof OverviewAnalyticsDay, 'date'>;

function Metric({ label: title, value, warning, tone = 'neutral', hint }: { label: string; value: string; warning?: boolean; tone?: MetricTone; hint?: string }) {
  return <article className={`metric metric--${tone}`}><p>{title}</p><strong className={warning ? 'warning' : ''}>{value}</strong>{hint && <small>{hint}</small>}</article>;
}

function DailyBarChart({ title, description, days, series, valueFormatter }: {
  title: string;
  description: string;
  days: OverviewAnalyticsDay[];
  series: Array<{ key: OverviewNumericKey; label: string; tone: ChartTone }>;
  valueFormatter: (value: number) => string;
}) {
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const values = days.flatMap((day) => series.map((item) => Number(day[item.key]) || 0));
  const maximum = Math.max(0, ...values);
  const hasData = maximum > 0;
  const selectedDay = days.find((day) => day.date === selectedDate);
  const fullDate = (date: string) => new Date(`${date}T00:00:00`).toLocaleDateString('en-PH', {
    weekday: 'short', year: 'numeric', month: 'short', day: 'numeric',
  });
  const daySummary = (day: OverviewAnalyticsDay) => series
    .map((item) => `${item.label}: ${valueFormatter(Number(day[item.key]) || 0)}`)
    .join(', ');
  return <section className="overview-chart">
    <div className="chart-heading"><div><h3>{title}</h3><p>{description}</p></div></div>
    <div className="chart-legend">{series.map((item) => <span key={item.key}><i className={`chart-swatch chart-swatch--${item.tone}`} />{item.label}</span>)}</div>
    <div className={`chart-readout${selectedDay ? ' chart-readout--active' : ''}`} aria-live="polite">
      {selectedDay
        ? <><strong>{fullDate(selectedDay.date)}</strong><span>{series.map((item) => <span key={item.key}><i className={`chart-swatch chart-swatch--${item.tone}`} />{item.label}: <b>{valueFormatter(Number(selectedDay[item.key]) || 0)}</b></span>)}</span></>
        : <span>Hover, focus, or tap a day’s bars to view its exact values.</span>}
    </div>
    {days.length > 0
      ? <div className="daily-chart-scroll">
        <div className="daily-chart" role="group" aria-label={`${title}. ${description}`}>
          {days.map((day) => <div className={`daily-chart-column${selectedDate === day.date ? ' daily-chart-column--selected' : ''}`} key={day.date}>
            <button
              type="button"
              className="daily-chart-bars"
              aria-label={`${fullDate(day.date)}. ${daySummary(day)}`}
              aria-pressed={selectedDate === day.date}
              title={`${fullDate(day.date)} — ${daySummary(day)}`}
              onClick={() => setSelectedDate(day.date)}
              onFocus={() => setSelectedDate(day.date)}
              onPointerEnter={() => setSelectedDate(day.date)}
            >
              {series.map((item) => {
                const value = Number(day[item.key]) || 0;
                const height = value > 0 && maximum > 0 ? Math.max(5, (value / maximum) * 100) : 0;
                return <span aria-hidden="true" className={`daily-chart-bar chart-bar--${item.tone}`} style={{ height: `${height}%` }} key={item.key} />;
              })}
            </button>
            <span>{new Date(`${day.date}T00:00:00`).toLocaleDateString('en-PH', { month: 'short', day: 'numeric' })}</span>
          </div>)}
        </div>
      </div>
      : <p className="muted">Loading real chart data…</p>}
    {!hasData && days.length > 0 && <p className="chart-empty">No matching activity was recorded during this period.</p>}
    {days.length > 0 && <details className="chart-data"><summary>View exact chart values</summary><div className="chart-data-scroll"><table><thead><tr><th>Date</th>{series.map((item) => <th key={item.key}>{item.label}</th>)}</tr></thead><tbody>{days.map((day) => <tr key={day.date}><td>{day.date}</td>{series.map((item) => <td key={item.key}>{valueFormatter(Number(day[item.key]) || 0)}</td>)}</tr>)}</tbody></table></div></details>}
  </section>;
}

function SnapshotBarChart({ title, items }: { title: string; items: Array<{ label: string; value: number; tone: ChartTone }> }) {
  const maximum = Math.max(1, ...items.map((item) => item.value));
  return <section className="overview-chart snapshot-chart"><div className="chart-heading"><div><h3>{title}</h3><p>Current authenticated scope, shown with exact values.</p></div></div><div className="snapshot-bars">{items.map((item) => <div className="snapshot-bar" key={item.label}><div><span>{item.label}</span><b>{item.value}</b></div><div className="snapshot-track" aria-hidden="true"><span className={`chart-bar--${item.tone}`} style={{ width: `${item.value > 0 ? Math.max(4, (item.value / maximum) * 100) : 0}%` }} /></div></div>)}</div></section>;
}

function CommissionPage({ onMessage }: { onMessage: (value: string) => void }) {
  const initialRange = useMemo(currentMonthRange, []);
  const todayRange = useMemo(currentDayRange, []);
  const weekRange = useMemo(currentWeekRange, []);
  const [percent, setPercent] = useState(0);
  const [recommended, setRecommended] = useState(10);
  const [maximum, setMaximum] = useState(30);
  const [updatedAt, setUpdatedAt] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [settlingDriverId, setSettlingDriverId] = useState<string | null>(null);
  const [startDate, setStartDate] = useState(initialRange.startDate);
  const [endDate, setEndDate] = useState(initialRange.endDate);
  const [appliedRange, setAppliedRange] = useState(initialRange);
  const [summary, setSummary] = useState<TodaCommissionReportSummary | null>(null);
  const [items, setItems] = useState<TodaCommissionReportItem[]>([]);
  const [driverSummaries, setDriverSummaries] = useState<TodaCommissionDriverSummary[]>([]);
  const [todaySummary, setTodaySummary] = useState<TodaCommissionReportSummary | null>(null);
  const [weekSummary, setWeekSummary] = useState<TodaCommissionReportSummary | null>(null);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [reportLoading, setReportLoading] = useState(true);
  const [reportError, setReportError] = useState('');
  useEffect(() => {
    void adminApi.todaCommission()
      .then((value) => {
        setPercent(value.percent);
        setRecommended(value.recommendedPercent);
        setMaximum(value.maximumPercent);
        setUpdatedAt(value.updatedAt || null);
      })
      .catch((error: unknown) => {
        onMessage(error instanceof Error ? error.message : 'Unable to load the current commission setting.');
      });
  }, [onMessage]);
  const loadReport = useCallback(async (cursor?: string | null, append = false) => {
    setReportLoading(true);
    try {
      const report = await adminApi.todaCommissionReport(
        appliedRange.startDate,
        appliedRange.endDate,
        { cursor },
      );
      setSummary(report.summary);
      setItems((current) => append
        ? [
          ...current,
          ...report.items.filter((item) =>
            !current.some((existing) => existing.bookingId === item.bookingId)),
        ]
        : report.items);
      if (!append) setDriverSummaries(report.driverSummaries);
      setNextCursor(report.nextCursor);
      setReportError('');
    } catch (error) {
      setReportError(error instanceof Error ? error.message : 'Unable to load the TODA commission report.');
    } finally {
      setReportLoading(false);
    }
  }, [appliedRange]);
  const loadPeriodSummaries = useCallback(async () => {
    try {
      const [today, week] = await Promise.all([
        adminApi.todaCommissionReport(todayRange.startDate, todayRange.endDate, { summaryOnly: true }),
        adminApi.todaCommissionReport(weekRange.startDate, weekRange.endDate, { summaryOnly: true }),
      ]);
      setTodaySummary(today.summary);
      setWeekSummary(week.summary);
    } catch (error) {
      setReportError(error instanceof Error ? error.message : 'Unable to load today and this week\'s commission totals.');
    }
  }, [todayRange, weekRange]);
  useEffect(() => {
    void loadReport();
  }, [loadReport]);
  useEffect(() => {
    void loadPeriodSummaries();
  }, [loadPeriodSummaries]);
  function applyReportRange(event: FormEvent) {
    event.preventDefault();
    if (!startDate || !endDate) {
      setReportError('Choose both a start and end date.');
      return;
    }
    if (endDate < startDate) {
      setReportError('The end date must be on or after the start date.');
      return;
    }
    setItems([]);
    setNextCursor(null);
    const nextRange = { startDate, endDate };
    if (nextRange.startDate === appliedRange.startDate && nextRange.endDate === appliedRange.endDate) {
      void loadReport();
    } else {
      setAppliedRange(nextRange);
    }
  }
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
  async function settleDriverCommission(driver: TodaCommissionDriverSummary) {
    if (driver.commissionDue <= 0 || settlingDriverId) return;
    const confirmed = window.confirm(
      `Mark ${peso(driver.commissionDue)} TODA commission as paid for ${driver.driverName} in the selected date range? This records a separate commission payout and does not change completed passenger receipts.`,
    );
    if (!confirmed) return;
    setSettlingDriverId(driver.driverId);
    try {
      const result = await adminApi.settleDriverCommission(
        driver.driverId,
        appliedRange.startDate,
        appliedRange.endDate,
      );
      onMessage(`${peso(result.commissionAmount)} commission settled for ${driver.driverName} across ${result.settledBookingCount} completed ride${result.settledBookingCount === 1 ? '' : 's'}.`);
      await Promise.all([loadReport(), loadPeriodSummaries()]);
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to settle this driver commission.');
    } finally {
      setSettlingDriverId(null);
    }
  }
  return <>
    <section className="panel wide">
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
    </section>
    <section className="panel wide">
      <div className="section-heading">
        <div>
          <h2>Completed-ride commission report</h2>
          <p className="muted">Totals use the immutable rate captured for each ride. A ride appears only after completion; pending and already-assigned rides are not recalculated when the setting above changes.</p>
        </div>
        <button type="button" onClick={() => void Promise.all([loadReport(), loadPeriodSummaries()])} disabled={reportLoading}>Refresh report</button>
      </div>
      <form className="commission-filters" onSubmit={applyReportRange}>
        <label>Start date<input type="date" value={startDate} onChange={(event) => setStartDate(event.target.value)} required /></label>
        <label>End date<input type="date" value={endDate} onChange={(event) => setEndDate(event.target.value)} required /></label>
        <button className="primary" disabled={reportLoading}>Apply dates</button>
      </form>
      {reportError && <div className="notice">{reportError}</div>}
      <div className="cards commission-cards">
        <Metric label="Completed rides" value={summary ? String(summary.completedRides) : '—'} />
        <Metric label="Gross passenger fares" value={summary ? peso(summary.grossFare) : '—'} />
        <Metric label="TODA commission earned" value={summary ? peso(summary.commissionAmount) : '—'} />
        <Metric label="TODA commission due" value={summary ? peso(summary.commissionDue) : '—'} warning={Boolean(summary?.commissionDue)} />
        <Metric label="TODA commission paid" value={summary ? peso(summary.commissionSettled) : '—'} />
        <Metric label="Driver net earnings" value={summary ? peso(summary.driverNetEarnings) : '—'} />
        <Metric label="Pending settlements" value={summary ? String(summary.pendingSettlements) : '—'} warning={Boolean(summary?.pendingSettlements)} />
        <Metric label="Settled rides" value={summary ? String(summary.settledSettlements) : '—'} />
        <Metric label="Disputed settlements" value={summary ? String(summary.disputedSettlements) : '—'} warning={Boolean(summary?.disputedSettlements)} />
      </div>
      <div className="cards commission-cards">
        <Metric label="Completed rides today" value={todaySummary ? String(todaySummary.completedRides) : '—'} />
        <Metric label="Commission due today" value={todaySummary ? peso(todaySummary.commissionDue) : '—'} />
        <Metric label="Completed rides this week" value={weekSummary ? String(weekSummary.completedRides) : '—'} />
        <Metric label="Commission due this week" value={weekSummary ? peso(weekSummary.commissionDue) : '—'} />
      </div>
      <section className="commission-report-section commission-driver-breakdown" aria-labelledby="commission-driver-heading">
        <div className="commission-report-heading">
          <div>
            <span className="commission-section-kicker">Driver totals</span>
            <h3 id="commission-driver-heading">Commission by registered driver</h3>
            <p className="muted">Every driver assigned to this TODA is listed, including drivers with no completed ride in the selected date range.</p>
          </div>
          <span className="commission-section-count">{driverSummaries.length} driver{driverSummaries.length === 1 ? '' : 's'}</span>
        </div>
        <div className="table commission-table">
          {driverSummaries.map((driver) => <div className="row commission-row commission-driver-row" key={driver.driverId}>
            <span data-label="Driver"><b>{driver.driverName}</b><small className="technical-id">Driver: {driver.driverId}</small></span>
            <span data-label="Completed rides"><b>{driver.completedRides}</b><small>completed ride{driver.completedRides === 1 ? '' : 's'}</small></span>
            <span data-label="Gross fares"><b>{peso(driver.grossFare)}</b><small>gross passenger fares</small></span>
            <span data-label="Commission"><b>{peso(driver.commissionDue)}</b><small>commission due of {peso(driver.commissionAmount)}</small></span>
            <span data-label="Driver net"><b>{peso(driver.driverNetEarnings)}</b><small>driver net earnings</small></span>
            <span data-label="Settlement" className={driver.commissionDue > 0 ? 'warning' : 'ok'}><b>{driver.commissionDue > 0 ? 'Due' : 'Settled'}</b><small>{peso(driver.commissionSettled)} paid</small><button type="button" onClick={() => void settleDriverCommission(driver)} disabled={driver.commissionDue <= 0 || settlingDriverId !== null}>{settlingDriverId === driver.driverId ? 'Settling…' : driver.commissionDue > 0 ? 'Mark commission settled' : 'Commission settled'}</button></span>
          </div>)}
          {!reportLoading && driverSummaries.length === 0 && <p className="muted">No registered drivers are available for this TODA scope.</p>}
        </div>
      </section>
      <section className="commission-report-section commission-trip-history" aria-labelledby="commission-trip-heading">
        <div className="commission-report-heading">
          <div>
            <span className="commission-section-kicker">Ride ledger</span>
            <h3 id="commission-trip-heading">Trip commission history</h3>
            <p className="muted">Each row is one completed ride, with its captured rate, TODA share, driver net earnings, receipt, and settlement status.</p>
          </div>
          <span className="commission-section-count">{items.length} ride{items.length === 1 ? '' : 's'} shown</span>
        </div>
        <div className="table commission-table">
          {items.map((item) => {
            const disputed = item.adjustmentStatus === 'disputed'
              || item.settlementStatus === 'disputed';
            return <div className="row commission-row commission-trip-row" key={item.bookingId}>
              <span data-label="Completed"><b>{item.completedAt ? new Date(item.completedAt).toLocaleString('en-PH') : 'Completion time unavailable'}</b><small className="technical-id">Booking: {item.bookingId}</small>{item.receiptNumber && <small>Receipt: {item.receiptNumber}</small>}</span>
              <span data-label="Driver"><b>{item.driverName || 'Driver name unavailable'}</b><small className="technical-id">Driver: {item.driverId}</small></span>
              <span data-label="Gross fare"><b>{peso(item.grossFare)} gross</b><small>{percentLabel(item.commissionPercent)} captured rate</small></span>
              <span data-label="Distribution"><b>{peso(item.commissionAmount)} TODA</b><small>{item.commissionSettlementStatus === 'settled' ? 'Commission paid' : 'Commission due'} · {peso(item.driverNetEarnings)} driver net</small></span>
              <span data-label="Settlement" className={disputed ? 'warning' : item.settlementStatus === 'settled' ? 'ok' : ''}><b>{statusLabel(item.settlementStatus)}</b>{item.adjustmentStatus && <small>Adjustment: {statusLabel(item.adjustmentStatus)}</small>}{item.disputeReason && <small>{item.disputeReason}</small>}</span>
            </div>;
          })}
          {reportLoading && items.length === 0 && <p className="muted">Loading completed-ride commissions…</p>}
          {!reportLoading && !reportError && items.length === 0 && <p className="muted">No completed rides were recorded in this date range.</p>}
        </div>
        <div className="commission-pagination">
          <button type="button" onClick={() => void loadReport(nextCursor, true)} disabled={reportLoading || !nextCursor}>{reportLoading && items.length > 0 ? 'Loading…' : nextCursor ? 'Load older completed rides' : 'End of results'}</button>
        </div>
      </section>
    </section>
  </>;
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
  useRefreshOnVisible(refresh);
  const points = drivers.map((driver) => ({
    id: driver.uid,
    latitude: driver.latitude,
    longitude: driver.longitude,
    title: driver.name,
    details: [
      `${driver.vehicleType || 'Vehicle'} · ${driver.plateNumber || 'No plate'}`,
      `Status: ${statusLabel(driver.bookingStatus)}`,
      driver.bookingId ? `Booking: ${driver.bookingId}` : 'No active booking',
    ],
  }));
  return <div className="two-column live-layout">
    <section className="panel wide">
      <h2>Online driver map</h2>
      <p className="muted">Only approved drivers who are online and have a fresh location are shown. Select a driver to expand their marker and current booking status.</p>
      {error && <div className="notice">{error}</div>}
      <Suspense fallback={<div className="map-missing">Loading live-driver map…</div>}>
        <AdminLocationMap points={points} selectedId={selectedId} onSelect={setSelectedId} ariaLabel="Online driver operations map" />
      </Suspense>
    </section>
    <section className="panel">
      <h2>Online now ({drivers.length})</h2>
      <div className="table">{drivers.map((driver) => <button className={selectedId === driver.uid ? 'live-driver selected' : 'live-driver'} onClick={() => setSelectedId(driver.uid)} key={driver.uid}>
        <b>{driver.name}</b>
        <small>{driver.vehicleType || 'Vehicle'} · {driver.plateNumber || 'No plate'}</small>
        <small>{statusLabel(driver.bookingStatus)}{driver.bookingId ? ` · ${driver.bookingId}` : ''}</small>
      </button>)}{drivers.length === 0 && <p className="muted">No online driver has a fresh location.</p>}</div>
    </section>
  </div>;
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
  async function openDocument(todaId: string, reference: string) {
    if (/^https:\/\//i.test(reference)) {
      window.open(reference, '_blank', 'noopener,noreferrer');
      return;
    }
    const popup = window.open('about:blank', '_blank');
    if (popup) popup.opener = null;
    try {
      const result = await adminApi.todaDocumentUrl(todaId, reference);
      if (popup) popup.location.replace(result.url);
      else window.location.assign(result.url);
    } catch (error) {
      popup?.close();
      onMessage(error instanceof Error ? error.message : 'Unable to open the secure document.');
    }
  }
  useEffect(() => {
    const interceptPrivateDocument = (event: MouseEvent) => {
      const anchor = (event.target as Element | null)?.closest<HTMLAnchorElement>('.toda-row .document-links a');
      const reference = anchor?.getAttribute('href');
      if (!anchor || !reference || /^https:\/\//i.test(reference)) return;
      const toda = todas.find((item) => Object.values(item.documents || {}).includes(reference));
      if (!toda) return;
      event.preventDefault();
      void openDocument(toda.id, reference);
    };
    document.addEventListener('click', interceptPrivateDocument);
    return () => document.removeEventListener('click', interceptPrivateDocument);
  }, [todas]);
  const location = (toda: Toda) => [toda.barangayName, toda.cityName, toda.regionName].filter(Boolean).join(', ') || toda.barangayCode;
  const evidence = (toda: Toda) => [
    ['SEC certificate', toda.documents?.secCertificate],
    ['SP resolution', toda.documents?.spResolution],
    ["Mayor's permit / BPLO license", toda.documents?.mayorsPermit],
    ['Barangay clearance', toda.documents?.barangayClearance],
    ["President's license", toda.documents?.presidentLicense],
  ].filter((entry): entry is [string, string] => Boolean(entry[1]));
  return <section className="panel wide"><h2>TODA applications and registrations</h2><p className="muted">Review the organization details, legal identifiers, verified administrator email, and secure evidence before approving a TODA administrator.</p><div className="table">{todas.map((toda) => <div className="row toda-row" key={toda.id}><span data-label="Organization"><b>{toda.name}</b><small>{location(toda)}</small><small>President: {toda.registration?.presidentName || 'Not supplied'} · License: {toda.registration?.presidentLicenseNumber || 'Not supplied'} · TIN: {toda.registration?.presidentTin || 'Not supplied'}</small><small>SEC: {toda.registration?.secCertificateNumber || 'Not supplied'} · SP: {toda.registration?.spResolutionNumber || 'Not supplied'} · BPLO: {toda.registration?.mayorsPermitNumber || 'Not supplied'} · Barangay: {toda.registration?.barangayClearanceNumber || 'Not supplied'}</small><details><summary>Legal evidence ({evidence(toda).length}/5)</summary><div className="document-links">{evidence(toda).map(([name, url]) => <a href={url} target="_blank" rel="noreferrer" key={name}>{name}</a>)}</div></details></span><span data-label="Status" className={`status-cell ${toda.status === 'pending' ? 'warning' : toda.isActive ? 'ok' : ''}`}>{toda.status || (toda.isActive ? 'approved' : 'suspended')}</span><span data-label="Actions" className="actions">{toda.status === 'pending' && <><button className="primary" onClick={() => review(toda, 'approved')}>Approve</button><button className="danger-outline" onClick={() => review(toda, 'declined')}>Decline</button></>}{toda.status !== 'pending' && <button className={toda.isActive ? 'danger-outline' : 'primary'} onClick={() => toggleToda(toda)}>{toda.isActive ? 'Suspend' : 'Restore'}</button>}</span></div>)}{todas.length === 0 && <p className="muted">No TODA applications yet.</p>}</div></section>;
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
    ['additionalDropoffFee', 'Additional drop-off fee', 'PHP'],
  ];
  return <section className="panel wide"><h2>City-controlled passenger fares</h2><p className="muted">Amounts are stored in PHP. Update metadata is recorded by the backend automatically and is not editable.</p><form className="form-grid fare-grid" onSubmit={submit}>{fields.map(([key, title, unit]) => <label key={key}>{title}<span className="input-with-unit"><input type="number" min={key === 'baseFare' || key.includes('Meters') ? 1 : 0} max="9999" step="0.01" value={fare[key]} onChange={(e) => setFare({ ...fare, [key]: Number(e.target.value) })} required /><small>{unit}</small></span></label>)}<button className="primary">Save city fare</button></form><div className="fare-summary">Fare = {peso(fare.baseFare)} for the first {fare.includedMeters} m, plus {peso(fare.distanceStepPrice)} per started {fare.distanceStepMeters} m after that. A second drop-off adds {peso(fare.additionalDropoffFee)}; passenger, baggage, and boundary charges remain separate.</div></section>;
}

function DriversPage({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const reload = useCallback(() => adminApi.drivers(todaId).then(setDrivers), [todaId]);
  useRefreshOnVisible(reload);
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
    <p className="muted">{todaId ? 'Review the camera-captured identity and vehicle documents. Record the licence details shown in the images before approval.' : 'System Admin oversight can suspend active accounts; routine approval and licence verification remain with each TODA.'}</p>
    <div className="table">{drivers.map((driver) => {
      const driverName = fullName(driver);
      return <div className="row driver" key={driver.uid}>
      <div className="applicant driver-applicant" data-label="Applicant and vehicle">
        <DriverAvatar driver={driver} name={driverName} />
        <div className="driver-applicant-details">
        <b>{driverName}</b>
        <small>{driver.applicant?.email || 'Email unavailable'} · {driver.applicant?.phoneNumber || 'Phone unavailable'}</small>
        <small>Date of birth: {driver.applicant?.dateOfBirth ? new Date(driver.applicant.dateOfBirth).toLocaleDateString('en-PH') : 'Not supplied (legacy registration)'}</small>
        <small>TODA: {driver.todaId} · Licence: {driver.licenseNumber || 'Awaiting TODA verification'}</small>
        <small>Vehicle: {driver.vehicle?.vehicleNumber || driver.vehicle?.model || 'Not registered'} · {driver.vehicle?.plateNumber || 'No plate'} · {driver.vehicle?.isVerified ? 'verified' : 'not verified'}</small>
        <details><summary>Registration documents ({documentLinks(driver).length})</summary><div className="document-links">{documentLinks(driver).map(([name, url]) => <a href={url} target="_blank" rel="noreferrer" key={name}>{name}</a>)}</div></details>
        <small className="technical-id">Firebase UID: {driver.uid}</small>
        </div>
      </div>
      <span data-label="Status" className={`status-cell ${driver.driverStatus === 'pending' ? 'warning' : driver.driverStatus === 'approved' ? 'ok' : ''}`}>{driver.driverStatus}</span>
      <span data-label="Performance">{todaId && <>★ {driver.rating || 0} from {driver.ratingCount || 0} ratings<br /></>}<small>{driver.completedTrips || 0} trips · {peso(driver.totalEarnings || 0)} net earnings</small></span>
      <span data-label="Actions" className="actions">
        {todaId && driver.vehicle && <button className={driver.vehicle.isVerified ? 'warning-button' : ''} onClick={() => verifyVehicle(driver, !driver.vehicle?.isVerified)}>{driver.vehicle.isVerified ? 'Remove vehicle verification' : 'Verify vehicle'}</button>}
        {todaId && (driver.driverStatus === 'pending' || driver.driverStatus === 'suspended') && <DriverReviewActions driver={driver} onApprove={(license) => update(driver, 'approved', license)} onReject={driver.driverStatus === 'pending' ? () => update(driver, 'rejected') : undefined} />}
        {driver.driverStatus === 'approved' && <button className="danger-outline" onClick={() => update(driver, 'suspended')}>Suspend</button>}
      </span>
    </div>})}{drivers.length === 0 && <p className="muted">No driver applications are available in this scope.</p>}</div>
  </section>;
}

function DriverAvatar({ driver, name }: { driver: Driver; name: string }) {
  const source = driver.profilePhotoUrl || driver.applicant?.profileImage || '';
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [source]);
  const nameParts = name.trim().split(/\s+/).filter(Boolean);
  const initials = nameParts.length > 1
    ? `${nameParts[0][0]}${nameParts[nameParts.length - 1][0]}`.toUpperCase()
    : (nameParts[0]?.slice(0, 2) || 'DR').toUpperCase();

  if (!source || failed) {
    return <span className="driver-avatar driver-avatar-fallback" role="img" aria-label={`${name} has no profile photo`}>{initials}</span>;
  }
  return <a className="driver-avatar" href={source} target="_blank" rel="noreferrer" aria-label={`Open ${name}'s profile photo`} title="Open profile photo">
    <img src={source} alt={`${name} profile`} loading="lazy" decoding="async" onError={() => setFailed(true)} />
  </a>;
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
    {onReject && <button className="danger-outline" onClick={onReject}>Reject</button>}
  </>;
}

function RatingsPage() {
  const [ratings, setRatings] = useState<DriverRatingRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [error, setError] = useState('');
  const reload = useCallback(async () => {
    try {
      const page = await adminApi.ratingPage();
      setRatings(page.items);
      setNextCursor(page.nextCursor);
      setError('');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to load driver ratings.');
    } finally {
      setLoading(false);
    }
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
  useRefreshOnVisible(reload);
  useEffect(() => {
    const timer = window.setInterval(() => void reload(), 15_000);
    return () => window.clearInterval(timer);
  }, [reload]);
  return <section className="panel wide"><h2>Passenger ratings</h2><p className="muted">Ratings are immutable trip records. TODA administrators see only feedback for drivers assigned to their TODA. This page refreshes every 15 seconds while open.</p>{error && <div className="notice">{error}</div>}{loading && <p>Loading ratings…</p>}<div className="table">{ratings.map((rating) => <div className="row report rating-row" key={rating.id}><span data-label="Rating"><b>{rating.rating} ★ for {rating.driverName || 'Driver'}</b><small>Passenger: {rating.passengerName || 'Passenger'}</small><small>TODA: {rating.todaName || rating.todaId || 'Not recorded'}</small></span><span data-label="Passenger comment">{rating.comment || 'Passenger left a star rating without a comment.'}</span><span data-label="Recorded"><small>{rating.createdAt ? new Date(rating.createdAt).toLocaleString('en-PH') : 'Date unavailable'}</small><br /><small className="technical-id">Booking: {rating.bookingId}</small></span></div>)}{!loading && ratings.length === 0 && <p className="muted">No ratings are available in this scope.</p>}{nextCursor && <button onClick={loadMore} disabled={loadingMore}>{loadingMore ? 'Loading…' : 'Load older ratings'}</button>}</div></section>;
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
  useRefreshOnVisible(reload);
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
  return <section className="panel wide"><h2>{todaId ? 'Driver reports for this TODA' : 'All passenger and driver reports'}</h2><p className="muted">{todaId ? 'TODA administrators receive reports about their drivers. Passenger-account reports are evaluated by the System Admin.' : 'System Admin receives every report. Reports about drivers are also synchronized to the driver’s TODA.'}</p><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search reports" aria-label="Search reports" /><div className="table">{reports.map((report) => <div className="row report report-card" key={report.id}><span data-label="Report"><b>{report.category}</b><small>Booking {report.bookingId}</small><small>{report.reportedRole ? `Reported ${report.reportedRole}` : 'Legacy report'}</small><small className={`status-cell ${report.status === 'open' ? 'warning' : 'ok'}`}>{report.status}</small></span><span data-label="People" className="report-parties"><b>Reported by: {name(report.reporter, 'Passenger identity restricted')}</b><small>{contact(report.reporter) || (report.reporter ? 'No contact details' : 'Restricted outside TODA scope')}</small><b>Reported account: {name(report.reportedUser, 'Driver or passenger identity restricted')}</b><small>{contact(report.reportedUser) || (report.reportedUser ? 'No contact details' : 'Restricted outside TODA scope')}</small></span><span data-label="Details">{report.details || 'No details provided.'}{report.action && <small>Action: {report.action}</small>}</span>{report.status === 'open' && <span data-label="Actions" className="actions"><button className="primary" onClick={() => action(report.id, 'resolved')}>Resolve</button><button onClick={() => action(report.id, 'dismissed')}>Dismiss</button>{!todaId && report.reportedUser?.isActive !== false && <button className="danger-outline" onClick={() => suspendReportedUser(report)}>Suspend reported account</button>}</span>}{!todaId && report.reportedUser?.isActive === false && <span data-label="Actions" className="actions"><button className="primary" onClick={() => restoreReportedUser(report)}>Restore after evaluation</button></span>}</div>)}{reports.length === 0 && <p className="muted">No reports are available in this scope.</p>}{nextCursor && <button onClick={loadMore} disabled={loadingMore}>{loadingMore ? 'Loading…' : 'Load older reports'}</button>}</div></section>;
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

  useRefreshOnVisible(load, overviewMetricsRefreshMs);

  async function resolveDispute(booking: BookingOperation) {
    const resolution = window.prompt('Settlement dispute resolution:')?.trim();
    if (!resolution) return;
    await adminApi.resolveSettlementDispute(booking.bookingId, resolution);
    await load();
  }

  return <section className="panel wide">
    <h2>{session.role === 'developer_admin' ? 'All bookings and cash settlements' : 'TODA bookings and cash settlements'}</h2>
    <p className="muted">{session.role === 'developer_admin' ? 'Every Firebase booking is available here, including pending, active, completed, and cancelled rides.' : 'Firebase restricts this list to bookings assigned to a driver in your TODA.'} Newest activity appears first and refreshes every 15 seconds. Search names, booking reference, driver ID, plate, receipt, or lifecycle status.</p>
    <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search ride operations" aria-label="Search ride operations" />
    {error && <div className="notice">{error}</div>}
    <div className="table">
      {items.map((booking) => <div className="row operation" key={booking.bookingId}>
        <span data-label="Passenger and route"><b>{booking.passengerName}</b><small>{booking.pickupName || booking.pickupAddress} → {booking.destinationName || booking.destinationAddress}</small><small className="muted">{booking.pickupName && booking.pickupAddress !== booking.pickupName ? booking.pickupAddress : ''}{booking.pickupName && booking.destinationName ? ' → ' : ''}{booking.destinationName && booking.destinationAddress !== booking.destinationName ? booking.destinationAddress : ''}</small><small className="technical-id">Booking: {booking.bookingId}</small></span>
        <span data-label="Driver"><b>{booking.driverName || 'Searching for driver'}</b><small>{booking.plateNumber || 'No plate assigned'} · {booking.todaName || 'No TODA assigned'}</small></span>
        {(booking.routeStops.length > 2 || booking.passengerNote) && <span data-label="Ordered drop-offs"><b>{booking.dropoffCount} drop-off{booking.dropoffCount === 1 ? '' : 's'}</b>{booking.routeStops.filter((stop) => stop.type === 'dropoff').map((stop, index) => <small key={`${booking.bookingId}-${stop.sequence}`}>{index + 1}. {stop.name || stop.address || 'Drop-off'}{stop.final ? ' (final)' : ''} · {statusLabel(stop.status || 'pending')}</small>)}{booking.passengerNote && <small className="notice">Passenger note: {booking.passengerNote}</small>}</span>}
        <span data-label="Ride status" className={`status-cell ${booking.status === 'cancelled' ? 'warning' : booking.status === 'completed' ? 'ok' : ''}`}>{statusLabel(booking.status)}{booking.cancellationCode && <small>{statusLabel(booking.cancellationCode)}</small>}</span>
        <span data-label="Fare and settlement"><b>{peso(booking.amountDue)}</b><small>{booking.paymentMethod} · {statusLabel(booking.settlementStatus)}</small><small>Adjustment: {statusLabel(booking.adjustmentStatus)}</small>{booking.receiptNumber && <small>Receipt: {booking.receiptNumber}</small>}{booking.adjustmentStatus === 'disputed' && <button onClick={() => resolveDispute(booking)}>Resolve dispute</button>}</span>
      </div>)}
      {loading && items.length === 0 && <p className="muted">Loading Firebase bookings…</p>}
      {!loading && !error && items.length === 0 && <p className="muted">No ride operations match this search.</p>}
    </div>
    <button onClick={() => load(nextCursor, true)} disabled={loading || !nextCursor}>{loading ? 'Loading…' : nextCursor ? 'Load next page' : 'End of results'}</button>
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
  useRefreshOnVisible(refresh);
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
      `Status: ${statusLabel(incident.bookingStatus)}`,
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
        <AdminLocationMap points={points} selectedId={selectedId} onSelect={setSelectedId} ariaLabel="Safety incident operations map" />
      </Suspense>
    </section>
    <section className="panel wide">
      <div className="table">{incidents.map((incident) => <div className="row report safety-incident-row" key={incident.id}>
        <span data-label="Incident"><b>{incident.category.toUpperCase()} · {statusLabel(incident.responseStatus || incident.status)}</b><small>{incident.createdAt ? new Date(incident.createdAt).toLocaleString('en-PH') : 'Date unavailable'}</small><small>Booking {incident.bookingId}</small><small>Alert: {statusLabel(incident.deliveryStatus || 'legacy record')} · escalation level {incident.escalationLevel || 0}</small></span>
        <span data-label="People"><b>Reported by {incident.reporterRole}</b><small>Passenger: {incident.passengerName || incident.passengerId}</small><small>Driver: {incident.driverName || incident.driverId || 'Not assigned'}</small><small>TODA: {incident.todaName || incident.todaId || 'Not assigned'}</small></span>
        <span data-label="Ride and location" className="warning">{statusLabel(incident.bookingStatus)}<small>{incident.pickupAddress || 'Pickup unavailable'} → {incident.destinationAddress || 'Destination unavailable'}</small><small>{incident.locationSource === 'live_driver_location' ? 'Live driver location' : 'SOS location snapshot'}{incident.driverLocation?.timestamp ? ` · ${new Date(incident.driverLocation.timestamp).toLocaleTimeString('en-PH')}` : ''}</small>{incident.lastResponseNote && <small>Latest note: {incident.lastResponseNote}</small>}{incident.resolutionNote && <small>Resolution: {incident.resolutionNote}</small>}</span>
        <span data-label="Response actions" className="actions">
          {incident.driverLocation && <button onClick={() => setSelectedId(incident.id)}>View location</button>}
          <button onClick={contact911}>Call 911</button>
          {!['accidental', 'resolved', 'reporter_safe'].includes(incident.status) && (incident.responseStatus || 'reported') === 'reported' && <button className="primary" onClick={() => updateResponse(incident, 'acknowledge')}>Acknowledge SOS</button>}
          {!['accidental', 'resolved', 'reporter_safe'].includes(incident.status) && !['responding', 'resolved'].includes(incident.responseStatus || 'reported') && <button onClick={() => updateResponse(incident, 'responding')}>Start response</button>}
          {!['accidental', 'resolved', 'reporter_safe'].includes(incident.status) && incident.responseStatus !== 'resolved' && <button onClick={() => updateResponse(incident, 'resolve')}>Resolve with note</button>}
          {incident.status === 'open' && incident.bookingStatus !== 'cancelled' && !incident.bookingCancelledForSafety && <button className="danger-outline" onClick={() => cancelAfterTimeout(incident)} disabled={!timeoutReached(incident) || ['passenger_on_board', 'payment_confirmation'].includes(incident.bookingStatus)}>Cancel after 5 min unresponsive</button>}
          {incident.status === 'open' && !timeoutReached(incident) && <small>Five-minute contact window still active.</small>}
        </span>
      </div>)}{loading && <p className="muted">Loading safety incidents…</p>}{!loading && incidents.length === 0 && <p className="muted">No safety incidents in this scope.</p>}</div>
    </section>
  </>;
}

function RouteRestrictionsPage({ onMessage }: { onMessage: (value: string) => void }) {
  const [restrictions, setRestrictions] = useState<RouteRestriction[]>([]);
  const [name, setName] = useState('');
  const [type, setType] = useState<RouteRestriction['type']>('no_service_area');
  const [notes, setNotes] = useState('');
  const [points, setPoints] = useState<Point[]>([]);
  const [completedAreas, setCompletedAreas] = useState<Point[][]>([]);
  const [bufferMeters, setBufferMeters] = useState(20);
  const [minimumAlignedTravelMeters, setMinimumAlignedTravelMeters] = useState(80);

  const reload = useCallback(async () => {
    try {
      setRestrictions(await adminApi.routeRestrictions());
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to load route restrictions.');
    }
  }, [onMessage]);
  useEffect(() => { void reload(); }, [reload]);

  const isHighway = type === 'prohibited_highway';
  const geometryType = isHighway ? 'corridor' : 'polygon';
  const minimumPoints = isHighway ? 2 : 3;
  const hasIncompleteDraft = points.length > 0 && points.length < minimumPoints;
  const allAreas = [
    ...completedAreas,
    ...(points.length >= minimumPoints ? [points] : []),
  ];
  const savedAreas = restrictions
    .filter((item) => item.isActive && item.geometryType === geometryType && (isHighway ? item.type === 'prohibited_highway' : item.type === 'no_service_area' || item.type === 'restricted_crossing'))
    .flatMap((item) => item.areas?.length ? item.areas : [item.polygon])
    .filter((area) => area.length >= minimumPoints);

  function finishGeometry() {
    if (points.length >= minimumPoints && completedAreas.length < 20) {
      setCompletedAreas([...completedAreas, points]);
      setPoints([]);
    }
  }

  async function create() {
    if (!name.trim() || allAreas.length === 0 || hasIncompleteDraft) {
      onMessage('Enter a restriction name and finish every polygon with at least three coordinates.');
      return;
    }
    try {
      await adminApi.createRouteRestriction(
        name.trim(),
        type,
        geometryType,
        allAreas[0],
        isHighway ? bufferMeters : 0,
        notes,
        allAreas,
        isHighway ? minimumAlignedTravelMeters : undefined,
      );
      setName('');
      setNotes('');
      setPoints([]);
      setCompletedAreas([]);
      onMessage(isHighway
        ? 'Highway group saved. Routes that travel along it are rejected; normal perpendicular crossings remain allowed.'
        : 'Route restriction saved and active. Restriction-aware route checks will use it after their next refresh.');
      await reload();
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to save restriction.');
    }
  }

  async function toggle(item: RouteRestriction) {
    try {
      await adminApi.setRouteRestrictionStatus(item.id, !item.isActive);
      onMessage(`${item.name} is now ${item.isActive ? 'disabled' : 'active'}. Restriction-aware route checks will use the change after refresh.`);
      await reload();
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to update restriction.');
    }
  }

  function changeType(next: RouteRestriction['type']) {
    setType(next);
    setPoints([]);
    setCompletedAreas([]);
  }

  return <>
    <section className="panel wide">
      <h2>Create a route restriction</h2>
      <p className="muted">
        No-service and restricted driving MultiPolygons block pickup,
        destination, and crossing routes. A highway group holds up to 20 curved
        centreline segments. Only sustained travel alongside a segment is
        blocked, so ordinary cross-street crossings remain allowed.
      </p>
      <div className="form-grid">
        <input value={name} onChange={(event) => setName(event.target.value)} placeholder="Restriction name" required />
        <select value={type} onChange={(event) => changeType(event.target.value as RouteRestriction['type'])}>
          <option value="no_service_area">No-service MultiPolygon</option>
          <option value="restricted_crossing">Restricted driving area</option>
          <option value="prohibited_highway">Highway group (polyline)</option>
        </select>
        {isHighway && <label>Highway buffer (metres)<input type="number" min="5" max="200" value={bufferMeters} onChange={(event) => setBufferMeters(Number(event.target.value))} /></label>}
        {isHighway && <label>Minimum aligned travel (metres)<input type="number" min="30" max="1000" value={minimumAlignedTravelMeters} onChange={(event) => setMinimumAlignedTravelMeters(Number(event.target.value))} /></label>}
      </div>
      <Suspense fallback={<div className="map-missing">Loading Mapbox route-restriction editor...</div>}>
        <PolygonEditor
          points={points}
          completedAreas={completedAreas}
          savedAreas={savedAreas}
          onChange={setPoints}
          onFinish={finishGeometry}
          disabled={completedAreas.length >= 20}
          geometryMode={isHighway ? 'polyline' : 'polygon'}
          maxPoints={200}
        />
      </Suspense>
      <div className="map-actions">
        <span>
          {allAreas.length} {isHighway ? 'segment(s)' : 'area(s)'} | current shape {points.length}/200 points
        </span>
        <button onClick={() => setPoints(points.slice(0, -1))} disabled={!points.length}>Undo point</button>
        <button
          onClick={finishGeometry}
          disabled={points.length < minimumPoints || completedAreas.length >= 20}
        >
          {isHighway ? 'Add another segment' : 'Add another area'}
        </button>
        <button onClick={() => { setPoints([]); setCompletedAreas([]); }} disabled={!points.length && !completedAreas.length}>Clear all</button>
        <button className="primary" onClick={create} disabled={allAreas.length === 0 || !name.trim() || hasIncompleteDraft}>Save restriction</button>
      </div>
      <textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Operational reason and driver guidance" />
    </section>
    <section className="panel wide">
      <h2>Active and archived restrictions</h2>
      <p className="muted">
        A highway group is direction-and-distance checked: a route must follow
        its centreline inside the configured buffer for the configured distance.
        A normal perpendicular crossing is not treated as highway travel.
      </p>
      <div className="table">
        {restrictions.map((item) => {
          const itemAreas = item.areas?.length ? item.areas : [item.polygon];
          const itemType = item.type === 'restricted_crossing'
            ? 'Restricted driving area'
            : item.type === 'no_service_area'
              ? 'No-service MultiPolygon'
              : 'Highway group (aligned travel)';
          return <div className="row" key={item.id}>
            <span data-label="Restriction">
              <b>{item.name}</b>
              <small>{itemType} | {item.geometryType === 'corridor' ? `${itemAreas.length} retained segment${itemAreas.length === 1 ? '' : 's'} | ${item.bufferMeters || 0} m buffer` : `${itemAreas.length} polygon${itemAreas.length === 1 ? '' : 's'}`} | {item.geometryVersion ? `geometry v${item.geometryVersion}` : 'legacy geometry'}</small>
              <small>{geometrySummary(itemAreas)}</small>
            </span>
            <span data-label="Guidance">{item.notes || 'No operational guidance supplied'}</span>
            <span data-label="Status" className={`status-cell ${item.isActive ? 'warning' : 'ok'}`}>
              {item.isActive
                ? item.type === 'prohibited_highway'
                  ? 'Active in route checks and driver highway warnings'
                  : 'Active in route and live-driver checks'
                : 'Disabled and retained for audit'}
            </span>
            <span data-label="Actions" className="actions"><button onClick={() => toggle(item)}>{item.isActive ? 'Disable' : 'Enable'}</button></span>
          </div>;
        })}
        {restrictions.length === 0 && <p className="muted">No active or archived route restrictions were found.</p>}
      </div>
    </section>
  </>;
}

function CoveragePage({ session, onMessage }: { session: AdminSession; onMessage: (value: string) => void }) {
  const [todas, setTodas] = useState<Toda[]>([]);
  const [todaId, setTodaId] = useState(session.todaId || '');
  const [points, setPoints] = useState<Point[]>([]);
  const [completedAreas, setCompletedAreas] = useState<Point[][]>([]);
  const [notes, setNotes] = useState('');
  const [zones, setZones] = useState<ZoneRequest[]>([]);
  const [editingZoneId, setEditingZoneId] = useState<string | null>(null);
  const isDeveloper = session.role === 'developer_admin';
  const reload = useCallback(async () => {
    try {
      const scope = isDeveloper ? undefined : session.todaId || undefined;
      const [todaList, zoneList] = await Promise.all([
        adminApi.todas(),
        adminApi.zones(scope),
      ]);
      setTodas(todaList);
      setZones(zoneList);
      if (!isDeveloper && session.todaId) setTodaId(session.todaId);
      else if (!todaId && todaList[0]) setTodaId(todaList[0].id);
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to load coverage requests.');
    }
  }, [isDeveloper, onMessage, session.todaId, todaId]);
  useEffect(() => { void reload(); }, [reload]);

  const areas = [...completedAreas, ...(points.length >= 3 ? [points] : [])];
  const hasIncompleteAreaDraft = points.length > 0 && points.length < 3;
  const selectedName = useMemo(() => todas.find((toda) => toda.id === todaId)?.name || 'selected TODA', [todas, todaId]);
  const todaNames = useMemo(() => new Map(todas.map((toda) => [toda.id, toda.name])), [todas]);

  function addAnotherArea() {
    // The current polygon becomes the next drawable area. Keep the twentieth
    // polygon current so Enter cannot commit it and open a twenty-first area.
    if (points.length >= 3 && completedAreas.length < 19) {
      setCompletedAreas([...completedAreas, points]);
      setPoints([]);
    }
  }

  function resetEditor() {
    setPoints([]);
    setCompletedAreas([]);
    setNotes('');
    setEditingZoneId(null);
  }

  function changeToda(nextTodaId: string) {
    setTodaId(nextTodaId);
    resetEditor();
  }

  async function submit() {
    if (hasIncompleteAreaDraft) { onMessage('Finish the current polygon with at least three points, or undo it before submitting.'); return; }
    if (areas.length === 0) { onMessage('Draw at least one polygon with three points.'); return; }
    if (!todaId) { onMessage('Select a TODA before submitting coverage.'); return; }
    const wasEditing = Boolean(editingZoneId);
    try {
      if (editingZoneId) await adminApi.updateZone(editingZoneId, areas[0], notes, areas);
      else await adminApi.submitZone(todaId, areas[0], notes, areas);
      resetEditor();
      if (wasEditing) {
        onMessage(isDeveloper
          ? 'Coverage request polygons updated. The request remains pending until it is approved or declined.'
          : 'Your pending coverage request was updated and sent back for System Admin review.');
      } else {
        onMessage(isDeveloper
          ? `Coverage request created for ${selectedName}; it remains pending System Admin review.`
          : 'Coverage request submitted for System Admin review.');
      }
      await reload();
    } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to save coverage polygons.'); }
  }

  async function review(id: string, status: 'approved' | 'declined') {
    if (editingZoneId === id) {
      onMessage('Save or cancel the pending geometry edit before reviewing this request.');
      return;
    }
    try {
      await adminApi.reviewZone(id, status);
      onMessage(status === 'approved'
        ? 'Coverage request approved. Its geometry is now the TODA coverage record.'
        : 'Coverage request declined; the current approved TODA coverage was not replaced.');
      await reload();
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to review zone.');
    }
  }

  function canEditZone(zone: ZoneRequest) {
    return zone.status === 'pending'
      && (isDeveloper || Boolean(session.todaId && zone.todaId === session.todaId));
  }

  function editZone(zone: ZoneRequest) {
    if (!canEditZone(zone)) {
      onMessage('Only a pending coverage request owned by your TODA can be edited.');
      return;
    }
    const zoneAreas = (zone.areas?.length ? zone.areas : [zone.polygon])
      .filter((area) => area.length >= 3);
    if (zoneAreas.length === 0) {
      onMessage('This request has no valid polygon coordinates to edit.');
      return;
    }
    setTodaId(zone.todaId);
    setCompletedAreas(zoneAreas.slice(0, -1));
    setPoints(zoneAreas[zoneAreas.length - 1]);
    setNotes(zone.notes || '');
    setEditingZoneId(zone.id);
  }

  return <>
    <section className="panel wide">
      <h2>{isDeveloper ? 'Create or review coverage areas' : 'Request TODA coverage area'}</h2>
      <p className="muted">Create one or several disconnected operating polygons. Select Add another area after finishing each shape; the System Admin approves the complete TODA coverage request together. A TODA administrator may revise its own request while it is pending; approved and declined requests are read-only.</p>
      {isDeveloper && <select value={todaId} onChange={(event) => changeToda(event.target.value)} disabled={editingZoneId !== null}>
        <option value="">Select TODA</option>
        {todas.map((toda) => <option key={toda.id} value={toda.id}>{toda.name}</option>)}
      </select>}
      {editingZoneId && <p className="muted">Editing pending request {editingZoneId} for {selectedName}. Save it to keep the revised coordinates, or cancel to leave the request unchanged.</p>}
      <Suspense fallback={<div className="map-missing">Loading Mapbox coverage editor...</div>}>
        <PolygonEditor points={points} completedAreas={completedAreas} onChange={setPoints} onFinish={addAnotherArea} />
      </Suspense>
      <div className="map-actions">
        <span>{areas.length} area{areas.length === 1 ? '' : 's'} for {selectedName} | current shape: {points.length} points</span>
        <button onClick={() => setPoints(points.slice(0, -1))} disabled={!points.length}>Undo point</button>
        <button onClick={addAnotherArea} disabled={points.length < 3 || completedAreas.length >= 19}>Add another area</button>
        <button onClick={() => { setPoints([]); setCompletedAreas([]); }} disabled={!points.length && !completedAreas.length}>Clear geometry</button>
        {editingZoneId && <button onClick={resetEditor}>Cancel edit</button>}
        <button className="primary" onClick={submit} disabled={areas.length === 0 || !todaId || hasIncompleteAreaDraft}>{editingZoneId ? 'Save pending request' : 'Submit coverage request'}</button>
      </div>
      <textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Route/terminal notes for the reviewer" />
    </section>
    <section className="panel wide">
      <h2>{isDeveloper ? 'Coverage requests' : 'My TODA zone requests'}</h2>
      <div className="table">
        {zones.map((zone) => {
          const zoneAreas = zone.areas?.length ? zone.areas : [zone.polygon];
          return <div className="row" key={zone.id}>
            <span data-label="TODA and request">
              <b>{todaNames.get(zone.todaId) || zone.todaId}</b>
              <small>Request {zone.id} | {zone.geometryVersion ? `geometry v${zone.geometryVersion}` : 'legacy geometry'}</small>
              <small>{geometrySummary(zoneAreas)}</small>
            </span>
            <span data-label="Notes">{zone.notes || 'No route or terminal notes supplied'}</span>
            <span data-label="Status" className={`status-cell ${zone.status === 'approved' ? 'ok' : 'warning'}`}>{zoneStatusLabel(zone.status)}</span>
            {canEditZone(zone) && <span data-label="Actions" className="actions">
              <button onClick={() => editZone(zone)}>Edit pending request</button>
              {isDeveloper && <>
                <button
                  onClick={() => review(zone.id, 'approved')}
                  disabled={editingZoneId === zone.id}
                >
                  Approve
                </button>
                <button
                  onClick={() => review(zone.id, 'declined')}
                  disabled={editingZoneId === zone.id}
                >
                  Decline
                </button>
              </>}
            </span>}
          </div>;
        })}
        {zones.length === 0 && <p className="muted">No coverage requests were found for this scope.</p>}
      </div>
    </section>
  </>;
}

