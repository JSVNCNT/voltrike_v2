import { FormEvent, useEffect, useRef, useState } from 'react';
import { adminApi } from '../admin-api';
import './passenger-privacy.css';

interface Props {
  bookingId: string;
  reportId?: string;
  incidentId?: string;
  chatIncidentId?: string;
}

const labels: Record<string, string> = {
  bookingId: 'Booking', passengerName: 'Passenger', phoneNumber: 'Phone number',
  email: 'Email', pickupAddress: 'Pickup address', destinationAddress: 'Destination address',
  passengerNote: 'Passenger note', cancellationDetail: 'Cancellation explanation',
  details: 'Report details', originalText: 'Original message', displayText: 'Delivered message',
  lastResponseNote: 'Response note', resolutionNote: 'Resolution note', ratingComment: 'Rating comment',
  appealReason: 'Appeal explanation', reasonDetail: 'Cancellation explanation', reviewReason: 'Review explanation',
  manualAppealReason: 'Booking restriction appeal',
};

export function PassengerCaseDetails(props: Props) {
  const [open, setOpen] = useState(false);
  if (!props.bookingId) return null;
  return <>
    <button type="button" onClick={() => setOpen(true)}>Open case details</button>
    {open && <CaseDialog {...props} onClose={() => setOpen(false)} />}
  </>;
}

function CaseDialog({ onClose, ...source }: Props & { onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [reason, setReason] = useState('');
  const [details, setDetails] = useState<Record<string, unknown> | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => {
    dialog.current?.showModal();
  }, []);
  async function reveal(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      const result = await adminApi.revealPassengerDetails({ ...source, reason: reason.trim() });
      setDetails(result.details);
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Unable to open case details.');
    } finally {
      setBusy(false);
    }
  }
  return <dialog className="passenger-case-dialog" ref={dialog} onCancel={onClose}>
    <div className="passenger-case-heading"><h2>Private case details</h2><button type="button" onClick={onClose} aria-label="Close private case details">Close</button></div>
    <p>Access is limited to your administrator scope and recorded with your investigation reason.</p>
    {error && <p role="alert" className="notice">{error}</p>}
    {details ? <dl className="passenger-case-fields">{Object.entries(details).filter(([, value]) => typeof value === 'string' && value.trim()).map(([key, value]) => <div key={key}><dt>{labels[key] || 'Case note'}</dt><dd>{String(value)}</dd></div>)}</dl>
      : <form onSubmit={(event) => void reveal(event)}>
        <label>Investigation reason<textarea required minLength={10} maxLength={500} value={reason} onChange={(event) => setReason(event.target.value)} autoFocus /></label>
        <button className="primary" disabled={busy || reason.trim().length < 10}>{busy ? 'Opening…' : 'Record reason and open details'}</button>
      </form>}
  </dialog>;
}
