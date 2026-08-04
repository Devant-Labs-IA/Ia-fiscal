-- IA Fiscal: harden batch idempotency and keep participant responses fail-closed.
-- Corrects: batch execution-mode/idempotency, manual-response replay,
-- and fail-closed response publication outside homologation.

begin;

alter table public.case_opening_batches
  add column if not exists request_sha256 text;

alter table public.case_opening_batches
  drop constraint if exists case_opening_batches_request_sha256_ck;
alter table public.case_opening_batches
  add constraint case_opening_batches_request_sha256_ck
  check (request_sha256 is null or request_sha256 ~ '^[a-f0-9]{64}$');

alter table public.case_opening_batches
  drop constraint if exists case_opening_batches_idempotency_key_ck;
alter table public.case_opening_batches
  add constraint case_opening_batches_idempotency_key_ck
  check (char_length(btrim(idempotency_key)) between 1 and 200);

-- Reconcile legacy rows to the source run. request_sha256 intentionally stays
-- NULL for legacy batches because the original caller payload cannot be
-- reconstructed safely from the selected/limited items.
update public.case_opening_batches b
set execution_mode = dr.execution_mode
from public.detection_runs dr
where dr.municipality_id = b.municipality_id
  and dr.id = b.detection_run_id
  and b.execution_mode is distinct from dr.execution_mode;

comment on column public.case_opening_batches.request_sha256 is
  'SHA-256 of the canonical caller payload for strict idempotency; NULL means legacy/non-replayable.';

-- Tenant-scoped, database-side sandbox gate. It defaults to false and cannot
-- be changed by authenticated/service_role under the current table grants.
-- Live publication remains impossible even when this sandbox flag is true.
alter table public.municipality_portal_settings
  add column if not exists sandbox_response_publication_enabled boolean
  not null default false;

comment on column public.municipality_portal_settings.sandbox_response_publication_enabled is
  'Fail-closed gate for synthetic participant responses in homologation; never enables live/external delivery.';

-- The legacy trigger referenced selected_count, a column that never existed in
-- case_opening_batches. Keep the intended normalization on requested_count so
-- batch creation and later status updates remain executable.
create or replace function private.normalize_case_opening_batch_counts()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  select
    count(*)::integer,
    count(*) filter (where bi.status = 'opened')::integer,
    count(*) filter (where bi.status in ('blocked', 'excluded'))::integer
  into
    new.requested_count,
    new.opened_count,
    new.blocked_count
  from public.case_opening_batch_items bi
  where bi.municipality_id = new.municipality_id
    and bi.batch_id = new.id;

  if old.status = 'processing'
     and new.status = 'processing'
     and not exists (
       select 1
       from public.case_opening_batch_items bi
       where bi.municipality_id = new.municipality_id
         and bi.batch_id = new.id
         and bi.status in ('approved', 'revalidating')
     ) then
    new.status := 'completed';
  end if;

  return new;
end;
$$;

-- Revalidate assignment targets at the final write boundary as well as at
-- batch submission. This closes the time-of-check/time-of-use interval while
-- a batch waits for approval or worker execution.
create or replace function private.validate_case_assignment_membership()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.municipality_memberships mm
    where mm.municipality_id = new.municipality_id
      and mm.id = new.membership_id
      and mm.status = 'active'
      and mm.valid_from <= now()
      and (mm.valid_until is null or mm.valid_until > now())
  ) then
    raise exception 'case assignment requires a currently valid municipal membership';
  end if;
  return new;
end;
$$;

drop trigger if exists case_assignments_validate_membership
  on public.case_assignments;
create trigger case_assignments_validate_membership
  before insert or update of municipality_id, membership_id
  on public.case_assignments
  for each row execute function private.validate_case_assignment_membership();

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
  v_user_id uuid := auth.uid();
  v_run public.detection_runs%rowtype;
  v_policy public.municipality_policy_versions%rowtype;
  v_existing public.case_opening_batches%rowtype;
  v_requested_ids uuid[];
  v_request_payload jsonb;
  v_request_sha256 text;
  v_idempotency_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_batch_id uuid;
  v_item_count integer;
