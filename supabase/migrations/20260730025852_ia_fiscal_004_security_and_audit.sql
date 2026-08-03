begin;

create schema if not exists audit;
comment on schema audit is
  'Trilha append-only e tamper-evident do IA Fiscal. Nao expor pela Data API.';
revoke all on schema audit from public, anon, authenticated;
grant usage on schema audit to service_role;

create table audit.audit_events (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete restrict,
  actor_user_id uuid,
  actor_role text,
  session_id text,
  action text not null,
  entity_schema text not null,
  entity_table text not null,
  entity_id text,
  correlation_id uuid not null,
  request_id text,
  ip_sha256 text,
  user_agent_sha256 text,
  old_row_sha256 text,
  new_row_sha256 text,
  event_data jsonb not null default '{}'::jsonb
    check (jsonb_typeof(event_data) = 'object'),
  previous_event_sha256 text,
  event_sha256 text not null check (event_sha256 ~ '^[a-f0-9]{64}$'),
  occurred_at timestamptz not null,
  constraint audit_events_chain_uq unique (municipality_id, event_sha256)
);

create index audit_events_entity_idx
  on audit.audit_events (municipality_id, entity_table, entity_id, occurred_at, id);
create index audit_events_actor_idx
  on audit.audit_events (municipality_id, actor_user_id, occurred_at desc, id);

create table audit.audit_anchors (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete restrict,
  last_event_id bigint not null references audit.audit_events(id) on delete restrict,
  last_event_sha256 text not null check (last_event_sha256 ~ '^[a-f0-9]{64}$'),
  external_destination text,
  external_reference text,
  anchored_at timestamptz not null default now(),
  constraint audit_anchors_event_uq unique (municipality_id, last_event_id)
);

create table private.idempotency_keys (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  scope text not null,
  idempotency_key text not null,
  actor_user_id uuid,
  request_sha256 text not null check (request_sha256 ~ '^[a-f0-9]{64}$'),
  result_reference jsonb check (result_reference is null or jsonb_typeof(result_reference) = 'object'),
  status text not null default 'processing'
    check (status in ('processing', 'completed', 'failed')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz,
  constraint idempotency_keys_scope_uq
    unique (municipality_id, scope, idempotency_key)
);

create index idempotency_keys_expiry_idx
  on private.idempotency_keys (expires_at, id)
  where expires_at is not null;

create table private.jobs (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  job_type text not null
    check (job_type in (
      'process_case_batch_item',
      'send_initial_notice',
      'generate_ai_draft',
      'send_approved_response',
      'embed_legal_chunk'
    )),
  aggregate_type text not null,
  aggregate_id uuid not null,
  payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(payload) = 'object'),
  status text not null default 'pending'
    check (status in (
      'pending',
      'processing',
      'completed',
      'retry',
      'dead_letter',
      'blocked_configuration',
      'cancelled'
    )),
  priority integer not null default 100 check (priority between 1 and 1000),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  lease_expires_at timestamptz,
  last_error_code text,
  last_error_detail text,
  idempotency_key text not null,
  correlation_id uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint jobs_idempotency_uq unique (municipality_id, idempotency_key)
);

create index jobs_claim_idx
  on private.jobs (status, available_at, priority, id)
  where status in ('pending', 'retry');
create index jobs_lease_idx
  on private.jobs (lease_expires_at, id)
  where status = 'processing';
create index jobs_aggregate_idx
  on private.jobs (municipality_id, aggregate_type, aggregate_id, created_at desc);

create table private.monthly_usage_counters (
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  category text not null check (category in ('email', 'ai_generation')),
  period_start date not null check (period_start = date_trunc('month', period_start)::date),
  quantity bigint not null default 0 check (quantity >= 0),
  estimated_cost numeric(18,8) not null default 0 check (estimated_cost >= 0),
  updated_at timestamptz not null default now(),
  primary key (municipality_id, category, period_start)
);

