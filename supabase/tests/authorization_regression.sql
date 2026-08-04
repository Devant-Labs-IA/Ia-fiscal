-- Transactional authorization regression suite.
-- It uses only synthetic auth identities and rolls back every fixture and mutation.

begin;

do $test$
declare
  v_municipality_id uuid;
  v_case_id uuid;
  v_question_id uuid;
  v_taxpayer_id uuid;
  v_accounting_firm_id uuid;
  v_tal_id uuid;
  v_question_status text;
  v_question_assignment uuid;
  v_assignment_count bigint;
  v_event_count bigint;
  v_denied boolean;
  v_first_question uuid;
  v_second_question uuid;
  v_message_count bigint;
  v_claim_last_activity_at timestamptz;
  v_terminal_status text;
  v_claim_replay_sentinel constant timestamptz := '2000-01-01 00:00:00+00';
  x_municipality constant uuid := '00000000-0000-4000-8000-000000000999';

  u_fiscal_unassigned constant uuid := '00000000-0000-4000-8000-000000000101';
  u_fiscal_assigned constant uuid := '00000000-0000-4000-8000-000000000102';
  u_supervisor constant uuid := '00000000-0000-4000-8000-000000000103';
  u_legal constant uuid := '00000000-0000-4000-8000-000000000104';
  u_municipal_admin constant uuid := '00000000-0000-4000-8000-000000000105';
  u_platform constant uuid := '00000000-0000-4000-8000-000000000106';
  u_expired_legal constant uuid := '00000000-0000-4000-8000-000000000107';
  u_future_fiscal constant uuid := '00000000-0000-4000-8000-000000000108';
  u_accountant constant uuid := '00000000-0000-4000-8000-000000000109';
  u_taxpayer_readonly constant uuid := '00000000-0000-4000-8000-000000000110';
  u_taxpayer_owner constant uuid := '00000000-0000-4000-8000-000000000111';

  m_fiscal_unassigned constant uuid := '00000000-0000-4000-8000-000000000201';
  m_fiscal_assigned constant uuid := '00000000-0000-4000-8000-000000000202';
  m_supervisor constant uuid := '00000000-0000-4000-8000-000000000203';
  m_legal constant uuid := '00000000-0000-4000-8000-000000000204';
  m_municipal_admin constant uuid := '00000000-0000-4000-8000-000000000205';
  m_expired_legal constant uuid := '00000000-0000-4000-8000-000000000207';
  m_future_fiscal constant uuid := '00000000-0000-4000-8000-000000000208';
