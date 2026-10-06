-- NAVC-004/005/013/014/015 independent holdout.
-- Authored from the approved EARS and frozen public declarations only.
-- No visible suite, application implementation or migration implementation was read.
BEGIN;
SET LOCAL search_path = public, extensions;
SELECT plan(141);
SELECT set_config('request.jwt.claims', '{}', true);
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', '', true);

CREATE TEMP TABLE holdout163_clock AS
SELECT statement_timestamp() AS captured_at;
GRANT SELECT ON holdout163_clock TO authenticated;

SELECT has_function('public', 'read_member_class_visibility', ARRAY[]::text[], 'NAVC public signature: read_member_class_visibility');

SELECT has_function('public', 'set_member_classes_enabled', ARRAY['boolean'], 'NAVC public signature: set_member_classes_enabled');

SELECT has_function('public', 'read_member_upcoming_class_bookings', ARRAY[]::text[], 'NAVC public signature: read_member_upcoming_class_bookings');

SELECT col_type_is('public', 'organization_settings', 'member_classes_enabled', 'boolean', 'NAVC setting is boolean');

SELECT col_not_null('public', 'organization_settings', 'member_classes_enabled', 'NAVC setting is non-null');

SELECT is((SELECT pg_get_expr(d.adbin, d.adrelid)
      FROM pg_attribute a
      JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
      WHERE a.attrelid = 'public.organization_settings'::regclass
        AND a.attname = 'member_classes_enabled'), 'false'::text, 'NAVC-015 new setting defaults Off');

SELECT ok((SELECT count(*) = 3
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname IN ('read_member_class_visibility','set_member_classes_enabled','read_member_upcoming_class_bookings')
        AND p.prosecdef AND pg_get_userbyid(p.proowner) = 'postgres'
        AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c IN ('search_path=', 'search_path=""'))), 'All NAVC boundaries are postgres definers with empty search paths');