create table private.rate_limit_counters (
  id bigint generated always as identity primary key,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  actor_user_id uuid,
  action text not null,
  window_started_at timestamptz not null,
  quantity integer not null default 1 check (quantity > 0),
  constraint rate_limit_counters_uq
    unique (municipality_id, actor_user_id, action, window_started_at)
);

create index rate_limit_counters_lookup_idx
  on private.rate_limit_counters (
    municipality_id, actor_user_id, action, window_started_at desc
  );

create or replace function private.is_aal2()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.is_service_role()
      or coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
$$;

create or replace function private.can_access_municipality(p_municipality_id uuid)
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
       )
       or exists (
         select 1
         from public.taxpayer_user_links tul
         where tul.municipality_id = p_municipality_id
           and tul.user_id = (select auth.uid())
           and tul.status = 'active'
           and tul.valid_from <= now()
           and (tul.valid_until is null or tul.valid_until > now())
       )
       or exists (
         select 1
         from public.accountant_user_links aul
         where aul.municipality_id = p_municipality_id
           and aul.user_id = (select auth.uid())
           and aul.status = 'active'
           and aul.valid_from <= now()
           and (aul.valid_until is null or aul.valid_until > now())
       )
     );
$$;

create or replace function private.can_manage_municipality(p_municipality_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_municipality_role(
    p_municipality_id,
    array['municipal_admin']::text[]
  );
$$;

create or replace function private.can_access_accounting_firm(
  p_municipality_id uuid,
  p_accounting_firm_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_municipality_role(
           p_municipality_id,
           array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
         )
      or exists (
        select 1
        from public.accountant_user_links aul
        where aul.municipality_id = p_municipality_id
          and aul.accounting_firm_id = p_accounting_firm_id
          and aul.user_id = (select auth.uid())
          and aul.status = 'active'
          and aul.valid_from <= now()
          and (aul.valid_until is null or aul.valid_until > now())
      );
$$;

create or replace function private.can_access_taxpayer(
  p_municipality_id uuid,
  p_taxpayer_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_municipality_role(
           p_municipality_id,
           array['supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
         )
      or exists (
        select 1
        from public.taxpayer_user_links tul
        where tul.municipality_id = p_municipality_id
          and tul.taxpayer_id = p_taxpayer_id
          and tul.user_id = (select auth.uid())
          and tul.status = 'active'
          and tul.valid_from <= now()
          and (tul.valid_until is null or tul.valid_until > now())
      )
      or exists (
        select 1
        from public.taxpayer_accountant_links tal
        join public.accountant_user_links aul
          on aul.municipality_id = tal.municipality_id
         and aul.accounting_firm_id = tal.accounting_firm_id
        where tal.municipality_id = p_municipality_id
          and tal.taxpayer_id = p_taxpayer_id
          and tal.status = 'active'
          and tal.can_access_portal
          and tal.valid_from <= now()
          and (tal.valid_until is null or tal.valid_until > now())
          and aul.user_id = (select auth.uid())
          and aul.status = 'active'
          and aul.valid_from <= now()
          and (aul.valid_until is null or aul.valid_until > now())
      );
$$;

create or replace function private.can_access_case(
  p_municipality_id uuid,
  p_case_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.fiscal_cases fc
    where fc.municipality_id = p_municipality_id
      and fc.id = p_case_id
      and (
        private.has_municipality_role(
          p_municipality_id,
          array['supervisor', 'legal_reviewer']::text[]
        )
        or (
          private.has_municipality_role(
            p_municipality_id,
            array['fiscal_auditor']::text[]
          )
          and exists (
            select 1
            from public.case_assignments ca
            join public.municipality_memberships mm
              on mm.municipality_id = ca.municipality_id
             and mm.id = ca.membership_id
            where ca.municipality_id = fc.municipality_id
              and ca.case_id = fc.id
              and ca.status = 'active'
              and mm.user_id = (select auth.uid())
              and mm.status = 'active'
          )
        )
        or exists (
          select 1
          from public.taxpayer_user_links tul
          where tul.municipality_id = fc.municipality_id
            and tul.taxpayer_id = fc.taxpayer_id
            and tul.user_id = (select auth.uid())
            and tul.status = 'active'
            and tul.valid_from <= now()
            and (tul.valid_until is null or tul.valid_until > now())
        )
        or exists (
          select 1
          from public.taxpayer_accountant_links tal
          join public.accountant_user_links aul
            on aul.municipality_id = tal.municipality_id
           and aul.accounting_firm_id = tal.accounting_firm_id
          where tal.municipality_id = fc.municipality_id
            and tal.taxpayer_id = fc.taxpayer_id
            and tal.status = 'active'
            and tal.can_access_portal
            and tal.valid_from <= now()
            and (tal.valid_until is null or tal.valid_until > now())
            and aul.user_id = (select auth.uid())
            and aul.status = 'active'
            and aul.valid_from <= now()
            and (aul.valid_until is null or aul.valid_until > now())
        )
      )
  );
$$;

create or replace function private.can_review_case(
  p_municipality_id uuid,
  p_case_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_municipality_role(
           p_municipality_id,
           array['supervisor', 'legal_reviewer']::text[]
         )
      or (
        private.has_municipality_role(
          p_municipality_id,
          array['fiscal_auditor']::text[]
        )
        and exists (
          select 1
          from public.case_assignments ca
          join public.municipality_memberships mm
            on mm.municipality_id = ca.municipality_id
           and mm.id = ca.membership_id
          where ca.municipality_id = p_municipality_id
            and ca.case_id = p_case_id
            and ca.status = 'active'
            and ca.assignment_role in ('responsible_fiscal', 'reviewer')
            and mm.user_id = (select auth.uid())
            and mm.status = 'active'
        )
      );
$$;

create or replace function private.can_access_divergence(
  p_municipality_id uuid,
  p_divergence_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_municipality_role(
           p_municipality_id,
           array['supervisor']::text[]
         )
      or exists (
        select 1
        from public.fiscal_cases fc
        where fc.municipality_id = p_municipality_id
          and fc.divergence_id = p_divergence_id
          and private.can_access_case(fc.municipality_id, fc.id)
      );
$$;

create or replace function private.sanitize_audit_json(p_row jsonb)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(p_row, '{}'::jsonb)
    - array[
        'tax_id',
        'value',
        'normalized_value',
        'email_snapshot',
        'body',
        'body_text',
        'body_html',
        'body_text_snapshot',
        'body_html_snapshot',
        'content_text',
        'source_snapshot',
        'raw_data',
        'normalized_data',
        'finding_snapshot',
        'non_secret_config',
        'operational_config',
        'event_data'
      ]::text[];
$$;

create or replace function private.append_audit_event(
  p_municipality_id uuid,
  p_action text,
  p_entity_schema text,
  p_entity_table text,
  p_entity_id text,
  p_correlation_id uuid,
  p_old_row jsonb,
  p_new_row jsonb,
  p_event_data jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
  v_occurred_at timestamptz := clock_timestamp();
  v_previous_hash text;
  v_event_hash text;
  v_old_hash text;
  v_new_hash text;
  v_headers jsonb := coalesce(
    nullif(current_setting('request.headers', true), '')::jsonb,
    '{}'::jsonb
  );
  v_jwt jsonb := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );
begin
  if p_municipality_id is null then
    raise exception 'municipality_id is required for audit event';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_municipality_id::text, 4865)
  );

  select ae.event_sha256
    into v_previous_hash
    from audit.audit_events ae
   where ae.municipality_id = p_municipality_id
   order by ae.id desc
   limit 1;

  v_old_hash := case
    when p_old_row is null then null
    else pg_catalog.encode(extensions.digest(p_old_row::text, 'sha256'), 'hex')
  end;
  v_new_hash := case
    when p_new_row is null then null
    else pg_catalog.encode(extensions.digest(p_new_row::text, 'sha256'), 'hex')
  end;

  v_event_hash := pg_catalog.encode(
    extensions.digest(
      concat_ws(
        '|',
        coalesce(v_previous_hash, ''),
        p_municipality_id::text,
        p_action,
        p_entity_schema,
        p_entity_table,
        coalesce(p_entity_id, ''),
        p_correlation_id::text,
        coalesce(v_old_hash, ''),
        coalesce(v_new_hash, ''),
        v_occurred_at::text
      ),
      'sha256'
    ),
    'hex'
  );

  insert into audit.audit_events (
    municipality_id,
    actor_user_id,
    actor_role,
    session_id,
    action,
    entity_schema,
    entity_table,
    entity_id,
    correlation_id,
    request_id,
    ip_sha256,
    user_agent_sha256,
    old_row_sha256,
    new_row_sha256,
    event_data,
    previous_event_sha256,
    event_sha256,
    occurred_at
  )
  values (
    p_municipality_id,
    auth.uid(),
    coalesce(v_jwt ->> 'role', auth.jwt() ->> 'role'),
    coalesce(v_jwt ->> 'session_id', auth.jwt() ->> 'session_id'),
    p_action,
    p_entity_schema,
    p_entity_table,
    p_entity_id,
    p_correlation_id,
    v_headers ->> 'x-request-id',
    case
      when coalesce(v_headers ->> 'x-forwarded-for', '') = '' then null
      else pg_catalog.encode(
        extensions.digest(split_part(v_headers ->> 'x-forwarded-for', ',', 1), 'sha256'),
        'hex'
      )
    end,
    case
      when coalesce(v_headers ->> 'user-agent', '') = '' then null
      else pg_catalog.encode(
        extensions.digest(v_headers ->> 'user-agent', 'sha256'),
        'hex'
      )
    end,
    v_old_hash,
    v_new_hash,
    private.sanitize_audit_json(p_event_data),
    v_previous_hash,
    v_event_hash,
    v_occurred_at
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_row jsonb;
  v_municipality_id uuid;
  v_entity_id text;
  v_correlation_id uuid;
begin
  if tg_op = 'INSERT' then
    v_new := to_jsonb(new);
    v_row := v_new;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_row := v_new;
  else
    v_old := to_jsonb(old);
    v_row := v_old;
  end if;

  v_municipality_id := nullif(v_row ->> 'municipality_id', '')::uuid;
  v_entity_id := v_row ->> 'id';
  v_correlation_id := coalesce(
    nullif(v_row ->> 'correlation_id', '')::uuid,
    gen_random_uuid()
  );

  perform private.append_audit_event(
    v_municipality_id,
    lower(tg_op),
    tg_table_schema,
    tg_table_name,
    v_entity_id,
    v_correlation_id,
    v_old,
    v_new,
    jsonb_build_object(
      'old', private.sanitize_audit_json(v_old),
      'new', private.sanitize_audit_json(v_new)
    )
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function private.prevent_tenant_or_id_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if to_jsonb(old) ->> 'municipality_id'
       is distinct from to_jsonb(new) ->> 'municipality_id' then
    raise exception 'municipality_id is immutable';
  end if;
  if to_jsonb(old) ->> 'id' is distinct from to_jsonb(new) ->> 'id' then
    raise exception 'id is immutable';
  end if;
  return new;
end;
$$;

create or replace function private.prevent_any_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only and cannot be changed', tg_table_name;
end;
$$;

create or replace function private.guard_frozen_content()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception '% cannot be deleted after creation', tg_table_name;
  end if;

  if tg_table_name = 'notification_template_versions'
     and old.status in ('approved', 'active', 'retired')
     and (
       old.subject is distinct from new.subject
       or old.body_text is distinct from new.body_text
       or old.body_html is distinct from new.body_html
       or old.content_sha256 is distinct from new.content_sha256
     ) then
    raise exception 'approved notification template content is immutable';
  elsif tg_table_name = 'legal_source_versions'
     and old.status in ('approved', 'published', 'revoked', 'retired')
     and (
       old.content_text is distinct from new.content_text
       or old.content_sha256 is distinct from new.content_sha256
       or old.source_id is distinct from new.source_id
       or old.version is distinct from new.version
     ) then
    raise exception 'approved legal source content is immutable';
  elsif tg_table_name = 'ai_prompt_versions'
     and old.status in ('approved', 'active', 'retired')
     and (
       old.system_prompt is distinct from new.system_prompt
       or old.output_schema is distinct from new.output_schema
       or old.content_sha256 is distinct from new.content_sha256
     ) then
    raise exception 'approved prompt content is immutable';
  elsif tg_table_name = 'notifications'
     and old.status in ('queued', 'processing', 'sent', 'partially_failed')
     and (
       old.subject_snapshot is distinct from new.subject_snapshot
       or old.body_text_snapshot is distinct from new.body_text_snapshot
       or old.body_html_snapshot is distinct from new.body_html_snapshot
       or old.content_sha256 is distinct from new.content_sha256
       or old.template_version_id is distinct from new.template_version_id
     ) then
    raise exception 'queued notification content is immutable';
  elsif tg_table_name = 'case_messages'
     and old.status = 'published'
     and (
       old.body is distinct from new.body
       or old.content_sha256 is distinct from new.content_sha256
       or old.source_draft_revision_id is distinct from new.source_draft_revision_id
       or old.author_user_id is distinct from new.author_user_id
     ) then
    raise exception 'published message content is immutable';
  end if;

  return new;
end;
$$;

do $$
declare
  r record;
begin
  for r in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.column_name = 'municipality_id'
      and exists (
        select 1
        from information_schema.columns i
        where i.table_schema = c.table_schema
          and i.table_name = c.table_name
          and i.column_name = 'id'
      )
  loop
    execute format(
      'create trigger %I before update on public.%I for each row execute function private.prevent_tenant_or_id_change()',
      r.table_name || '_immutable_identity',
      r.table_name
    );
  end loop;
end;
$$;

create trigger case_findings_append_only
  before update or delete on public.case_findings
  for each row execute function private.prevent_any_mutation();
create trigger divergence_items_append_only
  before update or delete on public.divergence_items
  for each row execute function private.prevent_any_mutation();
create trigger divergence_revalidations_append_only
  before update or delete on public.divergence_revalidations
  for each row execute function private.prevent_any_mutation();
create trigger case_events_append_only
  before update or delete on public.case_events
  for each row execute function private.prevent_any_mutation();
create trigger ai_draft_revisions_append_only
  before update or delete on public.ai_draft_revisions
  for each row execute function private.prevent_any_mutation();
create trigger ai_draft_citations_append_only
  before update or delete on public.ai_draft_citations
  for each row execute function private.prevent_any_mutation();
create trigger draft_reviews_append_only
  before update or delete on public.draft_reviews
  for each row execute function private.prevent_any_mutation();
create trigger audit_events_append_only
  before update or delete on audit.audit_events
  for each row execute function private.prevent_any_mutation();
create trigger audit_anchors_append_only
  before update or delete on audit.audit_anchors
  for each row execute function private.prevent_any_mutation();
create trigger email_provider_events_append_only
  before update or delete on private.email_provider_events
  for each row execute function private.prevent_any_mutation();
create trigger ai_run_sources_append_only
  before update or delete on private.ai_run_sources
  for each row execute function private.prevent_any_mutation();

create trigger notification_template_versions_guard
  before update or delete on public.notification_template_versions
  for each row execute function private.guard_frozen_content();
create trigger legal_source_versions_guard
  before update or delete on public.legal_source_versions
  for each row execute function private.guard_frozen_content();
create trigger ai_prompt_versions_guard
  before update or delete on public.ai_prompt_versions
  for each row execute function private.guard_frozen_content();
create trigger notifications_guard
  before update or delete on public.notifications
  for each row execute function private.guard_frozen_content();
create trigger case_messages_guard
  before update or delete on public.case_messages
  for each row execute function private.guard_frozen_content();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'municipality_memberships',
    'municipality_policy_versions',
    'integrations',
    'taxpayers',
    'accounting_firms',
    'taxpayer_user_links',
    'accountant_user_links',
    'taxpayer_accountant_links',
    'party_contacts',
    'source_systems',
    'import_batches',
    'current_account_entries',
    'taxpayer_fiscal_conditions',
    'divergence_rules',
    'divergence_rule_versions',
    'detection_runs',
    'divergences',
    'case_opening_batches',
    'case_opening_batch_items',
    'fiscal_cases',
    'case_assignments',
    'notification_templates',
    'notification_template_versions',
    'notification_channel_settings',
    'notifications',
    'notification_recipients',
    'case_questions',
    'legal_sources',
    'legal_source_versions',
    'knowledge_releases',
    'ai_prompt_versions',
    'ai_drafts',
    'retention_policies',
    'legal_holds',
    'privacy_requests'
  ]
  loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I for each row execute function private.audit_row_change()',
      v_table || '_audit',
      v_table
    );
  end loop;
end;
$$;

do $$
declare
  r record;
begin
  for r in
    select tablename
    from pg_catalog.pg_tables
    where schemaname = 'public'
  loop
    execute format('alter table public.%I enable row level security', r.tablename);
  end loop;
end;
$$;

alter table private.import_staging_rows enable row level security;
alter table private.municipality_case_counters enable row level security;
alter table private.delivery_attempts enable row level security;
alter table private.email_provider_events enable row level security;
alter table private.message_access_snapshots enable row level security;
alter table private.legal_chunks enable row level security;
alter table private.legal_embeddings enable row level security;
alter table private.ai_runs enable row level security;
alter table private.ai_run_sources enable row level security;
alter table private.idempotency_keys enable row level security;
alter table private.jobs enable row level security;
alter table private.monthly_usage_counters enable row level security;
alter table private.rate_limit_counters enable row level security;
alter table audit.audit_events enable row level security;
alter table audit.audit_anchors enable row level security;

create policy municipalities_select on public.municipalities
  for select to authenticated
  using ((select private.can_access_municipality(id)));

create policy profiles_select_self on public.profiles
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy profiles_update_self on public.profiles
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy platform_administrators_select_self on public.platform_administrators
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy memberships_select on public.municipality_memberships
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.can_manage_municipality(municipality_id))
    or (select private.has_municipality_role(
      municipality_id,
      array['supervisor']::text[]
    ))
  );

create policy policy_versions_select on public.municipality_policy_versions
  for select to authenticated
  using (
    (select private.can_manage_municipality(municipality_id))
    or (select private.has_municipality_role(
      municipality_id,
      array['supervisor']::text[]
    ))
  );
create policy integrations_select on public.integrations
  for select to authenticated
  using (
    (select private.can_manage_municipality(municipality_id))
    or (select private.has_municipality_role(
      municipality_id,
      array['supervisor']::text[]
    ))
  );

create policy taxpayers_select on public.taxpayers
  for select to authenticated
  using (
    (select private.can_manage_municipality(municipality_id))
    or (select private.can_access_taxpayer(municipality_id, id))
  );
create policy accounting_firms_select on public.accounting_firms
  for select to authenticated
  using (
    (select private.can_manage_municipality(municipality_id))
    or (select private.can_access_accounting_firm(municipality_id, id))
  );
create policy taxpayer_user_links_select on public.taxpayer_user_links
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.can_manage_municipality(municipality_id))
    or (select private.has_municipality_role(
      municipality_id,
      array['supervisor']::text[]
    ))
  );
