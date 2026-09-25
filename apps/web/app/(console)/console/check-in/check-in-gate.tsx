'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { ChevronDown } from 'lucide-react';
import { AVATAR_INITIALS_MAX, formatPhone, PRODUCT_NAME } from '@gymloop/shared';
import { usePreviewReadOnly } from '../../../preview-context';
import { StatusWord } from '../../../status-word';

/**
 * The gate itself: hold a gate code, pick a member, confirm in type you can read
 * from the other side of the room.
 *
 * Three notes on what it deliberately is not.
 *
 * **One encoder, platform decoding.** `BarcodeDetector` handles staff-side
 * scanning where the browser provides it. The small SVG encoder exists for the
 * opposite direction: a member phone must be able to scan every newly issued
 * gate code from this screen. The text remains visible as the accessible and
 * manual fallback.
 *
 * **No client-side tenant.** Nothing here names a gym. The member list came from
 * a Server Component read that RLS filtered, and the endpoint reads the tenant
 * from the verified token.
 *
 * **The confirmation is not a toast.** It replaces nothing and disappears on no
 * timer: the last result stays up until the next check-in overwrites it, because
 * a gate that clears itself after four seconds is a gate where the person who
 * looked away does not know whether they are in.
 */

type Member = {
  id: string;
  full_name: string;
  phone: string;
  status: string;
  /** The STATUS column's word (`loadMembershipStanding`); absent, the account status is shown. */
  standing?: { status: string; label: string };
};

/** Account states the desk must not check in as if nothing were wrong — they go straight to the reason step. */
const BARRED = new Set(['blocked', 'cancelled']);

type Outcome = {
  ok: boolean;
  headline: string;
  detail: string;
  /** Present only when the attempt failed for a reason worth repeating verbatim. */
  retry?: { memberId: string; body: CheckInBody; clientEventId: string };
};

type CheckInBody = { token?: string; reason?: string };

type GateMode = 'printed_poster' | 'rotating_screen';
type CurrentGate = { mode: GateMode; branchId: string; code?: string | null };

type CheckInResponse =
  | { ok: true; data: { replay: boolean; source: string } }
  | { ok: false; error: { code: string; message: string } };

/** Survives the page reload a member search causes; never leaves this browser. */
const GATE_CODE_KEY = 'gymloop.gate-code';

/** `BarcodeDetector` is not in `lib.dom`, so its shape is stated here. */
type DetectedBarcode = { rawValue: string };
type BarcodeDetectorLike = { detect(source: HTMLVideoElement): Promise<DetectedBarcode[]> };
type BarcodeDetectorCtor = new (options: { formats: string[] }) => BarcodeDetectorLike;

function barcodeDetector(): BarcodeDetectorCtor | undefined {
  return (window as unknown as { BarcodeDetector?: BarcodeDetectorCtor }).BarcodeDetector;
}

const FIELD_CLASS =
  'check-in-field';

