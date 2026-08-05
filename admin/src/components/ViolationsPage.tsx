import {
  FormEvent,
  Suspense,
  lazy,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { adminApi } from '../admin-api';
import type {
  AdminSession,
  DriverViolation,
  DriverViolationStatus,
  LiveDriver,
  RouteRestriction,
  ViolationMessage,
} from '../types';
import type { AdminMapPoint } from './AdminLocationMap';
import type { WebPushResult } from '../web-push';

const AdminLocationMap = lazy(() => import('./AdminLocationMap').then(
  (module) => ({ default: module.AdminLocationMap }),
));

interface Props {
  session: AdminSession;
  initialViolationId?: string | null;
  onSelectViolation: (violationId: string | null) => void;
  webPushResult: WebPushResult;
  onEnableWebPush: () => Promise<WebPushResult>;
}

const openStatuses = new Set<DriverViolationStatus>([
  'open',
  'acknowledged',
  'responding',
]);

function humanize(value: string | null | undefined): string {
  if (!value?.trim()) return 'Not recorded';
  if (value === 'responding') return 'Investigating';
  return value
    .split('_')
    .filter(Boolean)
    .map((part) => part[0]?.toUpperCase() + part.slice(1))
    .join(' ');
}

function displayDate(value?: string | null): string {
  if (!value) return 'Time unavailable';
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? 'Time unavailable'
    : date.toLocaleString('en-PH');
}

function messageId(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return `web_${Date.now()}_${Math.random().toString(36).slice(2, 14)}`;
}

function validLocation(violation: DriverViolation): boolean {
  const { latitude, longitude } = violation.eventLocation;
  return Number.isFinite(latitude)
    && Number.isFinite(longitude)
    && Math.abs(latitude) <= 90
    && Math.abs(longitude) <= 180
    && !(latitude === 0 && longitude === 0);
}

function restrictionAreas(violation: DriverViolation) {
  if (violation.restriction?.areas?.length) return violation.restriction.areas;
  if (violation.restriction?.polygon?.length) {
    return [violation.restriction.polygon];
  }
  return [];
}

export function ViolationsPage({
  session,
  initialViolationId,
  onSelectViolation,
  webPushResult,
  onEnableWebPush,
}: Props) {
  const [violations, setViolations] = useState<DriverViolation[]>([]);
  const [liveDrivers, setLiveDrivers] = useState<LiveDriver[]>([]);
  const [routeRestrictions, setRouteRestrictions] = useState<RouteRestriction[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(
    initialViolationId || null,
  );
  const [statusFilter, setStatusFilter] = useState<DriverViolationStatus | ''>('');
  const [classFilter, setClassFilter] = useState('');
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [loadingSelected, setLoadingSelected] = useState(false);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [selectedLoadError, setSelectedLoadError] = useState('');
  const [browserAlertsEnabled, setBrowserAlertsEnabled] = useState(
    webPushResult.enabled ||
      (typeof Notification !== 'undefined' && Notification.permission === 'granted'),
  );
  const [latestAlert, setLatestAlert] = useState<DriverViolation | null>(null);
  const knownOpenIds = useRef<Set<string> | null>(null);
  const hasLoadedMore = useRef(false);
  const selectedIdRef = useRef<string | null>(initialViolationId || null);

  useEffect(() => {
    const nextSelectedId = initialViolationId || null;
    selectedIdRef.current = nextSelectedId;
    setSelectedId(nextSelectedId);
  }, [initialViolationId]);

  useEffect(() => {
    setBrowserAlertsEnabled(
      webPushResult.enabled ||
        (typeof Notification !== 'undefined' &&
          Notification.permission === 'granted'),
    );
  }, [webPushResult.enabled]);

  useEffect(() => {
    void adminApi.routeRestrictions()
      .then(setRouteRestrictions)
      .catch(() => {
        // A violation still has a precise event marker when a legacy case has
        // no geometry snapshot and current restriction geometry cannot load.
      });
  }, []);

  const selectViolation = useCallback((violationId: string | null) => {
    selectedIdRef.current = violationId;
    setSelectedId(violationId);
    onSelectViolation(violationId);
  }, [onSelectViolation]);

  const selectedAlreadyLoaded = selectedId !== null &&
    violations.some((violation) => violation.id === selectedId);

  useEffect(() => {
    if (!selectedId || selectedAlreadyLoaded) {
      setLoadingSelected(false);
      setSelectedLoadError('');
      return;
    }
    let active = true;
    setLoadingSelected(true);
    setSelectedLoadError('');
    void adminApi.violation(selectedId)
      .then((violation) => {
        if (!active) return;
        setViolations((current) => current.some((item) => item.id === violation.id)
          ? current.map((item) => item.id === violation.id ? violation : item)
          : [...current, violation]);
        setSelectedLoadError('');
      })
      .catch((reason) => {
        if (!active) return;
        setSelectedLoadError(reason instanceof Error
          ? reason.message
          : 'Unable to load the linked violation case.');
      })
      .finally(() => {
        if (active) setLoadingSelected(false);
      });
    return () => {
      active = false;
    };
  }, [selectedAlreadyLoaded, selectedId]);

  const notifyNewCases = useCallback((items: DriverViolation[]) => {
    const openCases = items.filter((item) => item.status === 'open');
    const previous = knownOpenIds.current;
    if (previous) {
      const added = openCases.filter((item) => !previous.has(item.id));
      if (added[0]) {
        setLatestAlert(added[0]);
        window.navigator.vibrate?.([220, 100, 220]);
      }
      if (browserAlertsEnabled) {
        added.forEach((item) => {
          const notification = new Notification(
            'VolTrike restriction violation',
            {
              body: `${item.driverName || 'Driver'} · ${humanize(item.eventClass)}`,
              tag: `driver-violation-${item.id}`,
              requireInteraction: item.severity === 'critical',
            },
          );
          notification.onclick = () => {
            window.focus();
            selectViolation(item.id);
            notification.close();
          };
        });
      }
    }
    knownOpenIds.current = new Set(openCases.map((item) => item.id));
  }, [browserAlertsEnabled, selectViolation]);

  const refresh = useCallback(async (
    showLoading = false,
    preserveLoadedPages = false,
  ) => {
    if (showLoading) setLoading(true);
    try {
      const page = await adminApi.violationPage(null, {
        status: statusFilter,
        eventClass: classFilter,
      });
      const preserve = preserveLoadedPages && hasLoadedMore.current;
      setViolations((current) => {
        if (!preserve) {
          const selected = current.find(
            (item) => item.id === selectedIdRef.current,
          );
          return selected &&
              !page.items.some((item) => item.id === selected.id)
            ? [...page.items, selected]
            : page.items;
        }
        const freshIds = new Set(page.items.map((item) => item.id));
        return [
          ...page.items,
          ...current.filter((item) => !freshIds.has(item.id)),
        ];
      });
      if (!preserve) setNextCursor(page.nextCursor);
      notifyNewCases(page.items);
      setError('');
      void adminApi.liveDrivers()
        .then(setLiveDrivers)
        .catch(() => {
          // Current-location markers are optional. The immutable case list
          // and event markers remain available when RTDB is temporarily down.
          setLiveDrivers([]);
        });
    } catch (reason) {
      setError(reason instanceof Error
        ? reason.message
        : 'Unable to load driver violations.');
    } finally {
      setLoading(false);
    }
  }, [classFilter, notifyNewCases, statusFilter]);

  useEffect(() => {
    hasLoadedMore.current = false;
    setNextCursor(null);
    void refresh(true, false);
    const onVisible = () => {
      if (document.visibilityState === 'visible') void refresh(false, true);
    };
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('focus', onVisible);
    return () => {
      document.removeEventListener('visibilitychange', onVisible);
      window.removeEventListener('focus', onVisible);
    };
  }, [refresh]);

  async function loadMore() {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const page = await adminApi.violationPage(nextCursor, {
        status: statusFilter,
        eventClass: classFilter,
      });
      setViolations((current) => {
        const currentIds = new Set(current.map((item) => item.id));
        return [
          ...current,
          ...page.items.filter((item) => !currentIds.has(item.id)),
        ];
      });
      hasLoadedMore.current = true;
      setNextCursor(page.nextCursor);
      setError('');
    } catch (reason) {
      setError(reason instanceof Error
        ? reason.message
        : 'Unable to load older violation cases.');
    } finally {
      setLoadingMore(false);
    }
  }

  const visibleViolations = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    return violations.filter((violation) => {
      if (statusFilter && violation.status !== statusFilter) return false;
      if (classFilter && violation.eventClass !== classFilter) return false;
      if (!query) return true;
      return [
        violation.id,
        violation.driverId,
        violation.driverName,
        violation.ownerTodaId,
        violation.ownerTodaName,
        violation.bookingId,
        violation.eventClass,
        violation.restriction?.name,
      ].some((value) => value?.toLocaleLowerCase().includes(query));
    });
  }, [classFilter, search, statusFilter, violations]);

  const selected = violations.find((item) => item.id === selectedId) || null;
  const selectedDriver = selected
    ? liveDrivers.find((driver) => driver.uid === selected.driverId)
    : undefined;
  const mappedViolations = selected &&
      !visibleViolations.some((violation) => violation.id === selected.id)
    ? [...visibleViolations, selected]
    : visibleViolations;
  const points: AdminMapPoint[] = mappedViolations.filter(validLocation).map((violation) => ({
    id: `violation:${violation.id}`,
    latitude: violation.eventLocation.latitude,
    longitude: violation.eventLocation.longitude,
    title: `${humanize(violation.eventClass)} · ${violation.driverName || 'Driver'}`,
    details: [
      `Case: ${violation.id}`,
      `Status: ${humanize(violation.status)}`,
      violation.restriction?.name || 'Restriction name unavailable',
      displayDate(violation.createdAt),
    ],
    urgent: violation.status === 'open',
    tone: violation.status === 'resolved' || violation.status === 'dismissed'
      ? 'default'
      : 'danger',
  }));
  if (selectedDriver && Number.isFinite(selectedDriver.latitude) &&
      Number.isFinite(selectedDriver.longitude)) {
    points.push({
      id: `driver:${selectedDriver.uid}`,
      latitude: selectedDriver.latitude,
      longitude: selectedDriver.longitude,
      title: `${selectedDriver.name} · current location`,
      details: [
        humanize(selectedDriver.bookingStatus),
        selectedDriver.bookingId
          ? `Booking: ${selectedDriver.bookingId}`
          : 'No active booking',
      ],
      urgent: false,
      tone: 'driver',
    });
  }
  const selectedRestrictionAreas = selected
    ? restrictionAreas(selected)
    : [];
  const currentRestriction = selected && selectedRestrictionAreas.length === 0
    ? routeRestrictions.find((restriction) =>
      restriction.id === selected.restriction?.id)
    : undefined;
  const polygons = selected ? [{
    id: selected.restriction?.id || `restriction:${selected.id}`,
    name: selected.restriction?.name || 'Restricted area',
    areas: selectedRestrictionAreas.length > 0
      ? selectedRestrictionAreas
      : currentRestriction?.areas?.length
        ? currentRestriction.areas
        : currentRestriction?.polygon?.length
          ? [currentRestriction.polygon]
          : [],
    color: '#ef4444',
  }] : [];

  async function enableBrowserAlerts() {
    const result = await onEnableWebPush();
    const enabled = result.enabled ||
      (typeof Notification !== 'undefined' &&
        Notification.permission === 'granted');
    setBrowserAlertsEnabled(enabled);
    knownOpenIds.current = enabled
      ? new Set(violations.filter((item) => item.status === 'open').map((item) => item.id))
      : null;
    setError(result.mode === 'unavailable' ? result.message : '');
  }

  async function updateCase(
    violation: DriverViolation,
    action: 'acknowledge' | 'respond' | 'resolve' | 'dismiss',
  ) {
    let note = '';
    if (action === 'respond') {
      note = window.prompt('Optional investigation note:')?.trim() || '';
    } else if (action === 'resolve' || action === 'dismiss') {
      const requested = window.prompt(
        action === 'resolve'
          ? 'Required resolution note (at least 5 characters):'
          : 'Required dismissal reason (at least 5 characters):',
      )?.trim();
      if (!requested || requested.length < 5) return;
      note = requested;
    }
    try {
      const result = await adminApi.updateViolation(violation.id, action, note);
      setViolations((current) => current.map((item) =>
        item.id === violation.id ? { ...item, status: result.status } : item));
      await refresh();
    } catch (reason) {
      setError(reason instanceof Error
        ? reason.message
        : 'Unable to update the violation case.');
    }
  }

  const eventClasses = Array.from(new Set(
    violations.map((violation) => violation.eventClass),
  )).sort();
  return <>
    {latestAlert && <div className="violation-alert-strip" role="alert">
      <span>
        <b>New restriction violation:</b>{' '}
        {latestAlert.driverName || 'Driver'} · {humanize(latestAlert.eventClass)}
      </span>
      <span className="actions">
        <button onClick={() => selectViolation(latestAlert.id)}>Open case</button>
        <button aria-label="Dismiss alert" onClick={() => setLatestAlert(null)}>×</button>
      </span>
    </div>}
    <section className="panel violations-map-panel">
      <div className="section-heading">
        <div>
          <h2>{session.role === 'developer_admin'
            ? 'Platform driver violations'
            : 'My TODA driver violations'}</h2>
          <p className="muted">
            Red markers are immutable event locations. A green marker, when
            available, is the driver&apos;s current online location. TODA scope
            is enforced by the server.
          </p>
        </div>
        <button onClick={enableBrowserAlerts} disabled={webPushResult.enabled}>
          {webPushResult.enabled
            ? 'Violation-case web push enabled'
            : browserAlertsEnabled
              ? 'In-app violation alerts enabled'
              : 'Enable violation-case web push'}
        </button>
      </div>
      <div className="violation-filters" aria-label="Violation filters">
        <label>Status
          <select
            value={statusFilter}
            onChange={(event) =>
              setStatusFilter(event.target.value as DriverViolationStatus | '')}
          >
            <option value="">All statuses</option>
            <option value="open">Open</option>
            <option value="acknowledged">Acknowledged</option>
            <option value="responding">Investigating</option>
            <option value="resolved">Resolved</option>
            <option value="dismissed">Dismissed</option>
          </select>
        </label>
        <label>Event
          <select
            value={classFilter}
            onChange={(event) => setClassFilter(event.target.value)}
          >
            <option value="">All event types</option>
            {eventClasses.map((eventClass) =>
              <option value={eventClass} key={eventClass}>
                {humanize(eventClass)}
              </option>)}
          </select>
        </label>
        <label>Search
          <input
            type="search"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Driver, TODA, booking, case"
          />
        </label>
      </div>
      {error && <div className="notice" role="alert">{error}</div>}
      <Suspense fallback={<div className="map-missing">Loading operations map…</div>}>
        <AdminLocationMap
          points={points}
          polygons={polygons}
          selectedId={selected ? `violation:${selected.id}` : null}
          onSelect={(id) => {
            if (id.startsWith('violation:')) selectViolation(id.slice(10));
          }}
          ariaLabel="Driver restriction violation map"
        />
      </Suspense>
      <div className="map-legend" aria-label="Map legend">
        <span><i className="legend-dot danger" /> Violation event</span>
        <span><i className="legend-dot driver" /> Current online driver</span>
        <span><i className="legend-area" /> Restricted polygon</span>
      </div>
      <p className="muted alert-delivery-note">
        {webPushResult.message}
      </p>
    </section>

    <div className="violations-workspace">
      <section className="panel violation-list-panel">
        <h2>Cases ({visibleViolations.length})</h2>
        <div className="violation-list">
          {visibleViolations.map((violation) =>
            <button
              className={selectedId === violation.id
                ? 'violation-card selected'
                : 'violation-card'}
              onClick={() => selectViolation(violation.id)}
              key={violation.id}
            >
              <span>
                <b>{humanize(violation.eventClass)}</b>
                <small>{violation.driverName || violation.driverId || 'Unknown driver'}</small>
              </span>
              <span className={`case-status status-${violation.status}`}>
                {humanize(violation.status)}
              </span>
              <small>{violation.ownerTodaName || violation.ownerTodaId || 'No TODA recorded'}</small>
              <small>{violation.restriction?.name || 'Restriction unavailable'} · {displayDate(violation.createdAt)}</small>
              {Boolean(violation.unreadMessageCount) &&
                <small className="unread-count">
                  {violation.unreadMessageCount} unread message(s)
                </small>}
              {!violation.unreadMessageCount && Boolean(violation.messageCount) &&
                <small>{violation.messageCount} case message(s)</small>}
            </button>)}
          {loading && <p className="muted">Loading violation cases…</p>}
          {!loading && visibleViolations.length === 0 &&
            <p className="muted">No violation cases match these filters.</p>}
          {nextCursor &&
            <button onClick={loadMore} disabled={loadingMore}>
              {loadingMore ? 'Loading…' : 'Load older cases'}
            </button>}
        </div>
      </section>

      <section className="panel violation-detail-panel">
        {selected
          ? <ViolationDetails
              violation={selected}
              onUpdate={updateCase}
              onClose={() => selectViolation(null)}
            />
          : loadingSelected
            ? <p className="muted">Loading linked violation case…</p>
          : selectedLoadError
            ? <div className="empty-case">
                <h2>Unable to open this case</h2>
                <p className="muted">{selectedLoadError}</p>
              </div>
          : <div className="empty-case">
              <h2>Select a violation case</h2>
              <p className="muted">
                Open a case to review the immutable event location, response
                history, and driver–administrator conversation.
              </p>
            </div>}
      </section>

      <section className="panel violation-chat-panel">
        {selected
          ? <ViolationChat
              violation={selected}
              session={session}
              onError={setError}
            />
          : <div className="empty-case">
              <h2>Case chat</h2>
              <p className="muted">Select a violation to open its separate audited chat.</p>
            </div>}
      </section>
    </div>
  </>;
}

