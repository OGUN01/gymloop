'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { AVATAR_INITIALS_MAX, formatPhone } from '@gymloop/shared';
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
};

type Outcome = {
  ok: boolean;
  headline: string;
  detail: string;
  /** Present only when the attempt failed for a reason worth repeating verbatim. */
  retry?: { memberId: string; body: CheckInBody; clientEventId: string };
};

type CheckInBody = { token?: string; reason?: string };

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

export function CheckInGate({ members }: { members: Member[] }) {
  const readOnly = usePreviewReadOnly();
  const [gateCode, setGateCode] = useState('');
  const [issuedCode, setIssuedCode] = useState('');
  const [canScan, setCanScan] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [notice, setNotice] = useState('');
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [busyMemberId, setBusyMemberId] = useState('');
  const [assistFor, setAssistFor] = useState('');
  const [reason, setReason] = useState('');

  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  useEffect(() => {
    setCanScan(barcodeDetector() !== undefined);
    try {
      setGateCode(window.sessionStorage.getItem(GATE_CODE_KEY) ?? '');
    } catch {
      // Storage can be unavailable (private mode, blocked site data). The gate
      // still works; the code just does not survive a search.
      setGateCode('');
    }
  }, []);

  const rememberGateCode = useCallback((code: string) => {
    setGateCode(code);
    try {
      window.sessionStorage.setItem(GATE_CODE_KEY, code);
    } catch {
      // See above — losing the code on reload is not worth failing a check-in for.
      setNotice('This browser will not remember the code between searches.');
    }
  }, []);

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
  }, [rememberGateCode]);

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
    <fieldset disabled={readOnly} className="check-in-gate">
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

      <div className="check-in-gate-panel">
        <p className="cl-eyebrow">Gate access</p>
        <h2 className="check-in-gate-title">Gate code</h2>
        <p className="check-in-gate-copy">
          {gateCode
            ? 'Scans will be recorded against this code until it expires.'
            : 'Without a gate code, a visit can only be recorded at the desk, with a reason.'}
        </p>

        <div className="check-in-gate-controls">
          <input
            value={gateCode}
            onChange={(event) => rememberGateCode(event.target.value)}
            placeholder="Type or scan a code"
            aria-label="Gate code"
            autoComplete="off"
            spellCheck={false}
            className={`${FIELD_CLASS} check-in-gate-input`}
          />
          {canScan ? (
            <button
              type="button"
              onClick={scanning ? stopScanning : () => void startScanning()}
              className="cl-btn cl-btn--small"
            >
              {scanning ? 'Stop' : 'Scan'}
            </button>
          ) : null}
          <button
            type="button"
            onClick={() => void issueGateCode()}
            className="cl-btn cl-btn--small cl-btn--accent"
          >
            New code
          </button>
        </div>

        <video
          ref={videoRef}
          muted
          playsInline
          className={scanning ? 'check-in-camera' : 'hidden'}
        />

        {issuedCode ? (
          <div className="check-in-issued-gate">
            <div className="check-in-issued-qr" aria-label="Member check-in QR code">
              <QRCodeSVG
                value={issuedCode}
                level="M"
                marginSize={1}
                title="Scan this QR in the Gymloop member app"
              />
            </div>
            <p className="check-in-issued-code">{issuedCode}</p>
          </div>
        ) : null}

        {notice ? (
          <p role="alert" className="check-in-notice">
            {notice}
          </p>
        ) : null}
      </div>

      <ul className="check-in-members" aria-label="Members">
        <li className="check-in-member-headings" aria-hidden="true"><span>Member</span><span>Status</span><span>Check in</span></li>
        {members.map((member) => (
          <li key={member.id} className="check-in-member-row">
            <div className="check-in-member-content">
              <div className="check-in-member-identity">
                <span aria-hidden="true" className="check-in-member-initial">{member.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('')}</span>
                <div>
                <p className="check-in-member-name">{member.full_name}</p>
                <p className="check-in-member-phone">{formatPhone(member.phone)}</p>
                </div>
              </div>
              <StatusWord status={member.status} />
              <div className="check-in-actions">
                <button
                  type="button"
                  disabled={gateCode === '' || busyMemberId === member.id}
                  onClick={() => void submit(member, { token: gateCode }, crypto.randomUUID())}
                  className="cl-btn cl-btn--small"
                >
                  Check in
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setAssistFor(assistFor === member.id ? '' : member.id);
                    setReason('');
                  }}
                  aria-expanded={assistFor === member.id}
                  className="cl-btn cl-btn--small"
                >
                  At the desk
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
        ))}
      </ul>

      {members.length === 0 ? (
        <div className="cl-empty check-in-empty"><strong>No member matched</strong><p>No member of this gym matched. Check the number, or search with fewer digits.</p></div>
      ) : null}
    </fieldset>
  );
}