create policy accountant_user_links_select on public.accountant_user_links
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.can_manage_municipality(municipality_id))
    or (select private.has_municipality_role(
      municipality_id,
      array['supervisor']::text[]
    ))
  );
create policy taxpayer_accountant_links_select on public.taxpayer_accountant_links
  for select to authenticated
  using (
    (select private.can_manage_municipality(municipality_id))
    or (select private.has_municipality_role(
      municipality_id,
      array['supervisor']::text[]
    ))
    or (select private.can_access_taxpayer(municipality_id, taxpayer_id))
  );
create policy party_contacts_select on public.party_contacts
  for select to authenticated
  using (
    (select private.can_manage_municipality(municipality_id))
    or (
      taxpayer_id is not null
      and (select private.can_access_taxpayer(municipality_id, taxpayer_id))
    )
    or (
      accounting_firm_id is not null
      and (select private.can_access_accounting_firm(municipality_id, accounting_firm_id))
    )
  );

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'source_systems',
    'import_batches',
    'import_batch_errors',
    'current_account_entries',
    'taxpayer_fiscal_conditions',
    'divergence_rules',
    'divergence_rule_versions',
    'detection_runs',
    'case_opening_batches',
    'case_opening_batch_items'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select private.has_municipality_role(municipality_id, array[''supervisor'']::text[])))',
      v_table || '_select_supervisor',
      v_table
    );
  end loop;
