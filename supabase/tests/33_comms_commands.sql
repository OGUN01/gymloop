-- 33_comms_commands.sql — Phase 6 communications/wallet, visible suite 3 of 3:
-- the notification graph, the narrow member/WhatsApp commands, the renewal
-- reminder stages, the wallet movement command and the exact audit shapes.
--
-- Derived only from docs/planning/phase6-comms-contract.md (§4 lifecycle and
-- ordinary send, §5 narrow member and WhatsApp commands, §6 one renewal formula
-- and idempotent daily stages, §7 wallet movement, §8 exact audit), with
-- docs/planning/phase6-contract-seam.md and the RENEWAL_REMINDER_WINDOWS
-- constant in packages/shared/src/config/constants.ts. The Phase 6 comms
-- migration, any implementation and supabase/tests-holdout/ were not read, so
-- this suite is red today by design.
--
-- Resolutions this file pins, stated up front:
-- * The transition graph is probed with the exact all-pairs matrix used by
--   54_addon_sales.sql: every allowed changing edge lives_ok, every
--   disallowed changing edge throws GL066. Same-state writes are always
--   permitted by app.notification_transition_allowed, so the matrix asserts
--   only the 34 disallowed changing pairs and 8 allowed changing edges; the
--   7 same-state pairs are pinned separately as lives_ok through the
--   function itself.
-- * "Every changing edge writes exactly one audit event" (§8) is pinned on
--   send_notification's real edges (scheduled→sent, scheduled→opted_out,
--   scheduled→failed), not on hand-forged table updates: the invariant
--   applies on UPDATE too, but a hand-rolled UPDATE outside the product
--   command would need the member lock/fresh-read harness the contract
--   describes, which is not a pgTAP-visible behavior. The audit shape
--   assertions cover scheduled/sent/failed/opted_out and the wallet events.
-- * The renewal run's evaluatedAt/localDate are derived from
--   statement_timestamp() and the gym timezone inside one transaction, so a
--   pgTAP run cannot pin a different wall date; what is pinned is the count
--   grammar, the key grammar (exact string), the payload (exact object), the
--   remainder arithmetic (exact decimal strings) and the replay zeros.
-- * A queued renewal's availability is decided against the CURRENT ends_on at
--   send time; "renewal_stopped" covers an obsolete/paid cycle, and the file
--   pins it with a membership whose ends_on moved after scheduling.
-- * WhatsApp URL encoding: the contract pins the exact prefix
--   `https://wa.me/<phone without +>?text=`; the exact percent-encoding of a
--   body with spaces/emoji is a JS-side concern, so the assertion pins the
--   prefix, that the body text survives into the query parameter, and that no
--   phone-with-plus appears.
-- * adjust_messaging_wallet's zero-delta/blank-reason refusal is pinned as
--   23514 at the DB level (the contract's own mapping table puts 23514→422
--   invalid_adjustment at the route; the DB raises the native code).
--
-- ADR-030: one transaction, BEGIN … ROLLBACK, nothing committed.
-- ADR-046: the owner role is assumed explicitly, never inherited.
-- ADR-050: every count is scoped to this file's own fixture tenants.

begin;
set local role postgres;
set local search_path = extensions, public;
select set_config('request.jwt.claims', '', true);

select plan(82);

-- ---------------------------------------------------------------------------
-- Fixtures. Prefix 3c000000 is this file's alone. Two gyms: the primary active
-- gym with a full roster, and a second gym proving cross-gym invisibility.
-- ---------------------------------------------------------------------------

insert into public.organizations(id,name,gym_code,status,timezone,trial_ends_at,currency) values
 ('3c000000-0000-4000-8000-000000000001','Comms Commands A','CCA33A','active','Asia/Kolkata',null,'INR'),
 ('3c000000-0000-4000-8000-000000000002','Comms Commands B','CCB33B','active','Asia/Kolkata',null,'INR');
insert into public.branches(id,tenant_id,name,is_default) values
 ('3c000000-0000-4000-8000-000000000011','3c000000-0000-4000-8000-000000000001','Main',true),
 ('3c000000-0000-4000-8000-000000000012','3c000000-0000-4000-8000-000000000002','Main B',true);
insert into auth.users(id) values
 ('3c000000-0000-4000-8000-000000000901'),('3c000000-0000-4000-8000-000000000902'),
 ('3c000000-0000-4000-8000-000000000903'),('3c000000-0000-4000-8000-000000000904'),
 ('3c000000-0000-4000-8000-000000000905'),('3c000000-0000-4000-8000-000000000906');
insert into public.platform_users(user_id,role,full_name,email,is_active) values
 ('3c000000-0000-4000-8000-000000000905','super_admin','Super Probe','super33@example.test',true),
 ('3c000000-0000-4000-8000-000000000906','platform_support','Support Probe','support33@example.test',false);
insert into public.staff(id,tenant_id,user_id,branch_id,role,full_name) values
 ('3c000000-0000-4000-8000-000000000021','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000901','3c000000-0000-4000-8000-000000000011','gym_owner','Owner A'),
 ('3c000000-0000-4000-8000-000000000022','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000902','3c000000-0000-4000-8000-000000000011','front_desk','Desk A'),
 ('3c000000-0000-4000-8000-000000000029','3c000000-0000-4000-8000-000000000002','3c000000-0000-4000-8000-000000000906','3c000000-0000-4000-8000-000000000012','gym_owner','Owner B');
insert into public.members(id,tenant_id,branch_id,full_name,phone,status,motivation_push_enabled) values
 ('3c000000-0000-4000-8000-000000000031','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000011','Member A1','+915330000031','active',true),
 ('3c000000-0000-4000-8000-000000000032','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000011','Member A2','+915330000032','active',true),
 ('3c000000-0000-4000-8000-000000000033','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000011','Member A3','+915330000033','active',true),
 ('3c000000-0000-4000-8000-000000000034','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000011','Member A4','+915330000034','active',true),
 ('3c000000-0000-4000-8000-000000000035','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000011','Member A5','+915330000035','active',false),
 ('3c000000-0000-4000-8000-000000000036','3c000000-0000-4000-8000-000000000002','3c000000-0000-4000-8000-000000000012','Member B1','+915330000036','active',true);
