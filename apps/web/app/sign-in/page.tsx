import { redirect } from 'next/navigation';
import { PRODUCT_NAME } from '@gymloop/shared';
import { signIn } from '../../lib/auth-actions';
import { createServerSupabase } from '../../lib/supabase/server';

const FIELD_CLASS =
  'w-full rounded-md border border-neutral-300 px-3 py-2 text-base outline-none focus:border-neutral-900';

export default async function SignInPage({
  searchParams,
}: {
  searchParams: Promise<{ failed?: string }>;
}) {
  const supabase = await createServerSupabase();
  const { data } = await supabase.auth.getClaims();

  if (data?.claims) {
    redirect('/console');
  }

  const { failed } = await searchParams;

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-6 px-6">
      <div>
        <h1 className="text-2xl font-semibold">{PRODUCT_NAME}</h1>
        <p className="mt-1 text-sm text-neutral-600">Staff sign-in.</p>
      </div>

      {failed ? (
        <p role="alert" className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          Those details did not match. Check the email and password and try again.
        </p>
      ) : null}

      <form action={signIn} className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <label htmlFor="email" className="text-sm font-medium">
            Email
          </label>
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            required
            className={FIELD_CLASS}
          />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="password" className="text-sm font-medium">
            Password
          </label>
          <input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            required
            className={FIELD_CLASS}
          />
        </div>

        <button
          type="submit"
          className="rounded-md bg-neutral-900 px-3 py-2 text-base font-medium text-white"
        >
          Sign in
        </button>
      </form>

      <p className="text-sm text-neutral-600">
        There is no self sign-up. Your gym creates staff accounts; ask whoever runs it.
      </p>
    </main>
  );
}