function ViolationDetails({
  violation,
  onUpdate,
  onClose,
}: {
  violation: DriverViolation;
  onUpdate: (
    violation: DriverViolation,
    action: 'acknowledge' | 'respond' | 'resolve' | 'dismiss',
  ) => Promise<void>;
  onClose: () => void;
}) {
  const stillOpen = openStatuses.has(violation.status);
  const restrictionRevision = violation.restriction?.revision ??
    violation.restriction?.geometryVersion;
  const delivery = violation.delivery;
  const driverDelivery = violation.driverDelivery;
  return <>
    <div className="section-heading">
      <div>
        <p className="eyebrow">Violation case</p>
        <h2>{humanize(violation.eventClass)}</h2>
      </div>
      <button onClick={onClose}>Close</button>
    </div>
    <dl className="case-facts">
      <div><dt>Status</dt><dd>{humanize(violation.status)}</dd></div>
      <div><dt>Driver</dt><dd>{violation.driverName || violation.driverId || 'Unavailable'}</dd></div>
      <div><dt>TODA</dt><dd>{violation.ownerTodaName || violation.ownerTodaId || 'Unavailable'}</dd></div>
      <div>
        <dt>Restriction</dt>
        <dd>
          {violation.restriction?.name || 'Unavailable'}
          {restrictionRevision == null ? '' : ` · revision ${restrictionRevision}`}
        </dd>
      </div>
      <div><dt>Driver state</dt><dd>{humanize(violation.context || 'unknown')}</dd></div>
      <div>
        <dt>Booking</dt>
        <dd>
          {violation.bookingId || 'Online-idle event'}
          {violation.bookingStatus ? ` · ${humanize(violation.bookingStatus)}` : ''}
        </dd>
      </div>
      <div><dt>Occurred</dt><dd>{displayDate(violation.occurredAt || violation.createdAt)}</dd></div>
      <div><dt>Entered</dt><dd>{displayDate(violation.enteredAt)}</dd></div>
      <div><dt>Exited</dt><dd>{violation.exitedAt ? displayDate(violation.exitedAt) : 'Still inside or exit unconfirmed'}</dd></div>
      <div><dt>Source</dt><dd>{humanize(violation.source || 'unknown')}</dd></div>
      <div><dt>Accuracy</dt><dd>{violation.eventLocation.accuracy == null ? 'Unavailable' : `±${Math.round(violation.eventLocation.accuracy)} m`}</dd></div>
      <div>
        <dt>Evidence match</dt>
        <dd>
          {violation.confidence == null
            ? 'Evidence detail unavailable'
            : 'Two fresh driver-reported GPS fixes matched server geometry'}
        </dd>
      </div>
      <div>
        <dt>Admin alert</dt>
        <dd>
          {delivery?.status
            ? `${humanize(delivery.status)} · ${delivery.successCount ?? 0}/${delivery.attemptedCount ?? 0} delivered`
            : 'Delivery data unavailable'}
        </dd>
      </div>
      <div>
        <dt>Driver alert</dt>
        <dd>
          {driverDelivery?.status
            ? `${humanize(driverDelivery.status)} · ${driverDelivery.successCount ?? 0}/${driverDelivery.attemptedCount ?? 0} delivered`
            : 'Local warning or delivery data unavailable'}
        </dd>
      </div>
    </dl>
    {violation.routeAdvisory && <div className="case-note">
      <b>Routing advisory</b>
      <span>{violation.routeAdvisory}</span>
    </div>}
    {(violation.latestAdminNote || violation.resolutionNote) &&
      <div className="case-note">
        <b>Latest response note</b>
        <span>{violation.resolutionNote || violation.latestAdminNote}</span>
      </div>}
    <div className="actions case-actions">
      {violation.status === 'open' &&
        <button className="primary" onClick={() => onUpdate(violation, 'acknowledge')}>
          Acknowledge
        </button>}
      {stillOpen && violation.status !== 'responding' &&
        <button onClick={() => onUpdate(violation, 'respond')}>
          Start investigation
        </button>}
      {stillOpen &&
        <button onClick={() => onUpdate(violation, 'resolve')}>
          Resolve with note
        </button>}
      {stillOpen &&
        <button onClick={() => onUpdate(violation, 'dismiss')}>
          Dismiss with reason
        </button>}
    </div>
    <small className="technical-id">Case ID: {violation.id}</small>
  </>;
}