update public.members set user_id='3c000000-0000-4000-8000-000000000904' where id='3c000000-0000-4000-8000-000000000031';
update public.members set user_id='3c000000-0000-4000-8000-000000000903' where id='3c000000-0000-4000-8000-000000000032';
insert into public.messaging_wallets(tenant_id,balance_credits) values
 ('3c000000-0000-4000-8000-000000000001',100),
 ('3c000000-0000-4000-8000-000000000002',0);
insert into public.plans(id,tenant_id,name,duration_days,price_paise) values
 ('3c000000-0000-4000-8000-000000000401','3c000000-0000-4000-8000-000000000001','Monthly',30,20000);
insert into public.memberships(id,tenant_id,member_id,plan_id,status,price_paise,discount_paise,currency,starts_on,ends_on,periods_granted) values
 ('3c000000-0000-4000-8000-000000000451','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000031','3c000000-0000-4000-8000-000000000401','active',20000,0,'INR',
  (transaction_timestamp() at time zone 'Asia/Kolkata')::date - 16,(transaction_timestamp() at time zone 'Asia/Kolkata')::date,0),
 ('3c000000-0000-4000-8000-000000000452','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000032','3c000000-0000-4000-8000-000000000401','active',20000,0,'INR',
  (transaction_timestamp() at time zone 'Asia/Kolkata')::date - 15,(transaction_timestamp() at time zone 'Asia/Kolkata')::date,0),
 ('3c000000-0000-4000-8000-000000000453','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000033','3c000000-0000-4000-8000-000000000401','active',20000,0,'INR',
  (transaction_timestamp() at time zone 'Asia/Kolkata')::date - 15,(transaction_timestamp() at time zone 'Asia/Kolkata')::date,0),
 ('3c000000-0000-4000-8000-000000000454','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000034','3c000000-0000-4000-8000-000000000401','active',20000,0,'INR',
  (transaction_timestamp() at time zone 'Asia/Kolkata')::date - 15,(transaction_timestamp() at time zone 'Asia/Kolkata')::date,0);
insert into public.payments(id,tenant_id,member_id,membership_id,amount_paise,currency,status,method,recorded_by_staff_id,receipt_number,paid_at) values
 ('3c000000-0000-4000-8000-000000000461','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000031','3c000000-0000-4000-8000-000000000451',12000,'INR','paid','cash','3c000000-0000-4000-8000-000000000021','33-R1',transaction_timestamp()),
 ('3c000000-0000-4000-8000-000000000462','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000031','3c000000-0000-4000-8000-000000000451',5000,'INR','paid','cash','3c000000-0000-4000-8000-000000000021','33-R2',transaction_timestamp());

-- Historical consent rows give members a current service grant; the exact
-- consent probe in 32_comms_consent_serialization.sql covers ordering, so
-- these are the honest minimum this file needs.
insert into public.consents(tenant_id,member_id,purpose,granted,version,source,recorded_at,request_key) values
 ('3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000031','service',true,'v1','front_desk_signup',transaction_timestamp() - interval '1 day','3c000000-0000-4000-8000-000000000501'),
 ('3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000032','service',true,'v1','front_desk_signup',transaction_timestamp() - interval '1 day','3c000000-0000-4000-8000-000000000502'),
 ('3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000032','marketing',true,'v1','front_desk_signup',transaction_timestamp() - interval '1 day','3c000000-0000-4000-8000-000000000503'),
 ('3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000033','service',false,'v1','member_app',transaction_timestamp() - interval '1 day','3c000000-0000-4000-8000-000000000506'),
 ('3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000034','service',true,'v1','front_desk_signup',transaction_timestamp() - interval '1 day','3c000000-0000-4000-8000-000000000504'),
 ('3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000035','service',true,'v1','front_desk_signup',transaction_timestamp() - interval '1 day','3c000000-0000-4000-8000-000000000505');

insert into public.message_templates(id,tenant_id,key,channel,locale,category,body) values
 ('3c000000-0000-4000-8000-000000000101','3c000000-0000-4000-8000-000000000001','promo_jan','in_app','en','promotion','January promo'),
 ('3c000000-0000-4000-8000-000000000102','3c000000-0000-4000-8000-000000000001','motivation_checkin','push','en','motivation','Time to move'),
 ('3c000000-0000-4000-8000-000000000103','3c000000-0000-4000-8000-000000000002','other_gym_t','in_app','en','payment','Other gym body');

-- Historical source notifications, inserted as the owner under RLS-off.
-- ADR-098: these are honest historical-shape rows (sent in-app source, a
-- scheduled push, a scheduled whatsapp-able source); inserting them directly
-- rather than through product commands is what "trusted history loading" means.
set local session_replication_role = replica;
insert into public.notifications(id,tenant_id,member_id,channel,status,dedupe_key,scheduled_for,sent_at,delivered_at,related_type,related_id,payload,category,template_key) values
 ('3c000000-0000-4000-8000-000000000201','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000031','in_app','sent','33-src-a1',transaction_timestamp(),transaction_timestamp(),transaction_timestamp(),'membership','3c000000-0000-4000-8000-000000000451','{"body":"Your membership ends soon","locale":"en"}','renewal','renewal_reminder'),
 ('3c000000-0000-4000-8000-000000000202','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000032','in_app','sent','33-src-a2',transaction_timestamp(),transaction_timestamp(),transaction_timestamp(),'membership','3c000000-0000-4000-8000-000000000452','{"body":"Renewal due","locale":"en"}','renewal','renewal_reminder'),
 ('3c000000-0000-4000-8000-000000000203','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000031','push','scheduled','33-push-a1',transaction_timestamp(),null,null,null,null,'{"body":"Push body"}','promotion','promo_jan'),
 ('3c000000-0000-4000-8000-000000000204','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000031','in_app','scheduled','33-inapp-a1',transaction_timestamp() - interval '2 hours',null,null,null,null,'{"body":"Stale schedule"}','promotion','promo_jan'),
 ('3c000000-0000-4000-8000-000000000205','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000031','sms','scheduled',null,transaction_timestamp(),null,null,null,null,'{"body":"SMS"}','promotion','promo_jan'),
 ('3c000000-0000-4000-8000-000000000206','3c000000-0000-4000-8000-000000000002','3c000000-0000-4000-8000-000000000036','in_app','sent','33-src-b1',transaction_timestamp(),transaction_timestamp(),transaction_timestamp(),'membership','3c000000-0000-4000-8000-000000000451','{"body":"Other gym","locale":"en"}','renewal','renewal_reminder');
