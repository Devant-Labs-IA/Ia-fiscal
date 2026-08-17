-- Transactional regression for operational execution and publication boundaries.
-- It uses only synthetic auth identities and rolls back every fixture and mutation.

begin;

create temporary table operational_boundary_baseline (
  case_messages bigint not null,
  case_events bigint not null,
  notifications bigint not null,
  jobs bigint not null,
  delivery_attempts bigint not null,
  sandbox_messages bigint not null
) on commit drop;

insert into operational_boundary_baseline
select
  (select count(*) from public.case_messages),
  (select count(*) from public.case_events),
  (select count(*) from public.notifications),
  (select count(*) from private.jobs),
  (select count(*) from private.delivery_attempts),
  (select count(*) from private.sandbox_message_outbox);

do $test$
declare
  v_municipality_id uuid;
  v_detection_run_id uuid;
  v_divergence_id uuid;
  v_second_divergence_id uuid;
  v_third_divergence_id uuid;
  v_existing_case_id uuid;
  v_policy_id uuid;
  v_batch_id uuid;
  v_replay_batch_id uuid;
  v_live_batch_id uuid;
  v_live_item_id uuid;
  v_live_terminal_item_id uuid;
  v_live_approved_count integer;
  v_denied boolean;
  v_error text;
  v_worker_error text;
  v_batch_count bigint;
  v_item_count bigint;

  u_supervisor constant uuid := '00000000-0000-4000-8000-00000000b101';
  u_other_supervisor constant uuid := '00000000-0000-4000-8000-00000000b102';
  u_fiscal constant uuid := '00000000-0000-4000-8000-00000000b103';
  u_expired_fiscal constant uuid := '00000000-0000-4000-8000-00000000b104';
  u_future_fiscal constant uuid := '00000000-0000-4000-8000-00000000b105';
  u_second_fiscal constant uuid := '00000000-0000-4000-8000-00000000b106';

  m_supervisor constant uuid := '00000000-0000-4000-8000-00000000b201';
  m_other_supervisor constant uuid := '00000000-0000-4000-8000-00000000b202';
  m_fiscal constant uuid := '00000000-0000-4000-8000-00000000b203';
  m_expired_fiscal constant uuid := '00000000-0000-4000-8000-00000000b204';
  m_future_fiscal constant uuid := '00000000-0000-4000-8000-00000000b205';
  m_second_fiscal constant uuid := '00000000-0000-4000-8000-00000000b206';

  k_valid constant text := 'qa-operational-boundary-valid-v1';
  k_expired constant text := 'qa-operational-boundary-expired-v1';
  k_future constant text := 'qa-operational-boundary-future-v1';
  k_live constant text := 'qa-operational-boundary-live-v1';
  k_duplicate constant text := 'qa-operational-boundary-duplicate-v1';