begin
  if v_user_id is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if v_idempotency_key is null or char_length(v_idempotency_key) > 200 then
    raise exception 'valid idempotency key required';
  end if;

  select dr.* into strict v_run
  from public.detection_runs dr
  where dr.id = p_detection_run_id
    and dr.status = 'completed'
  for share;

  if not private.has_municipality_role(
    v_run.municipality_id,
    array['supervisor']::text[]
  ) then
    raise exception 'supervisor with aal2 required';
  end if;

  if not exists (
    select 1
    from public.municipalities m
    where m.id = v_run.municipality_id
      and (
        (v_run.execution_mode = 'homologation_test' and m.status = 'homologation')
        or (v_run.execution_mode = 'live' and m.status = 'active')
      )
  ) then
    raise exception 'detection run execution mode is incompatible with municipality status';
  end if;

  select coalesce(array_agg(x.id order by x.id), array[]::uuid[])
    into v_requested_ids
  from (
    select distinct u.id
    from unnest(coalesce(p_divergence_ids, array[]::uuid[])) as u(id)
  ) x;

  v_request_payload := jsonb_build_object(
    'contract_version', 1,
    'detection_run_id', v_run.id,
    'divergence_ids', to_jsonb(v_requested_ids),
    'assigned_membership_id', to_jsonb(p_assigned_membership_id)
  );
  v_request_sha256 := pg_catalog.encode(
    extensions.digest(v_request_payload::text, 'sha256'),
    'hex'
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'ia_create_case_opening_batch:' || v_run.municipality_id::text || ':' || v_idempotency_key,
      0
    )
  );

  select b.* into v_existing
  from public.case_opening_batches b
  where b.municipality_id = v_run.municipality_id
    and b.idempotency_key = v_idempotency_key
  for update;

  if found then
    if v_existing.request_sha256 is null then
      raise exception 'legacy idempotency record cannot be replayed safely';
    end if;
    if v_existing.submitted_by is distinct from v_user_id then
      raise exception 'idempotency key owner mismatch';
    end if;
    if v_existing.request_sha256 <> v_request_sha256 then
      raise exception 'idempotency key payload mismatch';
    end if;
    return v_existing.id;
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
      and mm.valid_from <= now()
      and (mm.valid_until is null or mm.valid_until > now())
  ) then
    raise exception 'assigned fiscal membership is not currently valid';
  end if;

  if cardinality(v_requested_ids) > 0 and (
    select count(*)
    from public.divergences d
    where d.municipality_id = v_run.municipality_id
      and d.detection_run_id = v_run.id
      and d.execution_mode = v_run.execution_mode
      and d.status = 'pending_revalidation'
      and d.id = any(v_requested_ids)
  ) <> cardinality(v_requested_ids) then
    raise exception 'one or more requested divergences are outside the current run, mode, or state';
  end if;

  insert into public.case_opening_batches (
    municipality_id,
    detection_run_id,
    policy_version_id,
    status,
    idempotency_key,
    request_sha256,
    execution_mode,
    submitted_by,
    submitted_at
  ) values (
    v_run.municipality_id,
    v_run.id,
    v_policy.id,
    'submitted',
    v_idempotency_key,
    v_request_sha256,
    v_run.execution_mode,
    v_user_id,
    now()
  )
  returning id into v_batch_id;

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
    and d.execution_mode = v_run.execution_mode
    and d.status = 'pending_revalidation'
    and (
      cardinality(v_requested_ids) = 0
      or d.id = any(v_requested_ids)
    )
  order by d.priority_score desc, d.difference_amount desc, d.id
  limit v_policy.top_debtors_limit;

  get diagnostics v_item_count = row_count;
  if v_item_count <= 0 then
    raise exception 'batch has no eligible divergences';
  end if;

  update public.case_opening_batches b
  set requested_count = v_item_count
  where b.municipality_id = v_run.municipality_id
    and b.id = v_batch_id;

  return v_batch_id;
end;
$$;