begin
  select fc.municipality_id, fc.id, cq.id, fc.taxpayer_id
    into strict v_municipality_id, v_case_id, v_question_id, v_taxpayer_id
  from public.fiscal_cases fc
  join public.case_questions cq
    on cq.municipality_id = fc.municipality_id
   and cq.case_id = fc.id
  where fc.confidentiality in ('restricted', 'fiscal_secret')
    and cq.assigned_membership_id is null
  order by fc.id, cq.id
  limit 1;

  select tal.id, tal.accounting_firm_id
    into strict v_tal_id, v_accounting_firm_id
  from public.taxpayer_accountant_links tal
  where tal.municipality_id = v_municipality_id
    and tal.taxpayer_id = v_taxpayer_id
  order by tal.created_at
  limit 1;

  update public.case_questions
     set status = 'awaiting_fiscal',
         assigned_membership_id = null,
         claimed_at = null,
         answered_at = null,
         last_activity_at = now()
   where municipality_id = v_municipality_id
     and id = v_question_id;

  insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  select id, 'authenticated', 'authenticated', email, '{}'::jsonb, '{}'::jsonb, now(), now()
  from (values
    (u_fiscal_unassigned, 'security-fiscal-unassigned@example.invalid'),
    (u_fiscal_assigned, 'security-fiscal-assigned@example.invalid'),
    (u_supervisor, 'security-supervisor@example.invalid'),
    (u_legal, 'security-legal@example.invalid'),
    (u_municipal_admin, 'security-municipal-admin@example.invalid'),
    (u_platform, 'security-platform@example.invalid'),
    (u_expired_legal, 'security-expired@example.invalid'),
    (u_future_fiscal, 'security-future@example.invalid'),
    (u_accountant, 'security-accountant@example.invalid'),
    (u_taxpayer_readonly, 'security-taxpayer-readonly@example.invalid'),
    (u_taxpayer_owner, 'security-taxpayer-owner@example.invalid')
  ) as users(id, email);

  insert into public.municipality_memberships (
    id, municipality_id, user_id, role, status, valid_from, valid_until, activated_at
  ) values
    (m_fiscal_unassigned, v_municipality_id, u_fiscal_unassigned, 'fiscal_auditor',
      'active', now() - interval '1 day', null, now()),
    (m_fiscal_assigned, v_municipality_id, u_fiscal_assigned, 'fiscal_auditor',
      'active', now() - interval '1 day', null, now()),
    (m_supervisor, v_municipality_id, u_supervisor, 'supervisor',
      'active', now() - interval '1 day', null, now()),
    (m_legal, v_municipality_id, u_legal, 'legal_reviewer',
      'active', now() - interval '1 day', null, now()),
    (m_municipal_admin, v_municipality_id, u_municipal_admin, 'municipal_admin',
      'active', now() - interval '1 day', null, now()),
    (m_expired_legal, v_municipality_id, u_expired_legal, 'legal_reviewer',
      'active', now() - interval '2 days', now() - interval '1 day', now() - interval '2 days'),
    (m_future_fiscal, v_municipality_id, u_future_fiscal, 'fiscal_auditor',
      'active', now() + interval '1 day', now() + interval '2 days', null);

  insert into public.platform_administrators (user_id, reason, active)
  values (u_platform, 'synthetic authorization regression', true);

  insert into public.case_assignments (
    municipality_id, case_id, membership_id, assignment_role, status, assigned_by
  ) values (
    v_municipality_id, v_case_id, m_fiscal_assigned, 'responsible_fiscal', 'active', u_supervisor
  );

  perform set_config('request.jwt.claim.sub', u_fiscal_unassigned::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_fiscal_unassigned, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  if private.can_view_case_staff(v_municipality_id, v_case_id) then
    raise exception 'unassigned fiscal viewed confidential case';
  end if;
  if private.can_review_case(v_municipality_id, v_case_id) then
    raise exception 'unassigned fiscal reviewed confidential case';
  end if;

  select cq.status, cq.assigned_membership_id
    into v_question_status, v_question_assignment
  from public.case_questions cq
  where cq.municipality_id = v_municipality_id and cq.id = v_question_id;
  select count(*) into v_assignment_count
  from public.case_assignments ca
  where ca.municipality_id = v_municipality_id
    and ca.case_id = v_case_id
    and ca.membership_id = m_fiscal_unassigned;
  select count(*) into v_event_count
  from public.case_events ce
  where ce.municipality_id = v_municipality_id
    and ce.case_id = v_case_id
    and ce.event_type = 'case_question_claimed'
    and ce.actor_user_id = u_fiscal_unassigned;

  v_denied := false;
  begin
    perform public.ia_claim_case_question(
      v_question_id, v_municipality_id, m_fiscal_unassigned, 'human'
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'unassigned fiscal claimed confidential case';
  end if;
  if exists (
    select 1 from public.case_assignments ca
    where ca.municipality_id = v_municipality_id
      and ca.case_id = v_case_id
      and ca.membership_id = m_fiscal_unassigned
  ) then
    raise exception 'denied claim created assignment';
  end if;
  if exists (
    select 1 from public.case_questions cq
    where cq.municipality_id = v_municipality_id
      and cq.id = v_question_id
      and (cq.status is distinct from v_question_status
        or cq.assigned_membership_id is distinct from v_question_assignment)
  ) then
    raise exception 'denied claim changed question';
  end if;
  if (
    select count(*) from public.case_events ce
    where ce.municipality_id = v_municipality_id
      and ce.case_id = v_case_id
      and ce.event_type = 'case_question_claimed'
      and ce.actor_user_id = u_fiscal_unassigned
  ) <> v_event_count then
    raise exception 'denied claim created event';
  end if;

  perform set_config('request.jwt.claim.sub', u_fiscal_assigned::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_fiscal_assigned, 'role', 'authenticated', 'aal', 'aal1')::text,
    true
  );
  if private.has_municipality_role(
       v_municipality_id, array['fiscal_auditor']::text[]
     ) then
    raise exception 'AAL1 fiscal passed municipal role authorization';
  end if;
  if private.current_municipality_membership_id(
       v_municipality_id, array['fiscal_auditor']::text[]
     ) is not null then
    raise exception 'AAL1 fiscal received a current membership';
  end if;
  if private.can_view_case_staff(v_municipality_id, v_case_id)
     or private.can_review_case(v_municipality_id, v_case_id)
     or private.can_access_case(v_municipality_id, v_case_id) then
    raise exception 'AAL1 fiscal crossed a regulated case boundary';
  end if;
  v_denied := false;
  begin
    perform public.ia_claim_case_question(
      v_question_id, v_municipality_id, m_fiscal_assigned, 'human'
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'AAL1 fiscal claimed a question';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_fiscal_assigned, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  if not private.can_view_case_staff(v_municipality_id, v_case_id)
     or not private.can_review_case(v_municipality_id, v_case_id) then
    raise exception 'assigned fiscal lost legitimate access';
  end if;
  -- A stale or cross-tenant client context must fail before any write, even
  -- when the caller has a legitimate fiscal membership for this question.
  v_denied := false;
  begin
    perform public.ia_claim_case_question(
      v_question_id, x_municipality, m_fiscal_assigned, 'human'
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'cross-municipality claim context was accepted';
  end if;

  v_denied := false;
  begin
    perform public.ia_claim_case_question(
      v_question_id, v_municipality_id, m_supervisor, 'human'
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'stale membership claim context was accepted';
  end if;

  if public.ia_claim_case_question(
       v_question_id, v_municipality_id, m_fiscal_assigned, 'human'
     ) is distinct from m_fiscal_assigned then
    raise exception 'assigned fiscal claim returned wrong membership';
  end if;
  update public.case_questions
     set last_activity_at = v_claim_replay_sentinel
   where municipality_id = v_municipality_id
     and id = v_question_id;
  select count(*) into v_event_count
  from public.case_events ce
  where ce.municipality_id = v_municipality_id
    and ce.case_id = v_case_id
    and ce.event_type = 'case_question_claimed'
    and ce.actor_user_id = u_fiscal_assigned
    and ce.event_data ->> 'question_id' = v_question_id::text;
  if v_event_count <> 1 then
    raise exception 'initial successful claim did not create exactly one event';
  end if;
  select count(*) into v_assignment_count
  from public.case_assignments ca
  where ca.municipality_id = v_municipality_id
    and ca.case_id = v_case_id
    and ca.membership_id = m_fiscal_assigned
    and ca.status = 'active';

  if public.ia_claim_case_question(
       v_question_id, v_municipality_id, m_fiscal_assigned, 'human'
     ) is distinct from m_fiscal_assigned then
    raise exception 'idempotent claim replay returned wrong membership';
  end if;
  select cq.last_activity_at into strict v_claim_last_activity_at
  from public.case_questions cq
  where cq.municipality_id = v_municipality_id
    and cq.id = v_question_id;
  if v_claim_last_activity_at is distinct from v_claim_replay_sentinel then
    raise exception 'idempotent claim replay changed last_activity_at';
  end if;
  if (
    select count(*)
    from public.case_events ce
    where ce.municipality_id = v_municipality_id
      and ce.case_id = v_case_id
      and ce.event_type = 'case_question_claimed'
      and ce.actor_user_id = u_fiscal_assigned
      and ce.event_data ->> 'question_id' = v_question_id::text
  ) <> v_event_count then
    raise exception 'idempotent claim replay created another event';
  end if;
  if (
    select count(*)
    from public.case_assignments ca
    where ca.municipality_id = v_municipality_id
      and ca.case_id = v_case_id
      and ca.membership_id = m_fiscal_assigned
      and ca.status = 'active'
  ) <> v_assignment_count then
    raise exception 'idempotent claim replay changed active assignments';
  end if;

  foreach v_terminal_status in array array['answered', 'closed']::text[] loop
    update public.case_questions
       set status = v_terminal_status,
           answered_at = now(),
           last_activity_at = v_claim_replay_sentinel
     where municipality_id = v_municipality_id
       and id = v_question_id;

    v_denied := false;
    begin
      perform public.ia_claim_case_question(
        v_question_id, v_municipality_id, m_fiscal_assigned, 'human'
      );
    exception when others then
      v_denied := true;
    end;
    if not v_denied then
      raise exception 'terminal question status % was reclaimed', v_terminal_status;
    end if;
    if exists (
      select 1
      from public.case_questions cq
      where cq.municipality_id = v_municipality_id
        and cq.id = v_question_id
        and (
          cq.status is distinct from v_terminal_status
          or cq.last_activity_at is distinct from v_claim_replay_sentinel
        )
    ) then
      raise exception 'denied terminal-status claim changed question';
    end if;
    if (
      select count(*)
      from public.case_events ce
      where ce.municipality_id = v_municipality_id
        and ce.case_id = v_case_id
        and ce.event_type = 'case_question_claimed'
        and ce.actor_user_id = u_fiscal_assigned
        and ce.event_data ->> 'question_id' = v_question_id::text
    ) <> v_event_count then
      raise exception 'denied terminal-status claim created another event';
    end if;
  end loop;

  perform set_config('request.jwt.claim.sub', u_supervisor::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_supervisor, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  if not private.can_view_case_staff(v_municipality_id, v_case_id)
     or not private.can_review_case(v_municipality_id, v_case_id) then
    raise exception 'supervisor lost legitimate access';
  end if;

  update public.case_questions
     set status = 'submitted',
         assigned_membership_id = null,
         handling_mode = 'human',
         answered_at = null,
         claimed_at = null
   where municipality_id = v_municipality_id
     and id = v_question_id;
  update public.case_assignments
     set status = 'completed',
         completed_at = now()
   where municipality_id = v_municipality_id
     and case_id = v_case_id
     and membership_id = m_fiscal_assigned
     and status = 'active';

  if public.ia_claim_case_question(
       v_question_id, v_municipality_id, m_supervisor, 'human'
     ) is distinct from m_supervisor then
    raise exception 'supervisor claim returned the wrong membership';
  end if;
  if not exists (
    select 1
    from public.case_assignments ca
    where ca.municipality_id = v_municipality_id
      and ca.case_id = v_case_id
      and ca.membership_id = m_supervisor
      and ca.assignment_role = 'reviewer'
      and ca.status = 'active'
  ) then
    raise exception 'supervisor claim was mislabeled as responsible fiscal';
  end if;

  perform set_config('request.jwt.claim.sub', u_municipal_admin::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_municipal_admin, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  if not private.can_view_case_staff(v_municipality_id, v_case_id) then
    raise exception 'municipal admin lost read access';
  end if;
  if private.can_review_case(v_municipality_id, v_case_id) then
    raise exception 'municipal admin inherited fiscal decision power';
  end if;

  perform set_config('request.jwt.claim.sub', u_platform::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_platform, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  if private.has_municipality_role(
       v_municipality_id,
       array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
     )
     or private.current_municipality_membership_id(v_municipality_id, null) is not null
     or private.can_view_case_staff(v_municipality_id, v_case_id)
     or private.can_review_case(v_municipality_id, v_case_id)
     or private.can_access_case(v_municipality_id, v_case_id) then
    raise exception 'technical platform admin inherited fiscal authority';
  end if;

  perform set_config('request.jwt.claim.sub', u_expired_legal::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_expired_legal, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  if private.current_municipality_membership_id(
    v_municipality_id, array['legal_reviewer']::text[]
  ) is not null then
    raise exception 'expired legal reviewer treated as current';
  end if;

  perform set_config('request.jwt.claim.sub', u_future_fiscal::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_future_fiscal, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  if private.current_municipality_membership_id(
    v_municipality_id, array['fiscal_auditor']::text[]
  ) is not null then
    raise exception 'future fiscal membership treated as current';
  end if;

  insert into public.accountant_user_links (
    municipality_id, accounting_firm_id, user_id, access_role, status,
    valid_from, verified_by, verified_at
  ) values (
    v_municipality_id, v_accounting_firm_id, u_accountant, 'accountant', 'active',
    now() - interval '1 day', u_supervisor, now()
  );

  update public.taxpayer_accountant_links
     set status = 'active',
         can_access_portal = true,
         valid_from = now() - interval '1 day',
         valid_until = null,
         verified_by = u_supervisor,
         verified_at = now(),
         authorization_basis = coalesce(nullif(authorization_basis, ''), 'synthetic regression'),
         relationship_status = 'proposed',
         verification_status = 'unverified',
         delivery_status = 'blocked'
   where municipality_id = v_municipality_id and id = v_tal_id;

  perform set_config('request.jwt.claim.sub', u_accountant::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_accountant, 'role', 'authenticated', 'aal', 'aal1')::text,
    true
  );
  if private.can_access_case(v_municipality_id, v_case_id) then
    raise exception 'AAL1 accountant accessed a verified relationship';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_accountant, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  if private.can_access_case(v_municipality_id, v_case_id) then
    raise exception 'unverified accountant relationship accessed case';
  end if;

  update public.taxpayer_accountant_links
     set relationship_status = 'linked',
         verification_status = 'verified'
   where municipality_id = v_municipality_id and id = v_tal_id;
  if not private.can_access_case(v_municipality_id, v_case_id) then
    raise exception 'verified accountant relationship lost legitimate access';
  end if;

  insert into public.taxpayer_user_links (
    municipality_id, taxpayer_id, user_id, access_role, status,
    valid_from, verified_by, verified_at
  ) values
    (v_municipality_id, v_taxpayer_id, u_taxpayer_readonly, 'readonly', 'active',
      now() - interval '1 day', u_supervisor, now()),
    (v_municipality_id, v_taxpayer_id, u_taxpayer_owner, 'owner', 'active',
      now() - interval '1 day', u_supervisor, now());

  perform set_config('request.jwt.claim.sub', u_taxpayer_owner::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_taxpayer_owner, 'role', 'authenticated', 'aal', 'aal1')::text,
    true
  );
  if private.can_access_case(v_municipality_id, v_case_id) then
    raise exception 'AAL1 taxpayer accessed a linked case';
  end if;

  perform set_config('request.jwt.claim.sub', u_taxpayer_readonly::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_taxpayer_readonly, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  if not private.can_access_case(v_municipality_id, v_case_id) then
    raise exception 'AAL2 linked taxpayer lost legitimate read access';
  end if;
  v_denied := false;
  begin
    perform public.ia_submit_case_question(
      v_case_id, 'Tentativa de escrita readonly', 'security-readonly-write-v1'
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'readonly taxpayer submitted a question';
  end if;

  perform set_config('request.jwt.claim.sub', u_taxpayer_owner::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u_taxpayer_owner, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  if not private.can_access_case(v_municipality_id, v_case_id) then
    raise exception 'AAL2 taxpayer owner lost legitimate case access';
  end if;
  v_first_question := public.ia_submit_case_question(
    v_case_id, 'Pergunta idempotente de homologacao', 'security-idempotency-v1'
  );
  v_second_question := public.ia_submit_case_question(
    v_case_id, 'Pergunta idempotente de homologacao', 'security-idempotency-v1'
  );
  if v_first_question is distinct from v_second_question then
    raise exception 'idempotent replay returned a different question';
  end if;
  select count(*) into v_message_count
  from public.case_messages cm
  where cm.municipality_id = v_municipality_id
    and cm.case_id = v_case_id
    and cm.client_request_id = 'security-idempotency-v1';
  if v_message_count <> 1 then
    raise exception 'idempotent replay created duplicate messages';
  end if;

  v_denied := false;
  begin
    perform public.ia_submit_case_question(
      v_case_id, 'Payload diferente', 'security-idempotency-v1'
    );
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'idempotency key accepted a different payload';
  end if;

  if pg_get_functiondef('public.ia_review_knowledge_article(uuid,uuid,text,text)'::regprocedure)
       not like '%current_municipality_membership_id%' then
    raise exception 'knowledge review does not enforce current membership';
  end if;
  if pg_get_functiondef('public.ia_publish_knowledge_article(uuid,text)'::regprocedure)
       not like '%current legal reviewer role required%' then
    raise exception 'knowledge publication does not enforce legal reviewer role';
  end if;
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'vw_fiscal_chat_inbox'
      and column_name = 'operational_priority'
  ) then
    raise exception 'fiscal inbox lacks server-side operational priority';
  end if;
  if pg_get_viewdef('public.vw_fiscal_chat_inbox'::regclass, true)
       not like '%sla_due_at < now()%' then
    raise exception 'fiscal inbox operational priority does not prioritize overdue SLA';
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'fiscal_chat_inbox'
      and policyname = 'fiscal_chat_inbox_select_staff'
      and qual like '%can_view_case_staff%'
  ) then
    raise exception 'fiscal inbox policy is not case-scoped';
  end if;

  if not has_function_privilege(
       'authenticated', 'private.has_municipality_role(uuid,text[])', 'execute'
     )
     or not has_function_privilege(
       'authenticated', 'private.can_view_case_staff(uuid,uuid)', 'execute'
     )
     or not has_function_privilege(
       'authenticated', 'private.can_review_case(uuid,uuid)', 'execute'
     )
     or not has_function_privilege(
       'authenticated', 'private.can_access_case(uuid,uuid)', 'execute'
     )
     or not has_function_privilege(
       'authenticated', 'public.ia_claim_case_question(uuid,uuid,uuid,text)', 'execute'
     ) then
    raise exception 'authenticated role is missing a required function grant';
  end if;
  if has_function_privilege(
       'authenticated', 'private.current_municipality_membership_id(uuid,text[])', 'execute'
     ) then
    raise exception 'internal membership resolver is directly executable by authenticated';
  end if;
  if has_function_privilege('anon', 'private.has_municipality_role(uuid,text[])', 'execute')
     or has_function_privilege('anon', 'private.can_view_case_staff(uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'private.can_review_case(uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'private.can_access_case(uuid,uuid)', 'execute')
     or has_function_privilege(
       'anon', 'public.ia_claim_case_question(uuid,uuid,uuid,text)', 'execute'
     )
     or has_function_privilege(
       'service_role', 'private.has_municipality_role(uuid,text[])', 'execute'
     )
     or has_function_privilege(
       'service_role', 'private.current_municipality_membership_id(uuid,text[])', 'execute'
     )
     or has_function_privilege(
       'service_role', 'private.can_view_case_staff(uuid,uuid)', 'execute'
     )
     or has_function_privilege(
       'service_role', 'private.can_review_case(uuid,uuid)', 'execute'
     )
     or has_function_privilege(
       'service_role', 'private.can_access_case(uuid,uuid)', 'execute'
     )
     or has_function_privilege(
       'service_role', 'public.ia_claim_case_question(uuid,uuid,uuid,text)', 'execute'
     ) then
    raise exception 'anon or service_role retained a regulated function grant';
  end if;
  if to_regprocedure('public.ia_claim_case_question(uuid,text)') is not null then
    raise exception 'legacy unscoped claim function still exists';
  end if;
end
$test$;

rollback;