export function CheckInGate({ members, mode, canManageGate = false }: {
  members: Member[]; mode?: GateMode | undefined; canManageGate?: boolean;
}) {
  const readOnly = usePreviewReadOnly();
  const [gateCode, setGateCode] = useState('');
  // What is typed into "Have a code?" — it becomes the gate code only on "Use code".
  const [codeDraft, setCodeDraft] = useState('');
  const [issuedCode, setIssuedCode] = useState('');
  const [activeMode, setActiveMode] = useState<GateMode | undefined>(mode);
  const [posterBranchId, setPosterBranchId] = useState('');
  const [posterUnavailable, setPosterUnavailable] = useState(false);
  const [changingGate, setChangingGate] = useState(false);
  const [canScan, setCanScan] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [notice, setNotice] = useState('');
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [busyMemberId, setBusyMemberId] = useState('');
  const [assistFor, setAssistFor] = useState('');
  const [reason, setReason] = useState('');
  // Nothing on this screen works before hydration — no handler is attached yet —
  // so the row actions say so instead of looking live and doing nothing.
  const [hydrated, setHydrated] = useState(false);

  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  useEffect(() => {
    setHydrated(true);
    setCanScan(barcodeDetector() !== undefined);
    if (mode !== 'rotating_screen') return;
    try {
      const stored = window.sessionStorage.getItem(GATE_CODE_KEY) ?? '';
      setGateCode(stored);
      setCodeDraft(stored);
    } catch {
      // Storage can be unavailable (private mode, blocked site data). The gate
      // still works; the code just does not survive a search.
      setGateCode('');
    }
  }, [mode]);

  const rememberGateCode = useCallback((code: string) => {
    setGateCode(code);
    setCodeDraft(code);
    try {
      if (activeMode === 'printed_poster') return;
      window.sessionStorage.setItem(GATE_CODE_KEY, code);
    } catch {
      // See above — losing the code on reload is not worth failing a check-in for.
      setNotice('This browser will not remember the code between searches.');
    }
  }, [activeMode]);

  const loadCurrentGate = useCallback(async () => {
    try {
      const response = await fetch('/api/gate-code', { cache: 'no-store' });
      const payload = await response.json() as
        | { ok: true; data: CurrentGate }
        | { ok: false; error: { message: string } };
      if (!payload.ok) {
        setGateCode('');
        setIssuedCode('');
        setPosterUnavailable(true);
        setNotice(payload.error.message);
        return;
      }
      setActiveMode(payload.data.mode);
      setPosterBranchId(payload.data.branchId);
      setPosterUnavailable(false);
      if (payload.data.mode === 'printed_poster') {
        setIssuedCode(payload.data.code ?? '');
        setGateCode(payload.data.code ?? '');
        setCodeDraft(payload.data.code ?? '');
        try { window.sessionStorage.removeItem(GATE_CODE_KEY); } catch { /* Storage is optional. */ }
      } else {
        setIssuedCode('');
        setGateCode('');
        setCodeDraft('');
      }
    } catch {
      setGateCode('');
      setIssuedCode('');
      setPosterUnavailable(true);
      setNotice('Gate status could not be loaded. Reload to see the current poster.');
    }
  }, []);

  useEffect(() => { void loadCurrentGate(); }, [loadCurrentGate]);

  const changeGateMode = useCallback(async (nextMode: GateMode) => {
    if (changingGate) return;
    setChangingGate(true);
    setNotice('');
    try {
      const response = await fetch('/api/gate-code/mode', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ mode: nextMode }),
      });
      const payload = await response.json() as
        | { ok: true; data: { mode: GateMode } }
        | { ok: false; error: { message: string } };
      if (!payload.ok) { setNotice(payload.error.message); return; }
      setActiveMode(payload.data.mode);
      setIssuedCode('');
      setGateCode('');
      setCodeDraft('');
      try { window.sessionStorage.removeItem(GATE_CODE_KEY); } catch { /* Storage is optional. */ }
      await loadCurrentGate();
      setNotice(payload.data.mode === 'printed_poster'
        ? 'Printed poster mode is on. Create and print its first poster.'
        : 'Rotating screen mode is on. Generate a new temporary code.');
    } catch {
      setNotice('Mode change could not be confirmed. Reload the gate before trying again.');
    } finally { setChangingGate(false); }
  }, [changingGate, loadCurrentGate]);

  const replacePoster = useCallback(async () => {
    if (changingGate || activeMode !== 'printed_poster') return;
    if (!window.confirm('Replace poster? The printed code at this branch will stop working immediately. Confirm replacement.')) return;
    setChangingGate(true);
    setNotice('');
    try {
      const response = await fetch('/api/gate-code/poster', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ confirmed: true, branchId: posterBranchId || undefined }),
      });
      const payload = await response.json() as
        | { ok: true; data: { code: string; branchId: string } }
        | { ok: false; error: { message: string } };
      if (!payload.ok) { setNotice(payload.error.message); return; }
      setPosterBranchId(payload.data.branchId);
      setIssuedCode(payload.data.code);
      setGateCode(payload.data.code);
      setCodeDraft(payload.data.code);
      setPosterUnavailable(false);
      setNotice('New poster is live. Remove the old printout and print this one.');
    } catch {
      setNotice('Replacement could not be confirmed. Reload the gate before trying again.');
    } finally { setChangingGate(false); }
  }, [activeMode, changingGate, posterBranchId]);

  const stopScanning = useCallback(() => {
    setScanning(false);
    const stream = streamRef.current;
    streamRef.current = null;
    if (stream) {
      for (const track of stream.getTracks()) track.stop();
    }
  }, []);

  const startScanning = useCallback(async () => {
    setNotice('');
    const Detector = barcodeDetector();
    const video = videoRef.current;
    if (!Detector || !video) {
      setNotice('This browser cannot scan. Type the gate code instead.');
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment' },
      });
      streamRef.current = stream;
      setScanning(true);
      video.srcObject = stream;
      await video.play();

      const detector = new Detector({ formats: ['qr_code'] });
      const readFrame = async () => {
        if (streamRef.current === null) return;
        try {
          const found = await detector.detect(video);
          const first = found[0];
          if (first) {
            rememberGateCode(first.rawValue.trim());
            stopScanning();
            return;
          }
        } catch {
          // A frame that decodes to nothing is the normal case between codes,
          // not a failure — keep looking. Nothing to do, deliberately.
        }
        window.requestAnimationFrame(() => void readFrame());
      };
      window.requestAnimationFrame(() => void readFrame());
    } catch {
      setNotice('The camera could not be opened. Type the gate code instead.');
      stopScanning();
    }
  }, [rememberGateCode, stopScanning]);

  useEffect(() => stopScanning, [stopScanning]);

  const issueGateCode = useCallback(async () => {
    setNotice('');
    if (activeMode !== 'rotating_screen') return;
    const response = await fetch('/api/gate-code', { method: 'POST' });
    const payload = (await response.json()) as
      | { ok: true; data: { code: string } }
      | { ok: false; error: { message: string } };

    if (!payload.ok) {
      setNotice(payload.error.message);
      return;
    }
    setIssuedCode(payload.data.code);
    rememberGateCode(payload.data.code);
  }, [activeMode, rememberGateCode]);

  const submit = useCallback(
    async (member: Member, body: CheckInBody, clientEventId: string) => {
      setBusyMemberId(member.id);
      try {
        const response = await fetch('/api/check-in', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ memberId: member.id, clientEventId, ...body }),
        });
        const payload = (await response.json()) as CheckInResponse;

        if (payload.ok) {
          setOutcome({
            ok: true,
            headline: member.full_name,
            detail: payload.data.replay ? 'Already recorded' : 'Checked in',
          });
          setAssistFor('');
          setReason('');
        } else {
          setOutcome({ ok: false, headline: member.full_name, detail: payload.error.message });
        }
      } catch {
        // The request may or may not have reached the database. Retrying with
        // the *same* client event id is what makes that safe to find out: the
        // unique index turns a second delivery of one attempt into the row that
        // already exists rather than a second visit.
        setOutcome({
          ok: false,
          headline: member.full_name,
          detail: 'No connection. Tap to send that check-in again.',
          retry: { memberId: member.id, body, clientEventId },
        });
      } finally {
        setBusyMemberId('');
      }
    },
    [],
  );

  const retry = useCallback(() => {
    const pending = outcome?.retry;
    const member = members.find((candidate) => candidate.id === pending?.memberId);
    if (pending && member) void submit(member, pending.body, pending.clientEventId);
  }, [members, outcome, submit]);

  return (
    <fieldset disabled={readOnly} className="check-in-gate" data-gate={gateCode ? 'open' : 'closed'}>
      {outcome ? (
        <button
          type="button"
          onClick={outcome.retry ? retry : () => setOutcome(null)}
          aria-live="polite"
          className={`check-in-outcome ${
            outcome.ok ? 'check-in-outcome-success' : 'check-in-outcome-risk'
          }`}
        >
          <span className="check-in-outcome-headline">{outcome.headline}</span>
          <span className="check-in-outcome-detail">{outcome.detail}</span>
          <span className="check-in-outcome-hint">{outcome.retry ? 'Send again' : 'Dismiss'}</span>
        </button>
      ) : null}

      <section className="check-in-gate-panel" aria-labelledby="check-in-gate-title">
        <div className="check-in-gate-inner">
          <p className="cl-eyebrow check-in-gate-eyebrow">{activeMode === 'printed_poster' ? 'Printed poster' : 'Rotating screen'}</p>
          {/* The gate's state is said here and only here: a display title beside the
              roster on a wide screen, one ruled status row above it on anything smaller. */}
          <h2 id="check-in-gate-title" className="check-in-gate-title">
            {activeMode === 'printed_poster'
              ? gateCode ? 'Poster live' : 'No poster available'
              : gateCode ? 'Gate open' : 'No gate code'}
          </h2>
          <p className="check-in-gate-copy">
            {activeMode === 'printed_poster'
              ? gateCode ? 'Permanent until replaced. A member may scan once per branch-local day during opening hours.'
                : posterUnavailable ? 'Poster could not be displayed. Reload or ask an owner to replace it.'
                  : 'No poster yet. Ask an owner or manager to create and print one.'
              : gateCode ? 'Scans are recorded against this code until it expires.'
                : 'Generate one for members to scan. Until then, check-ins are recorded at the desk with a reason.'}
          </p>

          {activeMode === 'rotating_screen' ? (
            <button type="button" onClick={() => void issueGateCode()}
              className={gateCode || assistFor ? 'cl-btn check-in-gate-issue' : 'cl-btn cl-btn--primary check-in-gate-issue'}>
              {gateCode ? 'New code' : 'Generate today�s code'}
            </button>
          ) : null}
          {canManageGate ? (
            <div className="check-in-gate-management" aria-label="Gate settings">
              {activeMode === 'printed_poster' ? (
                <>
                  <button type="button" className="cl-btn" disabled={!hydrated || changingGate}
                    onClick={() => void replacePoster()}>Replace poster � confirm</button>
                  <a className="cl-btn" href="/console/check-in/poster" target="_blank" rel="noopener noreferrer"
                    aria-disabled={!issuedCode || posterUnavailable} onClick={(event) => {
                      if (!issuedCode || posterUnavailable) event.preventDefault();
                    }}>Print poster</a>
                  <button type="button" className="cl-btn" disabled={!hydrated || changingGate}
                    onClick={() => void changeGateMode('rotating_screen')}>Switch to rotating screen</button>
                </>
              ) : (
                <button type="button" className="cl-btn" disabled={!hydrated || changingGate}
                  onClick={() => void changeGateMode('printed_poster')}>Switch to printed poster</button>
              )}
            </div>
          ) : null}

          {issuedCode ? (
            <div className="check-in-issued-gate">
              <div className="check-in-issued-qr" aria-label="Member check-in QR code">
                <QRCodeSVG
                  value={issuedCode}
                  level="M"
                  marginSize={1}
                  title={`Scan this QR in the ${PRODUCT_NAME} member app`}
                />
              </div>
              <p className="check-in-issued-code">{issuedCode}</p>
            </div>
          ) : null}

          {/* A code someone handed you is the rare path, so below the wide layout it
              waits behind "Have a code?" instead of pushing the roster down. */}
          <details className="check-in-gate-disclosure">
            <summary className="check-in-gate-summary">
              Have a code?
              <ChevronDown aria-hidden="true" className="check-in-gate-chevron" />
            </summary>
            <form
              className="check-in-gate-entry"
              onSubmit={(event) => {
                event.preventDefault();
                rememberGateCode(codeDraft);
              }}
            >
              <label htmlFor="check-in-gate-code" className="check-in-gate-label">Have a code? Enter it</label>
              <div className="check-in-gate-controls">
                <input
                  id="check-in-gate-code"
                  value={codeDraft}
                  onChange={(event) => setCodeDraft(event.target.value)}
                  placeholder="Gate code"
                  autoComplete="off"
                  spellCheck={false}
                  className={`${FIELD_CLASS} check-in-gate-input`}
                />
                {canScan ? (
                  <button
                    type="button"
                    onClick={scanning ? stopScanning : () => void startScanning()}
                    className="cl-btn"
                  >
                    {scanning ? 'Stop' : 'Scan'}
                  </button>
                ) : null}
                <button type="submit" disabled={!hydrated} className="cl-btn check-in-gate-use">Use code</button>
              </div>
            </form>
          </details>

          <video
            ref={videoRef}
            muted
            playsInline
            className={scanning ? 'check-in-camera' : 'hidden'}
          />

          {notice ? (
            <p role="alert" className="check-in-notice">
              {notice}
            </p>
          ) : null}
        </div>
      </section>

      <p className="check-in-roster-meta">
        <span className="check-in-count">{members.length === 1 ? '1 member' : `${members.length} members`}</span>
      </p>

      <ul className="check-in-members" aria-label="Members">
        <li className="check-in-member-headings" aria-hidden="true"><span>Member</span><span className="check-in-heading-phone">Phone</span><span>Status</span><span>Check in</span></li>
        {members.map((member) => {
          const barred = BARRED.has(member.status);
          return (
            <li key={member.id} className="check-in-member-row">
              <div className="check-in-member-content">
                <div className="check-in-member-identity">
                  <span aria-hidden="true" className="check-in-member-initial">{member.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                  <div>
                    <p className="check-in-member-name">{member.full_name}</p>
                    <p className="check-in-member-phone">{formatPhone(member.phone)}</p>
                  </div>
                </div>
                {member.standing ? <StatusWord status={member.standing.status} label={member.standing.label} /> : <StatusWord status={member.status} />}
                <div className="check-in-actions">
                  {gateCode && !barred ? (
                    <button
                      type="button"
                      disabled={busyMemberId === member.id}
                      onClick={() => void submit(member, { token: gateCode }, crypto.randomUUID())}
                      className="cl-btn check-in-row-action"
                    >
                      Check in
                    </button>
                  ) : null}
                  <button
                    type="button"
                    disabled={!hydrated}
                    onClick={() => {
                      setAssistFor(assistFor === member.id ? '' : member.id);
                      setReason('');
                    }}
                    aria-expanded={assistFor === member.id}
                    aria-label={`Check in ${member.full_name} at the desk`}
                    // One row button at every width; a barred account's reads quieter, in the risk colour.
                    className={barred ? 'cl-btn check-in-row-action check-in-row-action--anyway' : gateCode ? 'cl-btn check-in-row-action check-in-row-action--quiet' : 'cl-btn check-in-row-action'}
                  >
                    {barred ? 'Check in anyway' : gateCode ? 'Desk check-in' : 'Check in'}
                  </button>
                </div>
              </div>

              {assistFor === member.id ? (
                <form
                  className="check-in-assist-form"
                  onSubmit={(event) => {
                    event.preventDefault();
                    void submit(member, { reason }, crypto.randomUUID());
                  }}
                >
                  <input
                    value={reason}
                    onChange={(event) => setReason(event.target.value)}
                    required
                    placeholder="Why are you checking them in? (required)"
                    aria-label={`Reason for checking in ${member.full_name} at the desk`}
                    className={`${FIELD_CLASS} check-in-assist-input`}
                  />
                  <button
                    type="submit"
                    disabled={busyMemberId === member.id}
                    className="cl-btn cl-btn--primary"
                  >
                    Record
                  </button>
                </form>
              ) : null}
            </li>
          );
        })}
      </ul>

      {members.length === 0 ? (
        <div className="cl-empty check-in-empty"><strong>No member matched</strong><p>No member of this gym matched. Check the number, or search with fewer digits.</p></div>
      ) : null}
    </fieldset>
  );
}
