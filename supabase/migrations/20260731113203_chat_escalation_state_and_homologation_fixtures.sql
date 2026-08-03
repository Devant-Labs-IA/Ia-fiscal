create or replace function public.ia_route_case_question_from_knowledge(p_question_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_question public.case_questions%rowtype;
  v_case public.fiscal_cases%rowtype;
  v_question_message public.case_messages%rowtype;
  v_explanation public.case_explanations%rowtype;
  v_match record;
  v_normalized text;
  v_body text;
  v_message_id uuid;
  v_thread_id uuid;
begin
  if not private.is_service_role() then raise exception 'service role required'; end if;
  select cq.* into strict v_question from public.case_questions cq where cq.id=p_question_id for update;
  if v_question.status in ('answered','closed') then
    return jsonb_build_object('status','already_answered','question_id',v_question.id);
  end if;
  select fc.* into strict v_case from public.fiscal_cases fc
   where fc.municipality_id=v_question.municipality_id and fc.id=v_question.case_id;
  select cm.* into strict v_question_message from public.case_messages cm
   where cm.municipality_id=v_question.municipality_id and cm.id=v_question.message_id;
  select ce.* into strict v_explanation from public.case_explanations ce
   where ce.municipality_id=v_question.municipality_id and ce.case_id=v_question.case_id and ce.is_current;
  v_normalized := private.ia_normalize_question(v_question_message.body);

  select rka.*,kap.normalized_phrase into v_match
  from public.knowledge_article_patterns kap
  join public.vw_reusable_knowledge_articles rka
    on rka.municipality_id=kap.municipality_id and rka.article_id=kap.article_id
  where kap.municipality_id=v_question.municipality_id
    and kap.match_mode='exact'
    and kap.normalized_phrase=v_normalized
    and rka.is_test=(v_case.execution_mode='homologation_test')
  order by rka.semantic_version desc limit 1;

  if v_match.article_id is null then
    update public.case_questions set status='awaiting_fiscal',handling_mode='human',routing_confidence=0,
      routing_reason='no_current_approved_exact_knowledge',last_activity_at=now()
     where municipality_id=v_question.municipality_id and id=v_question.id;
    update public.fiscal_cases set status='awaiting_fiscal'
     where municipality_id=v_question.municipality_id and id=v_question.case_id
       and status not in ('resolved','closed','cancelled');
    insert into public.case_events (
      municipality_id,case_id,event_type,visibility,actor_type,event_data
    ) values (
      v_question.municipality_id,v_question.case_id,'question_escalated_to_fiscal','staff','service',
      jsonb_build_object('question_id',v_question.id,'reason','no_current_approved_exact_knowledge')
    );
    return jsonb_build_object('status','escalated','question_id',v_question.id,'reason','no_current_approved_exact_knowledge');
  end if;

  v_body := replace(v_match.answer_body,'{{case_summary}}',v_explanation.summary);
  v_body := replace(v_body,'{{legal_basis_summary}}',v_explanation.legal_basis_summary);
  v_body := replace(v_body,'{{official_system_url}}',v_explanation.official_system_url);
  select ct.id into strict v_thread_id from public.case_threads ct
   where ct.municipality_id=v_question.municipality_id and ct.case_id=v_question.case_id and ct.status='open';
  insert into public.case_messages (
    municipality_id,thread_id,case_id,parent_message_id,sender_type,author_user_id,
    source_type,visibility,body,content_sha256,status,client_request_id,published_at,source_knowledge_revision_id
  ) values (
    v_question.municipality_id,v_thread_id,v_question.case_id,v_question.message_id,
    'system',null,'approved_knowledge','participants',v_body,
    encode(extensions.digest(v_body,'sha256'),'hex'),'published',
    'knowledge-auto:'||v_question.id::text,now(),v_match.revision_id
  ) on conflict (municipality_id,case_id,client_request_id)
    where client_request_id is not null
    do update
    set client_request_id=excluded.client_request_id
  returning id into v_message_id;
  update public.case_questions set status='answered',handling_mode='approved_knowledge',routing_confidence=1,
    routing_reason='exact_current_approved_knowledge',answered_at=now(),last_activity_at=now()
   where municipality_id=v_question.municipality_id and id=v_question.id;
  update public.fiscal_cases set status='awaiting_taxpayer'
   where municipality_id=v_question.municipality_id and id=v_question.case_id
     and status not in ('resolved','closed','cancelled');
  insert into public.case_events (
    municipality_id,case_id,event_type,visibility,actor_type,event_data
  ) values (
    v_question.municipality_id,v_question.case_id,'approved_knowledge_answer_published','participants','service',
    jsonb_build_object('question_id',v_question.id,'message_id',v_message_id,'article_id',v_match.article_id,
      'revision_id',v_match.revision_id,'confidence',1)
  );
  return jsonb_build_object('status','answered','question_id',v_question.id,'message_id',v_message_id,
    'article_id',v_match.article_id,'revision_id',v_match.revision_id,'confidence',1);
end;
$$;


select set_config('request.jwt.claims','{"role":"service_role"}',true);

insert into public.case_messages (
  municipality_id,thread_id,case_id,sender_type,source_type,visibility,body,
  content_sha256,status,client_request_id,published_at
)
select fc.municipality_id,ct.id,fc.id,'system','system','participants',
       'Por que minha empresa pode sofrer fiscalização?',
       encode(extensions.digest('Por que minha empresa pode sofrer fiscalização?','sha256'),'hex'),
       'published','homologation-fixture-known-question-v1',now()
from public.fiscal_cases fc
join public.case_threads ct on ct.municipality_id=fc.municipality_id and ct.case_id=fc.id
join public.divergences d on d.municipality_id=fc.municipality_id and d.id=fc.divergence_id
where fc.execution_mode='homologation_test' and d.divergence_type='current_account_balance'
order by fc.created_at limit 1
on conflict (municipality_id,case_id,client_request_id)
where client_request_id is not null do nothing;

insert into public.case_questions (municipality_id,case_id,message_id,status,handling_mode,routing_reason)
select cm.municipality_id,cm.case_id,cm.id,'queued_for_ai','pending','homologation_fixture'
from public.case_messages cm
where cm.client_request_id='homologation-fixture-known-question-v1'
  and not exists (
    select 1 from public.case_questions cq
    where cq.municipality_id=cm.municipality_id and cq.message_id=cm.id
  );

select public.ia_route_case_question_from_knowledge(cq.id)
from public.case_questions cq
join public.case_messages cm on cm.municipality_id=cq.municipality_id and cm.id=cq.message_id
where cm.client_request_id='homologation-fixture-known-question-v1'
  and cq.status not in ('answered','closed');

insert into public.case_messages (
  municipality_id,thread_id,case_id,sender_type,source_type,visibility,body,
  content_sha256,status,client_request_id,published_at
)
select fc.municipality_id,ct.id,fc.id,'system','system','participants',
       'Enviei um comprovante ontem. Ele já foi analisado?',
       encode(extensions.digest('Enviei um comprovante ontem. Ele já foi analisado?','sha256'),'hex'),
       'published','homologation-fixture-escalated-question-v1',now()
from public.fiscal_cases fc
join public.case_threads ct on ct.municipality_id=fc.municipality_id and ct.case_id=fc.id
join public.divergences d on d.municipality_id=fc.municipality_id and d.id=fc.divergence_id
where fc.execution_mode='homologation_test' and d.divergence_type='current_account_balance'
order by fc.created_at limit 1
on conflict (municipality_id,case_id,client_request_id)
where client_request_id is not null do nothing;

insert into public.case_questions (municipality_id,case_id,message_id,status,handling_mode,routing_reason)
select cm.municipality_id,cm.case_id,cm.id,'queued_for_ai','pending','homologation_fixture'
from public.case_messages cm
where cm.client_request_id='homologation-fixture-escalated-question-v1'
  and not exists (
    select 1 from public.case_questions cq
    where cq.municipality_id=cm.municipality_id and cq.message_id=cm.id
  );

select public.ia_route_case_question_from_knowledge(cq.id)
from public.case_questions cq
join public.case_messages cm on cm.municipality_id=cq.municipality_id and cm.id=cq.message_id
where cm.client_request_id='homologation-fixture-escalated-question-v1'
  and cq.status not in ('answered','closed','awaiting_fiscal');