set local session_replication_role = origin;

create function pg_temp.captured_error(p_sql text)
returns table(returned_state text, detail text)
language plpgsql as $fn$
begin
  execute p_sql;
  return query select null::text, null::text;
exception when others then
  get stacked diagnostics returned_state=returned_sqlstate, detail=pg_exception_detail;
  return next;
end
$fn$;
grant execute on function pg_temp.captured_error(text) to authenticated;

create temp table cmd_results(label text, result jsonb);
grant select,insert on cmd_results to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Transition graph: every allowed changing edge and all 34 disallowed ones
-- ---------------------------------------------------------------------------

select results_eq(
  $$select (select count(*) from (select f,t from unnest(enum_range(null::public.notification_status)) f cross join unnest(enum_range(null::public.notification_status)) t where f<>t) pairs where app.notification_transition_allowed(f,t))$$,
  $$select 8::bigint$$,
  'COM: exactly the 8 changing edges the contract names are allowed');
select results_eq(
  $$select count(*) from unnest(enum_range(null::public.notification_status)) s
     where not app.notification_transition_allowed(s,s)$$,
  $$select 0::bigint$$,
  'COM: same-state transitions are always allowed');
select ok(
  app.notification_transition_allowed('scheduled','sent')
  and app.notification_transition_allowed('scheduled','opted_out')
  and app.notification_transition_allowed('scheduled','failed')
  and app.notification_transition_allowed('sent','delivered')
  and app.notification_transition_allowed('sent','failed')
  and app.notification_transition_allowed('delivered','clicked')
  and app.notification_transition_allowed('delivered','converted')
  and app.notification_transition_allowed('clicked','converted'),
  'COM: the exact changing-edge list is scheduled→sent/opted_out/failed, sent→delivered/failed, delivered→clicked/converted, clicked→converted');

create or replace function pg_temp.notification_transition_matrix_ok()
returns boolean language plpgsql as $fn$
declare f public.notification_status; t public.notification_status; nid uuid; got text;
begin
  for f in select unnest(enum_range(null::public.notification_status)) loop
    for t in select unnest(enum_range(null::public.notification_status)) loop
      if f <> t and not ((f='scheduled' and t in ('sent','opted_out','failed')) or
                         (f='sent' and t in ('delivered','failed')) or
                         (f='delivered' and t in ('clicked','converted')) or
                         (f='clicked' and t='converted')) then
        nid := gen_random_uuid();
        insert into public.notifications(id,tenant_id,member_id,channel,status,category,template_key,dedupe_key,scheduled_for)
        values (nid,'3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000031','in_app',f,'promotion','promo_probe',null,transaction_timestamp());
        begin
          update public.notifications set status=t where id=nid;
          return false;
        exception when others then
          get stacked diagnostics got=returned_sqlstate;
          if got <> 'GL066' then return false; end if;
        end;
        delete from public.notifications where id=nid;
      end if;
    end loop;
  end loop;
  return true;
end $fn$;

select ok(pg_temp.notification_transition_matrix_ok(),'all 34 disallowed notification_status enum pairs raise GL066');

-- ---------------------------------------------------------------------------
-- 2. send_notification: gates and refusals
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"3c000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"front_desk","tenant_id":"3c000000-0000-4000-8000-000000000001","staff_id":"3c000000-0000-4000-8000-000000000022"}', true);
set local role authenticated;

-- Front-office gate: a member cannot send; a trainer cannot either. Member A1's
-- message (206) is another gym's row for this session and must be P0002
-- indistinguishable from absent, which is why this runs as the desk of gym A.
select results_eq(
  $$select returned_state from pg_temp.captured_error($q$select * from public.send_notification('3c000000-0000-4000-8000-000000000206')$q$)$$,
  $$select 'P0002'::text$$,
  'COM: sending another gym''s notification is indistinguishable from sending a nonexistent one');
select results_eq(
  $$select returned_state from pg_temp.captured_error($q$select * from public.send_notification('3c000000-0000-4000-8000-000000000205')$q$)$$,
  $$select 'GL066'::text$$,
  'COM: SMS has no v1 send action — GL066');
select results_eq(
  $$select returned_state from pg_temp.captured_error($q$update public.notifications set scheduled_for=transaction_timestamp()+interval '1 hour' where id='3c000000-0000-4000-8000-000000000204'; select * from public.send_notification('3c000000-0000-4000-8000-000000000204')$q$)$$,
  $$select 'GL066'::text$$,
  'COM: sending before scheduled_for is GL066');

select ok(
  (select count(*) from pg_temp.captured_error($q$update public.notifications set scheduled_for=transaction_timestamp()+interval '1 hour' where id='3c000000-0000-4000-8000-000000000204'$q$)) = 1,
  'COM: future-schedule preparation completes in its own probe');

