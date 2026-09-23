BEGIN;

SELECT plan(30);

-- HARD-004 / ATT-005 / ATT-006: one invoker command, with no caller-supplied identity.
SELECT ok(
  to_regprocedure('public.record_staff_front_desk_check_in(uuid,text,uuid)') IS NOT NULL,
  'the assisted front-desk command has the frozen three-argument signature'
);

SELECT is(
  (SELECT count(*)::integer FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.proname = 'record_staff_front_desk_check_in'),
  1,
  'no overload can accept a caller-supplied tenant, branch, or actor'
);

SELECT is(
  (SELECT pg_get_function_identity_arguments(p.oid) FROM pg_proc p
   WHERE p.oid = to_regprocedure('public.record_staff_front_desk_check_in(uuid,text,uuid)')),
  'p_member_id uuid, p_reason text, p_client_event_id uuid',
  'the only inputs are member, reason, and client event'
);

SELECT ok(
  (SELECT NOT p.prosecdef AND p.provolatile = 'v' FROM pg_proc p
   WHERE p.oid = to_regprocedure('public.record_staff_front_desk_check_in(uuid,text,uuid)')),
  'the command is volatile and SECURITY INVOKER'
);

SELECT ok(
  has_function_privilege('authenticated',
    to_regprocedure('public.record_staff_front_desk_check_in(uuid,text,uuid)'), 'EXECUTE'),
  'authenticated may invoke the command'
);

SELECT ok(
  NOT has_function_privilege('anon',
    to_regprocedure('public.record_staff_front_desk_check_in(uuid,text,uuid)'), 'EXECUTE'),
  'anonymous callers cannot invoke the command'
);

SELECT is(
  (SELECT array_agg(a.arg_name ORDER BY a.ordinality)
   FROM pg_proc p
   CROSS JOIN LATERAL unnest(p.proargnames, p.proargmodes)
     WITH ORDINALITY AS a(arg_name, arg_mode, ordinality)
   WHERE p.oid = to_regprocedure('public.record_staff_front_desk_check_in(uuid,text,uuid)')
     AND a.arg_mode IN ('o', 't', 'b')),
  ARRAY['id', 'checked_in_at', 'source', 'member_name']::text[],
  'the database response exposes only the four approved fields'
);

-- The foreign fixture and every visit below vanish at ROLLBACK.
CREATE TEMP TABLE holdout_assisted_foreign (
  tenant_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  member_id uuid NOT NULL
);

INSERT INTO holdout_assisted_foreign
VALUES (gen_random_uuid(), gen_random_uuid(), gen_random_uuid());

INSERT INTO public.organizations (id, name, gym_code, status)
SELECT tenant_id, 'Holdout Other Gym', upper(substr(md5(tenant_id::text), 1, 6)), 'active'
FROM holdout_assisted_foreign;

INSERT INTO public.branches (id, tenant_id, name, is_default)
SELECT branch_id, tenant_id, 'Foreign Desk', true
FROM holdout_assisted_foreign;

INSERT INTO public.members (id, tenant_id, branch_id, full_name, phone, status)
SELECT member_id, tenant_id, branch_id, 'Foreign Holdout Member', '+919999998877', 'active'
FROM holdout_assisted_foreign;

