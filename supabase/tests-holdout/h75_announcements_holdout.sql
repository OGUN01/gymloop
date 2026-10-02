-- Independent ANC holdout, frozen contract only. No implementation or visible suites read.
begin;
set local role postgres;
set local search_path to public, extensions;
select plan(88);
create function pg_temp.u(n integer) returns uuid language sql immutable as $$
select ('75900000-0000-4000-8000-'||lpad(to_hex(n),12,'0'))::uuid $$;
create function pg_temp.claims(n integer default 1) returns text language sql as $$
select jsonb_build_object('sub',pg_temp.u(200+n),'role','authenticated','tenant_id',pg_temp.u(case when n=5 then 2 else 1 end),'staff_id',pg_temp.u(200+n),'app_role',case n when 1 then 'gym_owner' when 2 then 'gym_manager' when 3 then 'front_desk' when 4 then 'trainer' when 5 then 'gym_owner' else 'gym_owner' end)::text $$;
create function pg_temp.run(q text,c text default pg_temp.claims(),r text default 'authenticated') returns jsonb language plpgsql as $$
declare v jsonb;d text;begin
perform set_config('request.jwt.claims',coalesce(c,''),true);execute format('set local role %I',r);
begin execute q into v;exception when others then get stacked diagnostics d=pg_exception_detail;v:=jsonb_build_object('error',sqlstate,'detail',d);end;
set local role postgres;perform set_config('request.jwt.claims','',true);return coalesce(v,'null'::jsonb);end $$;
insert into public.organizations(id,name,gym_code,status,timezone,currency)values
(pg_temp.u(1),'ANC owner A','H75ANA','active','Asia/Kolkata','INR'),(pg_temp.u(2),'ANC owner B','H75ANB','active','Asia/Kolkata','INR');
insert into public.organization_settings(tenant_id)values(pg_temp.u(1)),(pg_temp.u(2));
insert into public.branches(id,tenant_id,name,is_default)values(pg_temp.u(11),pg_temp.u(1),'A',true),(pg_temp.u(12),pg_temp.u(2),'B',true);
insert into auth.users(id)select pg_temp.u(n)from generate_series(201,209)n;
insert into public.staff(id,user_id,tenant_id,branch_id,role,full_name,is_active)values
(pg_temp.u(201),pg_temp.u(201),pg_temp.u(1),pg_temp.u(11),'gym_owner','Owner A',true),
(pg_temp.u(202),pg_temp.u(202),pg_temp.u(1),pg_temp.u(11),'gym_manager','Manager',true),
(pg_temp.u(203),pg_temp.u(203),pg_temp.u(1),pg_temp.u(11),'front_desk','Desk',true),
(pg_temp.u(204),pg_temp.u(204),pg_temp.u(1),pg_temp.u(11),'trainer','Trainer',true),
(pg_temp.u(205),pg_temp.u(205),pg_temp.u(2),pg_temp.u(12),'gym_owner','Owner B',true),
(pg_temp.u(206),pg_temp.u(206),pg_temp.u(1),pg_temp.u(11),'gym_owner','Inactive',false);
insert into public.platform_users(user_id,role,full_name,email,is_active)values
(pg_temp.u(207),'super_admin','Super','super@h70.test',true),(pg_temp.u(208),'platform_support','Support','support@h70.test',true);
insert into public.members(id,user_id,tenant_id,branch_id,full_name,phone)values(pg_temp.u(100),pg_temp.u(209),pg_temp.u(1),pg_temp.u(11),'Member','+919709000100');