-- The generic processor is live-only. Homologation must continue through
-- ia_execute_homologation_case_test, which never enqueues external delivery.
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
  if exists (
    select 1
    from public.case_opening_batch_items bi
    left join public.municipality_memberships mm
      on mm.municipality_id = bi.municipality_id
     and mm.id = bi.assigned_membership_id
    where bi.municipality_id = v_batch.municipality_id
      and bi.batch_id = v_batch.id
      and bi.assigned_membership_id is not null
      and (
        mm.id is null
        or mm.status <> 'active'
        or mm.valid_from > now()
        or (mm.valid_until is not null and mm.valid_until <= now())
      )
  ) then
    raise exception 'batch contains an assignment to a membership that is no longer valid';
  end if;
  if v_batch.execution_mode <> 'live' then
    raise exception 'homologation batches require the sandbox case-test workflow';
  end if;
  if not exists (
    select 1 from public.municipalities m
    where m.id = v_batch.municipality_id and m.status = 'active'
  ) then
    raise exception 'live batch approval requires an active municipality';
  end if;
  if exists (
    select 1
    from public.case_opening_batch_items bi
    join public.divergences d
      on d.municipality_id = bi.municipality_id
     and d.id = bi.divergence_id
    where bi.municipality_id = v_batch.municipality_id
      and bi.batch_id = v_batch.id
      and d.execution_mode <> v_batch.execution_mode
  ) then
    raise exception 'batch contains a divergence from another execution mode';
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

-- Fail closed for every live case. A later, separately approved migration may
-- add a database-side global/tenant control mirrored from
-- IA_EXTERNAL_DELIVERY_ENABLED. Homologation publication is also disabled by
-- default and must be enabled explicitly for a synthetic test window.
create or replace function private.case_response_publication_allowed(
  p_municipality_id uuid,
  p_execution_mode text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p_execution_mode = 'homologation_test'
       and m.status = 'homologation'
       and ps.sandbox_response_publication_enabled
    from public.municipalities m
    join public.municipality_portal_settings ps
      on ps.municipality_id = m.id
    where m.id = p_municipality_id
  ), false);
$$;

revoke all on function private.case_response_publication_allowed(uuid, text)
  from public, anon, authenticated, service_role;

create or replace function public.ia_publish_manual_response(
  p_question_id uuid,
  p_body text,
  p_client_request_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_question public.case_questions%rowtype;
  v_execution_mode text;
  v_thread_id uuid;
  v_message_id uuid;
  v_existing_author_user_id uuid;
  v_existing_parent_message_id uuid;
  v_existing_content_sha256 text;
  v_existing_sender_type text;
  v_existing_source_type text;
  v_existing_visibility text;
  v_body text := trim(coalesce(p_body, ''));
  v_content_sha256 text;
  v_client_request_id text := nullif(trim(coalesce(p_client_request_id, '')), '');
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if char_length(v_body) not between 1 and 20000 then
    raise exception 'response must contain between 1 and 20000 characters';
  end if;
  if v_client_request_id is null or char_length(v_client_request_id) > 200 then
    raise exception 'valid client_request_id required';
  end if;
  v_content_sha256 := pg_catalog.encode(extensions.digest(v_body, 'sha256'), 'hex');

  select cq.* into strict v_question
  from public.case_questions cq
  where cq.id = p_question_id
  for update;

  if not private.can_review_case(v_question.municipality_id, v_question.case_id) then
    raise exception 'response access denied';
  end if;

  select fc.execution_mode into strict v_execution_mode
  from public.fiscal_cases fc
  where fc.municipality_id = v_question.municipality_id
    and fc.id = v_question.case_id
  for share;

  if not private.case_response_publication_allowed(
    v_question.municipality_id,
    v_execution_mode
  ) then
    raise exception 'case response publication is disabled outside homologation';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'ia_publish_manual_response:' || v_question.municipality_id::text || ':' ||
      v_question.case_id::text || ':' || v_client_request_id,
      0
    )
  );

  select
    cm.id,
    cm.author_user_id,
    cm.parent_message_id,
    cm.content_sha256,
    cm.sender_type,
    cm.source_type,
    cm.visibility
  into
    v_message_id,
    v_existing_author_user_id,
    v_existing_parent_message_id,
    v_existing_content_sha256,
    v_existing_sender_type,
    v_existing_source_type,
    v_existing_visibility
  from public.case_messages cm
  where cm.municipality_id = v_question.municipality_id
    and cm.case_id = v_question.case_id
    and cm.client_request_id = v_client_request_id;

  if v_message_id is not null then
    if v_existing_author_user_id is distinct from auth.uid()
       or v_existing_parent_message_id is distinct from v_question.message_id
       or v_existing_content_sha256 is distinct from v_content_sha256
       or v_existing_sender_type is distinct from 'fiscal'
       or v_existing_source_type is distinct from 'human'
       or v_existing_visibility is distinct from 'participants' then
      raise exception 'idempotency key owner or payload mismatch';
    end if;
    return v_message_id;
  end if;

  if v_question.status in ('answered', 'closed') then
    raise exception 'question already answered';
  end if;

  select ct.id into strict v_thread_id
  from public.case_threads ct
  where ct.municipality_id = v_question.municipality_id
    and ct.case_id = v_question.case_id
    and ct.status = 'open';

  insert into public.case_messages (
    municipality_id, thread_id, case_id, parent_message_id, sender_type,
    author_user_id, source_type, visibility, body, content_sha256, status,
    client_request_id, published_at
  ) values (
    v_question.municipality_id, v_thread_id, v_question.case_id,
    v_question.message_id, 'fiscal', auth.uid(), 'human', 'participants',
    v_body, v_content_sha256, 'published', v_client_request_id, now()
  ) returning id into v_message_id;

  update public.case_questions
  set status = 'answered', handling_mode = 'human', answered_at = now(),
      last_activity_at = now()
  where municipality_id = v_question.municipality_id and id = v_question.id;

  update public.fiscal_cases
  set status = 'awaiting_taxpayer'
  where municipality_id = v_question.municipality_id
    and id = v_question.case_id
    and status not in ('resolved', 'closed', 'cancelled');

  insert into public.case_events (
    municipality_id, case_id, event_type, visibility, actor_type,
    actor_user_id, event_data
  ) values (
    v_question.municipality_id, v_question.case_id,
    'manual_response_published', 'participants', 'staff', auth.uid(),
    jsonb_build_object(
      'question_id', v_question.id,
      'message_id', v_message_id,
      'sandbox_only', true
    )
  );

  return v_message_id;