CREATE TEMP TABLE holdout_assisted_context AS
WITH desk AS (
  SELECT s.id AS staff_id, s.user_id, s.tenant_id, s.branch_id
  FROM public.staff s
  JOIN public.organizations o ON o.id = s.tenant_id
  WHERE o.gym_code = 'IRNBX1' AND s.role = 'front_desk'
    AND s.is_active AND s.user_id IS NOT NULL
  LIMIT 1
), trainer AS (
  SELECT s.id AS trainer_id, s.user_id AS trainer_user_id, s.tenant_id
  FROM public.staff s
  WHERE s.role = 'trainer' AND s.is_active AND s.user_id IS NOT NULL
    AND s.tenant_id = (SELECT tenant_id FROM desk)
  LIMIT 1
), eligible AS (
  SELECT m.id, m.full_name, m.branch_id,
    row_number() OVER (ORDER BY m.id) AS ordinal
  FROM public.members m
  JOIN public.memberships ms ON ms.member_id = m.id AND ms.tenant_id = m.tenant_id
  JOIN public.organizations o ON o.id = m.tenant_id
  JOIN desk s ON s.tenant_id = m.tenant_id
  WHERE m.status = 'active' AND m.erased_at IS NULL
    AND ms.status = 'active'
    AND ms.starts_on <= (transaction_timestamp() AT TIME ZONE o.timezone)::date
    AND ms.ends_on >= (transaction_timestamp() AT TIME ZONE o.timezone)::date
    AND (s.branch_id IS NULL OR s.branch_id = m.branch_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.attendance a
      WHERE a.tenant_id = m.tenant_id AND a.member_id = m.id
        AND a.checked_in_at > transaction_timestamp() - interval '10 minutes'
    )
)
SELECT d.staff_id, d.user_id, d.tenant_id,
  t.trainer_id, t.trainer_user_id,
  (SELECT id FROM eligible WHERE ordinal = 1) AS member_id,
  (SELECT full_name FROM eligible WHERE ordinal = 1) AS member_name,
  (SELECT branch_id FROM eligible WHERE ordinal = 1) AS member_branch_id,
  (SELECT id FROM eligible WHERE ordinal = 2) AS other_member_id,
  f.tenant_id AS foreign_tenant_id, f.member_id AS foreign_member_id,
  gen_random_uuid() AS first_event_id,
  gen_random_uuid() AS duplicate_event_id,
  gen_random_uuid() AS no_reason_event_id,
  gen_random_uuid() AS whitespace_event_id,
  gen_random_uuid() AS trainer_event_id,
  gen_random_uuid() AS no_actor_event_id,
  gen_random_uuid() AS forged_identity_event_id,
  gen_random_uuid() AS foreign_event_id,
  gen_random_uuid() AS missing_event_id
FROM desk d CROSS JOIN trainer t CROSS JOIN holdout_assisted_foreign f;

SELECT ok(
  EXISTS (SELECT 1 FROM holdout_assisted_context
          WHERE member_id IS NOT NULL AND other_member_id IS NOT NULL),
  'two eligible demo members and real front-desk/trainer identities are available'
);

CREATE TEMP TABLE holdout_assisted_outcomes (
  case_name text PRIMARY KEY,
  payload jsonb,
  error_code text
);

GRANT SELECT ON holdout_assisted_context TO authenticated;
GRANT SELECT, INSERT ON holdout_assisted_outcomes TO authenticated;

CREATE FUNCTION pg_temp.holdout_assisted_identity(
  p_tenant uuid, p_role text, p_staff uuid, p_user uuid
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_strip_nulls(jsonb_build_object(
    'sub', p_user::text, 'role', 'authenticated', 'tenant_id', p_tenant::text,
    'app_role', p_role, 'staff_id', p_staff::text))::text, true);
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.tenant_id', coalesce(p_tenant::text, ''), true);
  PERFORM set_config('request.jwt.claim.app_role', p_role, true);
  PERFORM set_config('request.jwt.claim.staff_id', coalesce(p_staff::text, ''), true);
END;
$$;