SELECT ok((SELECT count(*) = 3
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname IN ('read_member_class_visibility','set_member_classes_enabled','read_member_upcoming_class_bookings')
        AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
        AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
        AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
        AND NOT EXISTS (
          SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')), 'Only authenticated receives ordinary EXECUTE on NAVC functions');

SELECT is((SELECT p.proargnames FROM pg_proc p WHERE p.oid = 'public.read_member_class_visibility()'::regprocedure), ARRAY['enabled']::text[], 'Visibility projection exposes only enabled');

SELECT is((SELECT p.proargnames FROM pg_proc p WHERE p.oid = 'public.set_member_classes_enabled(boolean)'::regprocedure), ARRAY['p_enabled','enabled','changed']::text[], 'Visibility command retains exact public input and result names');

SELECT is((SELECT p.proargnames FROM pg_proc p WHERE p.oid = 'public.read_member_upcoming_class_bookings()'::regprocedure), (SELECT (p.proargnames)[3:array_length(p.proargnames,1)] FROM pg_proc p WHERE p.oid = 'public.read_member_class_schedule(date,date)'::regprocedure), 'Own commitments expose exactly the established safe schedule column names');

SELECT is((SELECT p.proallargtypes FROM pg_proc p WHERE p.oid = 'public.read_member_upcoming_class_bookings()'::regprocedure), (SELECT (p.proallargtypes)[3:array_length(p.proallargtypes,1)] FROM pg_proc p WHERE p.oid = 'public.read_member_class_schedule(date,date)'::regprocedure), 'Own commitments retain the established safe schedule column types');

INSERT INTO auth.users (id, email) VALUES
('e1630000-0000-4000-8000-000000001001', 'navc-holdout-1001@example.invalid'),
('e1630000-0000-4000-8000-000000001002', 'navc-holdout-1002@example.invalid'),
('e1630000-0000-4000-8000-000000001003', 'navc-holdout-1003@example.invalid'),
('e1630000-0000-4000-8000-000000001004', 'navc-holdout-1004@example.invalid'),
('e1630000-0000-4000-8000-000000001005', 'navc-holdout-1005@example.invalid'),
('e1630000-0000-4000-8000-000000001006', 'navc-holdout-1006@example.invalid'),
('e1630000-0000-4000-8000-000000001007', 'navc-holdout-1007@example.invalid'),
('e1630000-0000-4000-8000-000000001008', 'navc-holdout-1008@example.invalid'),
('e1630000-0000-4000-8000-000000001009', 'navc-holdout-1009@example.invalid'),
('e1630000-0000-4000-8000-000000001101', 'navc-holdout-1101@example.invalid'),
('e1630000-0000-4000-8000-000000001102', 'navc-holdout-1102@example.invalid'),
('e1630000-0000-4000-8000-000000001103', 'navc-holdout-1103@example.invalid'),
('e1630000-0000-4000-8000-000000001104', 'navc-holdout-1104@example.invalid'),
('e1630000-0000-4000-8000-000000001105', 'navc-holdout-1105@example.invalid'),
('e1630000-0000-4000-8000-000000001106', 'navc-holdout-1106@example.invalid'),
('e1630000-0000-4000-8000-000000001107', 'navc-holdout-1107@example.invalid'),
('e1630000-0000-4000-8000-000000001108', 'navc-holdout-1108@example.invalid');

INSERT INTO public.organizations (id,name,gym_code,status,timezone) VALUES
('e1630000-0000-4000-8000-000000000001','Holdout discovery A','H163A1','active','Pacific/Kiritimati'),
('e1630000-0000-4000-8000-000000000002','Holdout discovery B','H163B1','active','UTC'),
('e1630000-0000-4000-8000-000000000003','Holdout absent settings','H163C1','active','Asia/Kolkata');

INSERT INTO public.branches (id,tenant_id,name,timezone,is_default) VALUES
('e1630000-0000-4000-8000-000000000101','e1630000-0000-4000-8000-000000000001','Current home','Pacific/Kiritimati',true),
('e1630000-0000-4000-8000-000000000102','e1630000-0000-4000-8000-000000000001','Previous home','Pacific/Pago_Pago',false),
('e1630000-0000-4000-8000-000000000103','e1630000-0000-4000-8000-000000000002','Foreign branch','UTC',true),
('e1630000-0000-4000-8000-000000000104','e1630000-0000-4000-8000-000000000003','Missing settings branch','Asia/Kolkata',true);

INSERT INTO public.organization_settings (tenant_id) VALUES ('e1630000-0000-4000-8000-000000000001'), ('e1630000-0000-4000-8000-000000000002');

INSERT INTO public.staff (id,tenant_id,user_id,full_name,role,is_active) VALUES
('e1630000-0000-4000-8000-000000002001','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000001001','Canonical owner','gym_owner',true),
('e1630000-0000-4000-8000-000000002002','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000001002','Canonical manager','gym_manager',true),
('e1630000-0000-4000-8000-000000002003','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000001003','Canonical desk','front_desk',true),
('e1630000-0000-4000-8000-000000002004','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000001004','Canonical trainer','trainer',true),
('e1630000-0000-4000-8000-000000002005','e1630000-0000-4000-8000-000000000002','e1630000-0000-4000-8000-000000001005','Foreign owner','gym_owner',true),
('e1630000-0000-4000-8000-000000002006','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000001006','Revoked owner','gym_owner',false),
('e1630000-0000-4000-8000-000000002007','e1630000-0000-4000-8000-000000000003','e1630000-0000-4000-8000-000000001007','Owner without settings','gym_owner',true);

INSERT INTO public.platform_users (user_id,full_name,email,role) VALUES
('e1630000-0000-4000-8000-000000001008','Holdout platform admin','navc-holdout-1008@example.invalid','super_admin'),
('e1630000-0000-4000-8000-000000001009','Holdout support','navc-holdout-1009@example.invalid','platform_support');

INSERT INTO public.members
(id,tenant_id,branch_id,user_id,full_name,phone,date_of_birth,status,erased_at) VALUES
('e1630000-0000-4000-8000-000000003001','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000000101','e1630000-0000-4000-8000-000000001101','Own caller','+919163001101',DATE '1990-01-01','active',NULL),
('e1630000-0000-4000-8000-000000003002','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000000101','e1630000-0000-4000-8000-000000001102','Peer not disclosed','+919163001102',DATE '1990-01-01','active',NULL),
('e1630000-0000-4000-8000-000000003003','e1630000-0000-4000-8000-000000000002','e1630000-0000-4000-8000-000000000103','e1630000-0000-4000-8000-000000001103','Other tenant caller','+919163001103',DATE '1990-01-01','active',NULL),
('e1630000-0000-4000-8000-000000003004','e1630000-0000-4000-8000-000000000003','e1630000-0000-4000-8000-000000000104','e1630000-0000-4000-8000-000000001104','Member without settings','+919163001104',DATE '1990-01-01','active',NULL),
('e1630000-0000-4000-8000-000000003005','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000000101','e1630000-0000-4000-8000-000000001105','Blocked caller','+919163001105',DATE '1990-01-01','blocked',NULL),
('e1630000-0000-4000-8000-000000003006','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000000101','e1630000-0000-4000-8000-000000001106','Cancelled caller','+919163001106',DATE '1990-01-01','cancelled',NULL),
('e1630000-0000-4000-8000-000000003007','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000000101','e1630000-0000-4000-8000-000000001107','Erased caller','+919163001107',DATE '1990-01-01','active',statement_timestamp()),
('e1630000-0000-4000-8000-000000003008','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000000101',NULL,'Unlinked caller','+919163001108',DATE '1990-01-01','active',NULL);

INSERT INTO public.services
(id,tenant_id,name,description,default_duration_minutes,default_capacity,is_active) VALUES
('e1630000-0000-4000-8000-000000004001','e1630000-0000-4000-8000-000000000001','Yoga holdout','Active catalogue',60,6,true),
('e1630000-0000-4000-8000-000000004002','e1630000-0000-4000-8000-000000000001','Dance holdout','Frozen catalogue',60,6,false),
('e1630000-0000-4000-8000-000000004003','e1630000-0000-4000-8000-000000000002','Foreign service','Foreign catalogue',60,6,true);

INSERT INTO public.class_rules
(id,tenant_id,service_id,branch_id,weekday,start_time,duration_minutes,capacity,valid_from,is_active) VALUES
('e1630000-0000-4000-8000-000000004501','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004002','e1630000-0000-4000-8000-000000000102',3,TIME '12:00',60,6,
 (SELECT (captured_at AT TIME ZONE 'Pacific/Pago_Pago')::date FROM holdout163_clock),false);

CREATE TEMP TABLE holdout163_sessions AS
SELECT v.code, v.id::uuid AS id, v.tenant_id::uuid AS tenant_id,
       v.service_id::uuid AS service_id, v.branch_id::uuid AS branch_id,
       c.captured_at + v.start_offset AS starts_at,
       c.captured_at + v.end_offset AS ends_at,
       v.status::public.class_session_status AS status
FROM holdout163_clock c CROSS JOIN (VALUES
('branch_lost','e1630000-0000-4000-8000-000000005001','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004002','e1630000-0000-4000-8000-000000000102',INTERVAL '8 hours',INTERVAL '9 hours','scheduled'),
('in_progress','e1630000-0000-4000-8000-000000005002','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004002','e1630000-0000-4000-8000-000000000102',INTERVAL '-30 minutes',INTERVAL '30 minutes','scheduled'),
('yesterday_future','e1630000-0000-4000-8000-000000005003','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004002','e1630000-0000-4000-8000-000000000102',INTERVAL '15 minutes',INTERVAL '75 minutes','scheduled'),
('member_cancel','e1630000-0000-4000-8000-000000005004','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004001','e1630000-0000-4000-8000-000000000101',INTERVAL '12 hours',INTERVAL '13 hours','scheduled'),
('gym_cancel','e1630000-0000-4000-8000-000000005005','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004001','e1630000-0000-4000-8000-000000000101',INTERVAL '16 hours',INTERVAL '17 hours','scheduled'),
('session_cancel','e1630000-0000-4000-8000-000000005006','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004002','e1630000-0000-4000-8000-000000000102',INTERVAL '20 hours',INTERVAL '21 hours','cancelled'),
('attended_live','e1630000-0000-4000-8000-000000005007','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004002','e1630000-0000-4000-8000-000000000102',INTERVAL '-20 minutes',INTERVAL '40 minutes','scheduled'),
('no_show_live','e1630000-0000-4000-8000-000000005008','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004002','e1630000-0000-4000-8000-000000000102',INTERVAL '-15 minutes',INTERVAL '45 minutes','scheduled'),
('ended','e1630000-0000-4000-8000-000000005009','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004002','e1630000-0000-4000-8000-000000000102',INTERVAL '-61 minutes',INTERVAL '-1 minute','scheduled'),
('beyond_horizon','e1630000-0000-4000-8000-000000005010','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004002','e1630000-0000-4000-8000-000000000102',INTERVAL '28 days 2 hours',INTERVAL '28 days 3 hours','scheduled'),
('inside_horizon','e1630000-0000-4000-8000-000000005011','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004002','e1630000-0000-4000-8000-000000000102',INTERVAL '27 days 22 hours',INTERVAL '27 days 23 hours','scheduled'),
('same_start','e1630000-0000-4000-8000-000000005012','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004001','e1630000-0000-4000-8000-000000000101',INTERVAL '8 hours',INTERVAL '9 hours','scheduled'),
('peer_only_home','e1630000-0000-4000-8000-000000005013','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004001','e1630000-0000-4000-8000-000000000101',INTERVAL '10 hours',INTERVAL '11 hours','scheduled'),
('peer_only_other_branch','e1630000-0000-4000-8000-000000005014','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000004001','e1630000-0000-4000-8000-000000000102',INTERVAL '11 hours',INTERVAL '12 hours','scheduled'),
('foreign_booked','e1630000-0000-4000-8000-000000005015','e1630000-0000-4000-8000-000000000002','e1630000-0000-4000-8000-000000004003','e1630000-0000-4000-8000-000000000103',INTERVAL '8 hours',INTERVAL '9 hours','scheduled')
) AS v(code,id,tenant_id,service_id,branch_id,start_offset,end_offset,status);
GRANT SELECT ON holdout163_sessions TO authenticated;

INSERT INTO public.class_sessions
(id,tenant_id,service_id,branch_id,session_date,starts_at,ends_at,capacity,status,
 cancelled_at,cancel_reason,cancelled_by_staff_id)
SELECT f.id,f.tenant_id,f.service_id,f.branch_id,
       (f.starts_at AT TIME ZONE b.timezone)::date,f.starts_at,f.ends_at,6,f.status,
       CASE WHEN f.status = 'cancelled' THEN c.captured_at ELSE NULL END,
       CASE WHEN f.status = 'cancelled' THEN 'Explicit gym cancellation' ELSE NULL END,
       CASE WHEN f.status = 'cancelled' THEN 'e1630000-0000-4000-8000-000000002001'::uuid ELSE NULL END
FROM holdout163_sessions f JOIN public.branches b ON b.id = f.branch_id
CROSS JOIN holdout163_clock c;

INSERT INTO public.class_bookings
(id,tenant_id,session_id,member_id,status,cancelled_at,cancel_reason,marked_at,acted_by_staff_id)
SELECT ('e1630000-0000-4000-8000-' || lpad((6000 + v.num)::text,12,'0'))::uuid,
       'e1630000-0000-4000-8000-000000000001'::uuid,f.id,'e1630000-0000-4000-8000-000000003001'::uuid,v.status::public.booking_status,
       CASE WHEN v.status IN ('cancelled_by_member','cancelled_by_gym','session_cancelled') THEN c.captured_at ELSE NULL END,
       CASE WHEN v.status IN ('cancelled_by_gym','session_cancelled') THEN 'Existing cancellation' ELSE NULL END,
       CASE WHEN v.status IN ('attended','no_show') THEN c.captured_at ELSE NULL END,
       CASE WHEN v.status IN ('cancelled_by_gym','attended','no_show') THEN 'e1630000-0000-4000-8000-000000002002'::uuid ELSE NULL END
FROM (VALUES
(1,'booked'),(2,'booked'),(3,'booked'),(4,'cancelled_by_member'),
(5,'cancelled_by_gym'),(6,'session_cancelled'),(7,'attended'),(8,'no_show'),
(9,'booked'),(10,'booked'),(11,'booked'),(12,'booked')
) v(num,status)
JOIN holdout163_sessions f
  ON f.id = ('e1630000-0000-4000-8000-' || lpad((5000 + v.num)::text,12,'0'))::uuid
CROSS JOIN holdout163_clock c;

INSERT INTO public.class_bookings (id,tenant_id,session_id,member_id,status) VALUES
('e1630000-0000-4000-8000-000000006101','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000005001','e1630000-0000-4000-8000-000000003002','booked'),
('e1630000-0000-4000-8000-000000006113','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000005013','e1630000-0000-4000-8000-000000003002','booked'),
('e1630000-0000-4000-8000-000000006114','e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000005014','e1630000-0000-4000-8000-000000003002','booked'),
('e1630000-0000-4000-8000-000000006115','e1630000-0000-4000-8000-000000000002','e1630000-0000-4000-8000-000000005015','e1630000-0000-4000-8000-000000003003','booked');

CREATE TEMP TABLE holdout163_class_snapshot AS
SELECT 'services'::text AS kind, jsonb_agg(to_jsonb(t) ORDER BY t.id) AS facts
FROM public.services t WHERE t.tenant_id = 'e1630000-0000-4000-8000-000000000001'
UNION ALL
SELECT 'rules',jsonb_agg(to_jsonb(t) ORDER BY t.id)
FROM public.class_rules t WHERE t.tenant_id = 'e1630000-0000-4000-8000-000000000001'
UNION ALL
SELECT 'sessions',jsonb_agg(to_jsonb(t) ORDER BY t.id)
FROM public.class_sessions t WHERE t.tenant_id = 'e1630000-0000-4000-8000-000000000001'
UNION ALL
SELECT 'bookings',jsonb_agg(to_jsonb(t) ORDER BY t.id)
FROM public.class_bookings t WHERE t.tenant_id = 'e1630000-0000-4000-8000-000000000001';
GRANT SELECT ON holdout163_class_snapshot TO authenticated;


SELECT is((SELECT member_classes_enabled FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'), false, 'New gym remains Off even after an active service is added');

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002001"}', true);

SELECT results_eq($actual$SELECT enabled,changed FROM public.set_member_classes_enabled(true)$actual$, $expected$VALUES (true,true)$expected$, 'Canonical owner enables discovery');

SELECT results_eq($actual$SELECT enabled,changed FROM public.set_member_classes_enabled(true)$actual$, $expected$VALUES (true,false)$expected$, 'Exact On retry returns unchanged');

SELECT is((SELECT count(*) FROM public.audit_log WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001' AND action = 'organization.class_visibility_changed'), 1::bigint, 'Only the real On change is audited');

SELECT is((SELECT count(*) FROM public.audit_log
      WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001' AND action = 'organization.class_visibility_changed'
        AND record_type = 'organization_settings' AND record_id = 'e1630000-0000-4000-8000-000000000001'
        AND actor_user_id = 'e1630000-0000-4000-8000-000000001001' AND actor_role = 'gym_owner'
        AND impersonation_session_id IS NULL
        AND before = '{"member_classes_enabled":false}'::jsonb
        AND after = '{"member_classes_enabled":true}'::jsonb), 1::bigint, 'Enable audit carries exact actor and before/after facts');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003001"}', true);

SELECT results_eq($actual$SELECT enabled FROM public.read_member_class_visibility()$actual$, $expected$VALUES (true)$expected$, 'Canonical member reads its own enabled tenant');

SELECT is((SELECT count(*) FROM public.read_member_class_visibility()), 1::bigint, 'Member visibility read is exactly one row');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001103","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000002","member_id":"e1630000-0000-4000-8000-000000003003"}', true);

SELECT results_eq($actual$SELECT enabled FROM public.read_member_class_visibility()$actual$, $expected$VALUES (false)$expected$, 'Different canonical tenant receives its own distinct Off value');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001002","app_role":"gym_manager","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002002"}', true);

SELECT results_eq($actual$SELECT enabled,changed FROM public.set_member_classes_enabled(false)$actual$, $expected$VALUES (false,true)$expected$, 'Canonical manager disables discovery');

SELECT results_eq($actual$SELECT enabled,changed FROM public.set_member_classes_enabled(false)$actual$, $expected$VALUES (false,false)$expected$, 'Exact Off retry returns unchanged');

SELECT is((SELECT count(*) FROM public.audit_log WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001' AND action = 'organization.class_visibility_changed'), 2::bigint, 'Off retry creates no second successful change audit');

SELECT is((SELECT count(*) FROM public.audit_log
      WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001' AND action = 'organization.class_visibility_changed'
        AND record_type = 'organization_settings' AND record_id = 'e1630000-0000-4000-8000-000000000001'
        AND actor_user_id = 'e1630000-0000-4000-8000-000000001002' AND actor_role = 'gym_manager'
        AND before = '{"member_classes_enabled":true}'::jsonb
        AND after = '{"member_classes_enabled":false}'::jsonb), 1::bigint, 'Disable audit attributes manager and only the visibility field');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(NULL)$refusal$, '22023', NULL, 'Canonical owner null setting is invalid');

SELECT throws_ok($refusal$UPDATE public.organization_settings SET member_classes_enabled = true WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'$refusal$, NULL, NULL, 'Direct authenticated owner visibility change is refused');

SELECT throws_ok($refusal$UPDATE public.organization_settings SET member_classes_enabled = true, city = 'Forbidden partial save' WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'$refusal$, NULL, NULL, 'Combined direct write is rejected atomically');

SELECT is((SELECT city FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'), NULL::text, 'Rejected combined write changes no unrelated field');

SELECT lives_ok($allowed$UPDATE public.organization_settings
       SET city = 'Holdout compatibility city', weekly_goal_default = 5,
           class_cancel_window_hours = 4, class_allow_cross_branch = false
       WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'$allowed$, 'Existing direct settings updates remain usable');

SELECT results_eq($actual$SELECT city,weekly_goal_default,class_cancel_window_hours,class_allow_cross_branch,member_classes_enabled
         FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'$actual$, $expected$VALUES ('Holdout compatibility city'::text,5::smallint,4::integer,false,false)$expected$, 'Unrelated settings persist without changing the independent switch');

SELECT lives_ok($allowed$SELECT public.set_checkin_gate_mode('printed_poster')$allowed$, 'Existing validated settings command remains compatible');

SELECT is((SELECT member_classes_enabled FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'), false, 'Other settings command preserves saved Off');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001002","app_role":"gym_manager","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002002"}', true);

SELECT throws_ok($refusal$UPDATE public.organization_settings SET member_classes_enabled = true WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'$refusal$, NULL, NULL, 'Direct authenticated manager visibility change is refused');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001007","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000003","staff_id":"e1630000-0000-4000-8000-000000002007"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '22023', NULL, 'Absent owner settings fail instead of being fabricated');

SELECT throws_ok($refusal$INSERT INTO public.organization_settings (tenant_id,member_classes_enabled) VALUES ('e1630000-0000-4000-8000-000000000003',true)$refusal$, NULL, NULL, 'Direct authenticated insertion cannot set discovery On');

SELECT is((SELECT count(*) FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000003'), 0::bigint, 'Rejected direct insert leaves settings absent');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001003","app_role":"front_desk","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002003"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses front desk before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001004","app_role":"trainer","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002004"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses trainer before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses member before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001008","app_role":"super_admin"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses platform administrator before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001009","app_role":"platform_support"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses platform support before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001006","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002006"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses revoked owner before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001003","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002003"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses role forged from desk row before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001002","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses owner staff id with another Auth subject before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001005","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002005"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses foreign canonical owner row named in tenant A before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000002","staff_id":"e1630000-0000-4000-8000-000000002001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses tenant B claim naming owner A before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002001","impersonation_session_id":"e1630000-0000-4000-8000-000000009001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses impersonated owner before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002001","member_id":"e1630000-0000-4000-8000-000000003001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses contradictory member and staff claims before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses missing subject before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","staff_id":"e1630000-0000-4000-8000-000000002001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses missing tenant before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses missing staff before saving');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002999"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'NAVC-004 refuses unknown staff before saving');

RESET ROLE;

SELECT set_config('request.jwt.claims', '{}', true);

UPDATE public.staff SET is_active = false WHERE id = 'e1630000-0000-4000-8000-000000002001';

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.set_member_classes_enabled(true)$refusal$, '42501', NULL, 'Previously valid owner token loses command authority immediately after canonical deactivation');

RESET ROLE;

SELECT set_config('request.jwt.claims', '{}', true);

UPDATE public.staff SET is_active = true WHERE id = 'e1630000-0000-4000-8000-000000002001';

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001008","app_role":"super_admin"}', true);

SELECT throws_ok($refusal$UPDATE public.organization_settings SET member_classes_enabled = true WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'$refusal$, NULL, NULL, 'Platform direct update cannot bypass the new-field guard');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001009","app_role":"platform_support"}', true);

SELECT is((SELECT count(*) FROM public.organization_settings WHERE tenant_id IN ('e1630000-0000-4000-8000-000000000001','e1630000-0000-4000-8000-000000000002')), 2::bigint, 'Existing platform settings read remains cross-tenant');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001003","app_role":"front_desk","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002003"}', true);

SELECT is((SELECT count(*) FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'), 1::bigint, 'Existing desk settings read remains available');

SELECT is((SELECT count(*) FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000002'), 0::bigint, 'Existing staff settings read remains tenant-isolated');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002001"}', true);

SELECT is((SELECT member_classes_enabled FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'), false, 'All refused actors leave saved Off unchanged');

SELECT is((SELECT count(*) FROM public.audit_log WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001' AND action = 'organization.class_visibility_changed'), 2::bigint, 'Refusals and direct attempts create no successful visibility-change audit');

RESET ROLE;

SELECT set_config('request.jwt.claims', '{}', true);

SELECT is((SELECT member_classes_enabled FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000002'), false, 'Tenant A commands leave tenant B unchanged');

SELECT is((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.services t WHERE t.tenant_id = 'e1630000-0000-4000-8000-000000000001'), (SELECT facts FROM holdout163_class_snapshot WHERE kind = 'services'), 'NAVC-005 discovery changes preserve all services facts');

SELECT is((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.class_rules t WHERE t.tenant_id = 'e1630000-0000-4000-8000-000000000001'), (SELECT facts FROM holdout163_class_snapshot WHERE kind = 'rules'), 'NAVC-005 discovery changes preserve all rules facts');

SELECT is((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.class_sessions t WHERE t.tenant_id = 'e1630000-0000-4000-8000-000000000001'), (SELECT facts FROM holdout163_class_snapshot WHERE kind = 'sessions'), 'NAVC-005 discovery changes preserve all sessions facts');

SELECT is((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.class_bookings t WHERE t.tenant_id = 'e1630000-0000-4000-8000-000000000001'), (SELECT facts FROM holdout163_class_snapshot WHERE kind = 'bookings'), 'NAVC-005 discovery changes preserve all bookings facts');

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003001"}', true);

SELECT results_eq($actual$SELECT enabled FROM public.read_member_class_visibility()$actual$, $expected$VALUES (false)$expected$, 'Member reads saved Off despite retained active catalogue and commitments');

SELECT is((SELECT count(*) FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'), 0::bigint, 'Member read does not introduce settings-table access');

SELECT is((SELECT count(*) FROM public.class_bookings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'), 0::bigint, 'Safe own projection does not expose direct booking rows');

CREATE TEMP TABLE holdout163_actual AS
SELECT row_number() OVER () AS returned_ordinal, r.*
FROM public.read_member_upcoming_class_bookings() r;

SELECT is((SELECT count(*) FROM holdout163_actual), 10::bigint, 'Own reader retains every eligible absolute commitment while discovery is Off');

SELECT results_eq($actual$SELECT session_id FROM holdout163_actual ORDER BY returned_ordinal$actual$, $expected$SELECT id FROM holdout163_sessions
 WHERE code IN ('branch_lost','in_progress','yesterday_future','member_cancel','gym_cancel','session_cancel','attended_live','no_show_live','inside_horizon','same_start')
 ORDER BY starts_at,id$expected$, 'Own reader includes only caller commitments and orders absolute start then session identity');

SELECT ok((SELECT bool_and(my_booking_id IS NOT NULL AND my_booking_status IS NOT NULL) FROM holdout163_actual), 'Every returned commitment has a caller booking identity and status');

SELECT results_eq($actual$SELECT session_id,my_booking_id,my_booking_status FROM holdout163_actual ORDER BY session_id$actual$, $expected$SELECT s.id,('e1630000-0000-4000-8000-' || lpad((6000 + v.num)::text,12,'0'))::uuid,
        v.status::public.booking_status
 FROM (VALUES (1,'booked'),(2,'booked'),(3,'booked'),(4,'cancelled_by_member'),
              (5,'cancelled_by_gym'),(6,'session_cancelled'),(7,'attended'),(8,'no_show'),
              (11,'booked'),(12,'booked')) v(num,status)
 JOIN holdout163_sessions s ON s.id = ('e1630000-0000-4000-8000-' || lpad((5000 + v.num)::text,12,'0'))::uuid
 ORDER BY s.id$expected$, 'Own result never substitutes another member booking identity or status');

SELECT ok(NOT EXISTS (SELECT 1 FROM holdout163_actual WHERE session_id IN ('e1630000-0000-4000-8000-000000005013','e1630000-0000-4000-8000-000000005014','e1630000-0000-4000-8000-000000005015')), 'Peer-only and foreign-tenant sessions do not enter own commitments');

SELECT ok(NOT EXISTS (SELECT 1 FROM holdout163_actual WHERE my_booking_id IN ('e1630000-0000-4000-8000-000000006101','e1630000-0000-4000-8000-000000006113','e1630000-0000-4000-8000-000000006114','e1630000-0000-4000-8000-000000006115')), 'No peer or foreign booking identity crosses the safe projection');

SELECT ok(NOT EXISTS (SELECT 1 FROM holdout163_actual WHERE session_id IN ('e1630000-0000-4000-8000-000000005009','e1630000-0000-4000-8000-000000005010')), 'Ended sessions and starts beyond the absolute 28-day upper horizon are excluded');

SELECT is((SELECT count(*) FROM holdout163_actual WHERE session_id = 'e1630000-0000-4000-8000-000000005011'), 1::bigint, 'An absolute start inside the upper horizon remains included regardless of its local date');

SELECT is((SELECT count(*) FROM holdout163_actual WHERE session_id IN ('e1630000-0000-4000-8000-000000005002','e1630000-0000-4000-8000-000000005007','e1630000-0000-4000-8000-000000005008')), 3::bigint, 'Sessions already started but not ended remain own commitments');

SELECT results_eq($actual$SELECT branch_id,branch_name,timezone,service_id,service_name,service_description
         FROM holdout163_actual WHERE session_id = 'e1630000-0000-4000-8000-000000005001'$actual$, $expected$VALUES ('e1630000-0000-4000-8000-000000000102'::uuid,'Previous home'::text,'Pacific/Pago_Pago'::text,
         'e1630000-0000-4000-8000-000000004002'::uuid,'Dance holdout'::text,'Frozen catalogue'::text)$expected$, 'Lost branch and disabled service retain truthful safe session context');

SELECT ok((SELECT r.session_date = (r.starts_at AT TIME ZONE 'Pacific/Pago_Pago')::date
           AND r.session_date < (c.captured_at AT TIME ZONE 'Pacific/Kiritimati')::date
           AND r.ends_at > c.captured_at
      FROM holdout163_actual r CROSS JOIN holdout163_clock c WHERE r.session_id = 'e1630000-0000-4000-8000-000000005003'), 'Yesterday in the remote branch remains visible when its absolute end is future');

SELECT results_eq($actual$SELECT booked_count,spots_left,capacity,availability
         FROM holdout163_actual WHERE session_id = 'e1630000-0000-4000-8000-000000005001'$actual$, $expected$VALUES (2::integer,4::integer,6::integer,'booked'::text)$expected$, 'Shared session reports aggregate capacity without returning the peer identity');

SELECT ok((SELECT bool_and(availability = 'booked') FROM holdout163_actual
     WHERE my_booking_status IN ('booked','attended','no_show')), 'Holding booking states retain authoritative booked availability');

SELECT results_eq($actual$SELECT my_booking_status,session_status,can_cancel,cancel_by
         FROM holdout163_actual WHERE session_id IN ('e1630000-0000-4000-8000-000000005004','e1630000-0000-4000-8000-000000005005','e1630000-0000-4000-8000-000000005006') ORDER BY session_id$actual$, $expected$VALUES
 ('cancelled_by_member'::public.booking_status,'scheduled'::public.class_session_status,false,NULL::timestamptz),
 ('cancelled_by_gym'::public.booking_status,'scheduled'::public.class_session_status,false,NULL::timestamptz),
 ('session_cancelled'::public.booking_status,'cancelled'::public.class_session_status,false,NULL::timestamptz)$expected$, 'Cancelled commitments retain truthful booking/session states and cancellation facts');

SELECT ok((SELECT bool_and(availability <> 'open') FROM holdout163_actual
           WHERE my_booking_status IN ('cancelled_by_member','cancelled_by_gym','session_cancelled')),
          'Cancelled commitments never advertise an open purchase opportunity');

SELECT ok((SELECT bool_and(cancel_by = starts_at - INTERVAL '4 hours')
     FROM holdout163_actual WHERE my_booking_status = 'booked'), 'Booked commitment deadlines use the current authoritative cancellation setting');

SELECT ok((SELECT bool_and(cancel_by IS NULL AND NOT can_cancel)
     FROM holdout163_actual WHERE my_booking_status <> 'booked'), 'Non-booked states have no fictional cancellation deadline or permission');

SELECT results_eq($actual$SELECT session_id FROM holdout163_actual WHERE can_cancel ORDER BY session_id$actual$, $expected$VALUES ('e1630000-0000-4000-8000-000000005001'::uuid),('e1630000-0000-4000-8000-000000005011'::uuid),('e1630000-0000-4000-8000-000000005012'::uuid)$expected$, 'Cancellation permission remains ordinary clock/status permission across lost branches');

SELECT ok((SELECT NOT can_cancel AND cancel_by < c.captured_at
     FROM holdout163_actual r CROSS JOIN holdout163_clock c WHERE r.session_id = 'e1630000-0000-4000-8000-000000005003'), 'An upcoming commitment inside the cancel window is visible with cancellation refused');

SELECT throws_ok($refusal$SELECT * FROM public.book_class_session('e1630000-0000-4000-8000-000000005014')$refusal$, 'GL094', NULL, 'Own reader and discovery switch do not grant new cross-branch booking eligibility');

SELECT throws_ok($refusal$SELECT * FROM public.book_class_session('e1630000-0000-4000-8000-000000005001')$refusal$, 'GL092', NULL, 'Discovery Off does not bypass inactive-service new-booking refusal');

SELECT results_eq($actual$SELECT booking_id,status FROM public.cancel_class_booking('e1630000-0000-4000-8000-000000006001')$actual$, $expected$VALUES ('e1630000-0000-4000-8000-000000006001'::uuid,'cancelled_by_member'::public.booking_status)$expected$, 'Normal member cancellation still works for a disabled-service commitment in the old branch');

SELECT results_eq($actual$SELECT my_booking_id,my_booking_status,session_status,availability,can_cancel,cancel_by
         FROM public.read_member_upcoming_class_bookings() WHERE session_id = 'e1630000-0000-4000-8000-000000005001'$actual$, $expected$VALUES ('e1630000-0000-4000-8000-000000006001'::uuid,'cancelled_by_member'::public.booking_status,
         'scheduled'::public.class_session_status,'closed'::text,false,NULL::timestamptz)$expected$, 'Cancelled old-branch commitment persists truthfully after ordinary cancellation');

SELECT is((SELECT count(*) FROM public.read_member_upcoming_class_bookings() WHERE session_id = 'e1630000-0000-4000-8000-000000005001'), 1::bigint, 'Cancellation creates no duplicate commitment row');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses owner audience');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses owner audience');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001002","app_role":"gym_manager","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002002"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses manager audience');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses manager audience');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001003","app_role":"front_desk","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002003"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses desk audience');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses desk audience');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001004","app_role":"trainer","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002004"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses trainer audience');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses trainer audience');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001008","app_role":"super_admin"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses platform administrator audience');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses platform administrator audience');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001009","app_role":"platform_support"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses platform support audience');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses platform support audience');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses missing Auth subject');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses missing Auth subject');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","member_id":"e1630000-0000-4000-8000-000000003001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses missing tenant');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses missing tenant');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses missing member');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses missing member');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003001","staff_id":"e1630000-0000-4000-8000-000000002001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses contradictory staff claim');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses contradictory staff claim');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003001","impersonation_session_id":"e1630000-0000-4000-8000-000000009002"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses impersonation claim');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses impersonation claim');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000002","member_id":"e1630000-0000-4000-8000-000000003001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses foreign tenant substituted for caller tenant');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses foreign tenant substituted for caller tenant');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003002"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses peer member substituted in caller tenant');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses peer member substituted in caller tenant');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000002","member_id":"e1630000-0000-4000-8000-000000003003"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses complete foreign identity with caller subject');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses complete foreign identity with caller subject');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001102","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses another subject naming caller member');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses another subject naming caller member');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003999"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses unknown member');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses unknown member');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001105","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003005"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses canonical blocked member');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses canonical blocked member');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001106","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003006"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses canonical cancelled member');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses canonical cancelled member');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001107","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003007"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses canonical erased member');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses canonical erased member');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001108","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003008"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Visibility read refuses stale linked claim after current binding is absent');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Own commitment read refuses stale linked claim after current binding is absent');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001104","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000003","member_id":"e1630000-0000-4000-8000-000000003004"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '22023', NULL, 'Absent settings are an explicit read failure rather than Off');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001103","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000002","member_id":"e1630000-0000-4000-8000-000000003003"}', true);

SELECT results_eq($actual$SELECT session_id,my_booking_id FROM public.read_member_upcoming_class_bookings()$actual$, $expected$VALUES ('e1630000-0000-4000-8000-000000005015'::uuid,'e1630000-0000-4000-8000-000000006115'::uuid)$expected$, 'Canonical tenant B owns only its own upcoming commitment');

RESET ROLE;

SELECT set_config('request.jwt.claims', '{}', true);

UPDATE public.members SET user_id = NULL WHERE id = 'e1630000-0000-4000-8000-000000003001';

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003001"}', true);

SELECT throws_ok($refusal$SELECT * FROM public.read_member_class_visibility()$refusal$, '42501', NULL, 'Former canonical member token is revalidated against current unlink');

SELECT throws_ok($refusal$SELECT * FROM public.read_member_upcoming_class_bookings()$refusal$, '42501', NULL, 'Former member token cannot retain booked-row access after unlink');

RESET ROLE;

SELECT set_config('request.jwt.claims', '{}', true);

UPDATE public.members SET user_id = 'e1630000-0000-4000-8000-000000001101' WHERE id = 'e1630000-0000-4000-8000-000000003001';

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001001","app_role":"gym_owner","tenant_id":"e1630000-0000-4000-8000-000000000001","staff_id":"e1630000-0000-4000-8000-000000002001"}', true);

SELECT lives_ok($allowed$SELECT public.set_service_active('e1630000-0000-4000-8000-000000004002',true)$allowed$, 'Existing service activation command remains compatible');

SELECT is((SELECT member_classes_enabled FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'), false, 'Later catalogue activation cannot rerun compatibility defaults over saved Off');

SELECT lives_ok($allowed$SELECT public.set_service_active('e1630000-0000-4000-8000-000000004002',false)$allowed$, 'Existing service disable command remains compatible');

SELECT is((SELECT member_classes_enabled FROM public.organization_settings WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001'), false, 'Later catalogue disable preserves the independent saved Off choice');

SELECT is((SELECT count(*) FROM public.audit_log WHERE tenant_id = 'e1630000-0000-4000-8000-000000000001' AND action = 'organization.class_visibility_changed'), 2::bigint, 'Compatibility commands and reads never add successful visibility-change audits');

SELECT set_config('request.jwt.claims', '{"role":"authenticated","aud":"authenticated","sub":"e1630000-0000-4000-8000-000000001101","app_role":"member","tenant_id":"e1630000-0000-4000-8000-000000000001","member_id":"e1630000-0000-4000-8000-000000003001"}', true);

SELECT results_eq($actual$SELECT enabled FROM public.read_member_class_visibility()$actual$, $expected$VALUES (false)$expected$, 'Final caller-bound visibility remains the owner choice');

RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);
SELECT * FROM finish();
ROLLBACK;
