begin;

alter table private.jobs
  add constraint jobs_municipality_id_id_uq unique (municipality_id, id);

alter table private.ai_runs
  add column job_id bigint,
  add constraint ai_runs_job_fk
    foreign key (municipality_id, job_id)
    references private.jobs(municipality_id, id),
  add constraint ai_runs_job_uq unique (job_id);

create or replace function private.consume_rate_limit(
  p_municipality_id uuid,
  p_actor_user_id uuid,
  p_action text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_window timestamptz;
  v_quantity integer;
begin
  if p_actor_user_id is null
     or nullif(trim(p_action), '') is null
     or p_limit < 1
     or p_window_seconds < 1 then
    return false;
  end if;

  v_window := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );

  insert into private.rate_limit_counters (
    municipality_id,
    actor_user_id,
    action,
    window_started_at,
    quantity
  )
  values (
    p_municipality_id,
    p_actor_user_id,
    p_action,
    v_window,
    1
  )
  on conflict (municipality_id, actor_user_id, action, window_started_at)
  do update set quantity = private.rate_limit_counters.quantity + 1
  returning quantity into v_quantity;

  return v_quantity <= p_limit;
end;
$$;

create or replace function public.ia_submit_case_question(
  p_case_id uuid,
  p_body text,
  p_client_request_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.fiscal_cases%rowtype;
  v_thread public.case_threads%rowtype;
  v_policy public.municipality_policy_versions%rowtype;
  v_user_id uuid := auth.uid();
  v_sender_type text;
  v_access_basis text;
  v_access_reference_id uuid;
  v_message_id uuid;
  v_question_id uuid;
  v_message_status text;
  v_body text := trim(coalesce(p_body, ''));
  v_client_request_id text := nullif(trim(coalesce(p_client_request_id, '')), '');
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;
  if not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if char_length(v_body) not between 1 and 10000 then
    raise exception 'question must contain between 1 and 10000 characters';
  end if;
  if v_client_request_id is null or char_length(v_client_request_id) > 200 then
    raise exception 'a valid client_request_id is required';
  end if;

  select fc.* into strict v_case
  from public.fiscal_cases fc
  where fc.id = p_case_id
  for share;

  if v_case.status in ('resolved', 'closed', 'cancelled') then
    raise exception 'case does not accept new questions';
  end if;
  if not private.can_access_case(v_case.municipality_id, v_case.id) then
    raise exception 'case access denied';
  end if;

  select cm.id into v_message_id
  from public.case_messages cm
  where cm.municipality_id = v_case.municipality_id
    and cm.case_id = v_case.id
    and cm.client_request_id = v_client_request_id;

  if v_message_id is not null then
    select cq.id into strict v_question_id
    from public.case_questions cq
    where cq.municipality_id = v_case.municipality_id
      and cq.message_id = v_message_id;
    return v_question_id;
  end if;

  select mm.id into v_access_reference_id
  from public.municipality_memberships mm
  where mm.municipality_id = v_case.municipality_id
    and mm.user_id = v_user_id
    and mm.status = 'active'
    and mm.role in ('fiscal_auditor', 'supervisor', 'legal_reviewer')
  limit 1;

  if v_access_reference_id is not null then
    v_sender_type := 'fiscal';
    v_access_basis := 'staff_membership';
  else
    select tul.id into v_access_reference_id
    from public.taxpayer_user_links tul
    where tul.municipality_id = v_case.municipality_id
      and tul.taxpayer_id = v_case.taxpayer_id
      and tul.user_id = v_user_id
      and tul.status = 'active'
      and tul.valid_from <= now()
      and (tul.valid_until is null or tul.valid_until > now())
    limit 1;

    if v_access_reference_id is not null then
      v_sender_type := 'taxpayer';
      v_access_basis := 'taxpayer_link';
    else
      select tal.id into v_access_reference_id
      from public.taxpayer_accountant_links tal
      join public.accountant_user_links aul
        on aul.municipality_id = tal.municipality_id
       and aul.accounting_firm_id = tal.accounting_firm_id
      where tal.municipality_id = v_case.municipality_id
        and tal.taxpayer_id = v_case.taxpayer_id
        and tal.status = 'active'
        and tal.can_access_portal
        and tal.valid_from <= now()
        and (tal.valid_until is null or tal.valid_until > now())
        and aul.user_id = v_user_id
        and aul.status = 'active'
        and aul.valid_from <= now()
        and (aul.valid_until is null or aul.valid_until > now())
      limit 1;
      v_sender_type := 'accountant';
      v_access_basis := 'accountant_link';
    end if;
  end if;

  if v_access_reference_id is null or v_sender_type is null then
    raise exception 'no active access link for this case';
  end if;

  if not private.consume_rate_limit(
    v_case.municipality_id,
    v_user_id,
    'submit_case_question',
    10,
    300
  ) then
    raise exception 'question rate limit exceeded';
  end if;

  select ct.* into strict v_thread
  from public.case_threads ct
  where ct.municipality_id = v_case.municipality_id
    and ct.case_id = v_case.id
    and ct.status = 'open'
  for share;

  select pv.* into v_policy
  from public.municipality_policy_versions pv
  where pv.municipality_id = v_case.municipality_id
    and pv.status = 'active';

  v_message_status := case
    when v_policy.id is not null and v_policy.ai_drafting_enabled
      then 'queued_for_ai'
    else 'needs_manual_answer'
  end;

  insert into public.case_messages (
    municipality_id,
    thread_id,
    case_id,
    sender_type,
    author_user_id,
    source_type,
    visibility,
    body,
    content_sha256,
    status,
    client_request_id,
    published_at
  )
  values (
    v_case.municipality_id,
    v_thread.id,
    v_case.id,
    v_sender_type,
    v_user_id,
    'human',
    'participants',
    v_body,
    pg_catalog.encode(extensions.digest(v_body, 'sha256'), 'hex'),
    'published',
    v_client_request_id,
    now()
  )
  returning id into v_message_id;

  insert into private.message_access_snapshots (
    municipality_id,
    message_id,
    user_id,
    access_basis,
    access_reference_id,
    snapshot
  )
  values (
    v_case.municipality_id,
    v_message_id,
    v_user_id,
    v_access_basis,
    v_access_reference_id,
    jsonb_build_object(
      'captured_at', now(),
      'sender_type', v_sender_type
    )
  );

  insert into public.case_questions (
    municipality_id,
    case_id,
    message_id,
    status
  )
  values (
    v_case.municipality_id,
    v_case.id,
    v_message_id,
    v_message_status
  )
  returning id into v_question_id;

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
    v_case.municipality_id,
    v_case.id,
    'case_question_submitted',
    'participants',
    case when v_sender_type = 'fiscal' then 'staff' else v_sender_type end,
    v_user_id,
    jsonb_build_object(
      'question_id', v_question_id,
      'message_id', v_message_id,
      'ai_queued', v_message_status = 'queued_for_ai'
    )
  );

  update public.fiscal_cases
     set status = 'awaiting_fiscal'
   where municipality_id = v_case.municipality_id
     and id = v_case.id
     and status not in ('resolved', 'closed', 'cancelled');

  if v_message_status = 'queued_for_ai' then
    perform private.enqueue_job(
      v_case.municipality_id,
      'generate_ai_draft',
      'case_question',
      v_question_id,
      jsonb_build_object('case_id', v_case.id, 'question_id', v_question_id),
      'generate-ai-draft:' || v_question_id::text,
      50,
      now(),
      3,
      gen_random_uuid()
    );
  end if;

  return v_question_id;