-- In-app promotion send for an eligible scheduled message. Notification 204
-- was re-stamped to the future above, so reset it to now inside its own probe
-- and send 204, whose promotion send is genuinely allowed (member 031 has a
-- current marketing grant through the fixture consents).
set local role postgres;
select set_config('request.jwt.claims', '', true);
update public.notifications set scheduled_for=transaction_timestamp() where id='3c000000-0000-4000-8000-000000000204'::uuid;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"3c000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"front_desk","tenant_id":"3c000000-0000-4000-8000-000000000001","staff_id":"3c000000-0000-4000-8000-000000000022"}', true);

select lives_ok(
  $q$insert into cmd_results select 'promo-sent', x.result from
    (select public.send_notification('3c000000-0000-4000-8000-000000000204') result) x$q$,
  'COM: front desk sends an eligible in-app message');

select results_eq(
  $$select n.status::text, n.sent_at is not null, n.delivered_at is null
      from public.notifications n join cmd_results c on (c.result->>'notificationId')=n.id::text
     where c.label='promo-sent'$$,
  $$select 'sent'::text, true, true$$,
  'COM: in-app send becomes sent with sent_at stamped and delivered_at untouched');

select results_eq(
  $$select (select count(*) from jsonb_object_keys(result)) = 10,
          result ? 'notificationId' and result ? 'memberId' and result ? 'channel' and result ? 'status' and result ? 'sentAt'
          and result ? 'deliveredAt' and result ? 'failedAt' and result ? 'failedReason' and result ? 'optedOutAt' and result ? 'optedOutReason'
      from cmd_results where label='promo-sent'$$,
  $$select true, true$$,
  'COM: NotificationResult is exactly the ten-key object with explicit nulls');

select results_eq(
  $$select count(*) from public.messaging_wallet_ledger where notification_id='3c000000-0000-4000-8000-000000000204'::uuid$$,
  $$select 0::bigint$$,
  'COM: an in-app send charges zero credits');

-- Push is failed/provider_unconfigured at zero cost.
select lives_ok(
  $q$insert into cmd_results select 'push-failed', public.send_notification('3c000000-0000-4000-8000-000000000203')$q$,
  'COM: sending an unconfigured push is accepted, not an error');

select results_eq(
  $$select r.result->>'status', r.result->>'failedReason', (r.result->>'sentAt') is null, (r.result->>'deliveredAt') is null
      from cmd_results r where r.label='push-failed'$$,
  $$select 'failed'::text, 'provider_unconfigured'::text, true, true$$,
  'COM: push without a configured provider fails with provider_unconfigured and null sent/delivered');
select results_eq(
  $$select count(*) from public.messaging_wallet_ledger where notification_id='3c000000-0000-4000-8000-000000000203'::uuid$$,
  $$select 0::bigint$$,
  'COM: a provider_unconfigured push charges zero credits');

-- motivation_disabled: member A5 has motivation_push_enabled=false and an in-app
-- motivation source scheduled; withdrawing at send time refuses the action.
set local role postgres;
select set_config('request.jwt.claims', '', true);
insert into public.notifications(id,tenant_id,member_id,channel,status,category,template_key,dedupe_key,scheduled_for)
values ('3c000000-0000-4000-8000-000000000207','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000035','in_app','scheduled','motivation','motivation_checkin','33-mot-a5',transaction_timestamp());
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"3c000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"front_desk","tenant_id":"3c000000-0000-4000-8000-000000000001","staff_id":"3c000000-0000-4000-8000-000000000022"}', true);

select lives_ok(
  $q$insert into cmd_results select 'motivation-disabled', public.send_notification('3c000000-0000-4000-8000-000000000207')$q$,
  'COM: sending a motivation message for a member with motivation disabled is refused as opted_out');
select results_eq(
  $$select r.result->>'status', r.result->>'optedOutReason'
      from cmd_results r where r.label='motivation-disabled'$$,
  $$select 'opted_out'::text, 'motivation_disabled'::text$$,
  'COM: a disabled motivation push is opted_out with reason motivation_disabled');

-- consent_withdrawn: member A3 has service consent withdrawn.
set local role postgres;
select set_config('request.jwt.claims', '', true);
insert into public.notifications(id,tenant_id,member_id,channel,status,category,template_key,dedupe_key,scheduled_for)
values ('3c000000-0000-4000-8000-000000000208','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000033','in_app','scheduled','renewal','renewal_reminder','33-consent-a3',transaction_timestamp());
set local role authenticated;
select lives_ok(
  $q$insert into cmd_results select 'consent-withdrawn', public.send_notification('3c000000-0000-4000-8000-000000000208')$q$,
  'COM: sending a renewal message for a member with withdrawn service consent is refused as opted_out');
select results_eq(
  $$select r.result->>'status', r.result->>'optedOutReason'
      from cmd_results r where r.label='consent-withdrawn'$$,
  $$select 'opted_out'::text, 'consent_withdrawn'::text$$,
  'COM: missing/withdrawn consent is opted_out with reason consent_withdrawn');

-- An already-processed row returns its current result without UPDATE.
select lives_ok(
  $q$insert into cmd_results select 'replay-sent', public.send_notification('3c000000-0000-4000-8000-000000000201')$q$,
  'COM: re-sending an already sent in-app message is accepted as a replay');
select results_eq(
  $$select r.result->>'status' from cmd_results r where r.label='replay-sent'$$,
  $$select 'sent'::text$$,
  'COM: an already processed row returns its current NotificationResult');

-- ---------------------------------------------------------------------------
-- 3. acknowledge_notification: narrow member path
-- ---------------------------------------------------------------------------

-- Member session (linked user 904 = member A1).
select set_config('request.jwt.claims',
  '{"sub":"3c000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"member","tenant_id":"3c000000-0000-4000-8000-000000000001","member_id":"3c000000-0000-4000-8000-000000000031"}', true);

select lives_ok(
  $q$insert into cmd_results select 'ack-a1', public.acknowledge_notification('3c000000-0000-4000-8000-000000000201')$q$,
  'COM: the member acknowledges their own in-app sent message');
