-- Fingerprint determinístico do catálogo de aplicação.
-- Execute depois de um replay em banco descartável e compare com
-- catalog-fingerprint.json. O timestamp de captura não participa dos hashes.
with
columns_src as (
  select format('%I.%I|%s|%I|%s|%s|%s|%s|%s',
    n.nspname, c.relname, a.attnum, a.attname,
    pg_catalog.format_type(a.atttypid, a.atttypmod),
    a.attnotnull, coalesce(pg_get_expr(ad.adbin, ad.adrelid), ''),
    a.attidentity, a.attgenerated) item
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
  where n.nspname in ('public', 'private', 'audit')
    and c.relkind in ('r', 'p', 'v', 'm')
    and a.attnum > 0
    and not a.attisdropped
),
constraints_src as (
  select format('%I.%I|%I|%s', n.nspname, c.relname, con.conname,
    pg_get_constraintdef(con.oid, true)) item
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private', 'audit')
),
indexes_src as (
  select format('%I.%I|%I|%s', n.nspname, c.relname, ic.relname,
    pg_get_indexdef(i.indexrelid)) item
  from pg_index i
  join pg_class c on c.oid = i.indrelid
  join pg_class ic on ic.oid = i.indexrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private', 'audit')
),
policies_src as (
  select concat_ws('|', schemaname, tablename, policyname, permissive,
    roles::text, cmd, coalesce(qual, ''), coalesce(with_check, '')) item
  from pg_policies
  where schemaname in ('public', 'private', 'audit')
),
functions_src as (
  select format('%I.%I(%s)|%s', n.nspname, p.proname,
    pg_get_function_identity_arguments(p.oid), pg_get_functiondef(p.oid)) item
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private', 'audit')
),
triggers_src as (
  select format('%I.%I|%I|%s', n.nspname, c.relname, t.tgname,
    pg_get_triggerdef(t.oid, true)) item
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private', 'audit')
    and not t.tgisinternal
),
grants_src as (
  select concat_ws('|', 'table', table_schema, table_name, grantee,
    privilege_type, is_grantable) item
  from information_schema.table_privileges
  where table_schema in ('public', 'private', 'audit')
  union all
  select concat_ws('|', 'routine', routine_schema, routine_name, grantee,
    privilege_type, is_grantable) item
  from information_schema.routine_privileges
  where routine_schema in ('public', 'private', 'audit')
),
fingerprints as (
  select 'columns' section, count(*)::int entries,
    md5(coalesce(string_agg(item, E'\n' order by item), '')) hash from columns_src
  union all select 'constraints', count(*)::int,
    md5(coalesce(string_agg(item, E'\n' order by item), '')) from constraints_src
  union all select 'indexes', count(*)::int,
    md5(coalesce(string_agg(item, E'\n' order by item), '')) from indexes_src
  union all select 'policies', count(*)::int,
    md5(coalesce(string_agg(item, E'\n' order by item), '')) from policies_src
  union all select 'functions', count(*)::int,
    md5(coalesce(string_agg(item, E'\n' order by item), '')) from functions_src
  union all select 'triggers', count(*)::int,
    md5(coalesce(string_agg(item, E'\n' order by item), '')) from triggers_src
  union all select 'grants', count(*)::int,
    md5(coalesce(string_agg(item, E'\n' order by item), '')) from grants_src
)
select jsonb_object_agg(
  section,
  jsonb_build_object('entries', entries, 'md5', hash)
  order by section
) as fingerprints
from fingerprints;
