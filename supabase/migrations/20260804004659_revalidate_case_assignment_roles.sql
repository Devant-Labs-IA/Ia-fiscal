-- IA Fiscal: revalidate assignment roles at approval, worker and case boundaries.

begin;

set local lock_timeout = '5s';
lock table public.case_opening_batch_items in share row exclusive mode;
lock table public.case_assignments in share row exclusive mode;

do $preflight$
begin
  if exists (
    select 1
    from public.case_opening_batch_items bi
    where bi.status in ('selected', 'approved', 'revalidating')
    group by bi.municipality_id, bi.divergence_id
    having count(*) > 1
  ) then
    raise exception 'active divergence reservations must be reconciled before hardening';
  end if;
  if exists (
    select 1
    from public.case_assignments ca
    join public.municipality_memberships mm
      on mm.municipality_id = ca.municipality_id
     and mm.id = ca.membership_id
    where ca.status = 'active'
      and (
        (ca.assignment_role = 'responsible_fiscal' and mm.role <> 'fiscal_auditor')
        or (
          ca.assignment_role = 'reviewer'
          and mm.role not in ('fiscal_auditor', 'supervisor', 'legal_reviewer')
        )
        or (ca.assignment_role = 'supervisor' and mm.role <> 'supervisor')
      )
  ) then
    raise exception 'active case assignments must be reconciled before role hardening';
  end if;
end
$preflight$;

create or replace function private.validate_case_assignment_membership()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_membership_role text;
begin
  if new.status <> 'active' then
    return new;
  end if;

  select mm.role into v_membership_role
  from public.municipality_memberships mm
  where mm.municipality_id = new.municipality_id
    and mm.id = new.membership_id
    and mm.status = 'active'
    and mm.valid_from <= now()
    and (mm.valid_until is null or mm.valid_until > now())
  for share;

  if v_membership_role is null then
    raise exception 'case assignment requires a currently valid municipal membership';
  end if;
  if new.assignment_role = 'responsible_fiscal'
     and v_membership_role <> 'fiscal_auditor' then
    raise exception 'case assignment role is incompatible with the municipal membership';
  end if;
  if new.assignment_role = 'reviewer'
     and v_membership_role not in ('fiscal_auditor', 'supervisor', 'legal_reviewer') then
    raise exception 'case assignment role is incompatible with the municipal membership';
  end if;
  if new.assignment_role = 'supervisor' and v_membership_role <> 'supervisor' then
    raise exception 'supervisor assignment requires a supervisor membership';
  end if;
  return new;
end;
$$;

drop trigger if exists case_assignments_validate_membership
  on public.case_assignments;
create trigger case_assignments_validate_membership
  before insert or update of municipality_id, membership_id, assignment_role, status
  on public.case_assignments
  for each row execute function private.validate_case_assignment_membership();

-- A divergence may be selected by only one operationally active batch. The
-- partial unique index is the race-safe reservation boundary for concurrent
-- supervisors; terminal items can be selected again only while the source
-- divergence itself remains eligible.
create unique index case_opening_batch_items_active_divergence_uq
  on public.case_opening_batch_items (municipality_id, divergence_id)
  where status in ('selected', 'approved', 'revalidating');

create or replace function private.validate_batch_item_assigned_membership()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_divergence_status text;
  v_membership_role text;
begin
  if new.status in ('selected', 'approved', 'revalidating') then
    select d.status into v_divergence_status
    from public.divergences d
    where d.municipality_id = new.municipality_id
      and d.id = new.divergence_id
    for update;

    if v_divergence_status is distinct from 'pending_revalidation' then
      raise exception 'active batch item requires a pending-revalidation divergence';
    end if;
  end if;

  if new.assigned_membership_id is not null
     and new.status in ('selected', 'approved', 'revalidating') then
    select mm.role into v_membership_role
    from public.municipality_memberships mm
    where mm.municipality_id = new.municipality_id
      and mm.id = new.assigned_membership_id
      and mm.status = 'active'
      and mm.valid_from <= now()
      and (mm.valid_until is null or mm.valid_until > now())
    for share;

    if v_membership_role is distinct from 'fiscal_auditor' then
      raise exception 'batch item requires a currently valid fiscal-auditor membership';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists case_opening_batch_items_validate_assignment
  on public.case_opening_batch_items;
create trigger case_opening_batch_items_validate_assignment
  before insert or update of municipality_id, divergence_id, assigned_membership_id, status
  on public.case_opening_batch_items
  for each row execute function private.validate_batch_item_assigned_membership();