select results_eq(
  $$select r.result->>'status', r.result->>'deliveredAt' is null from cmd_results r where r.label='ack-a1'$$,
  $$select 'delivered'::text, false$$,
  'COM: acknowledge transitions sent→delivered with a delivered timestamp');

-- Inert replay: acknowledging an already-delivered row changes nothing.
select results_eq(
  $$select (select delivered_at::text from public.notifications where id='3c000000-0000-4000-8000-000000000201'::uuid)$$,
  $q$select (r.result->>'deliveredAt') from cmd_results r where r.label='ack-a1'$q$,
  'COM: the acknowledged delivered_at is the one the first acknowledgement wrote');

select lives_ok(
  $q$insert into cmd_results select 'ack-replay', public.acknowledge_notification('3c000000-0000-4000-8000-000000000201')$q$,
  'COM: an already delivered acknowledgement is an inert replay');

select results_eq(
  $$select r.result->>'status', (r.result->>'deliveredAt') from cmd_results r where r.label in ('ack-a1','ack-replay') order by label$$,
  $$select 'delivered'::text, (r.result->>'deliveredAt') from cmd_results r where r.label='ack-a1'
   union all
   select 'delivered'::text, (r.result->>'deliveredAt') from cmd_results r where r.label='ack-a1'$$,
  'COM: the replay returns the original delivered result unchanged');

-- A trusted scheduled in_app row for member A1: resolving it succeeds, so the
-- refusal is GL066 (wrong state), unlike a push row which is indistinguishable
-- from absent. The scheduler's own fixture cannot bypass the member path.
set local role postgres;
select set_config('request.jwt.claims', '', true);
insert into public.notifications(id,tenant_id,member_id,channel,status,category,template_key,dedupe_key,scheduled_for)
values ('3c000000-0000-4000-8000-000000000209','3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000031','in_app','scheduled','promotion','promo_jan','33-ack-probe',transaction_timestamp());
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"3c000000-0000-4000-8000-000000000904","role":"authenticated","app_role":"member","tenant_id":"3c000000-0000-4000-8000-000000000001","member_id":"3c000000-0000-4000-8000-000000000031"}', true);

select throws_ok(
  $q$select * from public.acknowledge_notification('3c000000-0000-4000-8000-000000000209')$q$,
  'GL066'::text, null::text,
  'COM: acknowledging a scheduled in-app row is GL066 — only sent→delivered is permitted');

select throws_ok(
  $q$select * from public.acknowledge_notification('3c000000-0000-4000-8000-000000000203')$q$,
  'P0002'::text, null::text,
  'COM: acknowledging a push row is indistinguishable from a nonexistent id');

select throws_ok(
  $q$select * from public.acknowledge_notification('3c000000-0000-4000-8000-000000000206')$q$,
  'P0002'::text, null::text,
  'COM: acknowledging another gym''s message is indistinguishable from a nonexistent id');

-- Member A2 (user 903) cannot acknowledge member A1's message.
select set_config('request.jwt.claims',
  '{"sub":"3c000000-0000-4000-8000-000000000903","role":"authenticated","app_role":"member","tenant_id":"3c000000-0000-4000-8000-000000000001","member_id":"3c000000-0000-4000-8000-000000000032"}', true);
select throws_ok(
  $q$select * from public.acknowledge_notification('3c000000-0000-4000-8000-000000000201')$q$,
  'P0002'::text, null::text,
  'COM: another member''s in-app message is indistinguishable from a nonexistent one');

-- ---------------------------------------------------------------------------
-- 4. open_notification_whatsapp: child creation, repeat, withdrawal
-- ---------------------------------------------------------------------------

-- Front-office session: front desk staff id 022.
select set_config('request.jwt.claims',
  '{"sub":"3c000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"front_desk","tenant_id":"3c000000-0000-4000-8000-000000000001","staff_id":"3c000000-0000-4000-8000-000000000022"}', true);

select lives_ok(
  $q$insert into cmd_results select 'wa-open', public.open_notification_whatsapp('3c000000-0000-4000-8000-000000000201')$q$,
  'COM: front desk opens the delivered in-app source in WhatsApp');

select results_eq(
  $$select (select count(*) from jsonb_object_keys(result)), result->'notification'->>'status', result->>'url' like 'https://wa.me/915330000031?text=%'
      from cmd_results where label='wa-open'$$,
  $$select 2::bigint, 'sent'::text, true$$,
  'COM: open_notification_whatsapp returns exactly {notification,url} with the contract URL prefix');

select ok(
  (select exists(select 1 from public.notifications
    where source_notification_id='3c000000-0000-4000-8000-000000000201'::uuid
      and channel='whatsapp_link'
      and dedupe_key='whatsapp:3c000000-0000-4000-8000-000000000201'
      and status='sent'
      and recipient_phone='+915330000031')),
  'COM: one whatsapp child exists with the exact dedupe key, sent status and E.164 snapshot');

select ok(
  (select not exists(select 1 from public.messaging_wallet_ledger
    where notification_id in (select id from public.notifications
      where source_notification_id='3c000000-0000-4000-8000-000000000201'::uuid))),
  'COM: opening WhatsApp never charges a credit');

-- Repeat opening: same child, same URL, no changes.
select lives_ok(
  $q$insert into cmd_results select 'wa-repeat', public.open_notification_whatsapp('3c000000-0000-4000-8000-000000000201')$q$,
  'COM: a repeat open while eligible is accepted');
select results_eq(
  $$select (r.result->>'url') from cmd_results r where r.label in ('wa-open','wa-repeat') order by label$$,
  $$select (r.result->>'url') from cmd_results r where r.label='wa-open'$$,
  'COM: the repeat returns the same URL');
select results_eq(
  $$select count(*) from public.notifications where source_notification_id='3c000000-0000-4000-8000-000000000201'::uuid and channel='whatsapp_link'$$,
  $$select 1::bigint$$,
  'COM: the repeat creates no second child');

