import { useCallback, useEffect, useState } from 'react';
import { adminApi, type PassengerCancellation } from '../admin-api';
import { PassengerCaseDetails } from './PassengerCaseDetails';

export function PassengerCancellationsPage() {
  const [items, setItems] = useState<PassengerCancellation[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const load = useCallback(async (next?: string | null) => {
    setLoading(true);
    setError('');
    try {
      const result = await adminApi.passengerCancellations(next);
      setItems((current) => next ? [...current, ...result.items] : result.items);
      setCursor(result.nextCursor || null);
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Unable to load cancellations.');
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => { void load(); }, [load]);
  return <section className="panel wide">
    <h2>Passenger cancellations</h2>
    <p>Three qualifying cancellations within a rolling 24 hours restrict new bookings for 24 hours. Safety and driver-related claims require review. Disputed strikes stop counting during review. Repeat restrictions require System Admin evaluation.</p>
    <button onClick={() => void load()} disabled={loading}>Refresh</button>
    {error && <p role="alert" className="notice">{error}</p>}
    {!loading && items.length === 0 && <p>No cancellation cases recorded.</p>}
    <div className="cancellation-review-list">{items.map((item) => <CancellationCard key={item.bookingId} item={item} onUpdated={() => void load()} />)}</div>
    {cursor && <button onClick={() => void load(cursor)} disabled={loading}>Load older cases</button>}
  </section>;
}

function CancellationCard({ item, onUpdated }: { item: PassengerCancellation; onUpdated: () => void }) {
  const [reason, setReason] = useState('');
  const [hours, setHours] = useState(24);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const blocked = item.blockedUntil && new Date(item.blockedUntil).getTime() > Date.now();
  async function review(decision: 'uphold' | 'waive' | 'restrict' | 'restore') {
    setBusy(true);
    setError('');
    try {
      await adminApi.reviewPassengerCancellation(item.bookingId, decision, reason.trim(), hours);
      setReason('');
      onUpdated();
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Unable to review this cancellation.');
    } finally { setBusy(false); }
  }
  const disabled = busy || reason.trim().length < 10;
  return <article className="cancellation-review-card">
    <h3>{item.passengerName}</h3>
    <p>Booking {item.bookingId} · {item.status.replace(/_/g, ' ')} · {item.reasonCode.replace(/_/g, ' ')}</p>
    <p>{item.strikeCount} current strikes · {item.restrictionCount} recorded automatic restrictions{item.restrictionCount > 1 ? ' · Repeat restrictions: evaluate further action' : ''}</p>
    <p>{blocked ? `Booking restricted until ${new Date(item.blockedUntil!).toLocaleString('en-PH')}` : 'No active booking restriction'}</p>
    {item.manualAppealStatus === 'pending' && <p className="notice">Booking restriction appeal awaiting review. Open case details to read the explanation.</p>}
    {item.reasonCode === 'passenger_no_show' && <p>Arrival verified: {item.arrivalVerified ? 'yes' : 'no'} · Five-minute wait verified: {item.waitVerified ? 'yes' : 'no'}</p>}
    <PassengerCaseDetails bookingId={item.bookingId} />
    <label>Decision reason<textarea minLength={10} maxLength={1000} value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Record the evidence and reason for this decision" /></label>
    <label>Restriction duration (hours)<input type="number" min={1} max={720} value={hours} onChange={(event) => setHours(Number(event.target.value))} /></label>
    {error && <p role="alert">{error}</p>}
    <div className="actions">
      {(item.status === 'pending_review' || item.status === 'disputed') && <button disabled={disabled || item.reasonCode === 'passenger_no_show' && (!item.arrivalVerified || !item.waitVerified)} onClick={() => void review('uphold')}>Count cancellation</button>}
      {item.status !== 'waived' && <button disabled={disabled} onClick={() => void review('waive')}>Waive cancellation</button>}
      <button className="danger-outline" disabled={disabled || !Number.isInteger(hours) || hours < 1 || hours > 720} onClick={() => void review('restrict')}>Restrict new bookings</button>
      <button disabled={disabled} onClick={() => void review('restore')}>Restore booking access</button>
    </div>
  </article>;
}
