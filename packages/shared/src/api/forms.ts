import { z } from 'zod';

/**
 * **A blank optional input is absent, not empty**, and an HTML form cannot say
 * so any other way: a text field left untouched submits `''`, not nothing.
 *
 * Without this, a front desk logging a call and leaving the note blank — which
 * is most calls — had the whole follow-up refused as "not readable", because
 * `''` is present and fails `min(1)`. Found by pressing the button in a
 * browser; no unit test would have, because a test constructs the body it
 * means and a form constructs the body it has.
 *
 * It lives here rather than in either schema because both need it and `jscpd`
 * was right to say so: the second copy was written by pasting the first,
 * comment and all, which is how one of them would later be fixed alone.
 */
export function optionalField<T extends z.ZodTypeAny>(inner: T) {
  return z.preprocess(
    (value) => (typeof value === 'string' && value.trim() === '' ? undefined : value),
    inner.optional(),
  );
}
