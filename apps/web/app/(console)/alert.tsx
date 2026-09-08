/**
 * The one red banner every console screen uses to say something went wrong.
 *
 * It exists because two screens had spelled the same ten lines out —
 * `role="alert"`, the same six Tailwind classes, twice each for a form refusal
 * and a failed load — and `jscpd` called it a clone. It was right: the second
 * copy was made by pasting the first, which is how one of them ends up with a
 * different colour or, worse, without the `role`.
 *
 * `role="alert"` is not decoration. A front desk that has just pressed a button
 * needs the refusal read out to them by the screen reader without moving focus,
 * and that attribute is the whole of it.
 */
export function Alert({ children }: { children: React.ReactNode }) {
  return (
    <p role="alert" className="mt-4 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
      {children}
    </p>
  );
}
