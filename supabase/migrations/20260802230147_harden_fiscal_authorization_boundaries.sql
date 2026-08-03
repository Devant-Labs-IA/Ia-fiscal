-- IA Fiscal: close authorization, tenancy and idempotency gaps found during homologation.
-- Technical platform maintenance never substitutes a current municipal fiscal membership.

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
    and mm.municipality_id = p_municipality_id
    and mm.user_id = (select auth.uid())
    and mm.status = 'active'
    and mm.valid_from <= now()
    and (mm.valid_until is null or mm.valid_until > now())
    and (p_roles is null or mm.role = any(p_roles))
  order by mm.valid_from desc, mm.id
  limit 1;
$$;

revoke all on function private.current_municipality_membership_id(uuid, text[])
  from public, anon, authenticated, service_role;

comment on function private.current_municipality_membership_id(uuid, text[]) is
  'Returns a current municipal membership for auth.uid without platform-administrator bypass. Use for regulated fiscal reads and decisions.';


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
  select exists (
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
  select private.current_municipality_membership_id(
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
  select private.can_view_case_staff(p_municipality_id, p_case_id)
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
      );
$$;

create or replace function public.ia_claim_case_question(
  p_question_id uuid,
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
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if p_handling_mode not in ('human','ai_assist') then
    raise exception 'invalid handling mode';
  end if;
  select cq.* into strict v_question
  from public.case_questions cq where cq.id=p_question_id for update;
  if v_question.status in ('answered','closed') then
    raise exception 'question is already closed';
  end if;
  v_membership_id := private.current_municipality_membership_id(
    v_question.municipality_id,
    array['fiscal_auditor','supervisor','legal_reviewer']::text[]
  );
  if v_membership_id is null then
    raise exception 'current municipal fiscal role required';
  end if;
  if not private.can_view_case_staff(v_question.municipality_id, v_question.case_id) then
    raise exception 'case claim access denied';
  end if;

  if v_question.assigned_membership_id is not null
     and v_question.assigned_membership_id <> v_membership_id then
    raise exception 'question already claimed';
  end if;

  if not exists (
    select 1 from public.case_assignments ca
    where ca.municipality_id=v_question.municipality_id
      and ca.case_id=v_question.case_id
      and ca.membership_id=v_membership_id
      and ca.status='active'
  ) then
    insert into public.case_assignments (
      municipality_id,case_id,membership_id,assignment_role,status,assigned_by
    ) values (
      v_question.municipality_id,v_question.case_id,v_membership_id,
      'responsible_fiscal','active',auth.uid()
    );
  end if;

  update public.case_questions
     set status='awaiting_fiscal',
         assigned_membership_id=v_membership_id,
         handling_mode=p_handling_mode,
         claimed_at=coalesce(claimed_at,now()),
         last_activity_at=now()
   where municipality_id=v_question.municipality_id and id=v_question.id;

  insert into public.case_events (
    municipality_id,case_id,event_type,visibility,actor_type,actor_user_id,event_data
  ) values (
    v_question.municipality_id,v_question.case_id,'case_question_claimed','staff','staff',auth.uid(),
    jsonb_build_object('question_id',v_question.id,'membership_id',v_membership_id,'handling_mode',p_handling_mode)
  );
  return v_membership_id;
end;
$$;

create or replace function public.ia_review_knowledge_article(
  p_article_id uuid,
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
  v_article public.knowledge_articles%rowtype;
  v_revision public.knowledge_article_revisions%rowtype;
  v_membership_id uuid;
  v_review_id uuid;
begin
  if auth.uid() is null or not private.is_aal2() then raise exception 'aal2 authentication required'; end if;
  if p_decision not in ('approved','rejected','revision_requested') then raise exception 'invalid decision'; end if;
  select ka.* into strict v_article from public.knowledge_articles ka where ka.id=p_article_id for update;
  if v_article.is_test then raise exception 'homologation fixtures are not fiscally approved content'; end if;
  v_membership_id := private.current_municipality_membership_id(
    v_article.municipality_id,
    array['fiscal_auditor','supervisor','legal_reviewer']::text[]
  );
  if v_membership_id is null then
    raise exception 'current municipal fiscal role required';
  end if;
  if v_article.source_question_id is not null and not private.can_review_case(
    v_article.municipality_id,
    (select cq.case_id from public.case_questions cq where cq.municipality_id=v_article.municipality_id and cq.id=v_article.source_question_id)
  ) then raise exception 'knowledge review access denied'; end if;
  select kar.* into strict v_revision from public.knowledge_article_revisions kar
   where kar.municipality_id=v_article.municipality_id and kar.id=p_revision_id
     and kar.article_id=v_article.id and kar.revision_number=v_article.current_revision_number;
  if p_decision='approved' and not exists (
    select 1 from public.knowledge_article_citations kac
     where kac.municipality_id=v_article.municipality_id and kac.revision_id=v_revision.id
  ) then raise exception 'at least one legal citation is required'; end if;
  insert into public.knowledge_article_reviews (
    municipality_id,article_id,revision_id,decision,reviewer_membership_id,notes,approved_content_sha256
  ) values (
    v_article.municipality_id,v_article.id,v_revision.id,p_decision,v_membership_id,
    nullif(trim(p_notes),''),case when p_decision='approved' then v_revision.content_sha256 end
  ) returning id into v_review_id;
  update public.knowledge_articles set status=case when p_decision='approved' then 'approved'
    when p_decision='rejected' then 'rejected' else 'revision_requested' end
   where municipality_id=v_article.municipality_id and id=v_article.id;
  return v_review_id;
end;
$$;

create or replace function public.ia_publish_knowledge_article(
  p_article_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_article public.knowledge_articles%rowtype;
  v_revision public.knowledge_article_revisions%rowtype;
  v_publisher_membership_id uuid;
begin
  if auth.uid() is null or not private.is_aal2() then raise exception 'aal2 authentication required'; end if;
  if p_confirmation <> 'PUBLICAR' then raise exception 'explicit publication confirmation required'; end if;
  select ka.* into strict v_article from public.knowledge_articles ka where ka.id=p_article_id for update;
  v_publisher_membership_id := private.current_municipality_membership_id(
    v_article.municipality_id,
    array['legal_reviewer']::text[]
  );
  if v_publisher_membership_id is null then
    raise exception 'current legal reviewer role required';
  end if;
  if v_article.is_test or v_article.approval_basis<>'fiscal_review' then raise exception 'test fixture cannot be promoted to live knowledge'; end if;
  if v_article.status<>'approved' then raise exception 'knowledge article is not approved'; end if;
  select kar.* into strict v_revision from public.knowledge_article_revisions kar
   where kar.municipality_id=v_article.municipality_id and kar.article_id=v_article.id
     and kar.revision_number=v_article.current_revision_number;
  if not exists (
    select 1 from public.knowledge_article_reviews karv
    where karv.municipality_id=v_article.municipality_id and karv.article_id=v_article.id
      and karv.revision_id=v_revision.id and karv.decision='approved'
      and karv.approved_content_sha256=v_revision.content_sha256
  ) then raise exception 'approved review hash missing'; end if;
  if exists (
    select 1 from public.knowledge_article_citations kac
    join public.legal_source_versions lsv on lsv.municipality_id=kac.municipality_id and lsv.id=kac.source_version_id
    where kac.municipality_id=v_article.municipality_id and kac.revision_id=v_revision.id
      and (lsv.status<>'published' or lsv.content_sha256<>kac.source_sha256
           or (lsv.valid_until is not null and lsv.valid_until<=current_date))
  ) then raise exception 'one or more cited legal sources are not current and published'; end if;
  update public.knowledge_articles set status='retired'
   where municipality_id=v_article.municipality_id and intent_key=v_article.intent_key
     and id<>v_article.id and status='published' and not is_test;
  update public.knowledge_articles set status='published',valid_from=coalesce(valid_from,now()),published_at=now()
   where municipality_id=v_article.municipality_id and id=v_article.id;
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
  v_existing_content_sha256 text;
  v_existing_author_user_id uuid;
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'ia_submit_case_question:' || v_case.municipality_id::text || ':' ||
      v_case.id::text || ':' || v_client_request_id,
      0
    )
  );

  select cm.id, cm.content_sha256, cm.author_user_id
    into v_message_id, v_existing_content_sha256, v_existing_author_user_id
  from public.case_messages cm
  where cm.municipality_id = v_case.municipality_id
    and cm.case_id = v_case.id
    and cm.client_request_id = v_client_request_id;

  if v_message_id is not null then
    if v_existing_author_user_id is distinct from v_user_id then
      raise exception 'idempotency key owner mismatch';
    end if;
    if v_existing_content_sha256 is distinct from
       pg_catalog.encode(extensions.digest(v_body, 'sha256'), 'hex') then
      raise exception 'idempotency key payload mismatch';
    end if;
    select cq.id into strict v_question_id
    from public.case_questions cq
    where cq.municipality_id = v_case.municipality_id
      and cq.message_id = v_message_id;
    return v_question_id;
  end if;

  v_access_reference_id := private.current_municipality_membership_id(
    v_case.municipality_id,
    array['fiscal_auditor', 'supervisor', 'legal_reviewer']::text[]
  );

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
      and tul.access_role in ('owner', 'legal_representative', 'authorized_user')
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
        and tal.relationship_status = 'linked'
        and tal.verification_status = 'verified'
        and tal.verified_at is not null
        and tal.can_access_portal
        and tal.valid_from <= now()
        and (tal.valid_until is null or tal.valid_until > now())
        and aul.user_id = v_user_id
        and aul.status = 'active'
        and aul.verified_at is not null
        and aul.access_role in ('owner', 'accountant', 'authorized_user')
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


drop policy if exists fiscal_chat_inbox_select_staff
  on public.fiscal_chat_inbox;
create policy fiscal_chat_inbox_select_staff
on public.fiscal_chat_inbox
for select
to authenticated
using (
  (select private.can_view_case_staff(
    fiscal_chat_inbox.municipality_id,
    fiscal_chat_inbox.case_id
  ))
);

comment on policy fiscal_chat_inbox_select_staff on public.fiscal_chat_inbox is
  'Confidential questions require the same case visibility as their parent case.';

notify pgrst, 'reload schema';

