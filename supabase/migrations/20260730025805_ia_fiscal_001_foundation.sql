begin;

create extension if not exists citext with schema extensions;
create extension if not exists vector with schema extensions;

create schema if not exists private;
comment on schema private is
  'Objetos internos do IA Fiscal. Este schema nao deve ser exposto pela Data API.';

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role;

alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create table public.municipalities (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique
    check (slug = lower(slug) and slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  name text not null,
  state_code text not null check (state_code ~ '^[A-Z]{2}$'),
  ibge_code text unique check (ibge_code is null or ibge_code ~ '^[0-9]{7}$'),
  timezone text not null default 'America/Sao_Paulo',
  status text not null default 'setup'
    check (status in ('setup', 'homologation', 'active', 'suspended', 'archived')),
  data_classification text not null default 'restricted'
    check (data_classification in ('internal', 'restricted', 'highly_restricted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.municipalities is
  'Tenant raiz. Uma prefeitura nunca pode acessar dados de outra.';

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email extensions.citext,
  full_name text,
  phone text,
  locale text not null default 'pt-BR',
  status text not null default 'active'
    check (status in ('invited', 'active', 'blocked', 'disabled')),
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index profiles_email_unique_idx
  on public.profiles (email)
  where email is not null;

create table public.platform_administrators (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_by uuid references auth.users(id) on delete set null,
  reason text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table public.municipality_memberships (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (
    role in (
      'municipal_admin',
      'supervisor',
      'fiscal_auditor',
      'legal_reviewer',
      'support_readonly'
    )
  ),
  status text not null default 'invited'
    check (status in ('invited', 'active', 'suspended', 'revoked')),
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  invited_by uuid references auth.users(id) on delete set null,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint municipality_memberships_validity_ck
    check (valid_until is null or valid_until > valid_from),
  constraint municipality_memberships_municipality_id_id_uq
    unique (municipality_id, id),
  constraint municipality_memberships_municipality_user_uq
    unique (municipality_id, user_id)
);

create index municipality_memberships_user_active_idx
  on public.municipality_memberships (user_id, municipality_id, role)
  where status = 'active';

create table public.municipality_policy_versions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  version integer not null check (version > 0),
  status text not null default 'draft'
    check (status in ('draft', 'approved', 'active', 'retired', 'rejected')),
  minimum_divergence_amount numeric(18,2) not null default 1000
    check (minimum_divergence_amount >= 0),
  lookback_months integer not null default 60
    check (lookback_months between 1 and 240),
  top_debtors_limit integer not null default 30
    check (top_debtors_limit between 1 and 100000),
  daily_initial_notice_limit integer not null default 30
    check (daily_initial_notice_limit between 1 and 100000),
  revalidation_max_age_minutes integer not null default 15
    check (revalidation_max_age_minutes between 1 and 1440),
  auto_case_creation_enabled boolean not null default false,
  auto_initial_notice_enabled boolean not null default false,
  accountant_notice_enabled boolean not null default false,
  ai_drafting_enabled boolean not null default false,
  require_fiscal_review boolean not null default true,
  operational_config jsonb not null default '{}'::jsonb
    check (jsonb_typeof(operational_config) = 'object'),
  effective_from timestamptz,
  effective_until timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint municipality_policy_versions_effective_ck
    check (effective_until is null or effective_from is null or effective_until > effective_from),
  constraint municipality_policy_versions_approval_ck
    check (
      status not in ('approved', 'active')
      or (approved_by is not null and approved_at is not null)
    ),
  constraint municipality_policy_versions_municipality_id_id_uq
    unique (municipality_id, id),
  constraint municipality_policy_versions_number_uq
    unique (municipality_id, version)
);

create unique index municipality_policy_versions_one_active_idx
  on public.municipality_policy_versions (municipality_id)
  where status = 'active';

create table public.integrations (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  integration_type text not null
    check (integration_type in ('source_system', 'email', 'ai_provider', 'webhook')),
  provider_code text not null
    check (provider_code = lower(provider_code) and provider_code ~ '^[a-z0-9_-]+$'),
  display_name text not null,
  status text not null default 'not_configured'
    check (status in ('not_configured', 'configured', 'testing', 'active', 'error', 'disabled')),
  non_secret_config jsonb not null default '{}'::jsonb
    check (jsonb_typeof(non_secret_config) = 'object'),
  secret_reference text,
  last_tested_at timestamptz,
  last_error_code text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint integrations_municipality_id_id_uq
    unique (municipality_id, id),
  constraint integrations_provider_uq
    unique (municipality_id, integration_type, provider_code)
);

create index integrations_municipality_status_idx
  on public.integrations (municipality_id, integration_type, status);

create or replace function private.is_service_role()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role'
      or current_user in ('postgres', 'service_role');
$$;

create or replace function private.is_platform_administrator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
     and exists (
       select 1
       from public.platform_administrators pa
       where pa.user_id = (select auth.uid())
         and pa.active
         and pa.revoked_at is null
     );
$$;

create or replace function private.has_municipality_role(
  p_municipality_id uuid,
  p_roles text[] default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
     and (
       private.is_platform_administrator()
       or exists (
         select 1
         from public.municipality_memberships mm
         where mm.municipality_id = p_municipality_id
           and mm.user_id = (select auth.uid())
           and mm.status = 'active'
           and mm.valid_from <= now()
           and (mm.valid_until is null or mm.valid_until > now())
           and (p_roles is null or mm.role = any(p_roles))
       )
     );
$$;

create or replace function private.handle_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, email, full_name)
  values (
    new.id,
    new.email,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create or replace function private.handle_auth_user_updated()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
     set email = new.email,
         updated_at = clock_timestamp()
   where user_id = new.id;
  return new;
end;
$$;

drop trigger if exists ia_fiscal_auth_user_created on auth.users;
create trigger ia_fiscal_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_auth_user_created();

drop trigger if exists ia_fiscal_auth_user_updated on auth.users;
create trigger ia_fiscal_auth_user_updated
  after update of email on auth.users
  for each row execute function private.handle_auth_user_updated();

create trigger municipalities_set_updated_at
  before update on public.municipalities
  for each row execute function private.set_updated_at();
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();
create trigger municipality_memberships_set_updated_at
  before update on public.municipality_memberships
  for each row execute function private.set_updated_at();
create trigger municipality_policy_versions_set_updated_at
  before update on public.municipality_policy_versions
  for each row execute function private.set_updated_at();
create trigger integrations_set_updated_at
  before update on public.integrations
  for each row execute function private.set_updated_at();

revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.is_platform_administrator() to authenticated, service_role;
grant execute on function private.has_municipality_role(uuid, text[]) to authenticated, service_role;

commit;