end;
$$;

create or replace function public.ia_get_ai_job_context(
  p_job_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.jobs%rowtype;
  v_question public.case_questions%rowtype;
  v_message public.case_messages%rowtype;
  v_case public.fiscal_cases%rowtype;
  v_finding public.case_findings%rowtype;
  v_policy public.municipality_policy_versions%rowtype;
  v_prompt public.ai_prompt_versions%rowtype;
  v_release public.knowledge_releases%rowtype;
  v_integration public.integrations%rowtype;
  v_ai_run private.ai_runs%rowtype;
  v_sources jsonb;
  v_search_query tsquery;
  v_source_count integer;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  select j.* into strict v_job
  from private.jobs j
  where j.id = p_job_id
    and j.job_type = 'generate_ai_draft';

  select cq.* into strict v_question
  from public.case_questions cq
  where cq.municipality_id = v_job.municipality_id
    and cq.id = v_job.aggregate_id;

  select cm.* into strict v_message
  from public.case_messages cm
  where cm.municipality_id = v_question.municipality_id
    and cm.id = v_question.message_id;

  select fc.* into strict v_case
  from public.fiscal_cases fc
  where fc.municipality_id = v_question.municipality_id
    and fc.id = v_question.case_id;

  select cf.* into strict v_finding
  from public.case_findings cf
  where cf.municipality_id = v_case.municipality_id
    and cf.case_id = v_case.id;

  if v_case.status in ('resolved', 'closed', 'cancelled') then
    return jsonb_build_object('allowed', false, 'reason', 'case_not_answerable');
  end if;
  if v_question.status not in ('queued_for_ai', 'researching') then
    return jsonb_build_object('allowed', false, 'reason', 'question_not_queued');
  end if;

  select pv.* into v_policy
  from public.municipality_policy_versions pv
  where pv.municipality_id = v_job.municipality_id
    and pv.status = 'active';

  if v_policy.id is null or not v_policy.ai_drafting_enabled then
    return jsonb_build_object('allowed', false, 'reason', 'ai_feature_disabled');
  end if;

  select apv.* into v_prompt
  from public.ai_prompt_versions apv
  join public.ai_prompt_templates apt
    on apt.municipality_id = apv.municipality_id
   and apt.id = apv.prompt_template_id
  where apv.municipality_id = v_job.municipality_id
    and apv.status = 'active'
    and apt.status = 'active'
    and apt.purpose = 'fiscal_response_draft'
  order by apv.version desc
  limit 1;

  if v_prompt.id is null then
    return jsonb_build_object('allowed', false, 'reason', 'active_prompt_missing');
  end if;

  select kr.* into v_release
  from public.knowledge_releases kr
  where kr.municipality_id = v_job.municipality_id
    and kr.status = 'published'
    and kr.tax_scope = 'ISSQN'
    and kr.divergence_scope = 'current_account_balance'
    and (kr.effective_from is null or kr.effective_from <= now())
    and (kr.effective_until is null or kr.effective_until > now())
  order by kr.version desc
  limit 1;

  if v_release.id is null then
    return jsonb_build_object('allowed', false, 'reason', 'published_knowledge_missing');
  end if;

  select i.* into v_integration
  from public.integrations i
  where i.municipality_id = v_job.municipality_id
    and i.integration_type = 'ai_provider'
    and i.status = 'active'
    and nullif(i.non_secret_config ->> 'model', '') is not null
  order by i.updated_at desc
  limit 1;

  if v_integration.id is null then
    return jsonb_build_object('allowed', false, 'reason', 'ai_provider_not_configured');
  end if;

  select ar.* into v_ai_run
  from private.ai_runs ar
  where ar.job_id = v_job.id;

  if v_ai_run.id is null then
    insert into private.ai_runs (
      municipality_id,
      job_id,
      case_id,
      question_id,
      prompt_version_id,
      knowledge_release_id,
      provider_code,
      model,
      status,
      request_sha256
    )
    values (
      v_job.municipality_id,
      v_job.id,
      v_case.id,
      v_question.id,
      v_prompt.id,
      v_release.id,
      v_integration.provider_code,
      v_integration.non_secret_config ->> 'model',
      'started',
      pg_catalog.encode(
        extensions.digest(
          v_message.content_sha256 || ':' ||
          v_finding.content_sha256 || ':' ||
          v_prompt.content_sha256 || ':' ||
          v_release.release_sha256,
          'sha256'
        ),
        'hex'
      )
    )
    returning * into v_ai_run;

    v_search_query := plainto_tsquery('portuguese', left(v_message.body, 4000));

    insert into private.ai_run_sources (
      municipality_id,
      ai_run_id,
      legal_chunk_id,
      rank,
      score,
      citation_snapshot
    )
    select
      v_job.municipality_id,
      v_ai_run.id,
      ranked.legal_chunk_id,
      row_number() over (
        order by ranked.is_primary_basis desc, ranked.score desc, ranked.legal_chunk_id
      )::integer,
      ranked.score,
      jsonb_build_object(
        'legal_chunk_id', ranked.legal_chunk_id,
        'legal_section_id', ranked.legal_section_id,
        'source_version_id', ranked.source_version_id,
        'section_key', ranked.section_key,
        'heading', ranked.heading,
        'source_title', ranked.source_title,
        'official_identifier', ranked.official_identifier,
        'official_url', ranked.official_url,
        'issuing_authority', ranked.issuing_authority,
        'content_sha256', ranked.content_sha256
      )
    from (
      select
        lc.id as legal_chunk_id,
        ls.id as legal_section_id,
        lsv.id as source_version_id,
        ls.section_key,
        ls.heading,
        src.title as source_title,
        src.official_identifier,
        src.official_url,
        src.issuing_authority,
        lc.content_sha256,
        ts_rank_cd(lc.search_vector, v_search_query)::numeric(12,8) as score,
        exists (
          select 1
          from public.rule_legal_basis rlb
          where rlb.municipality_id = v_job.municipality_id
            and rlb.rule_version_id = v_finding.rule_version_id
            and rlb.knowledge_release_id = v_release.id
            and (rlb.legal_section_id is null or rlb.legal_section_id = ls.id)
        ) as is_primary_basis
      from private.legal_chunks lc
      join public.legal_sections ls
        on ls.municipality_id = lc.municipality_id
       and ls.id = lc.legal_section_id
      join public.legal_source_versions lsv
        on lsv.municipality_id = ls.municipality_id
       and lsv.id = ls.source_version_id
      join public.legal_sources src
        on src.municipality_id = lsv.municipality_id
       and src.id = lsv.source_id
      join public.knowledge_release_items kri
        on kri.municipality_id = lsv.municipality_id
       and kri.source_version_id = lsv.id
       and kri.release_id = v_release.id
      where lc.municipality_id = v_job.municipality_id
        and lsv.status = 'published'
        and src.status = 'active'
        and (
          lc.search_vector @@ v_search_query
          or exists (
            select 1
            from public.rule_legal_basis rlb
            where rlb.municipality_id = v_job.municipality_id
              and rlb.rule_version_id = v_finding.rule_version_id
              and rlb.knowledge_release_id = v_release.id
              and (rlb.legal_section_id is null or rlb.legal_section_id = ls.id)
          )
        )
      order by is_primary_basis desc, score desc, lc.id
      limit 12
    ) ranked;

    get diagnostics v_source_count = row_count;
    if v_source_count = 0 then
      update private.ai_runs
         set status = 'blocked_no_sources',
             safe_error_code = 'no_applicable_legal_sources',
             completed_at = now()
       where id = v_ai_run.id;
      return jsonb_build_object(
        'allowed', false,
        'reason', 'no_applicable_legal_sources',
        'ai_run_id', v_ai_run.id
      );
    end if;

    update public.case_questions
       set status = 'researching'
     where municipality_id = v_question.municipality_id
       and id = v_question.id;
  elsif v_ai_run.status <> 'started' then
    return jsonb_build_object(
      'allowed', false,
      'reason', 'ai_run_not_active',
      'ai_run_id', v_ai_run.id
    );
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'legal_chunk_id', ars.legal_chunk_id,
      'rank', ars.rank,
      'citation', ars.citation_snapshot,
      'content', lc.content_text
    )
    order by ars.rank
  )
  into v_sources
  from private.ai_run_sources ars
  join private.legal_chunks lc
    on lc.municipality_id = ars.municipality_id
   and lc.id = ars.legal_chunk_id
  where ars.municipality_id = v_ai_run.municipality_id
    and ars.ai_run_id = v_ai_run.id;

  return jsonb_build_object(
    'allowed', true,
    'ai_run_id', v_ai_run.id,
    'provider_code', v_ai_run.provider_code,
    'model', v_ai_run.model,
    'prompt_version_id', v_prompt.id,
    'system_prompt', v_prompt.system_prompt,
    'output_schema', v_prompt.output_schema,
    'question', v_message.body,
    'case_context', jsonb_build_object(
      'case_number', v_case.case_number,
      'tax_scope', 'ISSQN',
      'divergence_scope', 'current_account_balance',
      'period_start', v_finding.period_start,
      'period_end', v_finding.period_end,
      'assessed_amount', v_finding.assessed_amount,
      'paid_amount', v_finding.paid_amount,
      'other_credits_amount', v_finding.other_credits_amount,
      'difference_amount', v_finding.difference_amount
    ),
    'sources', coalesce(v_sources, '[]'::jsonb)
  );