end;
$$;

create policy divergences_select on public.divergences
  for select to authenticated
  using ((select private.can_access_divergence(municipality_id, id)));
create policy divergence_items_select on public.divergence_items
  for select to authenticated
  using ((select private.can_access_divergence(municipality_id, divergence_id)));
create policy divergence_revalidations_select on public.divergence_revalidations
  for select to authenticated
  using ((select private.can_access_divergence(municipality_id, divergence_id)));

create policy fiscal_cases_select on public.fiscal_cases
  for select to authenticated
  using ((select private.can_access_case(municipality_id, id)));
create policy case_findings_select on public.case_findings
  for select to authenticated
  using ((select private.can_access_case(municipality_id, case_id)));
create policy case_assignments_select on public.case_assignments
  for select to authenticated
  using ((select private.can_access_case(municipality_id, case_id)));
create policy case_events_select on public.case_events
  for select to authenticated
  using (
    (select private.can_access_case(municipality_id, case_id))
    and (
      visibility = 'participants'
      or (select private.can_review_case(municipality_id, case_id))
    )
  );

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'notification_templates',
    'notification_template_versions',
    'notification_channel_settings',
    'notification_batches'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select private.has_municipality_role(municipality_id, array[''municipal_admin'', ''supervisor'']::text[])))',
      v_table || '_select_staff',
      v_table
    );
  end loop;
