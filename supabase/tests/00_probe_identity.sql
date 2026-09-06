-- TEMPORARY PROBE — removed in the next commit. Deliberately raises 22P02 so
-- the session's identity lands on psql's stderr, which is what db.yml's log
-- shows. See docs/decisions.md ADR-045.
begin;

select cast(
  'PROBE user=' || current_user
  || ' session_user=' || session_user
  || ' search_path=' || current_setting('search_path')
  || ' db=' || current_database()
  || ' port=' || coalesce(inet_server_port()::text, 'null')
  || ' pgtap_in=' || coalesce((select n.nspname from pg_extension e
                               join pg_namespace n on n.oid = e.extnamespace
                              where e.extname = 'pgtap'), 'ABSENT')
  as integer
);

rollback;