function ViolationChat({
  violation,
  session,
  onError,
}: {
  violation: DriverViolation;
  session: AdminSession;
  onError: (message: string) => void;
}) {
  const [messages, setMessages] = useState<ViolationMessage[]>([]);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [loading, setLoading] = useState(true);
  const endRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    setMessages([]);
    setLoading(true);
    const unsubscribe = adminApi.listenViolationMessages(
      violation.id,
      (nextMessages) => {
        setMessages(nextMessages);
        setLoading(false);
        void adminApi.markViolationMessagesRead(violation.id).catch(() => {
          // Reading the chat remains useful if the read receipt cannot be saved.
        });
      },
      (reason) => {
        setLoading(false);
        onError(reason.message);
      },
    );
    return unsubscribe;
  }, [onError, violation.id]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ block: 'nearest' });
  }, [messages]);

  async function send(event: FormEvent) {
    event.preventDefault();
    const message = draft.trim();
    if (!message || sending) return;
    setSending(true);
    try {
      await adminApi.sendViolationMessage(
        violation.id,
        messageId(),
        message,
      );
      setDraft('');
      onError('');
    } catch (reason) {
      onError(reason instanceof Error
        ? reason.message
        : 'Unable to send the case message.');
    } finally {
      setSending(false);
    }
  }

  return <>
    <div className="section-heading">
      <div>
        <h2>Case chat</h2>
        <p className="muted">
          Separate from passenger booking chat · driver, TODA, and system administrators
        </p>
      </div>
      <span className="case-status">{messages.length}</span>
    </div>
    <div className="case-chat-log" aria-live="polite">
      {messages.map((message) => {
        const mine = message.senderId === session.uid;
        const unread = !mine && !message.readBy?.includes(session.uid);
        return <article
          className={[
            'case-message',
            mine ? 'mine' : '',
            unread ? 'unread' : '',
          ].filter(Boolean).join(' ')}
          key={message.id}
        >
          <header>
            <b>{message.senderName}</b>
            <span>{humanize(message.senderRole)}</span>
            {unread && <span className="unread-label">Unread</span>}
          </header>
          <p>{message.text}</p>
          <small>{displayDate(message.createdAt)}</small>
        </article>;
      })}
      {loading && <p className="muted">Loading case messages…</p>}
      {!loading && messages.length === 0 &&
        <p className="muted">No case messages yet.</p>}
      <div ref={endRef} />
    </div>
    <form className="case-chat-compose" onSubmit={send}>
      <label htmlFor="violation-chat-message">Message driver and administrators</label>
      <textarea
        id="violation-chat-message"
        value={draft}
        maxLength={2000}
        onChange={(event) => setDraft(event.target.value)}
        placeholder="Write a factual case update…"
      />
      <div>
        <small>{draft.length}/2000</small>
        <button className="primary" disabled={!draft.trim() || sending}>
          {sending ? 'Sending…' : 'Send update'}
        </button>
      </div>
    </form>
  </>;
}