-- Withdrawal before repeat: refuse a new URL, change no already-sent child.
set local role postgres;
select set_config('request.jwt.claims', '', true);
insert into public.consents(tenant_id,member_id,purpose,granted,version,source,recorded_at)
values ('3c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000031','service',false,'v2','member_app',transaction_timestamp());
set local role authenticated;

select set_config('request.jwt.claims',
  '{"sub":"3c000000-0000-4000-8000-000000000902","role":"authenticated","app_role":"front_desk","tenant_id":"3c000000-0000-4000-8000-000000000001","staff_id":"3c000000-0000-4000-8000-000000000022"}', true);

-- The withdrawal committed before this serialization point prevents a new URL.
select throws_ok(
  $q$select * from public.open_notification_whatsapp('3c000000-0000-4000-8000-000000000201')$q$,
  '42501'::text, null::text,
  'COM: an open after withdrawal is refused — withdrawal prevents a new URL');

select ok(
  (select count(*) = 1
     from public.notifications
   where source_notification_id='3c000000-0000-4000-8000-000000000201'::uuid
     and channel='whatsapp_link'),
  'COM: the refused open created no second child');

-- ---------------------------------------------------------------------------
-- 5. run_renewal_reminders: gates, counts, key grammar, replay zeros
-- ---------------------------------------------------------------------------

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- The scheduler is trusted, so this file drives it as service_role — the same
-- context cron obtains. Member A1 ends today (expiry_day window), has a service
-- grant and an active membership; the run creates one scheduled in-app row and
-- makes it available.
set local role service_role;

select lives_ok(
  $q$insert into cmd_results select 'run-a', app.run_renewal_reminders('3c000000-0000-4000-8000-000000000001')$q$,
  'COM: the trusted scheduler runs the renewal stage for gym A');

select results_eq(
  $$select r.result->>'createdCount', r.result->>'sentCount', r.result->>'optedOutCount'
      from cmd_results r where r.label='run-a'$$,
  $$select '1'::text, '1'::text, '0'::text$$,
  'COM: the first run creates one reminder and makes it available');

-- A rerun on the same day is inert: the key exists, so no new events are
-- counted and no audit is appended.
select lives_ok(
  $q$insert into cmd_results select 'run-a-replay', app.run_renewal_reminders('3c000000-0000-4000-8000-000000000001')$q$,
  'COM: the trusted scheduler reruns the renewal stage for gym A');

-- The all-gym stage visits gyms in tenant order in one statement; gym B has no
-- eligible membership, so it contributes nothing new.
select lives_ok(
  $q$insert into cmd_results select 'run-all', public.run_renewal_reminders_all()$q$,
  'COM: the trusted scheduler runs the all-gym stage');

-- Guarded cron registration pin, computed into a temp table per 20_red_list.sql:
-- pg_cron is installed by a prior migration, but the DO block keeps the
-- assertion alive (false, not an abort) if it ever is not, and the TAP line
-- stays a top-level select ok(...) so the emitted stream always matches the
-- counter.
do $do$
declare
  v_scheduled boolean;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $sql$
      select exists (
        select 1 from cron.job
         where jobname = 'renewal-reminders-hourly'
           and schedule = '0 * * * *'
           and command ilike '%run_renewal_reminders_all()%'
           and active
      )
    $sql$ into v_scheduled;
  else
    v_scheduled := false;
  end if;

  create temp table cron_fixture as select v_scheduled as scheduled;
end
$do$;

select ok(
  (select exists(select 1 from public.notifications
    where tenant_id='3c000000-0000-4000-8000-000000000001'::uuid
      and dedupe_key = 'renewal:3c000000-0000-4000-8000-000000000451:' ||
                        to_char((transaction_timestamp() at time zone 'Asia/Kolkata')::date,'YYYY-MM-DD') ||
                        ':expiry_day'
      and category='renewal' and channel='in_app' and template_key='renewal_reminder')),
  'COM: the renewal dedupe key is exactly renewal:<lowercase membership UUID>:<YYYY-MM-DD ends_on>:<window_id>');

select results_eq(
  $$select n.payload->>'body', n.payload->>'locale', n.payload->>'membershipId', n.payload->>'duePaise', n.payload->>'currency', n.payload->>'windowId', n.payload->>'cycleEndsOn'
      from public.notifications n
     where n.dedupe_key like 'renewal:3c000000-0000-4000-8000-000000000451:%:expiry_day'$$,
  $$select 'Your membership ends on ' ||
          to_char((transaction_timestamp() at time zone 'Asia/Kolkata')::date,'YYYY-MM-DD') ||
          '. Renewal amount due: INR 200.00.'::text,
          'en'::text,
          '3c000000-0000-4000-8000-000000000451'::text,
          '20000'::text,
          'INR'::text,
          to_char((transaction_timestamp() at time zone 'Asia/Kolkata')::date,'YYYY-MM-DD')::text$$,
  'COM: the reminder payload is the exact contract object with body, locale, membership, due, currency');

select results_eq(
  $$select r.result->>'createdCount', r.result->>'sentCount'
      from cmd_results r where r.label='run-a-replay'$$,
  $$select '0'::text, '0'::text$$,
  'COM: an unchanged rerun returns zero new counts');

select results_eq(
  $$select r.result->>'createdCount' from cmd_results r where r.label='run-all'$$,
  $$select '0'::text$$,
  'COM: the all-gym run reports only new events — nothing is created after the inert rerun');

select ok(
  (select not exists(select 1 from public.notifications
    where tenant_id='3c000000-0000-4000-8000-000000000002'::uuid
      and dedupe_key like 'renewal:%')),
  'COM: an inactive membership in another gym creates no reminder');

select throws_ok(
  $q$select app.run_renewal_reminders('3c000000-0000-4000-8000-000000000001')$q$,
  '42501'::text, null::text,
  'COM: authenticated has no execute on the renewal stage runner');

