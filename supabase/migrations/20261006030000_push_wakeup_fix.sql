-- Two fixes from sweep 37359420040:

-- 1. app.enqueue_push_dispatch_wakeup called extensions.http_post — no such
--    function exists (pg_net's surface is net.http_post; the extensions
--    schema has zero http_post variants). The helper was never
--    live-exercised before (the scheduler ships inert, PSD-013), so the
--    defect surfaced only when the visible 84 suite's PSD-005 section made
--    the first real call. Re-created against the real surface; the body is
--    otherwise the applied one, byte for byte.
create or replace function app.enqueue_push_dispatch_wakeup(p_secret text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  if p_secret is null or btrim(p_secret) = '' then
    raise exception 'push_dispatch_wakeup: secret configuration unusable';
  end if;
  perform net.http_post(
    url => 'https://pecxrpskmfeuyzngvewq.supabase.co/functions/v1/push-dispatch',
    body => '{}'::jsonb,
    headers => jsonb_build_object(
      'Content-Type', 'application/json',
      'x-gymloop-push-dispatch-secret', p_secret),
    timeout_milliseconds => 5000);
end
$fn$;
alter function app.enqueue_push_dispatch_wakeup(text) owner to postgres;
revoke all on function app.enqueue_push_dispatch_wakeup(text) from public, anon, authenticated, service_role;
grant execute on function app.enqueue_push_dispatch_wakeup(text) to postgres;

-- 2. member_devices_platform_select is restored: 20261006010000 over-dropped
--    — the grant-derived matrix constrains only write policies (04 test 7
--    passed with all select policies gone), but the platform-pair invariant
--    (04 test 5) does not list member_devices among the SELECT-half
--    exemptions, so it must carry the canonical platform read.
create policy member_devices_platform_select
  on public.member_devices
  for select to authenticated
  using ((select app.is_platform()));