create or replace function private.validate_batch_processing_assignments()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Preserve one canonical lock order across creation, approval and workers:
  -- active divergences first, then memberships, each ordered by UUID.
  perform d.id
  from public.case_opening_batch_items bi
  join public.divergences d
    on d.municipality_id = bi.municipality_id
   and d.id = bi.divergence_id
  where bi.municipality_id = new.municipality_id
    and bi.batch_id = new.id
    and bi.status in ('selected', 'approved', 'revalidating')
  order by d.id
  for update of d;

  -- Hold membership rows through the approval/worker transaction. A
  -- concurrent role, status, or validity change must wait and then observe
  -- the completed transition instead of racing the last authorization check.
  perform mm.id
  from public.case_opening_batch_items bi
  join public.municipality_memberships mm
    on mm.municipality_id = bi.municipality_id
   and mm.id = bi.assigned_membership_id
  where bi.municipality_id = new.municipality_id
    and bi.batch_id = new.id
    and bi.status in ('selected', 'approved', 'revalidating')
    and bi.assigned_membership_id is not null
  order by mm.id
  for share of mm;

  if new.status = 'processing'
     and exists (
       select 1
       from public.case_opening_batch_items bi
       left join public.municipality_memberships mm
         on mm.municipality_id = bi.municipality_id
        and mm.id = bi.assigned_membership_id
       where bi.municipality_id = new.municipality_id
         and bi.batch_id = new.id
         and bi.status in ('selected', 'approved', 'revalidating')
         and bi.assigned_membership_id is not null
         and (
           mm.id is null
           or mm.role <> 'fiscal_auditor'
           or mm.status <> 'active'
           or mm.valid_from > now()
           or (mm.valid_until is not null and mm.valid_until <= now())
         )
     ) then
    raise exception 'batch processing requires every assignment to retain a valid fiscal-auditor membership';
  end if;
  return new;
end;
$$;

drop trigger if exists case_opening_batches_b_validate_assignments
  on public.case_opening_batches;
create trigger case_opening_batches_b_validate_assignments
  before update of status, execution_mode
  on public.case_opening_batches
  for each row execute function private.validate_batch_processing_assignments();

-- Preserve supervisor/legal-reviewer question handling without labelling
-- those memberships as the responsible fiscal. The externally visible RPC
-- signature and idempotency contract remain unchanged.
create or replace function public.ia_claim_case_question(
  p_question_id uuid,
  p_expected_municipality_id uuid,
  p_expected_membership_id uuid,
  p_handling_mode text default 'human'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_question public.case_questions%rowtype;
  v_membership_id uuid;
  v_membership_role text;
  v_assignment_role text;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if p_expected_municipality_id is null or p_expected_membership_id is null then
    raise exception 'active municipal context required';
  end if;
  if p_handling_mode is null or p_handling_mode not in ('human', 'ai_assist') then
    raise exception 'invalid handling mode';
  end if;

  select cq.*
    into strict v_question
  from public.case_questions cq
  where cq.municipality_id = p_expected_municipality_id
    and cq.id = p_question_id
  for update;

  v_membership_id := private.current_municipality_membership_id(
    v_question.municipality_id,
    array['fiscal_auditor', 'supervisor', 'legal_reviewer']::text[]
  );
  if v_membership_id is null then
    raise exception 'current municipal fiscal role required';
  end if;
  if v_membership_id <> p_expected_membership_id then
    raise exception 'active municipal membership changed';
  end if;

  select mm.role into strict v_membership_role
  from public.municipality_memberships mm
  where mm.municipality_id = v_question.municipality_id
    and mm.id = v_membership_id
    and mm.status = 'active'
    and mm.valid_from <= now()
    and (mm.valid_until is null or mm.valid_until > now())
  for share;
  v_assignment_role := case
    when v_membership_role = 'fiscal_auditor' then 'responsible_fiscal'
    else 'reviewer'
  end;

  if not private.can_view_case_staff(v_question.municipality_id, v_question.case_id) then
    raise exception 'case claim access denied';
  end if;
  if v_question.status in ('answered', 'closed') then
    raise exception 'question is already closed';
  end if;

  if v_question.assigned_membership_id = v_membership_id
     and v_question.handling_mode = p_handling_mode then
    return v_membership_id;
  end if;
  if v_question.assigned_membership_id is not null
     and v_question.assigned_membership_id <> v_membership_id then
    raise exception 'question already claimed';
  end if;

  if not exists (
    select 1
    from public.case_assignments ca
    where ca.municipality_id = v_question.municipality_id
      and ca.case_id = v_question.case_id
      and ca.membership_id = v_membership_id
      and ca.status = 'active'
  ) then
    insert into public.case_assignments (
      municipality_id,
      case_id,
      membership_id,
      assignment_role,
      status,
      assigned_by
    ) values (
      v_question.municipality_id,
      v_question.case_id,
      v_membership_id,
      v_assignment_role,
      'active',
      v_user_id
    );
  end if;

  update public.case_questions
     set status = 'awaiting_fiscal',
         assigned_membership_id = v_membership_id,
         handling_mode = p_handling_mode,
         claimed_at = coalesce(claimed_at, now()),
         last_activity_at = now()
   where municipality_id = v_question.municipality_id
     and id = v_question.id;

  insert into public.case_events (
    municipality_id,
    case_id,
    event_type,
    visibility,
    actor_type,
    actor_user_id,
    event_data
  ) values (
    v_question.municipality_id,
    v_question.case_id,
    'case_question_claimed',
    'staff',
    'staff',
    v_user_id,
    jsonb_build_object(
      'question_id', v_question.id,
      'membership_id', v_membership_id,
      'handling_mode', p_handling_mode
    )
  );

  return v_membership_id;
end;
$$;

revoke all on function private.validate_case_assignment_membership()
  from public, anon, authenticated, service_role;
revoke all on function private.validate_batch_item_assigned_membership()
  from public, anon, authenticated, service_role;
revoke all on function private.validate_batch_processing_assignments()
  from public, anon, authenticated, service_role;

revoke all on function public.ia_claim_case_question(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_claim_case_question(uuid, uuid, uuid, text)
  to authenticated;

notify pgrst, 'reload schema';

commit;