-- Scope: promotional audience/receipts/media exposure and read-state privacy only.
insert into auth.users(id)select pg_temp.u(n)from generate_series(210,214)n;
insert into public.members(id,user_id,tenant_id,branch_id,full_name,phone,status)values
(pg_temp.u(101),pg_temp.u(210),pg_temp.u(1),pg_temp.u(11),'ANC withdrawn secret','+919759000101','paused'),
(pg_temp.u(102),pg_temp.u(211),pg_temp.u(1),pg_temp.u(11),'ANC never asked secret','+919759000102','expired'),
(pg_temp.u(103),pg_temp.u(212),pg_temp.u(1),pg_temp.u(11),'ANC granted secret','+919759000103','active'),
(pg_temp.u(104),pg_temp.u(213),pg_temp.u(2),pg_temp.u(12),'ANC foreign secret','+919759000104','active'),
(pg_temp.u(105),pg_temp.u(214),pg_temp.u(1),pg_temp.u(11),'ANC blocked secret','+919759000105','blocked');
create function pg_temp.mc(n integer default 0)returns text language sql as $$
select jsonb_build_object('sub',pg_temp.u(209+n),'role','authenticated','app_role','member','tenant_id',pg_temp.u(case when n=4 then 2 else 1 end),'member_id',pg_temp.u(100+n))::text $$;
create temp table h75_results(k text primary key,v jsonb);
create function pg_temp.aid(k text)returns uuid language sql stable as $$select(v#>>'{}')::uuid from h75_results where h75_results.k=aid.k $$;
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source,recorded_at)values
(pg_temp.u(401),pg_temp.u(1),pg_temp.u(100),'marketing',false,'v1','held',now()-interval '2 days'),
(pg_temp.u(402),pg_temp.u(1),pg_temp.u(100),'marketing',true,'v1','held',now()-interval '1 day'),
(pg_temp.u(403),pg_temp.u(1),pg_temp.u(101),'marketing',true,'v1','held',now()-interval '1 day'),
(pg_temp.u(404),pg_temp.u(1),pg_temp.u(101),'marketing',false,'v1','held',now()-interval '1 hour'),
(pg_temp.u(405),pg_temp.u(1),pg_temp.u(102),'service',true,'v1','held',now()-interval '1 day'),
(pg_temp.u(406),pg_temp.u(1),pg_temp.u(103),'marketing',true,'v1','held',now()-interval '1 day');
insert into h75_results values
('notice',pg_temp.run($q$select to_jsonb(public.create_announcement_draft('transactional','Service notice','Notice body','all_members',null,null,null,null))$q$)),
('promo',pg_temp.run($q$select to_jsonb(public.create_announcement_draft('promotional','Promotion','Offer body','all_members',null,null,null,null))$q$)),
('foreign',pg_temp.run($q$select to_jsonb(public.create_announcement_draft('transactional','Other gym','Other body','all_members',null,null,null,null))$q$,pg_temp.claims(5)));
select is(pg_temp.run('select to_jsonb(g)from public.publish_announcement(pg_temp.aid(''notice''))g')->>'audience_count','4','ANC-005 notice reaches four good-standing members without service consent');
select is(pg_temp.run('select to_jsonb(g)from public.publish_announcement(pg_temp.aid(''promo''))g')->>'audience_count','2','ANC-005 promotion reaches only latest marketing granted');
insert into h75_results values('foreign-publish',pg_temp.run('select to_jsonb(g)from public.publish_announcement(pg_temp.aid(''foreign''))g',pg_temp.claims(5)));
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()',pg_temp.mc()),'2'::jsonb,'ANC-005 granted sees notice and promotion');
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()',pg_temp.mc(1)),'1'::jsonb,'ANC-005 latest withdrawal sees notice only');
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()',pg_temp.mc(2)),'1'::jsonb,'ANC-005 service consent does not substitute marketing');
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()',pg_temp.mc(4)),'1'::jsonb,'ANC-016 foreign member sees only foreign gym notice');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''promo''),1))',pg_temp.mc(1)),'false'::jsonb,'ANC-011 not-targeted marker cannot create receipt');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''foreign''),1))',pg_temp.mc()),'false'::jsonb,'ANC-011 foreign marker same false');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.u(999),1))',pg_temp.mc()),'false'::jsonb,'ANC-011 unknown marker same false');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''promo''),99))',pg_temp.mc()),'false'::jsonb,'ANC-011 absent version same false');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''promo''),1))',pg_temp.mc()),'true'::jsonb,'ANC-011 caller own receipt');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''promo''),1))',pg_temp.mc()),'true'::jsonb,'ANC-011 receipt replay true');
select is((select count(*)from public.announcement_receipts where member_id=pg_temp.u(100)),1::bigint,'ANC-011 receipt idempotence one row');
select is(pg_temp.run('select to_jsonb(read_state)from public.read_member_announcements()where announcement_id=pg_temp.aid(''promo'')',pg_temp.mc()),'"read"'::jsonb,'ANC-012 own read state');
select is(pg_temp.run('select to_jsonb(read_state)from public.read_member_announcements()where announcement_id=pg_temp.aid(''promo'')',pg_temp.mc(3)),'"unread"'::jsonb,'ANC-012 another member never inherits receipt');
select is(pg_temp.run('select to_jsonb(count(*))from public.announcement_receipts',pg_temp.mc()),'1'::jsonb,'ANC-013 own receipts readable');
select is(pg_temp.run('select to_jsonb(count(*))from public.announcement_receipts',pg_temp.mc(3)),'0'::jsonb,'ANC-013 other member receipts invisible');
select is(pg_temp.run('select public.read_announcement(pg_temp.aid(''promo''))')->'announcement'->>'readCurrent','1','ANC-013 aggregate current count');
select is(pg_temp.run('select to_jsonb(g)from public.edit_announcement(pg_temp.aid(''promo''),1,''Promotion edited'',''New offer body'',null,null,''Terms clarified'')g')->>'version_no','2','ANC-012 edit creates current version');
select is(pg_temp.run('select to_jsonb(read_state)from public.read_member_announcements()where announcement_id=pg_temp.aid(''promo'')',pg_temp.mc()),'"updated"'::jsonb,'ANC-012 earlier reader updated after edit');
select is(pg_temp.run('select to_jsonb(read_state)from public.read_member_announcements()where announcement_id=pg_temp.aid(''promo'')',pg_temp.mc(3)),'"unread"'::jsonb,'ANC-012 never reader stays unread after edit');
select is(pg_temp.run('select to_jsonb(change_note)from public.read_member_announcements()where announcement_id=pg_temp.aid(''promo'')',pg_temp.mc(3)),'"Terms clarified"'::jsonb,'ANC-012 all current recipients see edit note');
select is(pg_temp.run('select public.read_announcement(pg_temp.aid(''promo''))')->'announcement'->>'readCurrent','0','ANC-013 current count resets to new version');
select is(pg_temp.run('select public.read_announcement(pg_temp.aid(''promo''))')->'announcement'->>'readAny','1','ANC-013 distinct any-version count retained');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''promo''),2))',pg_temp.mc()),'true'::jsonb,'ANC-011 mark edited version');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''promo''),1))',pg_temp.mc()),'true'::jsonb,'ANC-011 older version remains markable while visible');
select is(pg_temp.run('select public.read_announcement(pg_temp.aid(''promo''))')->'announcement'->>'readAny','1','ANC-013 two versions count one distinct member');
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source,recorded_at)
values(pg_temp.u(407),pg_temp.u(1),pg_temp.u(100),'marketing',false,'v1','withdrawn',clock_timestamp());
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()',pg_temp.mc()),'1'::jsonb,'ANC-005 withdrawal immediately removes promotion');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''promo''),2))',pg_temp.mc()),'false'::jsonb,'ANC-005 previously recorded receipt does not authorize withdrawn marker');
select is(pg_temp.run('select public.read_announcement(pg_temp.aid(''promo''))')->'announcement'->>'audienceCount','1','ANC-013 live count uses current consent');
select is(pg_temp.run('select public.read_announcement(pg_temp.aid(''promo''))')->'announcement'->>'readAny','0','ANC-013 withdrawn receipts excluded from live counts');
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source,recorded_at)
values(pg_temp.u(408),pg_temp.u(1),pg_temp.u(100),'marketing',true,'v1','re-granted',clock_timestamp());
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()',pg_temp.mc()),'2'::jsonb,'ANC-005 regrant restores live promotion');
select is(pg_temp.run('select to_jsonb(read_state)from public.read_member_announcements()where announcement_id=pg_temp.aid(''promo'')',pg_temp.mc()),'"read"'::jsonb,'ANC-012 read history survives withdrawal/regrant');
select is(pg_temp.run('select public.read_announcement(pg_temp.aid(''promo''))')->'announcement'->>'readAny','1','ANC-013 regrant restores aggregate count');
select is(pg_temp.run('select to_jsonb(count(*))from public.announcement_receipts',pg_temp.claims(1)),'0'::jsonb,'ANC-013 owner direct receipts invisible');
select is(pg_temp.run('select to_jsonb(count(*))from public.announcement_receipts',pg_temp.claims(2)),'0'::jsonb,'ANC-013 manager direct receipts invisible');
select is(pg_temp.run('select to_jsonb(count(*))from public.announcement_receipts',pg_temp.claims(3)),'0'::jsonb,'ANC-013 desk direct receipts invisible');
select is(pg_temp.run('select to_jsonb(count(*))from public.announcement_receipts',pg_temp.claims(4)),'0'::jsonb,'ANC-013 trainer direct receipts invisible');
select is(pg_temp.run('select to_jsonb(count(*))from public.announcement_receipts',pg_temp.claims(5)),'0'::jsonb,'ANC-013 foreign owner direct receipts invisible');
select is(pg_temp.run('select to_jsonb(count(*))from public.announcement_receipts',jsonb_build_object('sub',pg_temp.u(207),'role','authenticated','app_role','super_admin')::text),'0'::jsonb,'ANC-013 super_admin direct receipts invisible');
select is(pg_temp.run('select to_jsonb(count(*))from public.announcement_receipts',jsonb_build_object('sub',pg_temp.u(208),'role','authenticated','app_role','platform_support')::text),'0'::jsonb,'ANC-013 platform_support direct receipts invisible');
select is(pg_temp.run('select to_jsonb(count(*))from public.announcement_receipts',(pg_temp.claims()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(900)))::text),'0'::jsonb,'ANC-013 preview cannot read receipts');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()$q$,(pg_temp.mc()::jsonb||jsonb_build_object('sub',pg_temp.u(210)))::text)->>'error','42501','ANC member actor wrong user rejects feed');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('promo'),1))$q$,(pg_temp.mc()::jsonb||jsonb_build_object('sub',pg_temp.u(210)))::text)->>'error','42501','ANC member actor wrong user rejects marker');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()$q$,(pg_temp.mc()::jsonb||jsonb_build_object('staff_id',pg_temp.u(201)))::text)->>'error','42501','ANC member actor staff contamination rejects feed');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('promo'),1))$q$,(pg_temp.mc()::jsonb||jsonb_build_object('staff_id',pg_temp.u(201)))::text)->>'error','42501','ANC member actor staff contamination rejects marker');
select is(pg_temp.run($q$select to_jsonb(count(*))from public.read_member_announcements()$q$,(pg_temp.mc()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(900)))::text)->>'error','42501','ANC member actor preview rejects feed');
select is(pg_temp.run($q$select to_jsonb(public.mark_announcement_read(pg_temp.aid('promo'),1))$q$,(pg_temp.mc()::jsonb||jsonb_build_object('impersonation_session_id',pg_temp.u(900)))::text)->>'error','42501','ANC member actor preview rejects marker');

