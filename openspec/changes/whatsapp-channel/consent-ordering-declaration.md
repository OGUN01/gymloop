# WhatsApp consent ordering — mechanical verification declaration

Frozen 2026-10-04 before independent ordering regressions. This restates the
already-frozen proposal's channel-consent ordering and WSP-002/003/010; it
creates no consent, permission, provider activation, retry or money movement.

Current channel decision for a tenant/member/purpose is exactly the first row
ordered `recorded_at DESC,id DESC`. Equal recording instants use UUID order,
not insertion order, created_at, physical ctid, vacuum layout or any granted
historical row. Both grant and withdrawal participate before granted/recipient
eligibility is evaluated. Preparation, claim and immediately-before-I/O checks
must use that same decision and the immutable stored channel consent reference.

The mandatory generic category consent remains distinct: missing required
generic consent cannot authorize dormant paid provider I/O. No channel grant
substitutes for service/marketing consent or current guardian/recipient evidence.
Manual opening retains its separate approved baseline and zero wallet/I/O rules.

Independent fixtures must represent real current recipient evidence, preferably
through the public consent commands, rather than placeholder digests or contact
versions. Historical bootstrap rows need correct causal facts. Recorded-time
ties are deliberate tests of UUID ordering; chronological scenarios must have
distinct lawful recorded instants. Never modify source eligibility to admit an
invented fixture. Emit every assertion's TAP result for canonical pg_prove;
discarding PERFORM results is not sufficient output for the independent CI gate.
