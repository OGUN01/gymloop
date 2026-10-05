create or replace function public.register_payment_proof(
  p_request_id uuid, p_mime text, p_bytes integer, p_command_key uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $fn$
declare
  v_actor record;
  v_existing jsonb;
  v_facts jsonb;
  v_asset public.media_assets%rowtype;
  v_result jsonb;
begin
  select * into v_actor from app.shop_actor('member');
  if p_command_key is null then
    raise exception 'Registration arguments required' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'purchase-request:' || v_actor.tenant_id::text || ':' || p_request_id::text, 0));
  v_facts := jsonb_build_object('mime', p_mime, 'bytes', p_bytes);
  -- The command-table seam's take re-proves a minted capability row; the
  -- register path mints its own member-class capability here, exactly as the
  -- attach command does, so the lookup's take resolves instead of starving.
  perform app.pay_grant_capability('command_note', v_actor.tenant_id, p_request_id, 'member');
  v_existing := app.pay_command_lookup(v_actor.tenant_id, p_request_id, p_command_key, 'register');
  if v_existing is not null then
    -- Replay compares the CALLER-comparable facts only (frozen decision 5):
    -- the stored facts additionally carry the mint's own assetId output,
    -- which no caller can know at replay time, so the equality test
    -- normalizes to requestId (the lookup keys on it) + mime + bytes + actor.
    -- Every accessor below pins the jsonb type explicitly: the runtime
    -- capture showed `text ->> unknown` when the seam's return/row value
    -- resolved as text, and a text left-operand must never reach `->>`.
    if ((v_existing::jsonb)->'facts'->>'mime') = p_mime
      and ((v_existing::jsonb)->'facts'->>'bytes')::integer = p_bytes
      and (v_existing::jsonb)->>'actor_user_id' = v_actor.user_id::text then
      -- Read-only replay of the original registration result: same asset, same
      -- staging facts, no second counter use or deadline.
      select a.* into v_asset from public.media_assets a
       where a.tenant_id = v_actor.tenant_id
         and a.id = ((v_existing::jsonb)->'facts'->>'assetId')::uuid;
      if not found then
        raise exception 'Proof registration key already named different facts'
          using errcode = 'GL068', detail = 'idempotency_conflict';
      end if;
      return jsonb_build_object(
        'assetId', v_asset.id, 'stagingObjectKey', v_asset.staging_object_key,
        'mime', p_mime, 'bytes', p_bytes);
    end if;
    raise exception 'Proof registration key already named different facts'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;
  v_result := public.register_payment_proof(p_request_id, p_mime, p_bytes);
  perform app.pay_command_record(v_actor.tenant_id, p_request_id, p_command_key, 'register',
    jsonb_build_object('assetId', ((v_result::jsonb)->>'assetId')::uuid, 'mime', p_mime, 'bytes', p_bytes),
    v_actor.user_id);
  return v_result;
end
$fn$;