select ok(pg_temp.run('select public.read_announcement(pg_temp.aid(''promo''))')::text!~'ANC withdrawn secret|ANC never asked secret|ANC granted secret|member_id|memberId|read_at|readAt','ANC-013 staff detail exposes no individual reader facts');
select ok(pg_temp.run('select to_jsonb(g)from public.list_announcements()g')::text!~'ANC withdrawn secret|ANC never asked secret|ANC granted secret|member_id|memberId|read_at|readAt','ANC-013 staff list exposes no individual reader facts');
select ok(not exists(select 1 from public.audit_log where tenant_id=pg_temp.u(1)and action like 'announcement.%'and(coalesce(before::text,'')||coalesce(after::text,''))~'member_id|memberId|read_at|readAt'),'ANC-013 audit does not reveal read identities');
select ok(not has_table_privilege('authenticated','public.announcement_receipts','INSERT')and not has_table_privilege('authenticated','public.announcement_receipts','UPDATE')and not has_table_privilege('authenticated','public.announcement_receipts','DELETE'),'ANC-013 no direct receipt forgery or change');
select ok((select array_agg(polname::text order by polname)=array['announcement_receipts_member_select']::text[]from pg_policy where polrelid='public.announcement_receipts'::regclass),'ANC-013 receipts have only own-member policy, no platform loophole');
select is(pg_temp.run('select to_jsonb(public.unpublish_announcement(pg_temp.aid(''promo'')))')->>'error',null::text,'ANC-013 end live audience projection');
select is(pg_temp.run('select public.read_announcement(pg_temp.aid(''promo''))')->'announcement'->>'audienceCount',null::text,'ANC-013 taken-down audience absent');
select is(pg_temp.run('select public.read_announcement(pg_temp.aid(''promo''))')->'announcement'->>'readAny','1','ANC-013 ended counts retain historical distinct receipts');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''promo''),2))',pg_temp.mc()),'false'::jsonb,'ANC-011 taken-down receipt marker invisible');

