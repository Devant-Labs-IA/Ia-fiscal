begin;

create or replace function private.validate_initial_notice_template()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_combined text := lower(
    coalesce(new.subject, '') || ' ' ||
    coalesce(new.body_text, '') || ' ' ||
    coalesce(new.body_html, '')
  );
begin
  if v_combined ~ 'https?://' or v_combined ~ 'href[[:space:]]*=' then
    raise exception 'initial notice cannot contain links';
  end if;
  if v_combined ~ '\{\{[[:space:]]*(amount|value|difference|period|case_id|tax_id|cnpj|cpf)' then
    raise exception 'initial notice contains a prohibited placeholder';
  end if;
  if exists (
    select 1
    from unnest(new.allowed_placeholders) p
    where p not in ('municipality_name')
  ) then
    raise exception 'unsupported placeholder in initial notice template';
  end if;
  return new;
end;
$$;

create trigger notification_template_versions_validate
  before insert or update on public.notification_template_versions
  for each row execute function private.validate_initial_notice_template();

create or replace function private.next_case_number(p_municipality_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year integer := extract(year from now() at time zone 'America/Sao_Paulo')::integer;
  v_value bigint;
begin
  insert into private.municipality_case_counters (
    municipality_id, year, last_value
  )
  values (p_municipality_id, v_year, 1)
  on conflict (municipality_id, year)
  do update
     set last_value = private.municipality_case_counters.last_value + 1
  returning last_value into v_value;

  return 'IAF-' || v_year::text || '-' || lpad(v_value::text, 6, '0');
end;
$$;

create or replace function private.enqueue_job(
  p_municipality_id uuid,
  p_job_type text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_payload jsonb,
  p_idempotency_key text,
  p_priority integer default 100,
  p_available_at timestamptz default now(),
  p_max_attempts integer default 5,
  p_correlation_id uuid default gen_random_uuid()
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job_id bigint;
begin
  insert into private.jobs (
    municipality_id,
    job_type,
    aggregate_type,
    aggregate_id,
    payload,
    idempotency_key,
    priority,
    available_at,
    max_attempts,
    correlation_id
  )
  values (
    p_municipality_id,
    p_job_type,
    p_aggregate_type,
    p_aggregate_id,
    coalesce(p_payload, '{}'::jsonb),
    p_idempotency_key,
    p_priority,
    p_available_at,
    p_max_attempts,
    p_correlation_id
  )
  on conflict (municipality_id, idempotency_key)
  do update set
    available_at = least(private.jobs.available_at, excluded.available_at),
    priority = least(private.jobs.priority, excluded.priority)
  returning id into v_job_id;

  return v_job_id;
end;
$$;

create or replace function public.ia_claim_jobs(
  p_worker_id text,
  p_limit integer default 10,
  p_lease_seconds integer default 120
)
returns table (
  job_id bigint,
  municipality_id uuid,
  job_type text,
  aggregate_type text,
  aggregate_id uuid,
  payload jsonb,
  attempt_number integer,
  correlation_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;
  if nullif(trim(p_worker_id), '') is null then
    raise exception 'worker_id is required';
  end if;
  if p_limit not between 1 and 100 or p_lease_seconds not between 30 and 900 then
    raise exception 'invalid claim limits';
  end if;

  update private.jobs j
     set status = 'retry',
         locked_at = null,
         locked_by = null,
         lease_expires_at = null,
         available_at = now(),
         last_error_code = 'lease_expired',
         updated_at = now()
   where j.status = 'processing'
     and j.lease_expires_at < now();

  return query
  with candidates as (
    select j.id
    from private.jobs j
    where j.status in ('pending', 'retry')
      and j.available_at <= now()
    order by j.priority, j.available_at, j.id
    limit p_limit
    for update skip locked
  ),
  claimed as (
    update private.jobs j
       set status = 'processing',
           attempt_count = j.attempt_count + 1,
           locked_at = now(),
           locked_by = p_worker_id,
           lease_expires_at = now() + make_interval(secs => p_lease_seconds),
           updated_at = now()
      from candidates c
     where j.id = c.id
     returning j.*
  )
  select
    c.id,
    c.municipality_id,
    c.job_type,
    c.aggregate_type,
    c.aggregate_id,
    c.payload,
    c.attempt_count,
    c.correlation_id
  from claimed c
  order by c.priority, c.id;
end;
$$;

create or replace function public.ia_complete_job(
  p_job_id bigint,
  p_worker_id text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  update private.jobs j
     set status = 'completed',
         completed_at = now(),
         locked_at = null,
         locked_by = null,
         lease_expires_at = null,
         updated_at = now()
   where j.id = p_job_id
     and j.status = 'processing'
     and j.locked_by = p_worker_id;

  if not found then
    raise exception 'job not owned by worker or no longer processing';
  end if;
end;
$$;

create or replace function public.ia_fail_job(
  p_job_id bigint,
  p_worker_id text,
  p_error_code text,
  p_safe_error_detail text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  update private.jobs j
     set status = case
           when j.attempt_count >= j.max_attempts then 'dead_letter'
           else 'retry'
         end,
         available_at = case
           when j.attempt_count >= j.max_attempts then j.available_at
           else now() + make_interval(
             secs => least(3600, (30 * power(2, greatest(j.attempt_count - 1, 0)))::integer)
           )
         end,
         last_error_code = left(coalesce(p_error_code, 'unknown_error'), 120),
         last_error_detail = left(coalesce(p_safe_error_detail, ''), 1000),
         locked_at = null,
         locked_by = null,
         lease_expires_at = null,
         updated_at = now()
   where j.id = p_job_id
     and j.status = 'processing'
     and j.locked_by = p_worker_id
  returning j.status into v_status;

  if v_status is null then
    raise exception 'job not owned by worker or no longer processing';
  end if;
  return v_status;
end;
$$;

create or replace function public.ia_block_job(
  p_job_id bigint,
  p_worker_id text,
  p_reason_code text,
  p_safe_detail text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  update private.jobs j
     set status = 'blocked_configuration',
         last_error_code = left(coalesce(p_reason_code, 'blocked_configuration'), 120),
         last_error_detail = left(coalesce(p_safe_detail, ''), 1000),
         locked_at = null,
         locked_by = null,
         lease_expires_at = null,
         updated_at = now()
   where j.id = p_job_id
     and j.status = 'processing'
     and j.locked_by = p_worker_id;

  if not found then
    raise exception 'job not owned by worker or no longer processing';
  end if;
end;
$$;

create or replace function public.ia_bootstrap_municipality_admin(
  p_user_id uuid,
  p_municipality_slug text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_municipality_id uuid;
  v_membership_id uuid;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'auth user not found';
  end if;

  select m.id into strict v_municipality_id
  from public.municipalities m
  where m.slug = lower(trim(p_municipality_slug));

  insert into public.municipality_memberships (
    municipality_id,
    user_id,
    role,
    status,
    activated_at,
    valid_from
  )
  values (
    v_municipality_id,
    p_user_id,
    'municipal_admin',
    'active',
    now(),
    now()
  )
  on conflict (municipality_id, user_id)
  do update set
    role = 'municipal_admin',
    status = 'active',
    activated_at = coalesce(public.municipality_memberships.activated_at, now()),
    valid_until = null
  returning id into v_membership_id;

  return v_membership_id;
end;
$$;

create or replace function public.ia_list_my_context()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'user_id', (select auth.uid()),
    'municipalities', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'municipality_id', m.id,
          'slug', m.slug,
          'name', m.name,
          'state_code', m.state_code,
          'membership_role', mm.role
        )
        order by m.name
      )
      from public.municipality_memberships mm
      join public.municipalities m on m.id = mm.municipality_id
      where mm.user_id = (select auth.uid())
        and mm.status = 'active'
        and mm.valid_from <= now()
        and (mm.valid_until is null or mm.valid_until > now())
    ), '[]'::jsonb),
    'taxpayer_links', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'municipality_id', tul.municipality_id,
          'taxpayer_id', tul.taxpayer_id,
          'access_role', tul.access_role
        )
      )
      from public.taxpayer_user_links tul
      where tul.user_id = (select auth.uid())
        and tul.status = 'active'
        and tul.valid_from <= now()
        and (tul.valid_until is null or tul.valid_until > now())
    ), '[]'::jsonb)
  );
