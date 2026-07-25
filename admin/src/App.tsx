import { FormEvent, lazy, Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import { onAuthStateChanged, signInWithEmailAndPassword, signOut, type User } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { auth, db } from './firebase';
import { adminApi } from './admin-api';
import { bacolodBarangays } from './data/bacolodBarangays';
import type { AdminSession, Driver, FareConfig, Point, Report, Toda, TodaRegistration, ZoneRequest } from './types';

// Mapbox is substantial; only load it when an administrator opens Coverage.
const PolygonEditor = lazy(() => import('./components/PolygonEditor').then((module) => ({ default: module.PolygonEditor })));

type Page = 'overview' | 'todas' | 'fares' | 'drivers' | 'reports' | 'coverage';
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
  if (!session) return <Bootstrap user={user} reload={() => loadSession(auth.currentUser)} onMessage={setMessage} message={message} />;

  const isDeveloper = session.role === 'developer_admin';
  const visiblePages: Array<[Page, string]> = isDeveloper
    ? [['overview', 'Overview'], ['todas', 'TODAs'], ['fares', 'City fares'], ['drivers', 'Drivers'], ['reports', 'Reports'], ['coverage', 'Coverage areas']]
    : [['overview', 'Overview'], ['drivers', 'My drivers'], ['reports', 'TODA reports'], ['coverage', 'Zone request']];
  return <div className="shell">
    <aside className="sidebar"><div className="brand"><img src="/logo.png" onError={(event) => { event.currentTarget.style.display = 'none'; }} /><span>VolTrike<br /><b>Admin</b></span></div><div className="role-pill">{isDeveloper ? 'Developer Admin' : 'TODA Admin'}</div>
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
    </main>
  </div>;
}

function Login({ message, onMessage }: { message: string; onMessage: (value: string) => void }) {
  const [email, setEmail] = useState(''); const [password, setPassword] = useState(''); const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); try { await signInWithEmailAndPassword(auth, email.trim(), password); } catch { onMessage('Unable to sign in. Check the email and password.'); } finally { setBusy(false); } }
  return <main className="auth"><section><img src="/logo.png" className="auth-logo" /><p className="eyebrow">VolTrike operations</p><h1>Admin Portal</h1><p>Authorized Bacolod TODA and developer operations only.</p>{message && <div className="notice">{message}</div>}<form onSubmit={submit}><input type="email" placeholder="Email address" value={email} onChange={(e) => setEmail(e.target.value)} required /><input type="password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} required /><button className="primary" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button></form></section></main>;
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