end;
$$;

create policy notifications_select on public.notifications
  for select to authenticated
  using ((select private.can_review_case(municipality_id, case_id)));
create policy notification_recipients_select on public.notification_recipients
  for select to authenticated
  using (
    exists (
      select 1
      from public.notifications n
      where n.municipality_id = notification_recipients.municipality_id
        and n.id = notification_recipients.notification_id
        and (select private.can_review_case(n.municipality_id, n.case_id))
    )
  );

create policy case_threads_select on public.case_threads
  for select to authenticated
  using ((select private.can_access_case(municipality_id, case_id)));
create policy case_messages_select on public.case_messages
  for select to authenticated
  using (
    (select private.can_access_case(municipality_id, case_id))
    and (
      (status = 'published' and visibility = 'participants')
      or (select private.can_review_case(municipality_id, case_id))
    )
  );
create policy case_questions_select on public.case_questions
  for select to authenticated
  using ((select private.can_access_case(municipality_id, case_id)));

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'legal_sources',
    'legal_source_versions',
    'legal_sections',
    'knowledge_releases',
    'knowledge_release_items',
    'rule_legal_basis',
    'ai_prompt_templates',
    'ai_prompt_versions'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select private.has_municipality_role(municipality_id, array[''supervisor'', ''fiscal_auditor'', ''legal_reviewer'']::text[])))',
      v_table || '_select_fiscal_staff',
      v_table
    );
  end loop;