end;
$$;

-- Preserve the existing approved-response workflow, but add the same database
-- boundary before either replay or publication. The rest of the body remains
-- byte-for-byte equivalent to the current definition.
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
  v_execution_mode text;
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

  select fc.execution_mode into strict v_execution_mode
  from public.fiscal_cases fc
  where fc.municipality_id = v_draft.municipality_id
    and fc.id = v_draft.case_id
  for share;

  if not private.case_response_publication_allowed(
    v_draft.municipality_id,
    v_execution_mode
  ) then
    raise exception 'case response publication is disabled outside homologation';
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
    municipality_id, thread_id, case_id, sender_type, author_user_id,
    source_type, visibility, body, content_sha256, status, client_request_id,
    published_at, source_draft_revision_id
  ) values (
    v_draft.municipality_id, v_thread_id, v_draft.case_id, 'fiscal', auth.uid(),
    'approved_ai_draft', 'participants', v_revision.body,
    v_revision.content_sha256, 'published', v_client_request_id, now(), v_revision.id
  ) returning id into v_message_id;

  update public.ai_drafts set status = 'published'
  where municipality_id = v_draft.municipality_id and id = v_draft.id;

  update public.case_questions set status = 'answered', answered_at = now()
  where municipality_id = v_draft.municipality_id and id = v_draft.question_id;

  update public.fiscal_cases set status = 'awaiting_taxpayer'
  where municipality_id = v_draft.municipality_id
    and id = v_draft.case_id
    and status not in ('resolved', 'closed', 'cancelled');

  insert into public.case_events (
    municipality_id, case_id, event_type, visibility, actor_type,
    actor_user_id, event_data
  ) values (
    v_draft.municipality_id, v_draft.case_id,
    'approved_response_published', 'participants', 'staff', auth.uid(),
    jsonb_build_object(
      'question_id', v_draft.question_id,
      'draft_id', v_draft.id,
      'revision_id', v_revision.id,
      'message_id', v_message_id,
      'approved_content_sha256', v_revision.content_sha256,
      'sandbox_only', true
    )
  );

  return v_message_id;
end;
$$;

revoke all on function public.ia_create_case_opening_batch(uuid, uuid[], text, uuid)
  from public, anon, service_role;
revoke all on function public.ia_approve_case_opening_batch(uuid, text)
  from public, anon, service_role;
revoke all on function public.ia_publish_manual_response(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_publish_approved_response(uuid, text)
  from public, anon, authenticated, service_role;

grant execute on function public.ia_create_case_opening_batch(uuid, uuid[], text, uuid)
  to authenticated;
grant execute on function public.ia_approve_case_opening_batch(uuid, text)
  to authenticated;
-- Deliberately no authenticated/service_role grant for either response
-- publication RPC. A future migration may grant a dedicated executor only
-- after the global external-delivery control and legal gate are approved.

notify pgrst, 'reload schema';

commit;