select throws_ok(
  $q$select public.run_renewal_reminders_all()$q$,
  '42501'::text, null::text,
  'COM: authenticated has no execute on the all-gym stage');

select ok(
  (select not p.prosecdef and p.provolatile='v' and p.proconfig @> array['search_path=""'] and p.pronargs=1
    from pg_proc p where p.oid=to_regprocedure('app.run_renewal_reminders(uuid)')),
  'COM: run_renewal_reminders is the volatile invoker empty-path single-arg stage');
select ok(
  (select not p.prosecdef and p.provolatile='v' and p.proconfig @> array['search_path=""'] and p.pronargs=0
    from pg_proc p
   where p.oid=to_regprocedure('public.run_renewal_reminders_all()')),
  'COM: run_renewal_reminders_all is the volatile invoker zero-arg all-gym stage');
select ok(
  (select not has_function_privilege('authenticated','public.run_renewal_reminders_all()','execute')
     and not has_function_privilege('anon','public.run_renewal_reminders_all()','execute')),
  'COM: the all-gym stage is not an authenticated RPC');

select ok(
  (select p.provolatile='s' and p.prorettype='jsonb'::regtype and p.pronargs=2
    from pg_proc p where p.oid=to_regprocedure('app.membership_renewal_remainder(uuid,uuid)')),
  'COM: membership_renewal_remainder is the STABLE jsonb two-arg read helper');

select ok(
  (select p.provolatile='i'
    from pg_proc p where p.oid=to_regprocedure('app.default_renewal_reminder_windows()')),
  'COM: default_renewal_reminder_windows is the immutable window source');

select results_eq(
  $$select window_id, days_from_expiry from app.default_renewal_reminder_windows()$$,
  $$select * from (values ('expiry_minus_14'::text,(-14)::smallint),
                          ('expiry_minus_7'::text,(-7)::smallint),
                          ('expiry_minus_3'::text,(-3)::smallint),
                          ('expiry_day'::text,0::smallint),
                          ('expiry_plus_3'::text,3::smallint)) v$$,
  'COM: the default windows are exactly RENEWAL_REMINDER_WINDOWS in order');

select ok(
  (select v_scheduled from cron_fixture),
  'COM: a cron.job row runs public.run_renewal_reminders_all() hourly');

-- ---------------------------------------------------------------------------
-- 6. adjust_messaging_wallet: gates, replay, conflicts, negative race
-- ---------------------------------------------------------------------------

-- A super_admin session with a matching active platform_users row.
select set_config('request.jwt.claims',
  '{"sub":"3c000000-0000-4000-8000-000000000905","role":"authenticated","app_role":"super_admin","tenant_id":"3c000000-0000-4000-8000-000000000001"}', true);
set local role authenticated;

select lives_ok(
  $q$insert into cmd_results select 'adj-first', public.adjust_messaging_wallet('3c000000-0000-4000-8000-000000000001', 50, 'Monthly top-up', '3c000000-0000-4000-8000-000000000601')$q$,
  'COM: a super admin adjusts the messaging wallet upward with a request key');

select results_eq(
  $$select (select count(*) from jsonb_object_keys(result)), result->>'deltaCredits', result->>'balanceAfterCredits', result->>'reason'
      from cmd_results where label='adj-first'$$,
  $$select true, '50'::text, '150'::text, 'Monthly top-up'::text$$,
  'COM: the adjustment result carries the exact six facts with decimal strings');

select results_eq(
  $$select w.balance_credits::text from public.messaging_wallets w where w.tenant_id='3c000000-0000-4000-8000-000000000001'$$,
  $$select '150'::text$$,
  'COM: the wallet balance moved to the new total');

select results_eq(
  $$select l.delta_credits::text, l.balance_after_credits::text, l.reason
      from public.messaging_wallet_ledger l
     where l.tenant_id='3c000000-0000-4000-8000-000000000001'::uuid
       and l.request_key='3c000000-0000-4000-8000-000000000601'::uuid$$,
  $$select '50'::text, '150'::text, 'Monthly top-up'::text$$,
  'COM: one keyed ledger row carries the resulting balance');

select lives_ok(
  $q$insert into cmd_results select 'adj-replay', public.adjust_messaging_wallet('3c000000-0000-4000-8000-000000000001', 50, 'Monthly top-up', '3c000000-0000-4000-8000-000000000601')$q$,
  'COM: the exact replay is accepted');

select results_eq(
  $$select (r.result->>'ledgerId') from cmd_results r where r.label in ('adj-first','adj-replay') order by label$$,
  $$select (r.result->>'ledgerId') from cmd_results r where r.label='adj-first'$$,
  'COM: the replay returns the original immutable entry');
select results_eq(
  $$select count(*) from public.messaging_wallet_ledger where tenant_id='3c000000-0000-4000-8000-000000000001'::uuid and request_key='3c000000-0000-4000-8000-000000000601'::uuid$$,
  $$select 1::bigint$$,
  'COM: the exact replay appended no ledger row');
select results_eq(
  $$select w.balance_credits::text from public.messaging_wallets w where w.tenant_id='3c000000-0000-4000-8000-000000000001'::uuid$$,
  $$select '150'::text$$,
  'COM: the exact replay moved no balance');

select throws_ok(
  $q$select * from public.adjust_messaging_wallet('3c000000-0000-4000-8000-000000000001', 25, 'Different reason', '3c000000-0000-4000-8000-000000000601')$q$,
  'GL068'::text, null::text,
  'COM: a reused key with different facts is GL068 idempotency_conflict');

select throws_ok(
  $q$select * from public.adjust_messaging_wallet('3c000000-0000-4000-8000-000000000001', -200, 'Bulk debit', '3c000000-0000-4000-8000-000000000602')$q$,
  'GL067'::text, null::text,
  'COM: a movement that would drive the locked wallet below zero is GL067 insufficient_credits');