begin
  select
    candidate.municipality_id,
    candidate.detection_run_id,
    candidate.divergence_ids[1],
    candidate.divergence_ids[2],
    candidate.divergence_ids[3]
    into
      v_municipality_id,
      v_detection_run_id,
      v_divergence_id,
      v_second_divergence_id,
      v_third_divergence_id
  from (
    select
      dr.municipality_id,
      dr.id as detection_run_id,
      dr.created_at,
      array_agg(d.id order by d.priority_score desc, d.id) as divergence_ids
    from public.detection_runs dr
    join public.municipalities m
      on m.id = dr.municipality_id
    join public.divergences d
      on d.municipality_id = dr.municipality_id
     and d.detection_run_id = dr.id
    where dr.status = 'completed'
      and dr.execution_mode = 'homologation_test'
      and m.status = 'homologation'
      and d.execution_mode = dr.execution_mode
      and d.divergence_type = 'current_account_balance'
      and d.status = 'pending_revalidation'
    group by dr.municipality_id, dr.id, dr.created_at
    having count(*) >= 3
  ) candidate
  order by candidate.created_at, candidate.detection_run_id
  limit 1;

  if v_detection_run_id is null or v_third_divergence_id is null then
    raise exception 'regression fixture requires one completed homologation run with three eligible divergences';
  end if;

  select fc.id into v_existing_case_id
  from public.fiscal_cases fc
  where fc.municipality_id = v_municipality_id
  order by fc.created_at, fc.id
  limit 1;
  if v_existing_case_id is null then
    raise exception 'regression fixture requires one synthetic fiscal case';
  end if;

  if exists (
    select 1
    from auth.users au
    where au.id in (
      u_supervisor,
      u_other_supervisor,
      u_fiscal,
      u_expired_fiscal,
      u_future_fiscal,
      u_second_fiscal
    )
  ) then
    raise exception 'synthetic operational-boundary user already exists';
  end if;

  insert into auth.users (
    id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  )
  values
    (u_supervisor, 'authenticated', 'authenticated',
      'qa-operational-supervisor@example.invalid', '{}'::jsonb, '{}'::jsonb, now(), now()),
    (u_other_supervisor, 'authenticated', 'authenticated',
      'qa-operational-supervisor-2@example.invalid', '{}'::jsonb, '{}'::jsonb, now(), now()),
    (u_fiscal, 'authenticated', 'authenticated',
      'qa-operational-fiscal@example.invalid', '{}'::jsonb, '{}'::jsonb, now(), now()),
    (u_expired_fiscal, 'authenticated', 'authenticated',
      'qa-operational-expired@example.invalid', '{}'::jsonb, '{}'::jsonb, now(), now()),
    (u_future_fiscal, 'authenticated', 'authenticated',
      'qa-operational-future@example.invalid', '{}'::jsonb, '{}'::jsonb, now(), now()),
    (u_second_fiscal, 'authenticated', 'authenticated',
      'qa-operational-fiscal-2@example.invalid', '{}'::jsonb, '{}'::jsonb, now(), now());

  insert into public.municipality_memberships (
    id, municipality_id, user_id, role, status, valid_from, valid_until, activated_at
  )
  values
    (m_supervisor, v_municipality_id, u_supervisor, 'supervisor', 'active',
      now() - interval '1 day', null, now()),
    (m_other_supervisor, v_municipality_id, u_other_supervisor, 'supervisor', 'active',
      now() - interval '1 day', null, now()),
    (m_fiscal, v_municipality_id, u_fiscal, 'fiscal_auditor', 'active',
      now() - interval '1 day', null, now()),
    (m_expired_fiscal, v_municipality_id, u_expired_fiscal, 'fiscal_auditor', 'active',
      now() - interval '2 days', now() - interval '1 day', now() - interval '2 days'),
    (m_future_fiscal, v_municipality_id, u_future_fiscal, 'fiscal_auditor', 'active',
      now() + interval '1 day', now() + interval '2 days', null),
    (m_second_fiscal, v_municipality_id, u_second_fiscal, 'fiscal_auditor', 'active',
      now() - interval '1 day', null, now());

  v_denied := false;
  v_error := null;
  begin
    insert into public.case_assignments (
      municipality_id, case_id, membership_id, assignment_role, assigned_by
    ) values (
      v_municipality_id, v_existing_case_id, m_expired_fiscal,
      'collaborator', u_supervisor
    );
  exception when others then
    v_denied := true;
    v_error := sqlerrm;
  end;
  if not v_denied or v_error not like '%currently valid municipal membership%' then
    raise exception 'case-assignment trigger accepted an expired membership: %', v_error;
  end if;

  v_denied := false;
  v_error := null;
  begin
    update public.municipality_memberships
       set role = 'support_readonly'
     where municipality_id = v_municipality_id
       and id = m_fiscal;
    insert into public.case_assignments (
      municipality_id, case_id, membership_id, assignment_role, assigned_by
    ) values (
      v_municipality_id, v_existing_case_id, m_fiscal,
      'responsible_fiscal', u_supervisor
    );
  exception when others then
    v_denied := true;
    v_error := sqlerrm;
  end;
  if not v_denied or v_error not like '%role is incompatible%' then
    raise exception 'case-assignment trigger accepted an incompatible active role: %', v_error;
  end if;

  select pv.id into v_policy_id
  from public.municipality_policy_versions pv
  where pv.municipality_id = v_municipality_id
    and pv.status = 'active'
  order by pv.version desc
  limit 1;

  if v_policy_id is null then
    select pv.id into strict v_policy_id
    from public.municipality_policy_versions pv
    where pv.municipality_id = v_municipality_id
      and pv.status in ('draft', 'approved')
    order by pv.version desc
    limit 1
    for update;

    update public.municipality_policy_versions
       set status = 'active',
           approved_by = u_supervisor,
           approved_at = now(),
           effective_from = coalesce(effective_from, now())
     where municipality_id = v_municipality_id
       and id = v_policy_id;
  end if;

  perform set_config('request.jwt.claim.sub', u_supervisor::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', u_supervisor,
      'role', 'authenticated',
      'aal', 'aal2'
    )::text,
    true
  );

  v_denied := false;
  v_error := null;
  begin
    perform public.ia_create_case_opening_batch(
      v_detection_run_id,
      array[v_divergence_id],
      k_expired,
      m_expired_fiscal
    );
  exception when others then
    v_denied := true;
    v_error := sqlerrm;
  end;
  if not v_denied or v_error not like '%not currently valid%' then
    raise exception 'expired fiscal membership was not rejected precisely: %', v_error;
  end if;

  v_denied := false;
  v_error := null;
  begin
    perform public.ia_create_case_opening_batch(
      v_detection_run_id,
      array[v_divergence_id],
      k_future,
      m_future_fiscal
    );
  exception when others then
    v_denied := true;
    v_error := sqlerrm;
  end;
  if not v_denied or v_error not like '%not currently valid%' then
    raise exception 'future fiscal membership was not rejected precisely: %', v_error;
  end if;

  v_batch_id := public.ia_create_case_opening_batch(
    v_detection_run_id,
    array[v_divergence_id],
    k_valid,
    m_fiscal
  );

  if not exists (
    select 1
    from public.case_opening_batches b
    where b.municipality_id = v_municipality_id
      and b.id = v_batch_id
      and b.detection_run_id = v_detection_run_id
      and b.execution_mode = 'homologation_test'
      and b.submitted_by = u_supervisor
      and b.requested_count = 1
      and b.request_sha256 ~ '^[a-f0-9]{64}$'
  ) then
    raise exception 'batch did not preserve homologation mode, owner, count, or request hash';
  end if;

  select count(*) into v_item_count
  from public.case_opening_batch_items bi
  where bi.municipality_id = v_municipality_id
    and bi.batch_id = v_batch_id
    and bi.divergence_id = v_divergence_id
    and bi.assigned_membership_id = m_fiscal
    and bi.status = 'selected';
  if v_item_count <> 1 then
    raise exception 'valid batch did not create exactly one assigned item';
  end if;

  v_replay_batch_id := public.ia_create_case_opening_batch(
    v_detection_run_id,
    array[v_divergence_id, v_divergence_id],
    k_valid,
    m_fiscal
  );
  if v_replay_batch_id is distinct from v_batch_id then
    raise exception 'canonical idempotent replay returned another batch';
  end if;
  if (
    select count(*)
    from public.case_opening_batch_items bi
    where bi.municipality_id = v_municipality_id
      and bi.batch_id = v_batch_id
  ) <> v_item_count then
    raise exception 'idempotent replay duplicated batch items';
  end if;

  v_denied := false;
  v_error := null;
  begin
    perform public.ia_create_case_opening_batch(
      v_detection_run_id,
      array[v_divergence_id],
      k_valid,
      null
    );
  exception when others then
    v_denied := true;
    v_error := sqlerrm;
  end;
  if not v_denied or v_error not like '%payload mismatch%' then
    raise exception 'idempotency key accepted a different payload: %', v_error;
  end if;

  perform set_config('request.jwt.claim.sub', u_other_supervisor::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', u_other_supervisor,
      'role', 'authenticated',
      'aal', 'aal2'
    )::text,
    true
  );
  v_denied := false;
  v_error := null;
  begin
    update public.municipality_memberships
       set status = 'revoked'
     where municipality_id = v_municipality_id
       and id = m_fiscal;
    perform public.ia_approve_case_opening_batch(v_batch_id, 'stale assignment regression');
  exception when others then
    v_denied := true;
    v_error := sqlerrm;
  end;
  if not v_denied or v_error not like '%membership that is no longer valid%' then
    raise exception 'approval accepted a membership revoked after submission: %', v_error;
  end if;

  v_denied := false;
  v_error := null;
  begin
    perform public.ia_create_case_opening_batch(
      v_detection_run_id,
      array[v_divergence_id],
      k_valid,
      m_fiscal
    );
  exception when others then
    v_denied := true;
    v_error := sqlerrm;
  end;
  if not v_denied or v_error not like '%owner mismatch%' then
    raise exception 'idempotency key accepted a different owner: %', v_error;
  end if;

  perform set_config('request.jwt.claim.sub', u_supervisor::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', u_supervisor,
      'role', 'authenticated',
      'aal', 'aal2'
    )::text,
    true
  );
  v_denied := false;
  v_error := null;
  begin
    perform public.ia_approve_case_opening_batch(v_batch_id, 'synthetic regression');
  exception when others then
    v_denied := true;
    v_error := sqlerrm;
  end;
  if not v_denied or v_error not like '%sandbox case-test workflow%' then
    raise exception 'generic approval accepted a homologation batch: %', v_error;
  end if;

  select count(*) into v_batch_count
  from public.case_opening_batches b
  where b.municipality_id = v_municipality_id
    and b.idempotency_key in (k_valid, k_expired, k_future);
  if v_batch_count <> 1 then
    raise exception 'denied batch paths left unexpected records: %', v_batch_count;
  end if;

  if exists (
    select 1
    from public.case_opening_batches b
    where b.municipality_id = v_municipality_id
      and b.id = v_batch_id
      and b.status <> 'submitted'
  ) then
    raise exception 'denied homologation approval changed batch status';
  end if;

  -- Exercise the live transition in a nested subtransaction. The deliberate
  -- ZX002 exception rolls back the live fixture, its queue job, and every
  -- worker mutation before the outer zero-side-effect assertions run.
  begin
    update public.municipalities
       set status = 'active'
     where id = v_municipality_id;
    update public.detection_runs
       set execution_mode = 'live'
     where municipality_id = v_municipality_id
       and id = v_detection_run_id;
    update public.divergences
       set execution_mode = 'live'
     where municipality_id = v_municipality_id
       and id in (v_second_divergence_id, v_third_divergence_id);

    v_live_batch_id := public.ia_create_case_opening_batch(
      v_detection_run_id,
      array[v_second_divergence_id, v_third_divergence_id],
      k_live,
      m_fiscal
    );
    select bi.id into strict v_live_item_id
    from public.case_opening_batch_items bi
    where bi.municipality_id = v_municipality_id
      and bi.batch_id = v_live_batch_id
      and bi.divergence_id = v_second_divergence_id;
    select bi.id into strict v_live_terminal_item_id
    from public.case_opening_batch_items bi
    where bi.municipality_id = v_municipality_id
      and bi.batch_id = v_live_batch_id
      and bi.divergence_id = v_third_divergence_id;

    update public.case_opening_batch_items
       set assigned_membership_id = m_second_fiscal
     where municipality_id = v_municipality_id
       and id = v_live_terminal_item_id;

    v_denied := false;
    v_error := null;
    begin
      perform public.ia_create_case_opening_batch(
        v_detection_run_id,
        array[v_second_divergence_id],
        k_duplicate,
        m_fiscal
      );
    exception when others then
      v_denied := true;
      v_error := sqlerrm;
    end;
    if not v_denied or v_error not like '%case_opening_batch_items_active_divergence_uq%' then
      raise exception 'a second active batch reserved the same divergence: %', v_error;
    end if;

    v_denied := false;
    v_error := null;
    begin
      update public.municipality_memberships
         set role = 'legal_reviewer'
       where municipality_id = v_municipality_id
         and id = m_fiscal;
      perform public.ia_approve_case_opening_batch(
        v_live_batch_id,
        'role-change approval regression'
      );
    exception when others then
      v_denied := true;
      v_error := sqlerrm;
    end;
    if not v_denied or v_error not like '%valid fiscal-auditor membership%' then
      raise exception 'approval accepted a fiscal membership whose role changed: %', v_error;
    end if;

    v_live_approved_count := public.ia_approve_case_opening_batch(
      v_live_batch_id,
      'synthetic live transition regression'
    );
    if v_live_approved_count <> 2 then
      raise exception 'live approval queued an unexpected item count: %', v_live_approved_count;
    end if;
    if not exists (
      select 1
      from public.case_opening_batches b
      where b.municipality_id = v_municipality_id
        and b.id = v_live_batch_id
        and b.status = 'processing'
        and b.execution_mode = 'live'
    ) then
      raise exception 'live approval was completed before its items became processable';
    end if;
    if not exists (
      select 1
      from public.case_opening_batch_items bi
      where bi.municipality_id = v_municipality_id
        and bi.id = v_live_item_id
        and bi.status = 'approved'
    ) then
      raise exception 'live approval did not leave its item approved';
    end if;
    if not exists (
      select 1
      from private.jobs j
      where j.municipality_id = v_municipality_id
        and j.job_type = 'process_case_batch_item'
        and j.aggregate_id = v_live_item_id
        and j.status = 'pending'
    ) then
      raise exception 'live approval did not enqueue its processable item';
    end if;

    update public.case_opening_batch_items
       set status = 'excluded',
           exclusion_reason = 'synthetic terminal-member regression'
     where municipality_id = v_municipality_id
       and id = v_live_terminal_item_id;
    update public.municipality_memberships
       set status = 'revoked'
     where municipality_id = v_municipality_id
       and id = m_second_fiscal;
    update public.case_opening_batches
       set status = status
     where municipality_id = v_municipality_id
       and id = v_live_batch_id;
    if not exists (
      select 1
      from public.case_opening_batches b
      where b.municipality_id = v_municipality_id
        and b.id = v_live_batch_id
        and b.status = 'processing'
    ) then
      raise exception 'a revoked membership on a terminal item blocked the remaining live work';
    end if;

    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', u_supervisor,
        'role', 'service_role',
        'aal', 'aal2'
      )::text,
      true
    );

    v_denied := false;
    v_error := null;
    begin
      update public.municipality_memberships
         set role = 'legal_reviewer'
       where municipality_id = v_municipality_id
         and id = m_fiscal;
      update public.case_opening_batch_items
         set status = 'revalidating'
       where municipality_id = v_municipality_id
         and id = v_live_item_id;
    exception when others then
      v_denied := true;
      v_error := sqlerrm;
    end;
    if not v_denied or v_error not like '%currently valid fiscal-auditor membership%' then
      raise exception 'worker write boundary accepted a fiscal membership whose role changed: %', v_error;
    end if;

    v_worker_error := null;
    begin
      perform public.ia_process_case_batch_item(v_live_item_id);
      raise exception using
        errcode = 'ZX001',
        message = 'worker boundary probe completed';
    exception
      when sqlstate 'ZX001' then
        null;
      when others then
        v_worker_error := sqlerrm;
    end;
    if v_worker_error like '%batch item is not eligible for processing%'
       or v_worker_error like '%service role required%'
       or v_worker_error like '%homologation divergences require the sandbox processor%' then
      raise exception 'live worker rejected the approved processing boundary: %', v_worker_error;
    end if;

    raise exception using
      errcode = 'ZX002',
      message = 'live transition probe completed';
  exception
    when sqlstate 'ZX002' then
      null;
  end;