end;
$$;

create or replace function public.ia_mark_ai_job_blocked(
  p_job_id bigint,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.jobs%rowtype;
  v_question public.case_questions%rowtype;
  v_case_id uuid;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;

  select j.* into strict v_job
  from private.jobs j
  where j.id = p_job_id
    and j.job_type = 'generate_ai_draft';

  select cq.* into strict v_question
  from public.case_questions cq
  where cq.municipality_id = v_job.municipality_id
    and cq.id = v_job.aggregate_id
  for update;

  update private.ai_runs
     set status = case
           when p_reason = 'no_applicable_legal_sources' then 'blocked_no_sources'
           else 'blocked_configuration'
         end,
         safe_error_code = left(coalesce(p_reason, 'ai_blocked'), 120),
         completed_at = now()
   where job_id = v_job.id
     and status = 'started';

  update public.case_questions
     set status = 'needs_manual_answer'
   where municipality_id = v_question.municipality_id
     and id = v_question.id;

  v_case_id := v_question.case_id;
  insert into public.case_events (
    municipality_id,
    case_id,
    event_type,
    visibility,
    actor_type,
    event_data
  )
  values (
    v_question.municipality_id,
    v_case_id,
    'ai_draft_blocked',
    'staff',
    'service',
    jsonb_build_object(
      'question_id', v_question.id,
      'reason', left(coalesce(p_reason, 'ai_blocked'), 120)
    )
  );
end;
$$;

create or replace function public.ia_store_ai_draft(
  p_job_id bigint,
  p_ai_run_id uuid,
  p_body text,
  p_citations jsonb,
  p_limitation_summary text default null,
  p_provider_response_id text default null,
  p_input_tokens integer default null,
  p_output_tokens integer default null,
  p_latency_ms integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.jobs%rowtype;
  v_run private.ai_runs%rowtype;
  v_draft_id uuid;
  v_revision_id uuid;
  v_body text := trim(coalesce(p_body, ''));
  v_body_hash text;
  v_citation jsonb;
  v_chunk_id uuid;
  v_source record;
  v_citation_count integer := 0;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;
  if char_length(v_body) not between 1 and 20000 then
    raise exception 'draft must contain between 1 and 20000 characters';
  end if;
  if jsonb_typeof(p_citations) <> 'array'
     or jsonb_array_length(p_citations) not between 1 and 20 then
    raise exception 'citations must be a non-empty array with at most 20 items';
  end if;

  select j.* into strict v_job
  from private.jobs j
  where j.id = p_job_id
    and j.job_type = 'generate_ai_draft'
    and j.status = 'processing';

  select ar.* into strict v_run
  from private.ai_runs ar
  where ar.id = p_ai_run_id
    and ar.job_id = v_job.id
    and ar.municipality_id = v_job.municipality_id
    and ar.status = 'started'
  for update;

  v_body_hash := pg_catalog.encode(extensions.digest(v_body, 'sha256'), 'hex');

  update private.ai_runs
     set status = 'completed',
         response_sha256 = v_body_hash,
         provider_response_id = nullif(trim(p_provider_response_id), ''),
         input_tokens = p_input_tokens,
         output_tokens = p_output_tokens,
         latency_ms = p_latency_ms,
         completed_at = now()
   where id = v_run.id;

  insert into public.ai_drafts (
    municipality_id,
    case_id,
    question_id,
    ai_run_id,
    status,
    current_revision_number,
    requires_human_attention,
    limitation_summary
  )
  values (
    v_run.municipality_id,
    v_run.case_id,
    v_run.question_id,
    v_run.id,
    'awaiting_fiscal_review',
    1,
    true,
    nullif(trim(p_limitation_summary), '')
  )
  returning id into v_draft_id;

  insert into public.ai_draft_revisions (
    municipality_id,
    draft_id,
    revision_number,
    revision_type,
    body,
    content_sha256
  )
  values (
    v_run.municipality_id,
    v_draft_id,
    1,
    'ai_generated',
    v_body,
    v_body_hash
  )
  returning id into v_revision_id;

  for v_citation in
    select value from jsonb_array_elements(p_citations)
  loop
    v_chunk_id := nullif(v_citation ->> 'legal_chunk_id', '')::uuid;

    select
      ars.legal_chunk_id,
      lc.legal_section_id,
      ls.source_version_id,
      lc.content_text,
      lc.content_sha256,
      ars.citation_snapshot
    into strict v_source
    from private.ai_run_sources ars
    join private.legal_chunks lc
      on lc.municipality_id = ars.municipality_id
     and lc.id = ars.legal_chunk_id
    join public.legal_sections ls
      on ls.municipality_id = lc.municipality_id
     and ls.id = lc.legal_section_id
    where ars.municipality_id = v_run.municipality_id
      and ars.ai_run_id = v_run.id
      and ars.legal_chunk_id = v_chunk_id;

    insert into public.ai_draft_citations (
      municipality_id,
      draft_revision_id,
      legal_section_id,
      source_version_id,
      citation_label,
      quoted_excerpt,
      source_sha256
    )
    values (
      v_run.municipality_id,
      v_revision_id,
      v_source.legal_section_id,
      v_source.source_version_id,
      left(
        coalesce(
          nullif(trim(v_citation ->> 'citation_label'), ''),
          v_source.citation_snapshot ->> 'official_identifier',
          v_source.citation_snapshot ->> 'source_title',
          'Fonte oficial'
        ),
        500
      ),
      left(v_source.content_text, 2000),
      v_source.content_sha256
    )
    on conflict (municipality_id, draft_revision_id, legal_section_id)
    do nothing;

    if found then
      v_citation_count := v_citation_count + 1;
    end if;
  end loop;

  if v_citation_count = 0 then
    raise exception 'no valid citation from the approved source set';
  end if;

  update public.case_questions
     set status = 'awaiting_fiscal'
   where municipality_id = v_run.municipality_id
     and id = v_run.question_id;

  insert into private.monthly_usage_counters (
    municipality_id,
    category,
    period_start,
    quantity
  )
  values (
    v_run.municipality_id,
    'ai_generation',
    date_trunc('month', current_date)::date,
    1
  )
  on conflict (municipality_id, category, period_start)
  do update set
    quantity = private.monthly_usage_counters.quantity + 1,
    updated_at = now();

  insert into public.case_events (
    municipality_id,
    case_id,
    event_type,
    visibility,
    actor_type,
    event_data
  )
  values (
    v_run.municipality_id,
    v_run.case_id,
    'ai_draft_prepared',
    'staff',
    'service',
    jsonb_build_object(
      'question_id', v_run.question_id,
      'draft_id', v_draft_id,
      'revision_id', v_revision_id,
      'citation_count', v_citation_count
    )
  );

  return v_draft_id;
end;
$$;

create or replace function public.ia_edit_ai_draft(
  p_draft_id uuid,
  p_body text,
  p_change_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_draft public.ai_drafts%rowtype;
  v_revision_number integer;
  v_revision_id uuid;
  v_body text := trim(coalesce(p_body, ''));
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if char_length(v_body) not between 1 and 20000 then
    raise exception 'draft must contain between 1 and 20000 characters';
  end if;

  select ad.* into strict v_draft
  from public.ai_drafts ad
  where ad.id = p_draft_id
  for update;

  if not private.can_review_case(v_draft.municipality_id, v_draft.case_id) then
    raise exception 'draft review access denied';
  end if;
  if v_draft.status not in ('awaiting_fiscal_review', 'revision_requested') then
    raise exception 'draft cannot be edited in its current status';
  end if;

  v_revision_number := v_draft.current_revision_number + 1;
  insert into public.ai_draft_revisions (
    municipality_id,
    draft_id,
    revision_number,
    revision_type,
    body,
    content_sha256,
    created_by
  )
  values (
    v_draft.municipality_id,
    v_draft.id,
    v_revision_number,
    'fiscal_edited',
    v_body,
    pg_catalog.encode(extensions.digest(v_body, 'sha256'), 'hex'),
    auth.uid()
  )
  returning id into v_revision_id;

  insert into public.ai_draft_citations (
    municipality_id,
    draft_revision_id,
    legal_section_id,
    source_version_id,
    citation_label,
    quoted_excerpt,
    source_sha256
  )
  select
    c.municipality_id,
    v_revision_id,
    c.legal_section_id,
    c.source_version_id,
    c.citation_label,
    c.quoted_excerpt,
    c.source_sha256
  from public.ai_draft_citations c
  join public.ai_draft_revisions previous
    on previous.municipality_id = c.municipality_id
   and previous.id = c.draft_revision_id
  where previous.municipality_id = v_draft.municipality_id
    and previous.draft_id = v_draft.id
    and previous.revision_number = v_draft.current_revision_number;

  update public.ai_drafts
     set current_revision_number = v_revision_number,
         status = 'awaiting_fiscal_review',
         limitation_summary = coalesce(nullif(trim(p_change_note), ''), limitation_summary)
   where municipality_id = v_draft.municipality_id
     and id = v_draft.id;

  return v_revision_id;
end;
$$;

create or replace function public.ia_review_ai_draft(
  p_draft_id uuid,
  p_revision_id uuid,
  p_decision text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_draft public.ai_drafts%rowtype;
  v_revision public.ai_draft_revisions%rowtype;
  v_membership_id uuid;
  v_review_id uuid;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if p_decision not in ('approved', 'rejected', 'revision_requested') then
    raise exception 'invalid review decision';
  end if;

  select ad.* into strict v_draft
  from public.ai_drafts ad
  where ad.id = p_draft_id
  for update;

  if not private.can_review_case(v_draft.municipality_id, v_draft.case_id) then
    raise exception 'draft review access denied';
  end if;
  if v_draft.status not in ('awaiting_fiscal_review', 'revision_requested') then
    raise exception 'draft cannot be reviewed in its current status';
  end if;

  select adr.* into strict v_revision
  from public.ai_draft_revisions adr
  where adr.municipality_id = v_draft.municipality_id
    and adr.id = p_revision_id
    and adr.draft_id = v_draft.id
    and adr.revision_number = v_draft.current_revision_number;

  select mm.id into strict v_membership_id
  from public.municipality_memberships mm
  where mm.municipality_id = v_draft.municipality_id
    and mm.user_id = auth.uid()
    and mm.status = 'active'
    and mm.role in ('fiscal_auditor', 'supervisor', 'legal_reviewer')
  limit 1;

  if p_decision = 'approved' and not exists (
    select 1
    from public.ai_draft_citations c
    where c.municipality_id = v_draft.municipality_id
      and c.draft_revision_id = v_revision.id
  ) then
    raise exception 'a cited legal source is required for approval';
  end if;

  insert into public.draft_reviews (
    municipality_id,
    draft_id,
    draft_revision_id,
    decision,
    reviewer_membership_id,
    notes,
    approved_content_sha256
  )
  values (
    v_draft.municipality_id,
    v_draft.id,
    v_revision.id,
    p_decision,
    v_membership_id,
    nullif(trim(p_notes), ''),
    case when p_decision = 'approved' then v_revision.content_sha256 else null end
  )
  returning id into v_review_id;

  update public.ai_drafts
     set status = case
       when p_decision = 'approved' then 'approved'
       when p_decision = 'rejected' then 'rejected'
       else 'revision_requested'
     end
   where municipality_id = v_draft.municipality_id
     and id = v_draft.id;

  update public.case_questions
     set status = case
       when p_decision = 'approved' then 'awaiting_fiscal'
       when p_decision = 'rejected' then 'needs_manual_answer'
       else 'awaiting_fiscal'
     end
   where municipality_id = v_draft.municipality_id
     and id = v_draft.question_id;

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
    v_draft.municipality_id,
    v_draft.case_id,
    'ai_draft_reviewed',
    'staff',
    'staff',
    auth.uid(),
    jsonb_build_object(
      'draft_id', v_draft.id,
      'revision_id', v_revision.id,
      'decision', p_decision
    )
  );

  return v_review_id;
end;
$$;

create or replace function public.ia_publish_approved_response(
  p_draft_id uuid,
  p_client_request_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_draft public.ai_drafts%rowtype;
  v_revision public.ai_draft_revisions%rowtype;
  v_review public.draft_reviews%rowtype;
  v_thread_id uuid;
  v_message_id uuid;
  v_client_request_id text := nullif(trim(coalesce(p_client_request_id, '')), '');
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if v_client_request_id is null or char_length(v_client_request_id) > 200 then
    raise exception 'a valid client_request_id is required';
  end if;

  select ad.* into strict v_draft
  from public.ai_drafts ad
  where ad.id = p_draft_id
  for update;

  if not private.can_review_case(v_draft.municipality_id, v_draft.case_id) then
    raise exception 'draft publication access denied';
  end if;

  if v_draft.status = 'published' then
    select cm.id into strict v_message_id
    from public.case_messages cm
    join public.ai_draft_revisions adr
      on adr.municipality_id = cm.municipality_id
     and adr.id = cm.source_draft_revision_id
    where adr.municipality_id = v_draft.municipality_id
      and adr.draft_id = v_draft.id;
    return v_message_id;
  end if;
  if v_draft.status <> 'approved' then
    raise exception 'only an approved draft can be published';
  end if;

  select adr.* into strict v_revision
  from public.ai_draft_revisions adr
  where adr.municipality_id = v_draft.municipality_id
    and adr.draft_id = v_draft.id
    and adr.revision_number = v_draft.current_revision_number;

  select dr.* into strict v_review
  from public.draft_reviews dr
  where dr.municipality_id = v_draft.municipality_id
    and dr.draft_id = v_draft.id
    and dr.draft_revision_id = v_revision.id
    and dr.decision = 'approved';

  if v_review.approved_content_sha256 <> v_revision.content_sha256 then
    raise exception 'approved content hash mismatch';
  end if;

  select ct.id into strict v_thread_id
  from public.case_threads ct
  where ct.municipality_id = v_draft.municipality_id
    and ct.case_id = v_draft.case_id
    and ct.status = 'open';

  insert into public.case_messages (
    municipality_id,
    thread_id,
    case_id,
    sender_type,
    author_user_id,
    source_type,
    visibility,
    body,
    content_sha256,
    status,
    client_request_id,
    published_at,
    source_draft_revision_id
  )
  values (
    v_draft.municipality_id,
    v_thread_id,
    v_draft.case_id,
    'fiscal',
    auth.uid(),
    'approved_ai_draft',
    'participants',
    v_revision.body,
    v_revision.content_sha256,
    'published',
    v_client_request_id,
    now(),
    v_revision.id
  )
  returning id into v_message_id;

  update public.ai_drafts
     set status = 'published'
   where municipality_id = v_draft.municipality_id
     and id = v_draft.id;

  update public.case_questions
     set status = 'answered',
         answered_at = now()
   where municipality_id = v_draft.municipality_id
     and id = v_draft.question_id;

  update public.fiscal_cases
     set status = 'awaiting_taxpayer'
   where municipality_id = v_draft.municipality_id
     and id = v_draft.case_id
     and status not in ('resolved', 'closed', 'cancelled');

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
    v_draft.municipality_id,
    v_draft.case_id,
    'approved_response_published',
    'participants',
    'staff',
    auth.uid(),
    jsonb_build_object(
      'question_id', v_draft.question_id,
      'draft_id', v_draft.id,
      'revision_id', v_revision.id,
      'message_id', v_message_id,
      'approved_content_sha256', v_revision.content_sha256
    )
  );

  return v_message_id;
end;
$$;

revoke all on function public.ia_get_ai_job_context(bigint)
  from public, anon, authenticated;
revoke all on function public.ia_mark_ai_job_blocked(bigint, text)
  from public, anon, authenticated;
revoke all on function public.ia_store_ai_draft(
  bigint, uuid, text, jsonb, text, text, integer, integer, integer
) from public, anon, authenticated;

grant execute on function public.ia_get_ai_job_context(bigint) to service_role;
grant execute on function public.ia_mark_ai_job_blocked(bigint, text) to service_role;
grant execute on function public.ia_store_ai_draft(
  bigint, uuid, text, jsonb, text, text, integer, integer, integer
) to service_role;

revoke all on function public.ia_submit_case_question(uuid, text, text)
  from public, anon;
revoke all on function public.ia_edit_ai_draft(uuid, text, text)
  from public, anon;
revoke all on function public.ia_review_ai_draft(uuid, uuid, text, text)
  from public, anon;
revoke all on function public.ia_publish_approved_response(uuid, text)
  from public, anon;

grant execute on function public.ia_submit_case_question(uuid, text, text)
  to authenticated, service_role;
grant execute on function public.ia_edit_ai_draft(uuid, text, text)
  to authenticated, service_role;
grant execute on function public.ia_review_ai_draft(uuid, uuid, text, text)
  to authenticated, service_role;
grant execute on function public.ia_publish_approved_response(uuid, text)
  to authenticated, service_role;

commit;