end;
$$;

create policy ai_drafts_select on public.ai_drafts
  for select to authenticated
  using ((select private.can_review_case(municipality_id, case_id)));
create policy ai_draft_revisions_select on public.ai_draft_revisions
  for select to authenticated
  using (
    exists (
      select 1
      from public.ai_drafts ad
      where ad.municipality_id = ai_draft_revisions.municipality_id
        and ad.id = ai_draft_revisions.draft_id
        and (select private.can_review_case(ad.municipality_id, ad.case_id))
    )
  );
create policy ai_draft_citations_select on public.ai_draft_citations
  for select to authenticated
  using (
    exists (
      select 1
      from public.ai_draft_revisions adr
      join public.ai_drafts ad
        on ad.municipality_id = adr.municipality_id
       and ad.id = adr.draft_id
      where adr.municipality_id = ai_draft_citations.municipality_id
        and adr.id = ai_draft_citations.draft_revision_id
        and (select private.can_review_case(ad.municipality_id, ad.case_id))
    )
  );
create policy draft_reviews_select on public.draft_reviews
  for select to authenticated
  using (
    exists (
      select 1
      from public.ai_drafts ad
      where ad.municipality_id = draft_reviews.municipality_id
        and ad.id = draft_reviews.draft_id
        and (select private.can_review_case(ad.municipality_id, ad.case_id))
    )
  );

