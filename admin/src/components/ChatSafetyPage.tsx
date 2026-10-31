import { PassengerCaseDetails } from './PassengerCaseDetails';
import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';

import { adminApi } from '../admin-api';
import type {
  ChatModerationIncident,
  ChatModerationRule,
} from '../types';
import './chat-safety.css';

type RuleDraft = Omit<ChatModerationRule, 'createdAt' | 'updatedAt' | 'aliases'> & {
  aliasesText: string;
};

const blankRule = (): RuleDraft => ({
  ruleId: '',
  phrase: '',
  aliasesText: '',
  language: 'Filipino / English',
  category: 'profanity',
  severity: 'medium',
  action: 'mask',
  matchMode: 'word',
  matchVariants: true,
  isActive: true,
});

function when(value?: string | null): string {
  if (!value) return 'Time unavailable';
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? 'Time unavailable' : date.toLocaleString();
}

export function ChatSafetyPage({
  onMessage,
  canManageRules = false,
  incidentsOnly = false,
}: {
  onMessage: (value: string) => void;
  canManageRules?: boolean;
  incidentsOnly?: boolean;
}) {
  const [rules, setRules] = useState<ChatModerationRule[]>([]);
  const [incidents, setIncidents] = useState<ChatModerationIncident[]>([]);
  const [draft, setDraft] = useState<RuleDraft>(blankRule);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState('');

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const [nextRules, nextIncidents] = await Promise.all([
        canManageRules ? adminApi.chatModerationRules() : Promise.resolve([]),
        adminApi.chatModerationIncidents(),
      ]);
      setRules(nextRules);
      setIncidents(nextIncidents);
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to load chat safety controls.');
    } finally {
      setLoading(false);
    }
  }, [canManageRules, onMessage]);

  useEffect(() => { void refresh(); }, [refresh]);

  const openCount = incidents.filter((incident) => incident.status === 'open').length;
  const blockedCount = incidents.filter((incident) => incident.deliveryStatus === 'blocked').length;
  const activeRuleCount = rules.filter((rule) => rule.isActive).length;
  const aliasCount = useMemo(
    () => rules.reduce((total, rule) => total + rule.aliases.length, 0),
    [rules],
  );

  async function saveRule(event: FormEvent) {
    event.preventDefault();
    const aliases = draft.aliasesText
      .split(/[\n,]/)
      .map((value) => value.trim())
      .filter(Boolean);
    setBusy('rule');
    try {
      await adminApi.upsertChatModerationRule({
        ruleId: draft.ruleId,
        phrase: draft.phrase.trim(),
        aliases,
        language: draft.language.trim(),
        category: draft.category.trim(),
        severity: draft.severity,
        action: draft.action,
        matchMode: draft.matchMode,
        matchVariants: draft.matchVariants,
        isActive: draft.isActive,
      });
      setDraft(blankRule());
      onMessage('Chat moderation rule saved. New ride messages use it immediately.');
      await refresh();
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to save the chat rule.');
    } finally {
      setBusy('');
    }
  }

  function editRule(rule: ChatModerationRule) {
    setDraft({
      ...rule,
      aliasesText: rule.aliases.join(', '),
    });
    document.getElementById('chat-rule-editor')?.scrollIntoView({ behavior: 'smooth' });
  }

  async function archiveRule(rule: ChatModerationRule) {
    if (!window.confirm(`Deactivate the chat rule “${rule.phrase}”?`)) return;
    setBusy(rule.ruleId);
    try {
      await adminApi.archiveChatModerationRule(rule.ruleId);
      onMessage('Chat moderation rule deactivated.');
      await refresh();
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to deactivate the rule.');
    } finally {
      setBusy('');
    }
  }

  async function updateIncident(incident: ChatModerationIncident, action: 'dismiss' | 'resolve' | 'hide') {
    const note = window.prompt(
      action === 'hide'
        ? 'Optional reason for hiding this message:'
        : 'Optional review note:',
      '',
    );
    if (note === null) return;
    setBusy(incident.incidentId);
    try {
      await adminApi.updateChatModerationIncident(incident.incidentId, action, note);
      onMessage(`Chat incident ${action === 'hide' ? 'hidden and resolved' : `${action}d`}.`);
      await refresh();
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to update the chat incident.');
    } finally {
      setBusy('');
    }
  }

  async function setAccount(incident: ChatModerationIncident, isActive: boolean) {
    const verb = isActive ? 'restore' : 'suspend';
    if (!window.confirm(`${verb[0].toUpperCase()}${verb.slice(1)} account ${incident.senderId}?`)) return;
    setBusy(`${incident.incidentId}-${verb}`);
    try {
      await adminApi.setUserStatus(incident.senderId, isActive, incident.incidentId);
      onMessage(`Sender account ${isActive ? 'restored' : 'suspended'}.`);
    } catch (error) {
      onMessage(error instanceof Error ? error.message : `Unable to ${verb} the sender.`);
    } finally {
      setBusy('');
    }
  }

  async function viewEvidence(incident: ChatModerationIncident) {
    const reason = window.prompt('Enter your investigation reason to view this private photo (10–500 characters). Access will be recorded.');
    if (!reason) return;
    if (reason.trim().length < 10 || reason.trim().length > 500) {
      onMessage('Provide an investigation reason of 10–500 characters.');
      return;
    }
    setBusy(`${incident.incidentId}-media`);
    try {
      const result = await adminApi.chatModerationMediaUrl(incident.incidentId, reason.trim());
      const viewer = window.open(result.url, '_blank');
      if (!viewer) onMessage('Allow pop-ups for this admin site to view the protected chat photo.');
    } catch (error) {
      onMessage(error instanceof Error ? error.message : 'Unable to open retained chat evidence.');
    } finally {
      setBusy('');
    }
  }

  return <section className="chat-safety-page wide">
    {!incidentsOnly && <><div className="cards chat-safety-metrics" aria-label="Chat safety summary">
      {canManageRules && <article className="metric metric--operations"><p>Active rules</p><strong>{activeRuleCount}</strong><small>{aliasCount} shortcut aliases</small></article>}
      <article className="metric metric--attention"><p>Open incidents</p><strong>{openCount}</strong><small>Requires administrator review</small></article>
      <article className="metric metric--danger"><p>Blocked messages</p><strong>{blockedCount}</strong><small>Not delivered to the recipient</small></article>
    </div>

    {canManageRules && <div className="two-column chat-safety-layout">
      <form id="chat-rule-editor" className="panel form-grid" onSubmit={saveRule}>
        <div>
          <p className="eyebrow">SERVER-SIDE POLICY</p>
          <h2>{draft.ruleId ? 'Edit moderation rule' : 'Add moderation rule'}</h2>
          <p className="muted">Rules apply to passenger and driver ride chat. The mobile app cannot bypass or modify them.</p>
        </div>
        <label>Canonical word or phrase
          <input required minLength={2} maxLength={80} value={draft.phrase} onChange={(event) => setDraft({ ...draft, phrase: event.target.value })} placeholder="Example: prohibited phrase" />
        </label>
        <label>Shortened aliases (comma or new line separated)
          <textarea value={draft.aliasesText} onChange={(event) => setDraft({ ...draft, aliasesText: event.target.value })} placeholder="Example: shortcut1, shortcut2" />
          <small>Use aliases for known shorthand. Up to 25; they share this rule’s action.</small>
        </label>
        <div className="chat-rule-grid">
          <label>Language<input required maxLength={40} value={draft.language} onChange={(event) => setDraft({ ...draft, language: event.target.value })} /></label>
          <label>Category<input required maxLength={40} value={draft.category} onChange={(event) => setDraft({ ...draft, category: event.target.value })} /></label>
          <label>Severity<select value={draft.severity} onChange={(event) => setDraft({ ...draft, severity: event.target.value as RuleDraft['severity'] })}><option>low</option><option>medium</option><option>high</option><option>critical</option></select></label>
          <label>Action<select value={draft.action} onChange={(event) => setDraft({ ...draft, action: event.target.value as RuleDraft['action'] })}><option value="mask">Mask and deliver</option><option value="flag">Mask, deliver, and flag</option><option value="block">Block delivery</option></select></label>
          <label>Matching<select value={draft.matchMode} onChange={(event) => setDraft({ ...draft, matchMode: event.target.value as RuleDraft['matchMode'] })}><option value="word">Whole word / phrase</option><option value="substring">Contains / compound word</option></select></label>
        </div>
        <label className="chat-check"><input type="checkbox" checked={draft.matchVariants} onChange={(event) => setDraft({ ...draft, matchVariants: event.target.checked })} /><span>Match stretched spelling (for example repeated letters)</span></label>
        <label className="chat-check"><input type="checkbox" checked={draft.isActive} onChange={(event) => setDraft({ ...draft, isActive: event.target.checked })} /><span>Rule active</span></label>
        <div className="actions">
          <button className="primary" disabled={busy === 'rule'}>{busy === 'rule' ? 'Saving…' : 'Save rule'}</button>
          {draft.ruleId && <button type="button" onClick={() => setDraft(blankRule())}>Cancel editing</button>}
        </div>
      </form>

      <section className="panel">
        <p className="eyebrow">POLICY DIRECTORY</p>
        <h2>Configured rules</h2>
        <p className="muted">Use contains matching carefully: it can match text inside longer words.</p>
        <div className="chat-rule-list">
          {rules.length === 0 && !loading && <p>No moderation rules configured.</p>}
          {rules.map((rule) => <article className={`chat-rule-card ${rule.isActive ? '' : 'is-inactive'}`} key={rule.ruleId}>
            <div><strong>{rule.phrase}</strong><span className={`status-cell severity-${rule.severity}`}>{rule.severity}</span></div>
            <p>{rule.action} · {rule.matchMode === 'substring' ? 'contains' : 'whole word'}{rule.matchVariants ? ' · stretched spelling' : ''}</p>
            {rule.aliases.length > 0 && <small>Aliases: {rule.aliases.join(', ')}</small>}
            <small>{rule.language} · {rule.category} · {rule.isActive ? 'active' : 'inactive'}</small>
            <div className="actions"><button onClick={() => editRule(rule)}>Edit</button>{rule.isActive && <button className="danger-outline" disabled={busy === rule.ruleId} onClick={() => void archiveRule(rule)}>Deactivate</button>}</div>
          </article>)}
        </div>
      </section>
    </div>}</>}

    <section className="panel chat-incidents">
      <div className="chat-safety-heading"><div><p className="eyebrow">SAFETY EVIDENCE</p><h2>Chat incidents</h2></div><button onClick={() => void refresh()} disabled={loading}>{loading ? 'Refreshing…' : 'Refresh'}</button></div>
      <p className="muted">Passenger identities and message content are masked. Open case details with an investigation reason for authorized review. Normal chat photos expire after 48 hours; a reported photo has a separate protected evidence hold until resolution, with a 180-day maximum.</p>
      <div className="chat-incident-list">
        {incidents.length === 0 && !loading && <p>No chat incidents recorded.</p>}
        {incidents.map((incident) => <article className={`chat-incident-card severity-${incident.severity}`} key={incident.incidentId}>
          <div className="chat-incident-title"><div><strong>{incident.senderName} · {incident.senderRole}</strong><small>{incident.senderId} · {when(incident.createdAt)} · ride {incident.bookingId}</small></div><span className="status-cell">{incident.status} · {incident.deliveryStatus}</span></div>
          <PassengerCaseDetails bookingId={incident.bookingId} chatIncidentId={incident.incidentId} /><dl><div><dt>Original</dt><dd>{incident.originalText || (incident.messageType === 'image' ? 'Ride photo' : 'No text')}</dd></div><div><dt>Delivered display</dt><dd>{incident.displayText || 'Not delivered'}</dd></div></dl>
          {incident.matches.length > 0 && <p className="chat-match-summary">Matched: {incident.matches.map((match) => match.phrase || 'participant report').join(', ')}</p>}
          <small className="technical-id">Incident {incident.incidentId} · message {incident.messageId} · TODA {incident.todaId || 'not recorded'}</small>
          <div className="actions">
            {incident.mediaEvidencePath && <button className="primary" disabled={busy === `${incident.incidentId}-media`} onClick={() => void viewEvidence(incident)}>View protected photo</button>}
            {incident.status === 'open' && <><button className="warning-button" disabled={busy === incident.incidentId} onClick={() => void updateIncident(incident, 'hide')}>Hide message</button><button onClick={() => void updateIncident(incident, 'resolve')}>Resolve</button><button onClick={() => void updateIncident(incident, 'dismiss')}>Dismiss</button></>}
            <button className="danger-outline" disabled={busy.includes(incident.incidentId)} onClick={() => void setAccount(incident, false)}>Suspend sender</button>
            <button disabled={busy.includes(incident.incidentId)} onClick={() => void setAccount(incident, true)}>Restore sender</button>
          </div>
        </article>)}
      </div>
    </section>
  </section>;
}