$$;

create or replace function public.ia_run_current_account_detection(
  p_municipality_id uuid,
  p_rule_version_id uuid,
  p_as_of timestamptz,
  p_idempotency_key text,
  p_import_batch_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule public.divergence_rule_versions%rowtype;
  v_policy public.municipality_policy_versions%rowtype;
  v_run_id uuid;
  v_period_start date;
  v_period_end date;
  v_comparator text;
begin
  if not (
    private.is_service_role()
    or (
      private.is_aal2()
      and private.has_municipality_role(
        p_municipality_id,
        array['supervisor']::text[]
      )
    )
  ) then
    raise exception 'supervisor with aal2 required';
  end if;

  select rv.* into strict v_rule
  from public.divergence_rule_versions rv
  where rv.municipality_id = p_municipality_id
    and rv.id = p_rule_version_id
    and rv.status = 'active'
  for share;

  if coalesce((v_rule.parameters ->> 'formula_approved')::boolean, false) is not true then
    raise exception 'fiscal formula is not approved';
  end if;
  if v_rule.implementation_key <> 'current_account_generated_vs_paid_v1' then
    raise exception 'unsupported deterministic implementation';
  end if;

  select pv.* into strict v_policy
  from public.municipality_policy_versions pv
  where pv.municipality_id = p_municipality_id
    and pv.status = 'active'
    and (pv.effective_from is null or pv.effective_from <= p_as_of)
    and (pv.effective_until is null or pv.effective_until > p_as_of)
  for share;

  v_comparator := coalesce(v_rule.parameters ->> 'threshold_comparator', 'gte');
  if v_comparator not in ('gte', 'gt') then
    raise exception 'invalid threshold comparator';
  end if;

  v_period_end := p_as_of::date;
  v_period_start := (
    date_trunc('month', p_as_of)
    - make_interval(months => v_policy.lookback_months - 1)
  )::date;

  insert into public.detection_runs (
    municipality_id,
    rule_version_id,
    import_batch_id,
    status,
    as_of,
    period_start,
    period_end,
    idempotency_key,
    started_by,
    started_at
  )
  values (
    p_municipality_id,
    p_rule_version_id,
    p_import_batch_id,
    'running',
    p_as_of,
    v_period_start,
    v_period_end,
    p_idempotency_key,
    auth.uid(),
    now()
  )
  on conflict (municipality_id, idempotency_key)
  do update set idempotency_key = excluded.idempotency_key
  returning id into v_run_id;

  if exists (
    select 1 from public.divergences d
    where d.municipality_id = p_municipality_id
      and d.detection_run_id = v_run_id
  ) then
    return v_run_id;
  end if;

  with aggregated as (
    select
      e.taxpayer_id,
      sum(e.amount) filter (
        where e.direction = 'debit' and e.status = 'valid'
      )::numeric(18,2) as assessed_amount,
      sum(e.amount) filter (
        where e.direction = 'credit'
          and e.entry_kind = 'payment'
          and e.status = 'valid'
      )::numeric(18,2) as paid_amount,
      sum(e.amount) filter (
        where e.direction = 'credit'
          and e.entry_kind <> 'payment'
          and e.status = 'valid'
      )::numeric(18,2) as other_credits_amount
    from public.current_account_entries e
    where e.municipality_id = p_municipality_id
      and e.competence_month between v_period_start and v_period_end
    group by e.taxpayer_id
  ),
  candidates as (
    select
      a.taxpayer_id,
      coalesce(a.assessed_amount, 0)::numeric(18,2) as assessed_amount,
      coalesce(a.paid_amount, 0)::numeric(18,2) as paid_amount,
      coalesce(a.other_credits_amount, 0)::numeric(18,2) as other_credits_amount,
      greatest(
        coalesce(a.assessed_amount, 0)
        - coalesce(a.paid_amount, 0)
        - coalesce(a.other_credits_amount, 0),
        0
      )::numeric(18,2) as difference_amount,
      exists (
        select 1
        from public.taxpayer_fiscal_conditions c
        where c.municipality_id = p_municipality_id
          and c.taxpayer_id = a.taxpayer_id
          and c.status = 'active'
          and c.blocks_automation
          and c.effective_from <= p_as_of
          and (c.effective_until is null or c.effective_until > p_as_of)
          and (c.period_start is null or c.period_start <= v_period_end)
          and (c.period_end is null or c.period_end >= v_period_start)
      ) as has_block
    from aggregated a
  ),
  filtered as (
    select c.*,
      row_number() over (
        order by c.difference_amount desc, c.taxpayer_id
      ) as selection_rank
    from candidates c
    where (
      (v_comparator = 'gte' and c.difference_amount >= v_policy.minimum_divergence_amount)
      or
      (v_comparator = 'gt' and c.difference_amount > v_policy.minimum_divergence_amount)
    )
  ),
  selected as (
    select f.*
    from filtered f
    where f.selection_rank <= v_policy.top_debtors_limit
  ),
  prepared as (
    select
      s.*,
      jsonb_build_object(
        'implementation_key', v_rule.implementation_key,
        'implementation_version', v_rule.implementation_version,
        'rule_version_id', v_rule.id,
        'policy_version_id', v_policy.id,
        'as_of', p_as_of,
        'period_start', v_period_start,
        'period_end', v_period_end,
        'selection_rank', s.selection_rank
      ) as snapshot
    from selected s
  )
  insert into public.divergences (
    municipality_id,
    taxpayer_id,
    detection_run_id,
    rule_version_id,
    divergence_type,
    period_start,
    period_end,
    as_of,
    assessed_amount,
    paid_amount,
    other_credits_amount,
    difference_amount,
    threshold_amount,
    priority_score,
    status,
    block_reasons,
    source_snapshot,
    snapshot_sha256
  )
  select
    p_municipality_id,
    p.taxpayer_id,
    v_run_id,
    v_rule.id,
    'current_account_balance',
    v_period_start,
    v_period_end,
    p_as_of,
    p.assessed_amount,
    p.paid_amount,
    p.other_credits_amount,
    p.difference_amount,
    v_policy.minimum_divergence_amount,
    p.difference_amount,
    case when p.has_block then 'blocked' else 'pending_revalidation' end,
    case
      when p.has_block then jsonb_build_array(jsonb_build_object('code', 'active_fiscal_condition'))
      else '[]'::jsonb
    end,
    p.snapshot,
    pg_catalog.encode(extensions.digest(p.snapshot::text, 'sha256'), 'hex')
  from prepared p;

  insert into public.divergence_items (
    municipality_id,
    divergence_id,
    current_account_entry_id,
    entry_kind,
    direction,
    amount_snapshot,
    competence_month,
    source_sha256
  )
  select
    d.municipality_id,
    d.id,
    e.id,
    e.entry_kind,
    e.direction,
    e.amount,
    e.competence_month,
    e.payload_sha256
  from public.divergences d
  join public.current_account_entries e
    on e.municipality_id = d.municipality_id
   and e.taxpayer_id = d.taxpayer_id
   and e.competence_month between d.period_start and d.period_end
   and e.status = 'valid'
  where d.municipality_id = p_municipality_id
    and d.detection_run_id = v_run_id
  on conflict do nothing;

  update public.detection_runs dr
     set status = 'completed',
         candidate_count = (
           select count(*) from public.divergences d
           where d.municipality_id = p_municipality_id
             and d.detection_run_id = v_run_id
         ),
         divergence_count = (
           select count(*) from public.divergences d
           where d.municipality_id = p_municipality_id
             and d.detection_run_id = v_run_id
             and d.status = 'pending_revalidation'
         ),
         blocked_count = (
           select count(*) from public.divergences d
           where d.municipality_id = p_municipality_id
             and d.detection_run_id = v_run_id
             and d.status = 'blocked'
         ),
         finished_at = now()
   where dr.municipality_id = p_municipality_id
     and dr.id = v_run_id;

  return v_run_id;
end;
$$;

create or replace function public.ia_create_case_opening_batch(
  p_detection_run_id uuid,
  p_divergence_ids uuid[],
  p_idempotency_key text,
  p_assigned_membership_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.detection_runs%rowtype;
  v_policy public.municipality_policy_versions%rowtype;
  v_batch_id uuid;
begin
  select dr.* into strict v_run
  from public.detection_runs dr
  where dr.id = p_detection_run_id
    and dr.status = 'completed'
  for share;

  if not (
    private.is_aal2()
    and private.has_municipality_role(
      v_run.municipality_id,
      array['supervisor']::text[]
    )
  ) then
    raise exception 'supervisor with aal2 required';
  end if;

  select pv.* into strict v_policy
  from public.municipality_policy_versions pv
  where pv.municipality_id = v_run.municipality_id
    and pv.status = 'active'
  for share;

  if p_assigned_membership_id is not null and not exists (
    select 1
    from public.municipality_memberships mm
    where mm.municipality_id = v_run.municipality_id
      and mm.id = p_assigned_membership_id
      and mm.role = 'fiscal_auditor'
      and mm.status = 'active'
  ) then
    raise exception 'assigned fiscal membership is invalid';
  end if;

  insert into public.case_opening_batches (
    municipality_id,
    detection_run_id,
    policy_version_id,
    status,
    idempotency_key,
    submitted_by,
    submitted_at
  )
  values (
    v_run.municipality_id,
    v_run.id,
    v_policy.id,
    'submitted',
    p_idempotency_key,
    auth.uid(),
    now()
  )
  on conflict (municipality_id, idempotency_key)
  do update set idempotency_key = excluded.idempotency_key
  returning id into v_batch_id;

  if not exists (
    select 1 from public.case_opening_batch_items bi
    where bi.municipality_id = v_run.municipality_id
      and bi.batch_id = v_batch_id
  ) then
    insert into public.case_opening_batch_items (
      municipality_id,
      batch_id,
      divergence_id,
      assigned_membership_id,
      status,
      selection_rank
    )
    select
      d.municipality_id,
      v_batch_id,
      d.id,
      p_assigned_membership_id,
      'selected',
      row_number() over (
        order by d.priority_score desc, d.difference_amount desc, d.id
      )::integer
    from public.divergences d
    where d.municipality_id = v_run.municipality_id
      and d.detection_run_id = v_run.id
      and d.status = 'pending_revalidation'
      and (
        p_divergence_ids is null
        or cardinality(p_divergence_ids) = 0
        or d.id = any(p_divergence_ids)
      )
    order by d.priority_score desc, d.difference_amount desc, d.id
    limit v_policy.top_debtors_limit;
  end if;

  update public.case_opening_batches b
     set requested_count = (
       select count(*) from public.case_opening_batch_items bi
       where bi.municipality_id = b.municipality_id
         and bi.batch_id = b.id
     )
   where b.municipality_id = v_run.municipality_id
     and b.id = v_batch_id;

  return v_batch_id;
end;
$$;

create or replace function public.ia_approve_case_opening_batch(
  p_batch_id uuid,
  p_approval_notes text default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.case_opening_batches%rowtype;
  v_item record;
  v_count integer := 0;
begin
  select b.* into strict v_batch
  from public.case_opening_batches b
  where b.id = p_batch_id
  for update;

  if not (
    private.is_aal2()
    and private.has_municipality_role(
      v_batch.municipality_id,
      array['supervisor']::text[]
    )
  ) then
    raise exception 'supervisor with aal2 required';
  end if;
  if v_batch.status <> 'submitted' then
    raise exception 'batch is not awaiting approval';
  end if;
  if v_batch.requested_count <= 0 then
    raise exception 'batch has no selected items';
  end if;

  update public.case_opening_batches
     set status = 'processing',
         approved_by = auth.uid(),
         approved_at = now(),
         approval_notes = nullif(trim(p_approval_notes), ''),
         approved_count = requested_count
   where municipality_id = v_batch.municipality_id
     and id = v_batch.id;

  update public.case_opening_batch_items
     set status = 'approved'
   where municipality_id = v_batch.municipality_id
     and batch_id = v_batch.id
     and status = 'selected';

  for v_item in
    select bi.id
    from public.case_opening_batch_items bi
    where bi.municipality_id = v_batch.municipality_id
      and bi.batch_id = v_batch.id
      and bi.status = 'approved'
    order by bi.selection_rank, bi.id
  loop
    perform private.enqueue_job(
      v_batch.municipality_id,
      'process_case_batch_item',
      'case_opening_batch_item',
      v_item.id,
      jsonb_build_object('batch_id', v_batch.id),
      'process-case-item:' || v_item.id::text,
      20,
      now(),
      5,
      gen_random_uuid()
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

create or replace function public.ia_process_case_batch_item(
  p_batch_item_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.case_opening_batch_items%rowtype;
  v_batch public.case_opening_batches%rowtype;
  v_divergence public.divergences%rowtype;
  v_policy public.municipality_policy_versions%rowtype;
  v_rule public.divergence_rule_versions%rowtype;
  v_channel public.notification_channel_settings%rowtype;
  v_template public.notification_template_versions%rowtype;
  v_taxpayer_contact public.party_contacts%rowtype;
  v_case_id uuid;
  v_case_number text;
  v_finding_id uuid;
  v_thread_id uuid;
  v_notification_batch_id uuid;
  v_notification_id uuid;
  v_recipient_id uuid;
  v_assessed numeric(18,2);
  v_paid numeric(18,2);
  v_credits numeric(18,2);
  v_difference numeric(18,2);
  v_has_block boolean;
  v_eligible boolean;
  v_revalidation_number integer;
  v_revalidation_id uuid;
  v_snapshot jsonb;
  v_snapshot_hash text;
  v_subject text;
  v_body_text text;
  v_body_html text;
  v_municipality_name text;
  v_comparator text;
  v_accountant record;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  select bi.* into strict v_item
  from public.case_opening_batch_items bi
  where bi.id = p_batch_item_id
  for update;

  select b.* into strict v_batch
  from public.case_opening_batches b
  where b.municipality_id = v_item.municipality_id
    and b.id = v_item.batch_id
  for update;

  if v_batch.status <> 'processing' or v_item.status not in ('approved', 'revalidating') then
    raise exception 'batch item is not eligible for processing';
  end if;

  select d.* into strict v_divergence
  from public.divergences d
  where d.municipality_id = v_item.municipality_id
    and d.id = v_item.divergence_id
  for update;

  if v_divergence.status = 'converted' then
    select fc.id into v_case_id
    from public.fiscal_cases fc
    where fc.municipality_id = v_divergence.municipality_id
      and fc.divergence_id = v_divergence.id;
    return v_case_id;
  end if;

  select pv.* into strict v_policy
  from public.municipality_policy_versions pv
  where pv.municipality_id = v_batch.municipality_id
    and pv.id = v_batch.policy_version_id
    and pv.status = 'active'
  for share;

  if not v_policy.auto_case_creation_enabled
     or not v_policy.auto_initial_notice_enabled then
    raise exception 'automatic case opening or notice is disabled';
  end if;

  select rv.* into strict v_rule
  from public.divergence_rule_versions rv
  where rv.municipality_id = v_divergence.municipality_id
    and rv.id = v_divergence.rule_version_id
    and rv.status = 'active'
  for share;

  if coalesce((v_rule.parameters ->> 'formula_approved')::boolean, false) is not true then
    raise exception 'fiscal formula is not approved';
  end if;
  v_comparator := coalesce(v_rule.parameters ->> 'threshold_comparator', 'gte');

  update public.case_opening_batch_items
     set status = 'revalidating'
   where municipality_id = v_item.municipality_id
     and id = v_item.id;

  select
    coalesce(sum(e.amount) filter (
      where e.direction = 'debit' and e.status = 'valid'
    ), 0)::numeric(18,2),
    coalesce(sum(e.amount) filter (
      where e.direction = 'credit'
        and e.entry_kind = 'payment'
        and e.status = 'valid'
    ), 0)::numeric(18,2),
    coalesce(sum(e.amount) filter (
      where e.direction = 'credit'
        and e.entry_kind <> 'payment'
        and e.status = 'valid'
    ), 0)::numeric(18,2)
  into v_assessed, v_paid, v_credits
  from public.current_account_entries e
  where e.municipality_id = v_divergence.municipality_id
    and e.taxpayer_id = v_divergence.taxpayer_id
    and e.competence_month between v_divergence.period_start and v_divergence.period_end;

  v_difference := greatest(v_assessed - v_paid - v_credits, 0);

  select exists (
    select 1
    from public.taxpayer_fiscal_conditions c
    where c.municipality_id = v_divergence.municipality_id
      and c.taxpayer_id = v_divergence.taxpayer_id
      and c.status = 'active'
      and c.blocks_automation
      and c.effective_from <= now()
      and (c.effective_until is null or c.effective_until > now())
      and (c.period_start is null or c.period_start <= v_divergence.period_end)
      and (c.period_end is null or c.period_end >= v_divergence.period_start)
  ) into v_has_block;

  v_eligible := not v_has_block and (
    (v_comparator = 'gte' and v_difference >= v_policy.minimum_divergence_amount)
    or (v_comparator = 'gt' and v_difference > v_policy.minimum_divergence_amount)
  );

  v_snapshot := jsonb_build_object(
    'revalidated_at', now(),
    'assessed_amount', v_assessed,
    'paid_amount', v_paid,
    'other_credits_amount', v_credits,
    'difference_amount', v_difference,
    'rule_version_id', v_rule.id,
    'policy_version_id', v_policy.id,
    'has_block', v_has_block
  );
  v_snapshot_hash := pg_catalog.encode(
    extensions.digest(v_snapshot::text, 'sha256'),
    'hex'
  );

  select coalesce(max(r.revalidation_number), 0) + 1
    into v_revalidation_number
  from public.divergence_revalidations r
  where r.municipality_id = v_divergence.municipality_id
    and r.divergence_id = v_divergence.id;

  insert into public.divergence_revalidations (
    municipality_id,
    divergence_id,
    revalidation_number,
    assessed_amount,
    paid_amount,
    other_credits_amount,
    difference_amount,
    eligible,
    block_reasons,
    source_snapshot,
    snapshot_sha256,
    performed_by
  )
  values (
    v_divergence.municipality_id,
    v_divergence.id,
    v_revalidation_number,
    v_assessed,
    v_paid,
    v_credits,
    v_difference,
    v_eligible,
    case
      when v_has_block then jsonb_build_array(jsonb_build_object('code', 'active_fiscal_condition'))
      when not v_eligible then jsonb_build_array(jsonb_build_object('code', 'below_threshold'))
      else '[]'::jsonb
    end,
    v_snapshot,
    v_snapshot_hash,
    auth.uid()
  )
  returning id into v_revalidation_id;

  if not v_eligible then
    update public.divergences
       set status = 'blocked',
           assessed_amount = v_assessed,
           paid_amount = v_paid,
           other_credits_amount = v_credits,
           difference_amount = v_difference,
           last_revalidated_at = now(),
           block_reasons = case
             when v_has_block then jsonb_build_array(jsonb_build_object('code', 'active_fiscal_condition'))
             else jsonb_build_array(jsonb_build_object('code', 'below_threshold'))
           end
     where municipality_id = v_divergence.municipality_id
       and id = v_divergence.id;

    update public.case_opening_batch_items
       set status = 'blocked',
           exclusion_reason = case
             when v_has_block then 'active_fiscal_condition'
             else 'below_threshold'
           end,
           processed_at = now()
     where municipality_id = v_item.municipality_id
       and id = v_item.id;

    update public.case_opening_batches
       set blocked_count = blocked_count + 1
     where municipality_id = v_batch.municipality_id
       and id = v_batch.id;
    return null;
  end if;

  select cs.* into strict v_channel
  from public.notification_channel_settings cs
  where cs.municipality_id = v_batch.municipality_id
    and cs.channel = 'email'
    and cs.status = 'active'
    and cs.kill_switch = false
  for share;

  select tv.* into strict v_template
  from public.notification_template_versions tv
  where tv.municipality_id = v_batch.municipality_id
    and tv.id = v_channel.initial_template_version_id
    and tv.status = 'active'
  for share;

  select pc.* into strict v_taxpayer_contact
  from public.party_contacts pc
  where pc.municipality_id = v_divergence.municipality_id
    and pc.taxpayer_id = v_divergence.taxpayer_id
    and pc.contact_type = 'email'
    and pc.status = 'verified'
    and pc.valid_from <= now()
    and (pc.valid_until is null or pc.valid_until > now())
  order by pc.is_primary desc, pc.verified_at desc nulls last, pc.created_at
  limit 1;

  select m.name into strict v_municipality_name
  from public.municipalities m
  where m.id = v_batch.municipality_id;

  v_subject := replace(v_template.subject, '{{municipality_name}}', v_municipality_name);
  v_body_text := replace(v_template.body_text, '{{municipality_name}}', v_municipality_name);
  v_body_html := case
    when v_template.body_html is null then null
    else replace(v_template.body_html, '{{municipality_name}}', v_municipality_name)
  end;

  if lower(v_subject || ' ' || v_body_text || ' ' || coalesce(v_body_html, ''))
       ~ 'https?://|href[[:space:]]*=' then
    raise exception 'rendered initial notice contains a link';
  end if;

  v_case_number := private.next_case_number(v_batch.municipality_id);

  insert into public.fiscal_cases (
    municipality_id,
    taxpayer_id,
    divergence_id,
    batch_item_id,
    case_number,
    status,
    opened_by
  )
  values (
    v_batch.municipality_id,
    v_divergence.taxpayer_id,
    v_divergence.id,
    v_item.id,
    v_case_number,
    'initial_notice_pending',
    v_batch.approved_by
  )
  returning id into v_case_id;

  insert into public.case_findings (
    municipality_id,
    case_id,
    divergence_id,
    rule_version_id,
    revalidation_id,
    assessed_amount,
    paid_amount,
    other_credits_amount,
    difference_amount,
    period_start,
    period_end,
    finding_snapshot,
    content_sha256
  )
  values (
    v_batch.municipality_id,
    v_case_id,
    v_divergence.id,
    v_rule.id,
    v_revalidation_id,
    v_assessed,
    v_paid,
    v_credits,
    v_difference,
    v_divergence.period_start,
    v_divergence.period_end,
    v_snapshot,
    v_snapshot_hash
  )
  returning id into v_finding_id;

  insert into public.case_threads (municipality_id, case_id)
  values (v_batch.municipality_id, v_case_id)
  returning id into v_thread_id;

  if v_item.assigned_membership_id is not null then
    insert into public.case_assignments (
      municipality_id,
      case_id,
      membership_id,
      assignment_role,
      assigned_by
    )
    values (
      v_batch.municipality_id,
      v_case_id,
      v_item.assigned_membership_id,
      'responsible_fiscal',
      v_batch.approved_by
    );
  end if;

  insert into public.case_events (
    municipality_id,
    case_id,
    event_type,
    visibility,
    actor_type,
    actor_user_id,
    event_data
  )
  values (
    v_batch.municipality_id,
    v_case_id,
    'inspection_case_opened',
    'participants',
    'service',
    null,
    jsonb_build_object(
      'case_number', v_case_number,
      'finding_id', v_finding_id,
      'batch_id', v_batch.id
    )
  );

  insert into public.notification_batches (
    municipality_id,
    case_opening_batch_id,
    status,
    idempotency_key
  )
  values (
    v_batch.municipality_id,
    v_batch.id,
    'queued',
    'initial-notification-batch:' || v_batch.id::text
  )
  on conflict (municipality_id, idempotency_key)
  do update set idempotency_key = excluded.idempotency_key
  returning id into v_notification_batch_id;

  insert into public.notifications (
    municipality_id,
    notification_batch_id,
    case_id,
    template_version_id,
    notification_type,
    legal_nature,
    subject_snapshot,
    body_text_snapshot,
    body_html_snapshot,
    content_sha256,
    status,
    idempotency_key,
    queued_at
  )
  values (
    v_batch.municipality_id,
    v_notification_batch_id,
    v_case_id,
    v_template.id,
    'initial_inspection_alert',
    'informational_alert',
    v_subject,
    v_body_text,
    v_body_html,
    pg_catalog.encode(
      extensions.digest(
        v_subject || E'\n' || v_body_text || E'\n' || coalesce(v_body_html, ''),
        'sha256'
      ),
      'hex'
    ),
    'queued',
    'initial-notice:' || v_case_id::text,
    now()
  )
  returning id into v_notification_id;

  insert into public.notification_recipients (
    municipality_id,
    notification_id,
    recipient_type,
    contact_id,
    email_snapshot,
    relationship_snapshot,
    status,
    idempotency_key
  )
  values (
    v_batch.municipality_id,
    v_notification_id,
    'taxpayer',
    v_taxpayer_contact.id,
    v_taxpayer_contact.normalized_value,
    jsonb_build_object(
      'contact_verified_at', v_taxpayer_contact.verified_at,
      'taxpayer_id', v_divergence.taxpayer_id
    ),
    'queued',
    'initial-notice:' || v_case_id::text || ':taxpayer:' ||
      lower(v_taxpayer_contact.normalized_value::text)
  )
  returning id into v_recipient_id;

  perform private.enqueue_job(
    v_batch.municipality_id,
    'send_initial_notice',
    'notification_recipient',
    v_recipient_id,
    jsonb_build_object('notification_id', v_notification_id, 'case_id', v_case_id),
    'send-initial-recipient:' || v_recipient_id::text,
    30,
    now(),
    5,
    gen_random_uuid()
  );

  if v_policy.accountant_notice_enabled then
    for v_accountant in
      select distinct on (pc.normalized_value)
        tal.id as link_id,
        pc.id as contact_id,
        pc.normalized_value,
        tal.verified_at as link_verified_at
      from public.taxpayer_accountant_links tal
      join public.party_contacts pc
        on pc.municipality_id = tal.municipality_id
       and pc.accounting_firm_id = tal.accounting_firm_id
      where tal.municipality_id = v_batch.municipality_id
        and tal.taxpayer_id = v_divergence.taxpayer_id
        and tal.status = 'active'
        and tal.can_receive_initial_notice
        and tal.valid_from <= now()
        and (tal.valid_until is null or tal.valid_until > now())
        and pc.contact_type = 'email'
        and pc.status = 'verified'
        and pc.valid_from <= now()
        and (pc.valid_until is null or pc.valid_until > now())
      order by pc.normalized_value, pc.is_primary desc, pc.verified_at desc nulls last
    loop
      insert into public.notification_recipients (
        municipality_id,
        notification_id,
        recipient_type,
        contact_id,
        taxpayer_accountant_link_id,
        email_snapshot,
        relationship_snapshot,
        status,
        idempotency_key
      )
      values (
        v_batch.municipality_id,
        v_notification_id,
        'accountant',
        v_accountant.contact_id,
        v_accountant.link_id,
        v_accountant.normalized_value,
        jsonb_build_object(
          'link_verified_at', v_accountant.link_verified_at,
          'taxpayer_id', v_divergence.taxpayer_id
        ),
        'queued',
        'initial-notice:' || v_case_id::text || ':accountant:' ||
          lower(v_accountant.normalized_value::text)
      )
      on conflict (municipality_id, notification_id, email_snapshot)
      do nothing
      returning id into v_recipient_id;

      if v_recipient_id is not null then
        perform private.enqueue_job(
          v_batch.municipality_id,
          'send_initial_notice',
          'notification_recipient',
          v_recipient_id,
          jsonb_build_object('notification_id', v_notification_id, 'case_id', v_case_id),
          'send-initial-recipient:' || v_recipient_id::text,
          40,
          now(),
          5,
          gen_random_uuid()
        );
      end if;
      v_recipient_id := null;
    end loop;
  end if;

  update public.divergences
     set status = 'converted',
         assessed_amount = v_assessed,
         paid_amount = v_paid,
         other_credits_amount = v_credits,
         difference_amount = v_difference,
         last_revalidated_at = now(),
         block_reasons = '[]'::jsonb
   where municipality_id = v_divergence.municipality_id
     and id = v_divergence.id;

  update public.case_opening_batch_items
     set status = 'opened',
         processed_at = now()
   where municipality_id = v_item.municipality_id
     and id = v_item.id;

  update public.case_opening_batches b
     set opened_count = b.opened_count + 1,
         status = case
           when not exists (
             select 1
             from public.case_opening_batch_items bi
             where bi.municipality_id = b.municipality_id
               and bi.batch_id = b.id
               and bi.status in ('approved', 'revalidating')
           ) then 'completed'
           else b.status
         end
   where b.municipality_id = v_batch.municipality_id
     and b.id = v_batch.id;

  update public.notification_batches nb
     set total_notifications = (
       select count(*)
       from public.notifications n
       where n.municipality_id = nb.municipality_id
         and n.notification_batch_id = nb.id
     )
   where nb.municipality_id = v_batch.municipality_id
     and nb.id = v_notification_batch_id;

  return v_case_id;
end;
$$;

create or replace function public.ia_get_notification_job_context(
  p_job_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.jobs%rowtype;
  v_recipient public.notification_recipients%rowtype;
  v_notification public.notifications%rowtype;
  v_case public.fiscal_cases%rowtype;
  v_channel public.notification_channel_settings%rowtype;
  v_policy public.municipality_policy_versions%rowtype;
  v_valid boolean := false;
  v_reason text;
  v_daily_sent bigint := 0;
  v_monthly_sent bigint := 0;
  v_timezone text;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  select j.* into strict v_job
  from private.jobs j
  where j.id = p_job_id
    and j.job_type = 'send_initial_notice';

  select nr.* into strict v_recipient
  from public.notification_recipients nr
  where nr.municipality_id = v_job.municipality_id
    and nr.id = v_job.aggregate_id;

  select n.* into strict v_notification
  from public.notifications n
  where n.municipality_id = v_recipient.municipality_id
    and n.id = v_recipient.notification_id;

  select fc.* into strict v_case
  from public.fiscal_cases fc
  where fc.municipality_id = v_notification.municipality_id
    and fc.id = v_notification.case_id;

  if v_case.status in ('cancelled', 'resolved', 'closed') then
    v_reason := 'case_not_sendable';
  elsif v_notification.status in ('cancelled', 'sent') then
    v_reason := 'notification_not_sendable';
  elsif v_recipient.status not in ('pending', 'queued', 'failed') then
    v_reason := 'recipient_not_sendable';
  else
    select pv.* into v_policy
    from public.municipality_policy_versions pv
    where pv.municipality_id = v_job.municipality_id
      and pv.status = 'active';

    select cs.* into v_channel
    from public.notification_channel_settings cs
    where cs.municipality_id = v_job.municipality_id
      and cs.channel = 'email'
      and cs.status = 'active'
      and cs.kill_switch = false;

    if v_policy.id is null or not v_policy.auto_initial_notice_enabled then
      v_reason := 'notification_feature_disabled';
    elsif v_channel.id is null then
      v_reason := 'email_channel_disabled';
    else
      select m.timezone into strict v_timezone
      from public.municipalities m
      where m.id = v_job.municipality_id;

      select count(*) into v_daily_sent
      from public.notification_recipients nr
      where nr.municipality_id = v_job.municipality_id
        and nr.sent_at >= (
          date_trunc('day', now() at time zone v_timezone)
          at time zone v_timezone
        )
        and nr.status in ('sent', 'delivered');

      select coalesce((
        select muc.quantity
        from private.monthly_usage_counters muc
        where muc.municipality_id = v_job.municipality_id
          and muc.category = 'email'
          and muc.period_start = date_trunc('month', current_date)::date
      ), 0) into v_monthly_sent;

      if v_daily_sent >= least(
        v_policy.daily_initial_notice_limit,
        v_channel.daily_limit
      ) then
        v_reason := 'daily_email_limit_reached';
      elsif v_monthly_sent >= v_channel.monthly_limit then
        v_reason := 'monthly_email_limit_reached';
      end if;
    end if;

    if v_reason is null and v_recipient.recipient_type = 'taxpayer' then
      select exists (
        select 1
        from public.party_contacts pc
        where pc.municipality_id = v_recipient.municipality_id
          and pc.id = v_recipient.contact_id
          and pc.taxpayer_id = v_case.taxpayer_id
          and pc.contact_type = 'email'
          and pc.status = 'verified'
          and pc.normalized_value = v_recipient.email_snapshot
          and pc.valid_from <= now()
          and (pc.valid_until is null or pc.valid_until > now())
      ) into v_valid;
      if not v_valid then v_reason := 'taxpayer_contact_invalid'; end if;
    elsif v_reason is null and v_recipient.recipient_type = 'accountant' then
      select exists (
        select 1
        from public.taxpayer_accountant_links tal
        join public.party_contacts pc
          on pc.municipality_id = tal.municipality_id
         and pc.id = v_recipient.contact_id
         and pc.accounting_firm_id = tal.accounting_firm_id
        where tal.municipality_id = v_recipient.municipality_id
          and tal.id = v_recipient.taxpayer_accountant_link_id
          and tal.taxpayer_id = v_case.taxpayer_id
          and tal.status = 'active'
          and tal.can_receive_initial_notice
          and tal.valid_from <= now()
          and (tal.valid_until is null or tal.valid_until > now())
          and pc.contact_type = 'email'
          and pc.status = 'verified'
          and pc.normalized_value = v_recipient.email_snapshot
          and pc.valid_from <= now()
          and (pc.valid_until is null or pc.valid_until > now())
      ) into v_valid;
      if not v_valid then v_reason := 'accountant_link_or_contact_invalid'; end if;
    end if;
  end if;

  if v_reason is not null then
    return jsonb_build_object(
      'allowed', false,
      'reason', v_reason,
      'recipient_id', v_recipient.id
    );
  end if;

  return jsonb_build_object(
    'allowed', true,
    'job_id', v_job.id,
    'recipient_id', v_recipient.id,
    'recipient_type', v_recipient.recipient_type,
    'to', v_recipient.email_snapshot,
    'from_name', v_channel.sender_name,
    'from_email', v_channel.sender_email,
    'reply_to', v_channel.reply_to_email,
    'subject', v_notification.subject_snapshot,
    'text', v_notification.body_text_snapshot,
    'html', v_notification.body_html_snapshot,
    'idempotency_key', v_recipient.idempotency_key,
    'case_id', v_case.id,
    'notification_id', v_notification.id
  );
end;
$$;

create or replace function public.ia_record_email_delivery(
  p_job_id bigint,
  p_provider_code text,
  p_provider_message_id text,
  p_status text,
  p_response_code integer default null,
  p_safe_error_code text default null,
  p_safe_error_detail text default null,
  p_next_attempt_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.jobs%rowtype;
  v_recipient public.notification_recipients%rowtype;
  v_notification public.notifications%rowtype;
  v_attempt integer;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;
  if p_status not in ('accepted', 'delivered', 'temporary_failure', 'permanent_failure', 'ambiguous') then
    raise exception 'invalid provider status';
  end if;

  select j.* into strict v_job
  from private.jobs j
  where j.id = p_job_id
    and j.job_type = 'send_initial_notice'
  for update;

  select nr.* into strict v_recipient
  from public.notification_recipients nr
  where nr.municipality_id = v_job.municipality_id
    and nr.id = v_job.aggregate_id
  for update;

  select n.* into strict v_notification
  from public.notifications n
  where n.municipality_id = v_recipient.municipality_id
    and n.id = v_recipient.notification_id
  for update;

  select coalesce(max(da.attempt_number), 0) + 1
    into v_attempt
  from private.delivery_attempts da
  where da.municipality_id = v_recipient.municipality_id
    and da.recipient_id = v_recipient.id;

  insert into private.delivery_attempts (
    municipality_id,
    recipient_id,
    attempt_number,
    provider_code,
    provider_message_id,
    idempotency_key,
    status,
    response_code,
    safe_error_code,
    safe_error_detail,
    completed_at,
    next_attempt_at
  )
  values (
    v_recipient.municipality_id,
    v_recipient.id,
    v_attempt,
    p_provider_code,
    p_provider_message_id,
    v_recipient.idempotency_key || ':attempt:' || v_attempt::text,
    p_status,
    p_response_code,
    left(p_safe_error_code, 120),
    left(p_safe_error_detail, 1000),
    now(),
    p_next_attempt_at
  );

  update public.notification_recipients
     set status = case
           when p_status = 'accepted' then 'sent'
           when p_status = 'delivered' then 'delivered'
           when p_status = 'permanent_failure' then 'failed'
           else 'failed'
         end,
         sent_at = case when p_status in ('accepted', 'delivered') then now() else sent_at end,
         delivered_at = case when p_status = 'delivered' then now() else delivered_at end,
         last_error_code = case
           when p_status in ('accepted', 'delivered') then null
           else left(coalesce(p_safe_error_code, p_status), 120)
         end
   where municipality_id = v_recipient.municipality_id
     and id = v_recipient.id;

  if p_status in ('accepted', 'delivered')
     and v_recipient.status not in ('sent', 'delivered') then
    insert into private.monthly_usage_counters (
      municipality_id, category, period_start, quantity
    )
    values (
      v_recipient.municipality_id,
      'email',
      date_trunc('month', current_date)::date,
      1
    )
    on conflict (municipality_id, category, period_start)
    do update set
      quantity = private.monthly_usage_counters.quantity + 1,
      updated_at = now();

    if v_recipient.recipient_type = 'taxpayer' then
      update public.fiscal_cases
         set status = 'initial_notice_sent'
       where municipality_id = v_notification.municipality_id
         and id = v_notification.case_id
         and status = 'initial_notice_pending';

      insert into public.case_events (
        municipality_id,
        case_id,
        event_type,
        visibility,
        actor_type,
        event_data
      )
      values (
        v_notification.municipality_id,
        v_notification.case_id,
        'initial_alert_sent',
        'participants',
        'service',
        jsonb_build_object(
          'notification_id', v_notification.id,
          'recipient_type', v_recipient.recipient_type
        )
      );
    end if;
  end if;

  update public.notifications n
     set status = case
       when exists (
         select 1
         from public.notification_recipients nr
         where nr.municipality_id = n.municipality_id
           and nr.notification_id = n.id
           and nr.status in ('pending', 'queued')
       ) then 'processing'
       when exists (
         select 1
         from public.notification_recipients nr
         where nr.municipality_id = n.municipality_id
           and nr.notification_id = n.id
           and nr.status = 'failed'
       ) then 'partially_failed'
       else 'sent'
     end,
     sent_at = case
       when not exists (
         select 1
         from public.notification_recipients nr
         where nr.municipality_id = n.municipality_id
           and nr.notification_id = n.id
           and nr.status in ('pending', 'queued')
       ) then coalesce(n.sent_at, now())
       else n.sent_at
     end
   where n.municipality_id = v_notification.municipality_id
     and n.id = v_notification.id;

  if v_notification.notification_batch_id is not null then
    update public.notification_batches nb
       set sent_notifications = (
             select count(*)
             from public.notifications n
             where n.municipality_id = nb.municipality_id
               and n.notification_batch_id = nb.id
               and n.status = 'sent'
           ),
           failed_notifications = (
             select count(*)
             from public.notifications n
             where n.municipality_id = nb.municipality_id
               and n.notification_batch_id = nb.id
               and n.status in ('failed', 'partially_failed')
           ),
           status = case
             when exists (
               select 1
               from public.notifications n
               where n.municipality_id = nb.municipality_id
                 and n.notification_batch_id = nb.id
                 and n.status in ('queued', 'processing', 'prepared')
             ) then 'processing'
             when exists (
               select 1
               from public.notifications n
               where n.municipality_id = nb.municipality_id
                 and n.notification_batch_id = nb.id
                 and n.status in ('failed', 'partially_failed')
             ) then 'partially_failed'
             else 'completed'
           end
     where nb.municipality_id = v_notification.municipality_id
       and nb.id = v_notification.notification_batch_id;
  end if;
end;
$$;

revoke all on function public.ia_claim_jobs(text, integer, integer)
  from public, anon, authenticated;
revoke all on function public.ia_complete_job(bigint, text)
  from public, anon, authenticated;
revoke all on function public.ia_fail_job(bigint, text, text, text)
  from public, anon, authenticated;
revoke all on function public.ia_block_job(bigint, text, text, text)
  from public, anon, authenticated;
revoke all on function public.ia_bootstrap_municipality_admin(uuid, text)
  from public, anon, authenticated;
revoke all on function public.ia_process_case_batch_item(uuid)
  from public, anon, authenticated;
revoke all on function public.ia_get_notification_job_context(bigint)
  from public, anon, authenticated;
revoke all on function public.ia_record_email_delivery(
  bigint, text, text, text, integer, text, text, timestamptz
) from public, anon, authenticated;

grant execute on function public.ia_claim_jobs(text, integer, integer) to service_role;
grant execute on function public.ia_complete_job(bigint, text) to service_role;
grant execute on function public.ia_fail_job(bigint, text, text, text) to service_role;
grant execute on function public.ia_block_job(bigint, text, text, text) to service_role;
grant execute on function public.ia_bootstrap_municipality_admin(uuid, text) to service_role;
grant execute on function public.ia_process_case_batch_item(uuid) to service_role;
grant execute on function public.ia_get_notification_job_context(bigint) to service_role;
grant execute on function public.ia_record_email_delivery(
  bigint, text, text, text, integer, text, text, timestamptz
) to service_role;

revoke all on function public.ia_list_my_context() from public, anon;
revoke all on function public.ia_run_current_account_detection(
  uuid, uuid, timestamptz, text, uuid
) from public, anon;
revoke all on function public.ia_create_case_opening_batch(
  uuid, uuid[], text, uuid
) from public, anon;
revoke all on function public.ia_approve_case_opening_batch(uuid, text)
  from public, anon;

grant execute on function public.ia_list_my_context() to authenticated, service_role;
grant execute on function public.ia_run_current_account_detection(
  uuid, uuid, timestamptz, text, uuid
) to authenticated, service_role;
grant execute on function public.ia_create_case_opening_batch(
  uuid, uuid[], text, uuid
) to authenticated, service_role;
grant execute on function public.ia_approve_case_opening_batch(uuid, text)
  to authenticated, service_role;

commit;