-- Trusted-verifier fixture exercises DB exposure only; it claims no R2 byte verification.
insert into h75_results values('asset',pg_temp.run(format($q$select to_jsonb(public.register_media_asset('announcement',%L,'image/png',64))$q$,pg_temp.u(1)::text||'/staging/announcement/'||pg_temp.u(750)::text||'.png')));
select is(pg_temp.run(format($q$select to_jsonb(public.finalize_media_asset(%L,%L,%L,'gym_owner',%L,'announcement','image/png',64,%L,'source-held-etag',%L,'published-held-etag'))$q$,
pg_temp.aid('asset'),pg_temp.u(201),pg_temp.u(201),pg_temp.u(1),pg_temp.u(1)::text||'/staging/announcement/'||pg_temp.u(750)::text||'.png',pg_temp.u(1)::text||'/published/announcement/'||pg_temp.u(751)::text||'.png'),'{"role":"service_role"}','service_role'),'true'::jsonb,'ANC media fixture finalized through credential-only verifier boundary');
insert into h75_results values('image-promo',pg_temp.run(format($q$select to_jsonb(public.create_announcement_draft('promotional','Image promotion','Visible image body','all_members',null,null,null,%L))$q$,pg_temp.aid('asset'))));
select is(pg_temp.run('select to_jsonb(g)from public.publish_announcement(pg_temp.aid(''image-promo''))g')->>'audience_count','2','ANC-005 current consent applies to image announcement');
select is(pg_temp.run('select to_jsonb(image_asset_id)from public.read_member_announcements()where announcement_id=pg_temp.aid(''image-promo'')',pg_temp.mc()),to_jsonb(pg_temp.aid('asset')),'ANC-005/017 current authorized image id exposed');
select ok(pg_temp.run('select to_jsonb(g)from public.read_member_announcements()g where announcement_id=pg_temp.aid(''image-promo'')',pg_temp.mc())::text!~'object_key|imageKey|image_key|staging|published/|mime|etag|ETag','ANC approved media public RPC has only opaque id, no private projection');
select is(pg_temp.run('select to_jsonb(image_asset_id)from public.read_member_announcements()where announcement_id=pg_temp.aid(''image-promo'')',pg_temp.mc(1)),'null'::jsonb,'ANC-005 withdrawn cannot recover image id by direct feed');
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source,recorded_at)values
(pg_temp.u(409),pg_temp.u(1),pg_temp.u(100),'marketing',false,'v1','image withdrawal',clock_timestamp());
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid(''image-promo'')',pg_temp.mc()),'0'::jsonb,'ANC-005 withdrawal removes current card and image exposure');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''image-promo''),1))',pg_temp.mc()),'false'::jsonb,'ANC-005 withdrawal removes image read-marker reach');
select is(pg_temp.run('select public.read_announcement(pg_temp.aid(''image-promo''))')->'announcement'->>'audienceCount','1','ANC-005 image count follows withdrawal');
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source,recorded_at)values
(pg_temp.u(410),pg_temp.u(1),pg_temp.u(100),'marketing',true,'v1','image regrant',clock_timestamp());
select is(pg_temp.run('select to_jsonb(image_asset_id)from public.read_member_announcements()where announcement_id=pg_temp.aid(''image-promo'')',pg_temp.mc()),to_jsonb(pg_temp.aid('asset')),'ANC-005 regrant restores current image exposure');
select is(pg_temp.run('select to_jsonb(g)from public.edit_announcement(pg_temp.aid(''image-promo''),1,''Image removed'',''Now text only'',null,null,''Removed photo'')g')->>'version_no','2','ANC-017 image removal is versioned');
select is(pg_temp.run('select to_jsonb(image_asset_id)from public.read_member_announcements()where announcement_id=pg_temp.aid(''image-promo'')',pg_temp.mc()),'null'::jsonb,'ANC-017 old historic image never revives current exposure');
select is((select image_asset_id from public.announcement_versions where announcement_id=pg_temp.aid('image-promo')and version_no=1),pg_temp.aid('asset'),'ANC-017 immutable historical FK survives replacement');
select ok((select attached_to_id is null and deleted_at is not null from public.media_assets where id=pg_temp.aid('asset')),'ANC-017 released old image tombstone retained');
select is(pg_temp.run(format($q$delete from public.media_assets where id=%L returning to_jsonb(id)$q$,pg_temp.aid('asset')),'','postgres')->>'error','GL086','ANC amended retention forbids deleting referenced media metadata');
select is((select image_asset_id from public.announcement_versions where announcement_id=pg_temp.aid('image-promo')and version_no=1),pg_temp.aid('asset'),'ANC metadata pruning cannot rewrite historic image reference');
-- Equal timestamps deliberately prove the consent id-desc tie-break independently of clock order.
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source,recorded_at)values
(pg_temp.u(420),pg_temp.u(1),pg_temp.u(101),'marketing',true,'v1','equal timestamp granted',now()+interval '1 minute'),
(pg_temp.u(421),pg_temp.u(1),pg_temp.u(101),'marketing',false,'v1','equal timestamp withdrawn',now()+interval '1 minute');
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid(''image-promo'')',pg_temp.mc(1)),'0'::jsonb,'ANC-005 latest consent ordered by id descending on equal timestamp');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''image-promo''),2))',pg_temp.mc(1)),'false'::jsonb,'ANC-005 equal-timestamp withdrawal gate matches marker');