function Todas({ onMessage }: { onMessage: (value: string) => void }) {
  const [todas, setTodas] = useState<Toda[]>([]); const [name, setName] = useState('Test TODA'); const [barangayCode, setBarangayCode] = useState('064501059'); const [registration, setRegistration] = useState<TodaRegistration>({ secCertificateNumber: '', spResolutionNumber: '', mayorsPermitNumber: '', barangayClearanceNumber: '', presidentName: '', presidentLicenseNumber: '', presidentTin: '' }); const [documents, setDocuments] = useState<Record<string, File>>({}); const [targetUid, setTargetUid] = useState(''); const [selectedToda, setSelectedToda] = useState('');
  const reload = useCallback(() => adminApi.todas().then((items) => { setTodas(items); if (!selectedToda && items[0]) setSelectedToda(items[0].id); }), [selectedToda]); useEffect(() => { reload(); }, [reload]);
  async function create(event: FormEvent) { event.preventDefault(); const requiredDocuments = ['secCertificate', 'spResolution', 'mayorsPermit', 'barangayClearance']; if (!requiredDocuments.every((key) => documents[key])) { onMessage('Upload the SEC certificate, SP resolution, Mayor’s permit, and Barangay clearance.'); return; } try { const result = await adminApi.createToda({ name, barangayCode, registration }); await adminApi.uploadTodaDocuments(result.todaId, documents); onMessage(`TODA registered with legal documents. ID: ${result.todaId}`); setDocuments({}); await reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to create TODA.'); } }
  async function assign(event: FormEvent) { event.preventDefault(); try { await adminApi.assignTodaAdmin(targetUid.trim(), selectedToda); onMessage('Account promoted to TODA admin. Its former driver profile is suspended. The user must sign out and sign in again.'); setTargetUid(''); await reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to assign TODA admin.'); } }
  async function toggleToda(toda: Toda) { if (!window.confirm(`${toda.isActive ? 'Suspend' : 'restore'} ${toda.name}?`)) return; try { await adminApi.setTodaStatus(toda.id, !toda.isActive); onMessage(`${toda.name} ${toda.isActive ? 'suspended' : 'restored'}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update TODA.'); } }
  return <div className="two-column"><section className="panel"><h2>Register TODA</h2><p className="muted">Collects official city-registration details and four legal evidence files. Only official Bacolod barangays are accepted.</p><form className="form-grid" onSubmit={create}><input value={name} onChange={(e) => setName(e.target.value)} placeholder="TODA name" required /><select value={barangayCode} onChange={(e) => setBarangayCode(e.target.value)} required>{bacolodBarangays.map(([code, barangay]) => <option key={code} value={code}>{barangay} — {code}</option>)}</select>{registrationFields.map(([key, title]) => <input key={key} value={registration[key]} onChange={(e) => setRegistration({ ...registration, [key]: e.target.value })} placeholder={title} required />)}{[['secCertificate', 'SEC certificate'], ['spResolution', 'SP resolution'], ['mayorsPermit', "Mayor's permit / BPLO license"], ['barangayClearance', 'Barangay clearance']].map(([key, title]) => <label className="file-label" key={key}>{title}<input type="file" accept="image/*,application/pdf" onChange={(event) => { const file = event.target.files?.[0]; if (file) setDocuments({ ...documents, [key]: file }); }} required /></label>)}<button className="primary">Create TODA</button></form></section><section className="panel"><h2>Test TODA administrator</h2><p className="muted">Enter the Firebase Authentication UID of the existing test-driver account. Promotion intentionally suspends its driving profile.</p><form className="form-grid" onSubmit={assign}><select value={selectedToda} onChange={(e) => setSelectedToda(e.target.value)} required><option value="">Select TODA</option>{todas.map((toda) => <option key={toda.id} value={toda.id}>{toda.name} — {toda.barangayCode}</option>)}</select><input value={targetUid} onChange={(e) => setTargetUid(e.target.value)} placeholder="Existing driver Firebase UID" required /><button className="primary">Make TODA admin</button></form><h3>Registered TODAs</h3><div className="table">{todas.map((toda) => <div className="row" key={toda.id}><b>{toda.name}</b><span>{toda.barangayCode}</span><span className={toda.isActive ? 'ok' : 'warning'}>{toda.isActive ? 'Active' : 'Suspended'}</span><button onClick={() => toggleToda(toda)}>{toda.isActive ? 'Suspend' : 'Restore'}</button></div>)}</div></section></div>;
}

function Fares({ onMessage }: { onMessage: (value: string) => void }) {
  const [fare, setFare] = useState<FareConfig>(initialFare); useEffect(() => { adminApi.fare().then(setFare); }, []);
  async function submit(event: FormEvent) { event.preventDefault(); try { await adminApi.updateFare(fare); onMessage('City fare configuration saved in Philippine pesos. New passenger estimates will use it.'); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update fares.'); } }
  return <section className="panel wide"><h2>City-controlled passenger fares</h2><p className="muted">TODA administrators can view the city fares but cannot change them. All amounts are PHP.</p><form className="form-grid fare-grid" onSubmit={submit}>{(Object.keys(fare) as Array<keyof FareConfig>).map((key) => <label key={key}>{label(key)}<input type="number" min={key === 'baseFare' || key.includes('Meters') ? 1 : 0} max="9999" value={fare[key]} onChange={(e) => setFare({ ...fare, [key]: Number(e.target.value) })} required /></label>)}<button className="primary">Save city fare</button></form><div className="fare-summary">Example: base {peso(fare.baseFare)} includes {fare.includedMeters} m; then {peso(fare.distanceStepPrice)} every {fare.distanceStepMeters} m. Additional passenger, large baggage, and out-of-TODA fees are applied exactly once.</div></section>;
}

function DriversPage({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [drivers, setDrivers] = useState<Driver[]>([]); const reload = useCallback(() => adminApi.drivers(todaId).then(setDrivers), [todaId]); useEffect(() => { reload(); }, [reload]);
  async function update(uid: string, status: string) { try { await adminApi.setDriverStatus(uid, status); onMessage(`Driver ${status}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update driver.'); } }
  return <section className="panel wide"><h2>{todaId ? 'Drivers registered in this TODA' : 'All registered drivers'}</h2><div className="table">{drivers.map((driver) => <div className="row driver" key={driver.uid}><span><b>{driver.uid}</b><small>TODA: {driver.todaId}</small></span><span>{driver.driverStatus}</span><span>★ {driver.rating || 0} · {driver.completedTrips || 0} trips<br /><small>{peso(driver.totalEarnings || 0)} earnings</small></span><span className="actions"><button onClick={() => update(driver.uid, 'approved')}>Approve</button><button onClick={() => update(driver.uid, 'suspended')}>Suspend</button><button onClick={() => update(driver.uid, 'rejected')}>Reject</button></span></div>)}{drivers.length === 0 && <p className="muted">No drivers are available in this scope.</p>}</div></section>;
}

function ReportsPage({ todaId, onMessage }: { todaId?: string; onMessage: (value: string) => void }) {
  const [reports, setReports] = useState<Report[]>([]); const reload = useCallback(() => adminApi.reports(todaId).then(setReports), [todaId]); useEffect(() => { reload(); }, [reload]);
  async function action(id: string, status: string) { const note = window.prompt('Action note (optional):') ?? ''; try { await adminApi.resolveReport(id, status, note); onMessage(`Report ${status}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to update report.'); } }
  async function suspendReportedUser(uid: string) { if (!window.confirm('Suspend this reported account? This prevents it from using VolTrike.')) return; try { await adminApi.setUserStatus(uid, false); onMessage('Reported account suspended.'); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to suspend account.'); } }
  return <section className="panel wide"><h2>Ride reports</h2><div className="table">{reports.map((report) => <div className="row report" key={report.id}><span><b>{report.category}</b><small>Booking {report.bookingId}</small><small>Reported user: {report.reportedUserId}</small></span><span>{report.details || 'No details provided.'}</span><span className={report.status === 'open' ? 'warning' : 'ok'}>{report.status}</span>{report.status === 'open' && <span className="actions"><button onClick={() => action(report.id, 'resolved')}>Resolve</button><button onClick={() => action(report.id, 'dismissed')}>Dismiss</button>{!todaId && <button onClick={() => suspendReportedUser(report.reportedUserId)}>Suspend user</button>}</span>}</div>)}{reports.length === 0 && <p className="muted">No reports are available in this scope.</p>}</div></section>;
}

function CoveragePage({ session, onMessage }: { session: AdminSession; onMessage: (value: string) => void }) {
  const [todas, setTodas] = useState<Toda[]>([]); const [todaId, setTodaId] = useState(session.todaId || ''); const [points, setPoints] = useState<Point[]>([]); const [notes, setNotes] = useState(''); const [zones, setZones] = useState<ZoneRequest[]>([]); const [editingZoneId, setEditingZoneId] = useState<string | null>(null);
  const reload = useCallback(async () => { const scope = session.role === 'developer_admin' ? undefined : session.todaId!; const [todoList, zoneList] = await Promise.all([adminApi.todas(), adminApi.zones(scope)]); setTodas(todoList); setZones(zoneList); if (!todaId && todoList[0]) setTodaId(todoList[0].id); }, [session, todaId]); useEffect(() => { reload(); }, [reload]);
  async function submit() { try { if (editingZoneId) { await adminApi.updateZone(editingZoneId, points, notes); onMessage('Zone request polygon updated. You can now approve or decline it.'); } else { await adminApi.submitZone(todaId, points, notes); onMessage('Polygon zone request submitted for developer review.'); } setPoints([]); setNotes(''); setEditingZoneId(null); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'A polygon needs at least three points.'); } }
  async function review(id: string, status: string) { try { await adminApi.reviewZone(id, status); onMessage(`Zone request ${status}.`); reload(); } catch (error) { onMessage(error instanceof Error ? error.message : 'Unable to review zone.'); } }
  const selectedName = useMemo(() => todas.find((toda) => toda.id === todaId)?.name || 'selected TODA', [todas, todaId]);
  return <><section className="panel wide"><h2>{session.role === 'developer_admin' ? 'Create or review coverage areas' : 'Request TODA coverage area'}</h2><p className="muted">Choose a TODA, then left-click the map to add points. Press <b>Enter</b> or use Finish polygon when at least three points have been added. The developer admin approves or declines the request.</p>{session.role === 'developer_admin' && <select value={todaId} onChange={(e) => setTodaId(e.target.value)}><option value="">Select TODA</option>{todas.map((toda) => <option key={toda.id} value={toda.id}>{toda.name}</option>)}</select>}<Suspense fallback={<div className="map-missing">Loading Mapbox coverage editor…</div>}><PolygonEditor points={points} onChange={setPoints} onFinish={submit} /></Suspense><div className="map-actions"><span>{points.length} points for {selectedName}</span><button onClick={() => setPoints(points.slice(0, -1))} disabled={!points.length}>Undo point</button><button onClick={() => { setPoints([]); setEditingZoneId(null); }} disabled={!points.length}>Clear</button><button className="primary" onClick={submit} disabled={points.length < 3 || !todaId}>{editingZoneId ? 'Save edited polygon' : 'Finish polygon & request review'}</button></div><textarea value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Route/terminal notes for the reviewer" /></section><section className="panel wide"><h2>{session.role === 'developer_admin' ? 'Pending zone requests' : 'My TODA zone requests'}</h2><div className="table">{zones.map((zone) => <div className="row" key={zone.id}><span><b>{zone.todaId}</b><small>{zone.polygon.length} polygon points</small></span><span>{zone.notes || 'No notes'}</span><span className={zone.status === 'pending' ? 'warning' : 'ok'}>{zone.status}</span>{session.role === 'developer_admin' && zone.status === 'pending' && <span className="actions"><button onClick={() => { setTodaId(zone.todaId); setPoints(zone.polygon); setNotes(zone.notes || ''); setEditingZoneId(zone.id); }}>Edit</button><button onClick={() => review(zone.id, 'approved')}>Approve</button><button onClick={() => review(zone.id, 'declined')}>Decline</button></span>}</div>)}</div></section></>;
}