end
$test$;

-- Prove the participant-publication RPCs fail at the ACL before their bodies
-- can inspect or mutate any case. Static privilege checks below cover the
-- other API roles without granting them a test session.
set local role authenticated;

do $acl_test$
declare
  v_denied boolean;
begin
  v_denied := false;
  begin
    perform public.ia_publish_manual_response(
      '00000000-0000-4000-8000-00000000b301'::uuid,
      'synthetic manual response that must never publish',
      'qa-operational-manual-v1'
    );
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'authenticated crossed the manual-response ACL';
  end if;

  v_denied := false;
  begin
    perform public.ia_publish_approved_response(
      '00000000-0000-4000-8000-00000000b302'::uuid,
      'qa-operational-approved-v1'
    );
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'authenticated crossed the approved-response ACL';
  end if;
end
$acl_test$;

reset role;

do $verification$
declare
  v_baseline operational_boundary_baseline%rowtype;
begin
  select * into strict v_baseline from operational_boundary_baseline;

  if has_function_privilege(
       'anon', 'public.ia_publish_manual_response(uuid,text,text)', 'execute'
     )
     or has_function_privilege(
       'authenticated', 'public.ia_publish_manual_response(uuid,text,text)', 'execute'
     )
     or has_function_privilege(
       'service_role', 'public.ia_publish_manual_response(uuid,text,text)', 'execute'
     )
     or has_function_privilege(
       'anon', 'public.ia_publish_approved_response(uuid,text)', 'execute'
     )
     or has_function_privilege(
       'authenticated', 'public.ia_publish_approved_response(uuid,text)', 'execute'
     )
     or has_function_privilege(
       'service_role', 'public.ia_publish_approved_response(uuid,text)', 'execute'
     ) then
    raise exception 'an API role retained participant-publication EXECUTE privilege';
  end if;

  if has_function_privilege(
       'anon', 'private.case_response_publication_allowed(uuid,text)', 'execute'
     )
     or has_function_privilege(
       'authenticated', 'private.case_response_publication_allowed(uuid,text)', 'execute'
     )
     or has_function_privilege(
       'service_role', 'private.case_response_publication_allowed(uuid,text)', 'execute'
     ) then
    raise exception 'an API role can execute the internal publication gate directly';
  end if;

  if not has_function_privilege(
       'authenticated', 'public.ia_create_case_opening_batch(uuid,uuid[],text,uuid)', 'execute'
     )
     or not has_function_privilege(
       'authenticated', 'public.ia_approve_case_opening_batch(uuid,text)', 'execute'
     ) then
    raise exception 'authenticated lost a required supervised-batch RPC privilege';
  end if;

  if pg_get_functiondef(
       'private.normalize_case_opening_batch_counts()'::regprocedure
     ) not like '%new.requested_count%'
     or pg_get_functiondef(
       'private.normalize_case_opening_batch_counts()'::regprocedure
     ) like '%new.selected_count%' then
    raise exception 'batch count normalization still targets the nonexistent selected_count column';
  end if;
  if pg_get_functiondef(
       'private.normalize_case_opening_batch_counts()'::regprocedure
     ) not like '%old.status = ''processing''%'
     or pg_get_functiondef(
       'private.normalize_case_opening_batch_counts()'::regprocedure
     ) not like '%new.status = ''processing''%' then
    raise exception 'batch auto-completion lacks the old-processing transition guard';
  end if;

  if to_regclass('public.case_opening_batch_items_active_divergence_uq') is null then
    raise exception 'active batch items do not have a race-safe divergence reservation';
  end if;
  if lower(pg_get_functiondef(
       'private.validate_case_assignment_membership()'::regprocedure
     )) not like '%for share%'
     or lower(pg_get_functiondef(
       'private.validate_batch_item_assigned_membership()'::regprocedure
     )) not like '%for share%'
     or lower(pg_get_functiondef(
       'private.validate_batch_processing_assignments()'::regprocedure
     )) not like '%for share%'
     or lower(pg_get_functiondef(
       'private.validate_batch_processing_assignments()'::regprocedure
     )) not like '%bi.status in (''selected'', ''approved'', ''revalidating'')%' then
    raise exception 'membership revalidation lacks its lock or non-terminal scope';
  end if;
  if lower(pg_get_triggerdef((
       select t.oid
       from pg_catalog.pg_trigger t
       join pg_catalog.pg_class c on c.oid = t.tgrelid
       join pg_catalog.pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relname = 'case_assignments'
         and t.tgname = 'case_assignments_validate_membership'
         and not t.tgisinternal
     ))) not like '%assignment_role%status%' then
    raise exception 'case-assignment trigger does not revalidate role/status changes';
  end if;

  if has_table_privilege(
       'anon', 'public.municipality_portal_settings', 'update'
     )
     or has_table_privilege(
       'authenticated', 'public.municipality_portal_settings', 'update'
     )
     or has_table_privilege(
       'service_role', 'public.municipality_portal_settings', 'update'
     ) then
    raise exception 'an API role can enable sandbox response publication directly';
  end if;

  if (select count(*) from public.case_messages) <> v_baseline.case_messages
     or (select count(*) from public.case_events) <> v_baseline.case_events
     or (select count(*) from public.notifications) <> v_baseline.notifications
     or (select count(*) from private.jobs) <> v_baseline.jobs
     or (select count(*) from private.delivery_attempts) <> v_baseline.delivery_attempts
     or (select count(*) from private.sandbox_message_outbox) <> v_baseline.sandbox_messages then
    raise exception 'operational regression produced an internal or external publication side effect';
  end if;

  raise notice 'operational boundary regression passed: mode, validity, idempotency, ACL, zero side effects';
end
$verification$;

rollback;
