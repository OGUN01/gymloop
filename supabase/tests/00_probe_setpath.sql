-- TEMPORARY PROBE — removed in the next commit. Answers one question: is an
-- explicit `set local search_path` enough to reach pgTAP from this session?
begin;

set local search_path to extensions, public;

select plan(1);
select ok(true, 'PROBE: an explicit set local search_path reaches pgTAP');
select * from finish();

rollback;
