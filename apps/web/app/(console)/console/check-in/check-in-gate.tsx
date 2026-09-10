'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { usePreviewReadOnly } from '../../../preview-context';

/**
 * The gate itself: hold a gate code, pick a member, confirm in type you can read
 * from the other side of the room.
 *
 * Three notes on what it deliberately is not.
 *
 * **No QR library.** `BarcodeDetector` is in Chrome and on Android and is what
 * this uses; where it is absent — Safari, an old browser, a desktop with no
 * camera — the same field takes the code typed by hand, which is why the code is
 * sixteen characters of hex and not a 43-character token. A scanner shipped as a
 * dependency would be a decoder for a format the platform already decodes.
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
  'w-full rounded-md border border-neutral-300 px-3 py-2 text-base outline-none focus:border-neutral-900';

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
    <fieldset disabled={readOnly} className="mt-6 min-w-0">
      {outcome ? (
        <button
          type="button"
          onClick={outcome.retry ? retry : () => setOutcome(null)}
          className={`block w-full rounded-lg px-6 py-8 text-left ${
            outcome.ok ? 'bg-green-600' : 'bg-red-600'
          }`}
        >
          <span className="block text-4xl font-bold text-white sm:text-6xl">{outcome.detail}</span>
          <span className="mt-1 block text-xl text-white/90 sm:text-3xl">{outcome.headline}</span>
        </button>
      ) : null}

      <div className="mt-6 rounded-lg border border-neutral-200 p-4">
        <h2 className="text-sm font-medium text-neutral-700">Gate code</h2>
        <p className="mt-1 text-sm text-neutral-600">
          {gateCode
            ? 'Scans will be recorded against this code until it expires.'
            : 'Without a gate code, a visit can only be recorded at the desk, with a reason.'}
        </p>

        <div className="mt-3 flex flex-wrap gap-2">
          <input
            value={gateCode}
            onChange={(event) => rememberGateCode(event.target.value)}
            placeholder="Type or scan the gate code"
            aria-label="Gate code"
            autoComplete="off"
            spellCheck={false}
            className={`${FIELD_CLASS} font-mono uppercase sm:w-80`}
          />
          {canScan ? (
            <button
              type="button"
              onClick={scanning ? stopScanning : () => void startScanning()}
              className="rounded-md bg-neutral-900 px-4 py-2 text-white"
            >
              {scanning ? 'Stop' : 'Scan'}
            </button>
          ) : null}
          <button
            type="button"
            onClick={() => void issueGateCode()}
            className="rounded-md border border-neutral-300 px-4 py-2"
          >
            New code
          </button>
        </div>

        <video
          ref={videoRef}
          muted
          playsInline
          className={scanning ? 'mt-3 w-full max-w-sm rounded-md bg-black' : 'hidden'}
        />

        {issuedCode ? (
          <p className="mt-3 break-all font-mono text-2xl tracking-widest">{issuedCode}</p>
        ) : null}

        {notice ? (
          <p role="alert" className="mt-3 text-sm text-amber-700">
            {notice}
          </p>
        ) : null}
      </div>

      <ul className="mt-6 divide-y divide-neutral-100">
        {members.map((member) => (
          <li key={member.id} className="py-3">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="font-medium">{member.full_name}</p>
                <p className="text-sm tabular-nums text-neutral-600">
                  {member.phone}
                  {member.status === 'active' ? null : ` · ${member.status}`}
                </p>
              </div>
              <div className="flex gap-2">
                <button
                  type="button"
                  disabled={gateCode === '' || busyMemberId === member.id}
                  onClick={() => void submit(member, { token: gateCode }, crypto.randomUUID())}
                  className="rounded-md bg-neutral-900 px-4 py-2 text-white disabled:bg-neutral-300"
                >
                  Check in
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setAssistFor(assistFor === member.id ? '' : member.id);
                    setReason('');
                  }}
                  className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
                >
                  At the desk
                </button>
              </div>
            </div>

            {assistFor === member.id ? (
              <form
                className="mt-3 flex flex-wrap gap-2"
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
                  className={`${FIELD_CLASS} sm:w-96`}
                />
                <button
                  type="submit"
                  disabled={busyMemberId === member.id}
                  className="rounded-md bg-neutral-900 px-4 py-2 text-white disabled:bg-neutral-300"
                >
                  Record
                </button>
              </form>
            ) : null}
          </li>
        ))}
      </ul>

      {members.length === 0 ? (
        <p className="mt-6 text-sm text-neutral-600">No member of this gym matched.</p>
      ) : null}
    </fieldset>
  );
}