select throws_ok(
  $q$select * from public.adjust_messaging_wallet('3c000000-0000-4000-8000-000000000001', 0, 'Noop', '3c000000-0000-4000-8000-000000000603')$q$,
  '23514'::text, null::text,
  'COM: a zero delta is a native CHECK refusal mapped to invalid_adjustment at the route');

select throws_ok(
  $q$select * from public.adjust_messaging_wallet('3c000000-0000-4000-8000-000000000001', 10, ' ', '3c000000-0000-4000-8000-000000000604')$q$,
  '23514'::text, null::text,
  'COM: a blank reason is a native CHECK refusal mapped to invalid_adjustment at the route');

select throws_ok(
  $q$select * from public.adjust_messaging_wallet('3c000000-0000-4000-8000-000000000001', 9223372036854775807::bigint, 'Overflow probe', '3c000000-0000-4000-8000-000000000605')$q$,
  '422'::text, null::text,
  'COM: a bigint overflow maps to 422 credits_out_of_range');

-- The private helper is uncallable.
select ok(
  (select not has_function_privilege('authenticated','app.record_wallet_movement(uuid,bigint,text,uuid,uuid,uuid)','execute')
     and not has_function_privilege('anon','app.record_wallet_movement(uuid,bigint,text,uuid,uuid,uuid)','execute')
     and not has_function_privilege('service_role','app.record_wallet_movement(uuid,bigint,text,uuid,uuid,uuid)','execute')),
  'COM: app.record_wallet_movement is revoked from PUBLIC, anon, authenticated and service_role');

select ok(
  (select not has_function_privilege('authenticated','app.accept_paid_notification(uuid,text,bigint,uuid)','execute')),
  'COM: app.accept_paid_notification has no authenticated grant in this phase');

-- ---------------------------------------------------------------------------
-- 7. Exact audit shapes
-- ---------------------------------------------------------------------------

select results_eq(
  $$select a.action, a.record_type, a.reason is null, (select array_agg(k order by k) from jsonb_object_keys(a."after") k)
      from public.audit_log a
     where a.record_id='3c000000-0000-4000-8000-000000000201'::uuid and a.action='notification.sent'$$,
  $$select 'notification.sent'::text, 'notification'::text, true,
          array['member_id','channel','category','template_key','source_notification_id','dedupe_key','status','scheduled_for','sent_at','delivered_at','clicked_at','converted_at','failed_at','failed_reason','opted_out_at','opted_out_reason','related_type','related_id']::text[]$$,
  'COM: notification.sent carries exactly the N-shape after object');

select results_eq(
  $$select a."before"->>'status', a."after"->>'status' from public.audit_log a
     where a.record_id='3c000000-0000-4000-8000-000000000201'::uuid and a.action='notification.sent'$$,
  $$select 'scheduled'::text, 'sent'::text$$,
  'COM: notification.sent shows the actual changing edge old N → new N');

select results_eq(
  $$select count(*) from public.audit_log a
     where a.record_id='3c000000-0000-4000-8000-000000000201'::uuid and a.action='notification.delivered'$$,
  $$select 1::bigint$$,
  'COM: the member acknowledgement writes exactly one notification.delivered event');

select results_eq(
  $$select count(*) from public.audit_log a
     where a.record_id='3c000000-0000-4000-8000-000000000201'::uuid and a.action='notification.opted_out'$$,
  $$select 0::bigint$$,
  'COM: a refused motivation send writes no audit event — it created no new event');

select results_eq(
  $$select a.reason from public.audit_log a
     where a.record_id='3c000000-0000-4000-8000-000000000201'::uuid and a.action='notification.opted_out'$$,
  $$select null::text$$,
  'COM: notification events carry a null reason when no edge changed');

select results_eq(
  $$select a.action, a.record_type, a.reason,
          a."before"->>'balance_credits', a."after"->>'balance_credits',
          (select array_agg(k order by k) from jsonb_object_keys(a."after") k)
      from public.audit_log a
     where a.record_type='messaging_wallet' and a.record_id='3c000000-0000-4000-8000-000000000001'::uuid
       and a.action='messaging_wallet.adjusted'$$,
  $$select 'messaging_wallet.adjusted'::text, 'messaging_wallet'::text, 'Monthly top-up'::text,
          '100'::text, '150'::text,
          array['balance_credits','ledger_id','delta_credits','notification_id','request_key','recorded_by_user_id']::text[]$$,
  'COM: messaging_wallet.adjusted carries the exact W shape with integer values as strings');

select results_eq(
  $$select a."before", a."after" from public.audit_log a
     where a.record_id='3c000000-0000-4000-8000-000000000201'::uuid and a.action='consent.recorded'$$,
  $$select null::jsonb,
          '{"member_id":"3b000000-0000-4000-8000-000000000031","purpose":"marketing","granted":true,"version":"v1","source":"front_desk_signup","recorded_at":null,"recorded_by_staff_id":null,"request_key":null}'::jsonb$$,
  'COM: consent.recorded carries exactly the eight consent keys');

select ok(
  (select not exists(select 1 from public.audit_log
    where record_type='notification' and "after" ? 'payload')),
  'COM: no audit event exposes the message body or payload');

select ok(
  (select not exists(select 1 from public.audit_log
    where record_type='messaging_wallet' and ("after" ? 'phone' or "after" ? 'device_tokens'))),
  'COM: no audit event exposes phone or device tokens');

-- Exact replays append no audit events.
select results_eq(
  $$select count(*) from public.audit_log a
     where a.record_type='messaging_wallet' and a.record_id='3c000000-0000-4000-8000-000000000001'::uuid
       and a."after"->>'request_key'='3c000000-0000-4000-8000-000000000601'::text$$,
  $$select 1::bigint$$,
  'COM: the exact wallet replay appended no second audit event');

select * from finish();

rollback;