CREATE FUNCTION pg_temp.holdout_try_assisted(
  p_case text, p_member uuid, p_reason text, p_event uuid
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO pg_temp.holdout_assisted_outcomes (case_name, payload)
  SELECT p_case, to_jsonb(result)
  FROM public.record_staff_front_desk_check_in(p_member, p_reason, p_event) AS result;
  IF NOT FOUND THEN
    INSERT INTO pg_temp.holdout_assisted_outcomes (case_name) VALUES (p_case);
  END IF;
EXCEPTION WHEN OTHERS THEN
  INSERT INTO pg_temp.holdout_assisted_outcomes (case_name, error_code)
  VALUES (p_case, SQLSTATE);
END;
$$;

GRANT EXECUTE ON FUNCTION pg_temp.holdout_assisted_identity(uuid,text,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.holdout_try_assisted(text,uuid,text,uuid) TO authenticated;

SET LOCAL ROLE authenticated;

DO $$
DECLARE
  f record;
BEGIN
  SELECT * INTO f FROM pg_temp.holdout_assisted_context;
  IF NOT FOUND THEN RETURN; END IF;

  PERFORM pg_temp.holdout_assisted_identity(f.tenant_id, 'front_desk', f.staff_id, f.user_id);
  PERFORM pg_temp.holdout_try_assisted('new', f.member_id, 'Staff assisted at desk', f.first_event_id);
  PERFORM pg_temp.holdout_try_assisted('foreign', f.foreign_member_id, 'Staff assisted at desk', f.foreign_event_id);
  PERFORM pg_temp.holdout_try_assisted('missing', gen_random_uuid(), 'Staff assisted at desk', f.missing_event_id);
  PERFORM pg_temp.holdout_try_assisted('no_reason', f.other_member_id, '', f.no_reason_event_id);
  PERFORM pg_temp.holdout_try_assisted('whitespace', f.other_member_id, E' \t\n ', f.whitespace_event_id);
  PERFORM pg_temp.holdout_try_assisted('duplicate_window', f.member_id, 'Second arrival', f.duplicate_event_id);
  PERFORM pg_temp.holdout_try_assisted('same_event', f.member_id, 'Staff assisted at desk', f.first_event_id);
  PERFORM pg_temp.holdout_try_assisted('reused_event', f.other_member_id, 'Staff assisted at desk', f.first_event_id);

  PERFORM pg_temp.holdout_assisted_identity(f.tenant_id, 'trainer', f.trainer_id, f.trainer_user_id);
  PERFORM pg_temp.holdout_try_assisted('trainer', f.other_member_id, 'Staff assisted at desk', f.trainer_event_id);

  PERFORM pg_temp.holdout_assisted_identity(f.tenant_id, 'front_desk', NULL, f.user_id);
  PERFORM pg_temp.holdout_try_assisted('no_actor', f.other_member_id, 'Staff assisted at desk', f.no_actor_event_id);

  PERFORM pg_temp.holdout_assisted_identity(f.foreign_tenant_id, 'front_desk', f.staff_id, f.user_id);
  PERFORM pg_temp.holdout_try_assisted('forged_tenant', f.foreign_member_id,
    'Staff assisted at desk', f.forged_identity_event_id);
END;
$$;

RESET ROLE;

SELECT is(
  (SELECT count(*)::integer FROM holdout_assisted_outcomes WHERE case_name = 'new'), 1,
  'a new assisted check-in returns exactly one row'
);

SELECT ok(
  (SELECT payload IS NOT NULL AND error_code IS NULL
   FROM holdout_assisted_outcomes WHERE case_name = 'new'),
  'the eligible staff command succeeds'
);

SELECT is(
  (SELECT array_agg(k.key ORDER BY k.key)
   FROM holdout_assisted_outcomes o
   CROSS JOIN LATERAL jsonb_object_keys(o.payload) AS k(key)
   WHERE o.case_name = 'new'),
  ARRAY['checked_in_at', 'id', 'member_name', 'source']::text[],
  'the successful database row contains the exact response projection'
);

SELECT ok(
  (SELECT o.payload->>'source' = 'front_desk'
      AND o.payload->>'member_name' = f.member_name
   FROM holdout_assisted_outcomes o CROSS JOIN holdout_assisted_context f
   WHERE o.case_name = 'new'),
  'source and member name are returned from the visible member'
);

SELECT is(
  (SELECT count(*)::integer FROM public.attendance a
   JOIN holdout_assisted_context f ON a.client_event_id = f.first_event_id),
  1,
  'one accepted event produces one attendance row'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.attendance a JOIN holdout_assisted_context f
      ON a.client_event_id = f.first_event_id
    WHERE a.tenant_id = f.tenant_id AND a.member_id = f.member_id
      AND a.branch_id = f.member_branch_id AND a.assisted_by_staff_id = f.staff_id
      AND a.assist_reason = 'Staff assisted at desk' AND a.source = 'front_desk'
  ),
  'tenant, branch, and actor are derived and the mandatory reason is saved'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.attendance a
    JOIN holdout_assisted_context f ON a.client_event_id = f.first_event_id
    JOIN holdout_assisted_outcomes o ON o.case_name = 'new'
    WHERE o.payload->>'id' = a.id::text
      AND (o.payload->>'checked_in_at')::timestamptz = a.checked_in_at
  ),
  'the returned id and timestamp identify the persisted visit'
);

