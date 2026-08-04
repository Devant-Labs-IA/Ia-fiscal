-- IA Fiscal: require AAL2 at every regulated case-access boundary and make
-- repeated question claims side-effect free for the same fiscal and mode.

begin;

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
     and private.is_aal2()
     and exists (
       select 1
       from public.municipality_memberships mm
       where mm.municipality_id = p_municipality_id
         and mm.user_id = (select auth.uid())
         and mm.status = 'active'
         and mm.valid_from <= now()
         and (mm.valid_until is null or mm.valid_until > now())
         and (p_roles is null or mm.role = any(p_roles))
     );
$$;

comment on function private.has_municipality_role(uuid, text[]) is
  'Checks an AAL2-authenticated user current municipal membership. Platform administration never grants municipal fiscal authority.';


create or replace function private.current_municipality_membership_id(
  p_municipality_id uuid,
  p_roles text[] default null
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select mm.id
  from public.municipality_memberships mm
  where (select auth.uid()) is not null
    and private.is_aal2()
    and mm.municipality_id = p_municipality_id
    and mm.user_id = (select auth.uid())
    and mm.status = 'active'
    and mm.valid_from <= now()
    and (mm.valid_until is null or mm.valid_until > now())
    and (p_roles is null or mm.role = any(p_roles))
  order by mm.valid_from desc, mm.id
  limit 1;
$$;

comment on function private.current_municipality_membership_id(uuid, text[]) is
  'Returns a current municipal membership only for an AAL2-authenticated user, without platform-administrator bypass.';


create or replace function private.can_view_case_staff(
  p_municipality_id uuid,
  p_case_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
     and private.is_aal2()
     and exists (
       select 1
       from public.fiscal_cases fc
       where fc.municipality_id = p_municipality_id
         and fc.id = p_case_id
         and (
           private.current_municipality_membership_id(
             p_municipality_id,
             array['municipal_admin', 'supervisor', 'legal_reviewer']::text[]
           ) is not null
           or (
             private.current_municipality_membership_id(
               p_municipality_id,
               array['fiscal_auditor']::text[]
             ) is not null
             and (
               fc.confidentiality = 'internal'
               or exists (
                 select 1
                 from public.case_assignments ca
                 where ca.municipality_id = fc.municipality_id
                   and ca.case_id = fc.id
                   and ca.status = 'active'
                   and ca.membership_id = private.current_municipality_membership_id(
                     p_municipality_id,
                     array['fiscal_auditor']::text[]
                   )
               )
             )
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
  select (select auth.uid()) is not null
     and private.is_aal2()
     and (
       private.current_municipality_membership_id(
         p_municipality_id,
         array['supervisor', 'legal_reviewer']::text[]
       ) is not null
       or (
         private.current_municipality_membership_id(
           p_municipality_id,
           array['fiscal_auditor']::text[]
         ) is not null
         and exists (
           select 1
           from public.case_assignments ca
           where ca.municipality_id = p_municipality_id
             and ca.case_id = p_case_id
             and ca.status = 'active'
             and ca.assignment_role in ('responsible_fiscal', 'reviewer')
             and ca.membership_id = private.current_municipality_membership_id(
               p_municipality_id,
               array['fiscal_auditor']::text[]
             )
         )
       )
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
  select (select auth.uid()) is not null
     and private.is_aal2()
     and (
       private.can_view_case_staff(p_municipality_id, p_case_id)
       or exists (
         select 1
         from public.fiscal_cases fc
         join public.taxpayer_user_links tul
           on tul.municipality_id = fc.municipality_id
          and tul.taxpayer_id = fc.taxpayer_id
         where fc.municipality_id = p_municipality_id
           and fc.id = p_case_id
           and tul.user_id = (select auth.uid())
           and tul.status = 'active'
           and tul.valid_from <= now()
           and (tul.valid_until is null or tul.valid_until > now())
       )
       or exists (
         select 1
         from public.fiscal_cases fc
         join public.taxpayer_accountant_links tal
           on tal.municipality_id = fc.municipality_id
          and tal.taxpayer_id = fc.taxpayer_id
         join public.accountant_user_links aul
           on aul.municipality_id = tal.municipality_id
          and aul.accounting_firm_id = tal.accounting_firm_id
         where fc.municipality_id = p_municipality_id
           and fc.id = p_case_id
           and tal.status = 'active'
           and tal.relationship_status = 'linked'
           and tal.verification_status = 'verified'
           and tal.verified_at is not null
           and tal.can_access_portal
           and tal.valid_from <= now()
           and (tal.valid_until is null or tal.valid_until > now())
           and aul.user_id = (select auth.uid())
           and aul.status = 'active'
           and aul.verified_at is not null
           and aul.valid_from <= now()
           and (aul.valid_until is null or aul.valid_until > now())
       )
     );
$$;


create or replace view public.vw_fiscal_chat_inbox
with (security_invoker = true)
as
select
  fi.municipality_id,
  fi.question_id,
  fi.case_id,
  fc.case_number,
  fi.taxpayer_id,
  t.legal_name as taxpayer_name,
  fi.status,
  fi.priority,
  fi.question_preview,
  fi.handling_mode,
  fi.assigned_membership_id,
  fi.routing_confidence,
  fi.routing_reason,
  fi.sla_due_at,
  fi.claimed_at,
  fi.answered_at,
  fi.created_at,
  fi.updated_at,
  case
    when fi.status in ('answered', 'closed') then 1
    when fi.sla_due_at is not null and fi.sla_due_at < now() then 4
    when fi.status = 'waiting' then 3
    when fi.status = 'claimed' then 2
    else 1
  end as operational_priority
from public.fiscal_chat_inbox fi
join public.fiscal_cases fc
  on fc.municipality_id = fi.municipality_id
 and fc.id = fi.case_id
join public.taxpayers t
  on t.municipality_id = fi.municipality_id
 and t.id = fi.taxpayer_id;

comment on column public.vw_fiscal_chat_inbox.operational_priority is
  'Queue ordering only: overdue SLA, waiting, claimed, then terminal. It is not a legal or fiscal conclusion.';


-- Replace the legacy two-argument entry point so every claim is bound to the
-- municipality and membership selected by the authenticated client context.
revoke all on function public.ia_claim_case_question(uuid, text)
  from public, anon, authenticated, service_role;
drop function public.ia_claim_case_question(uuid, text);

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
  if not private.can_view_case_staff(v_question.municipality_id, v_question.case_id) then
    raise exception 'case claim access denied';
  end if;

  if v_question.status in ('answered', 'closed') then
    raise exception 'question is already closed';
  end if;

  -- The locked open row is the idempotency record for this command. An exact
  -- replay returns before any assignment, update, trigger, or event write.
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
      'responsible_fiscal',
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

comment on function public.ia_claim_case_question(uuid, uuid, uuid, text) is
  'Claims a case question under AAL2 and an explicit active municipality/membership context. Exact retries are no-op replays.';


-- Reset every inherited/default ACL before granting only the intended callers.
revoke all on function private.has_municipality_role(uuid, text[])
  from public, anon, authenticated, service_role;
grant execute on function private.has_municipality_role(uuid, text[])
  to authenticated;

revoke all on function private.current_municipality_membership_id(uuid, text[])
  from public, anon, authenticated, service_role;

revoke all on function private.can_view_case_staff(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.can_view_case_staff(uuid, uuid)
  to authenticated;

revoke all on function private.can_review_case(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.can_review_case(uuid, uuid)
  to authenticated;

revoke all on function private.can_access_case(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.can_access_case(uuid, uuid)
  to authenticated;

revoke all on function public.ia_claim_case_question(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_claim_case_question(uuid, uuid, uuid, text)
  to authenticated;

notify pgrst, 'reload schema';

commit;
