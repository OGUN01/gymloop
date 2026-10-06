'use client';

import { useEffect, useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { ClassCommandStatus, useClassCommand } from '../../../member/classes/class-actions';

export function MemberClassVisibilityEditor({ enabled }: { enabled: boolean | null }) {
  const router = useRouter();
  const command = useClassCommand();
  const [draft, setDraft] = useState(enabled);
  useEffect(() => { setDraft(enabled); }, [enabled]);

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (draft === null || enabled === null || command.disabled) return;
    const result = await command.send('/api/class-visibility', { enabled: draft }, 'PUT');
    if (result === null) return;
    if (typeof result.enabled !== 'boolean' || typeof result.changed !== 'boolean') {
      command.setMessage('Classes visibility could not be confirmed. Refresh and try again.');
      return;
    }
    setDraft(result.enabled);
    command.setMessage(result.changed ? `Classes visibility saved. Classes are ${result.enabled ? 'shown' : 'hidden'} in the member app.` : 'Classes visibility is already up to date.');
  }

  return <section className="cl-panel">
    <h2 className="cl-section-title">Member Classes visibility</h2>
    <p>Show a Classes tab in the member app. Manage availability and new bookings in the class catalogue.</p>
    {enabled === null || draft === null ? <div className="cl-alert" role="alert">
      <p>Classes visibility could not be loaded. Try again to read the current setting.</p>
      <button className="cl-btn cl-btn--quiet" type="button" onClick={() => router.refresh()}>Retry</button>
    </div> : <form className="class-editor" onSubmit={save}>
      <fieldset disabled={command.disabled}>
        <label><input type="checkbox" checked={draft} disabled={command.disabled} onChange={(event) => { setDraft(event.target.checked); command.setMessage(null); }} />Show Classes to members</label>
        <button className="cl-btn" type="submit" disabled={command.disabled}>Save Classes visibility</button>
      </fieldset>
    </form>}
    <ClassCommandStatus command={command} />
  </section>;
}