SELECT ok(
  (SELECT payload IS NULL AND error_code IS NULL
   FROM holdout_assisted_outcomes WHERE case_name = 'foreign'),
  'a member hidden by RLS yields zero command rows for the existing 404 mapping'
);

SELECT is(
  (SELECT count(*)::integer FROM public.attendance a
   JOIN holdout_assisted_context f ON a.client_event_id = f.foreign_event_id),
  0,
  'a foreign member never receives attendance'
);

SELECT ok(
  (SELECT payload IS NULL AND error_code IS NULL
   FROM holdout_assisted_outcomes WHERE case_name = 'missing'),
  'an unknown member has the same invisible-member result'
);

SELECT ok(
  (SELECT payload IS NULL AND error_code IS NOT NULL
   FROM holdout_assisted_outcomes WHERE case_name = 'no_reason'),
  'an empty assisted reason is refused'
);

SELECT ok(
  (SELECT payload IS NULL AND error_code IS NOT NULL
   FROM holdout_assisted_outcomes WHERE case_name = 'whitespace'),
  'spaces, tabs, and newlines are not a reason'
);

SELECT ok(
  (SELECT payload IS NULL AND error_code IS NOT NULL
   FROM holdout_assisted_outcomes WHERE case_name = 'trainer'),
  'a real trainer cannot use the staff assisted command'
);

SELECT ok(
  (SELECT payload IS NULL AND error_code IS NOT NULL
   FROM holdout_assisted_outcomes WHERE case_name = 'no_actor'),
  'a front-desk claim without an acting staff identity is refused'
);

SELECT ok(
  (SELECT payload IS NULL FROM holdout_assisted_outcomes
   WHERE case_name = 'forged_tenant'),
  'a real staff identity cannot be replayed with a foreign tenant claim'
);

SELECT is(
  (SELECT count(*)::integer FROM public.attendance a
   JOIN holdout_assisted_context f ON a.client_event_id IN (
     f.no_reason_event_id, f.whitespace_event_id, f.trainer_event_id,
     f.no_actor_event_id, f.forged_identity_event_id, f.missing_event_id
   )),
  0,
  'all invalid identity, role, reason, and unknown-member calls leave no visit'
);

SELECT ok(
  (SELECT payload IS NULL AND error_code IS NOT NULL
   FROM holdout_assisted_outcomes WHERE case_name = 'duplicate_window'),
  'a new event inside the same-member duplicate window is refused'
);

SELECT is(
  (SELECT count(*)::integer FROM public.attendance a
   JOIN holdout_assisted_context f ON a.client_event_id = f.duplicate_event_id),
  0,
  'duplicate-window refusal preserves the original event only'
);

SELECT is(
  (SELECT count(*)::integer FROM public.attendance a
   JOIN holdout_assisted_context f ON a.client_event_id = f.first_event_id),
  1,
  'replaying the exact event cannot create a second visit'
);

SELECT ok(
  (SELECT payload IS NULL FROM holdout_assisted_outcomes
   WHERE case_name = 'reused_event'),
  'another member cannot receive the first member''s event as a response'
);

SELECT is(
  (SELECT count(*)::integer FROM public.attendance a
   JOIN holdout_assisted_context f ON a.member_id = f.other_member_id
     AND a.client_event_id = f.first_event_id),
  0,
  'reusing one client event for another member writes no visit'
);

SELECT ok(
  (SELECT payload IS NULL OR payload->>'id' = (
    SELECT original.payload->>'id' FROM holdout_assisted_outcomes original
    WHERE original.case_name = 'new')
   FROM holdout_assisted_outcomes WHERE case_name = 'same_event'),
  'an exact same-member retry cannot return a different visit'
);

SELECT * FROM finish();
ROLLBACK;