-- Targeting paths must share the promotion rule, including status/membership segments.
insert into public.plans(id,tenant_id,name,duration_days,price_paise,currency)values(pg_temp.u(800),pg_temp.u(1),'ANC target fixture',120,10000,'INR');
-- ADR-098 unrelated membership period guards bypassed only for these controlled fixtures.
set local session_replication_role=replica;
insert into public.memberships(id,tenant_id,member_id,plan_id,status,starts_on,ends_on,price_paise,discount_paise,currency,periods_granted,duration_days)values
(pg_temp.u(801),pg_temp.u(1),pg_temp.u(100),pg_temp.u(800),'active',current_date-60,current_date+60,10000,0,'INR',1,120),
(pg_temp.u(802),pg_temp.u(1),pg_temp.u(103),pg_temp.u(800),'frozen',current_date-60,current_date+60,10000,0,'INR',1,120);
set local session_replication_role=origin;
insert into public.consents(id,tenant_id,member_id,purpose,granted,version,source,recorded_at)values
(pg_temp.u(422),pg_temp.u(1),pg_temp.u(101),'marketing',true,'v1','segment regrant',clock_timestamp()+interval '2 minutes');
insert into h75_results values
('live-segment',pg_temp.run($q$select to_jsonb(public.create_announcement_draft('promotional','Live members','Segment live','segment',array['active']::public.member_status[],'live',null,null))$q$)),
('notlive-segment',pg_temp.run($q$select to_jsonb(public.create_announcement_draft('promotional','No live membership','Segment not live','segment',array['paused','expired']::public.member_status[],'not_live',null,null))$q$));
select is(pg_temp.run('select to_jsonb(g)from public.publish_announcement(pg_temp.aid(''live-segment''))g')->>'audience_count','2','ANC-006 active/frozen live membership targeted through current consent');
select is(pg_temp.run('select to_jsonb(g)from public.publish_announcement(pg_temp.aid(''notlive-segment''))g')->>'audience_count','1','ANC-006 not-live status segment still requires latest marketing grant');
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid(''live-segment'')',pg_temp.mc(3)),'1'::jsonb,'ANC-006 frozen membership is live for announcement segment');
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid(''notlive-segment'')',pg_temp.mc(1)),'1'::jsonb,'ANC-006 no live membership sees matching paused segment');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''live-segment''),1))',pg_temp.mc(1)),'false'::jsonb,'ANC-006 not-targeted segment marker false');
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid(''notlive-segment'')',pg_temp.mc(2)),'0'::jsonb,'ANC-006 matching status with missing marketing consent still excluded');
select is(pg_temp.run('select to_jsonb(public.unpublish_announcement(pg_temp.aid(''image-promo'')))')->>'error',null::text,'ANC-005/017 take-down invalidates remaining card exposure');
select is(pg_temp.run('select to_jsonb(count(*))from public.read_member_announcements()where announcement_id=pg_temp.aid(''image-promo'')',pg_temp.mc()),'0'::jsonb,'ANC-005/017 taken-down current feed grants no image exposure');
select is(pg_temp.run('select to_jsonb(public.mark_announcement_read(pg_temp.aid(''image-promo''),2))',pg_temp.mc()),'false'::jsonb,'ANC-005/017 taken-down marker same false');


select ok(not exists(select 1 from generate_series(100,105)n where position(pg_temp.u(n)::text in pg_temp.run('select public.read_announcement(pg_temp.aid(''promo''))')::text)>0),'ANC-013 no raw member UUID in aggregate staff detail');
select ok(not exists(select 1 from generate_series(100,105)n where position(pg_temp.u(n)::text in pg_temp.run('select coalesce(jsonb_agg(to_jsonb(g)),''[]''::jsonb)from public.list_announcements()g')::text)>0),'ANC-013 no raw member UUID in aggregate staff list');
select is(pg_temp.run('select public.read_announcement(pg_temp.aid(''foreign''))')->>'error','42501','ANC-013 foreign staff aggregate read cannot enumerate receipts');
select is(pg_temp.run('select public.read_announcement(pg_temp.u(999))')->>'error','42501','ANC-013 unknown staff aggregate same refusal');
select is(pg_temp.run('select to_jsonb(count(*))from public.announcement_receipts',pg_temp.mc(4)),'0'::jsonb,'ANC-013 foreign member receives no other-gym receipt');

select * from finish();
rollback;