create policy case_documents_select on public.case_documents
  for select to authenticated
  using (
    (select private.can_access_case(municipality_id, case_id))
    and (
      status = 'available'
      or (select private.can_review_case(municipality_id, case_id))
    )
  );

create policy retention_policies_select on public.retention_policies
  for select to authenticated
  using (
    (select private.can_manage_municipality(municipality_id))
    or (select private.has_municipality_role(
      municipality_id,
      array['supervisor']::text[]
    ))
  );
create policy legal_holds_select on public.legal_holds
  for select to authenticated
  using (
    (select private.has_municipality_role(
      municipality_id,
      array['supervisor']::text[]
    ))
    or (
      case_id is not null
      and (select private.can_review_case(municipality_id, case_id))
    )
  );
create policy privacy_requests_select on public.privacy_requests
  for select to authenticated
  using (
    requester_user_id = (select auth.uid())
    or (select private.can_manage_municipality(municipality_id))
  );

revoke all on all tables in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;
grant select on all tables in schema public to authenticated;
grant update (full_name, phone, locale, last_seen_at)
  on public.profiles to authenticated;

grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant all on all tables in schema private to service_role;
grant usage, select on all sequences in schema private to service_role;
grant all on all tables in schema audit to service_role;
grant usage, select on all sequences in schema audit to service_role;

revoke all on all functions in schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;
grant execute on function private.is_aal2() to authenticated, service_role;
grant execute on function private.can_access_municipality(uuid) to authenticated, service_role;
grant execute on function private.can_manage_municipality(uuid) to authenticated, service_role;
grant execute on function private.can_access_accounting_firm(uuid, uuid) to authenticated, service_role;
grant execute on function private.can_access_taxpayer(uuid, uuid) to authenticated, service_role;
grant execute on function private.can_access_case(uuid, uuid) to authenticated, service_role;
grant execute on function private.can_review_case(uuid, uuid) to authenticated, service_role;
grant execute on function private.can_access_divergence(uuid, uuid) to authenticated, service_role;

commit;

