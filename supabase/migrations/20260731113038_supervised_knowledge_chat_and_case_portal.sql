-- IA Fiscal: supervised knowledge, taxpayer case home, chat routing and fiscal inbox.
-- External delivery remains disabled; all seed data is homologation-only.

create table if not exists public.municipality_portal_settings (
  municipality_id uuid primary key references public.municipalities(id) on delete cascade,
  sigiss_login_url text not null,
  case_portal_base_url text,
  official_help_url text,
  external_email_enabled boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint municipality_portal_settings_sigiss_https_ck
    check (sigiss_login_url ~ '^https://'),
  constraint municipality_portal_settings_portal_https_ck
    check (case_portal_base_url is null or case_portal_base_url ~ '^https://'),
  constraint municipality_portal_settings_help_https_ck
    check (official_help_url is null or official_help_url ~ '^https://')
);

create table if not exists public.case_explanations (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  case_id uuid not null,
  explanation_version integer not null,
  is_current boolean not null default true,
  status text not null default 'draft_review',
  title text not null,
  summary text not null,
  divergence_summary jsonb not null default '{}'::jsonb,
  legal_basis_summary text not null,
  citations_snapshot jsonb not null default '[]'::jsonb,
  official_system_url text not null,
  portal_path text not null,
  legal_review_required boolean not null default true,
  content_sha256 text not null,
  prepared_by uuid references auth.users(id) on delete set null,
  prepared_at timestamptz not null default now(),
  reviewed_by_membership_id uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint case_explanations_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id) on delete cascade,
  constraint case_explanations_review_membership_fk
    foreign key (municipality_id, reviewed_by_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint case_explanations_version_ck check (explanation_version > 0),
  constraint case_explanations_status_ck
    check (status in ('draft_review', 'ready_test', 'approved', 'superseded')),
  constraint case_explanations_divergence_json_ck
    check (jsonb_typeof(divergence_summary) = 'object'),
  constraint case_explanations_citations_json_ck
    check (jsonb_typeof(citations_snapshot) = 'array'),
  constraint case_explanations_hash_ck
    check (content_sha256 ~ '^[a-f0-9]{64}$'),
  constraint case_explanations_case_version_uq
    unique (municipality_id, case_id, explanation_version),
  constraint case_explanations_municipality_id_id_uq
    unique (municipality_id, id)
);

create unique index if not exists case_explanations_current_uq
  on public.case_explanations(municipality_id, case_id)
  where is_current;

create table if not exists public.knowledge_articles (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  intent_key text not null,
  semantic_version integer not null default 1,
  canonical_question text not null,
  tax_scope text not null,
  divergence_scope text not null,
  status text not null default 'draft',
  current_revision_number integer not null default 1,
  is_test boolean not null default false,
  approval_basis text not null default 'fiscal_review',
  source_question_id uuid,
  source_message_id uuid,
  valid_from timestamptz,
  valid_until timestamptz,
  published_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint knowledge_articles_intent_ck
    check (intent_key ~ '^[a-z0-9][a-z0-9:_-]{2,119}$'),
  constraint knowledge_articles_version_ck check (semantic_version > 0),
  constraint knowledge_articles_revision_ck check (current_revision_number > 0),
  constraint knowledge_articles_status_ck
    check (status in ('draft', 'under_review', 'revision_requested', 'approved', 'published', 'rejected', 'retired', 'revoked')),
  constraint knowledge_articles_approval_basis_ck
    check (approval_basis in ('fiscal_review', 'homologation_fixture')),
  constraint knowledge_articles_test_approval_ck
    check ((not is_test and approval_basis = 'fiscal_review') or is_test),
  constraint knowledge_articles_validity_ck
    check (valid_until is null or valid_from is null or valid_until > valid_from),
  constraint knowledge_articles_question_fk
    foreign key (municipality_id, source_question_id)
    references public.case_questions(municipality_id, id) on delete set null,
  constraint knowledge_articles_message_fk
    foreign key (municipality_id, source_message_id)
    references public.case_messages(municipality_id, id) on delete set null,
  constraint knowledge_articles_intent_version_uq
    unique (municipality_id, intent_key, semantic_version),
  constraint knowledge_articles_source_message_uq
    unique (municipality_id, source_message_id),
  constraint knowledge_articles_municipality_id_id_uq
    unique (municipality_id, id)
);

create table if not exists public.knowledge_article_revisions (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  article_id uuid not null,
  revision_number integer not null,
  answer_body text not null,
  allowed_placeholders jsonb not null default '[]'::jsonb,
  source_type text not null,
  source_message_id uuid,
  source_draft_revision_id uuid,
  content_sha256 text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint knowledge_article_revisions_article_fk
    foreign key (municipality_id, article_id)
    references public.knowledge_articles(municipality_id, id) on delete cascade,
  constraint knowledge_article_revisions_message_fk
    foreign key (municipality_id, source_message_id)
    references public.case_messages(municipality_id, id) on delete set null,
  constraint knowledge_article_revisions_draft_fk
    foreign key (municipality_id, source_draft_revision_id)
    references public.ai_draft_revisions(municipality_id, id) on delete set null,
  constraint knowledge_article_revisions_number_ck check (revision_number > 0),
  constraint knowledge_article_revisions_body_ck
    check (char_length(trim(answer_body)) between 1 and 20000),
  constraint knowledge_article_revisions_placeholders_ck
    check (jsonb_typeof(allowed_placeholders) = 'array'),
  constraint knowledge_article_revisions_source_ck
    check (source_type in ('fiscal_answer', 'approved_ai_draft', 'legal_seed', 'homologation_fixture')),
  constraint knowledge_article_revisions_hash_ck
    check (content_sha256 ~ '^[a-f0-9]{64}$'),
  constraint knowledge_article_revisions_number_uq
    unique (municipality_id, article_id, revision_number),
  constraint knowledge_article_revisions_municipality_id_id_uq
    unique (municipality_id, id)
);

create table if not exists public.knowledge_article_patterns (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  article_id uuid not null,
  phrase text not null,
  normalized_phrase text not null,
  match_mode text not null default 'exact',
  created_at timestamptz not null default now(),
  constraint knowledge_article_patterns_article_fk
    foreign key (municipality_id, article_id)
    references public.knowledge_articles(municipality_id, id) on delete cascade,
  constraint knowledge_article_patterns_mode_ck check (match_mode in ('exact', 'suggestion')),
  constraint knowledge_article_patterns_phrase_ck check (char_length(trim(phrase)) between 3 and 500),
  constraint knowledge_article_patterns_normalized_ck check (char_length(trim(normalized_phrase)) between 3 and 500),
  constraint knowledge_article_patterns_phrase_uq
    unique (municipality_id, normalized_phrase),
  constraint knowledge_article_patterns_municipality_id_id_uq
    unique (municipality_id, id)
);

create table if not exists public.knowledge_article_citations (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  revision_id uuid not null,
  legal_section_id uuid not null,
  source_version_id uuid not null,
  citation_label text not null,
  quoted_excerpt text not null,
  source_sha256 text not null,
  created_at timestamptz not null default now(),
  constraint knowledge_article_citations_revision_fk
    foreign key (municipality_id, revision_id)
    references public.knowledge_article_revisions(municipality_id, id) on delete cascade,
  constraint knowledge_article_citations_section_fk
    foreign key (municipality_id, legal_section_id)
    references public.legal_sections(municipality_id, id),
  constraint knowledge_article_citations_version_fk
    foreign key (municipality_id, source_version_id)
    references public.legal_source_versions(municipality_id, id),
  constraint knowledge_article_citations_hash_ck
    check (source_sha256 ~ '^[a-f0-9]{64}$'),
  constraint knowledge_article_citations_revision_section_uq
    unique (municipality_id, revision_id, legal_section_id),
  constraint knowledge_article_citations_municipality_id_id_uq
    unique (municipality_id, id)
);

create table if not exists public.knowledge_article_reviews (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  article_id uuid not null,
  revision_id uuid not null,
  decision text not null,
  reviewer_membership_id uuid not null,
  notes text,
  approved_content_sha256 text,
  reviewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint knowledge_article_reviews_article_fk
    foreign key (municipality_id, article_id)
    references public.knowledge_articles(municipality_id, id) on delete cascade,
  constraint knowledge_article_reviews_revision_fk
    foreign key (municipality_id, revision_id)
    references public.knowledge_article_revisions(municipality_id, id),
  constraint knowledge_article_reviews_membership_fk
    foreign key (municipality_id, reviewer_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint knowledge_article_reviews_decision_ck
    check (decision in ('approved', 'rejected', 'revision_requested')),
  constraint knowledge_article_reviews_hash_ck
    check ((decision = 'approved' and approved_content_sha256 ~ '^[a-f0-9]{64}$')
        or (decision <> 'approved' and approved_content_sha256 is null)),
  constraint knowledge_article_reviews_municipality_id_id_uq
    unique (municipality_id, id)
);

alter table public.case_questions
  add column if not exists handling_mode text not null default 'pending',
  add column if not exists routing_confidence numeric(5,4),
  add column if not exists routing_reason text,
  add column if not exists claimed_at timestamptz,
  add column if not exists sla_due_at timestamptz,
  add column if not exists last_activity_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.case_questions'::regclass
      and conname = 'case_questions_handling_mode_ck'
  ) then
    alter table public.case_questions
      add constraint case_questions_handling_mode_ck
      check (handling_mode in ('pending', 'approved_knowledge', 'ai_assist', 'human'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.case_questions'::regclass
      and conname = 'case_questions_confidence_ck'
  ) then
    alter table public.case_questions
      add constraint case_questions_confidence_ck
      check (routing_confidence is null or routing_confidence between 0 and 1);
  end if;
end;
$$;

create table if not exists public.fiscal_chat_inbox (
  question_id uuid primary key,
  municipality_id uuid not null references public.municipalities(id) on delete cascade,
  case_id uuid not null,
  taxpayer_id uuid not null,
  status text not null default 'waiting',
  priority integer not null default 100,
  question_preview text not null,
  handling_mode text not null default 'pending',
  assigned_membership_id uuid,
  routing_confidence numeric(5,4),
  routing_reason text,
  sla_due_at timestamptz,
  claimed_at timestamptz,
  answered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fiscal_chat_inbox_question_fk
    foreign key (municipality_id, question_id)
    references public.case_questions(municipality_id, id) on delete cascade,
  constraint fiscal_chat_inbox_case_fk
    foreign key (municipality_id, case_id)
    references public.fiscal_cases(municipality_id, id) on delete cascade,
  constraint fiscal_chat_inbox_taxpayer_fk
    foreign key (municipality_id, taxpayer_id)
    references public.taxpayers(municipality_id, id) on delete cascade,
  constraint fiscal_chat_inbox_assignment_fk
    foreign key (municipality_id, assigned_membership_id)
    references public.municipality_memberships(municipality_id, id),
  constraint fiscal_chat_inbox_status_ck
    check (status in ('waiting', 'claimed', 'answered', 'closed')),
  constraint fiscal_chat_inbox_handling_ck
    check (handling_mode in ('pending', 'approved_knowledge', 'ai_assist', 'human')),
  constraint fiscal_chat_inbox_priority_ck check (priority between 1 and 1000),
  constraint fiscal_chat_inbox_confidence_ck
    check (routing_confidence is null or routing_confidence between 0 and 1),
  constraint fiscal_chat_inbox_municipality_id_question_id_uq
    unique (municipality_id, question_id)
);

alter table public.case_messages
  add column if not exists source_knowledge_revision_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.case_messages'::regclass
      and conname = 'case_messages_source_knowledge_revision_fk'
  ) then
    alter table public.case_messages
      add constraint case_messages_source_knowledge_revision_fk
      foreign key (municipality_id, source_knowledge_revision_id)
      references public.knowledge_article_revisions(municipality_id, id);
  end if;
end;
$$;

alter table public.case_messages drop constraint if exists case_messages_source_type_check;
alter table public.case_messages
  add constraint case_messages_source_type_check
  check (source_type in ('human', 'approved_ai_draft', 'approved_knowledge', 'system'));

alter table public.case_messages drop constraint if exists case_messages_ai_source_ck;
alter table public.case_messages
  add constraint case_messages_governed_source_ck
  check (
    (source_type = 'approved_ai_draft' and source_draft_revision_id is not null and source_knowledge_revision_id is null)
    or (source_type = 'approved_knowledge' and source_knowledge_revision_id is not null and source_draft_revision_id is null)
    or (source_type not in ('approved_ai_draft', 'approved_knowledge')
        and source_draft_revision_id is null and source_knowledge_revision_id is null)
  );

create index if not exists case_explanations_case_current_idx
  on public.case_explanations(municipality_id, case_id, is_current, prepared_at desc);
create index if not exists knowledge_articles_lookup_idx
  on public.knowledge_articles(municipality_id, status, is_test, intent_key, semantic_version desc);
create index if not exists knowledge_article_patterns_lookup_idx
  on public.knowledge_article_patterns(municipality_id, match_mode, normalized_phrase);
create index if not exists knowledge_article_citations_revision_idx
  on public.knowledge_article_citations(municipality_id, revision_id);
create index if not exists knowledge_article_reviews_revision_idx
  on public.knowledge_article_reviews(municipality_id, revision_id, decision, reviewed_at desc);
create index if not exists fiscal_chat_inbox_queue_idx
  on public.fiscal_chat_inbox(municipality_id, status, priority, created_at);
create index if not exists case_questions_routing_idx
  on public.case_questions(municipality_id, status, handling_mode, submitted_at);

alter table public.municipality_portal_settings enable row level security;
alter table public.case_explanations enable row level security;
alter table public.knowledge_articles enable row level security;
alter table public.knowledge_article_revisions enable row level security;
alter table public.knowledge_article_patterns enable row level security;
alter table public.knowledge_article_citations enable row level security;
alter table public.knowledge_article_reviews enable row level security;
alter table public.fiscal_chat_inbox enable row level security;

drop policy if exists municipality_portal_settings_select on public.municipality_portal_settings;
create policy municipality_portal_settings_select
  on public.municipality_portal_settings for select to authenticated
  using ((select private.can_access_municipality(municipality_id)));

drop policy if exists case_explanations_select on public.case_explanations;
create policy case_explanations_select
  on public.case_explanations for select to authenticated
  using ((select private.can_access_case(municipality_id, case_id)));

drop policy if exists knowledge_articles_select_staff on public.knowledge_articles;
create policy knowledge_articles_select_staff
  on public.knowledge_articles for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['fiscal_auditor','supervisor','legal_reviewer']::text[]
  )));

drop policy if exists knowledge_article_revisions_select_staff on public.knowledge_article_revisions;
create policy knowledge_article_revisions_select_staff
  on public.knowledge_article_revisions for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['fiscal_auditor','supervisor','legal_reviewer']::text[]
  )));

drop policy if exists knowledge_article_patterns_select_staff on public.knowledge_article_patterns;
create policy knowledge_article_patterns_select_staff
  on public.knowledge_article_patterns for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['fiscal_auditor','supervisor','legal_reviewer']::text[]
  )));

drop policy if exists knowledge_article_citations_select_staff on public.knowledge_article_citations;
create policy knowledge_article_citations_select_staff
  on public.knowledge_article_citations for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['fiscal_auditor','supervisor','legal_reviewer']::text[]
  )));

drop policy if exists knowledge_article_reviews_select_staff on public.knowledge_article_reviews;
create policy knowledge_article_reviews_select_staff
  on public.knowledge_article_reviews for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['fiscal_auditor','supervisor','legal_reviewer']::text[]
  )));

drop policy if exists fiscal_chat_inbox_select_staff on public.fiscal_chat_inbox;
create policy fiscal_chat_inbox_select_staff
  on public.fiscal_chat_inbox for select to authenticated
  using ((select private.has_municipality_role(
    municipality_id,
    array['fiscal_auditor','supervisor','legal_reviewer']::text[]
  )));

revoke all on public.municipality_portal_settings from anon;
revoke all on public.case_explanations from anon;
revoke all on public.knowledge_articles from anon;
revoke all on public.knowledge_article_revisions from anon;
revoke all on public.knowledge_article_patterns from anon;
revoke all on public.knowledge_article_citations from anon;
revoke all on public.knowledge_article_reviews from anon;
revoke all on public.fiscal_chat_inbox from anon;

revoke insert, update, delete, truncate, references, trigger
  on public.municipality_portal_settings,
     public.case_explanations,
     public.knowledge_articles,
     public.knowledge_article_revisions,
     public.knowledge_article_patterns,
     public.knowledge_article_citations,
     public.knowledge_article_reviews,
     public.fiscal_chat_inbox
  from authenticated;

grant select on public.municipality_portal_settings,
                public.case_explanations,
                public.knowledge_articles,
                public.knowledge_article_revisions,
                public.knowledge_article_patterns,
                public.knowledge_article_citations,
                public.knowledge_article_reviews,
                public.fiscal_chat_inbox
  to authenticated;

create or replace function private.ia_normalize_question(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select trim(regexp_replace(
    translate(lower(coalesce(p_text, '')),
      'áàâãäéèêëíìîïóòôõöúùûüç',
      'aaaaaeeeeiiiiooooouuuuc'),
    '[^a-z0-9]+', ' ', 'g'
  ));
$$;

create or replace function private.sync_fiscal_chat_inbox()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.fiscal_cases%rowtype;
  v_message public.case_messages%rowtype;
begin
  select fc.* into strict v_case
  from public.fiscal_cases fc
  where fc.municipality_id = new.municipality_id
    and fc.id = new.case_id;

  select cm.* into strict v_message
  from public.case_messages cm
  where cm.municipality_id = new.municipality_id
    and cm.id = new.message_id;

  insert into public.fiscal_chat_inbox (
    question_id, municipality_id, case_id, taxpayer_id,
    status, priority, question_preview, handling_mode,
    assigned_membership_id, routing_confidence, routing_reason,
    sla_due_at, claimed_at, answered_at, created_at, updated_at
  )
  values (
    new.id, new.municipality_id, new.case_id, v_case.taxpayer_id,
    case when new.status = 'answered' then 'answered'
         when new.status = 'closed' then 'closed'
         when new.assigned_membership_id is not null then 'claimed'
         else 'waiting' end,
    100,
    left(v_message.body, 500),
    new.handling_mode,
    new.assigned_membership_id,
    new.routing_confidence,
    new.routing_reason,
    coalesce(new.sla_due_at, new.submitted_at + interval '4 hours'),
    new.claimed_at,
    new.answered_at,
    new.created_at,
    now()
  )
  on conflict (question_id) do update
    set status = excluded.status,
        handling_mode = excluded.handling_mode,
        assigned_membership_id = excluded.assigned_membership_id,
        routing_confidence = excluded.routing_confidence,
        routing_reason = excluded.routing_reason,
        sla_due_at = excluded.sla_due_at,
        claimed_at = excluded.claimed_at,
        answered_at = excluded.answered_at,
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists case_questions_sync_fiscal_inbox on public.case_questions;
create trigger case_questions_sync_fiscal_inbox
after insert or update of status, handling_mode, assigned_membership_id,
  routing_confidence, routing_reason, claimed_at, sla_due_at, answered_at
on public.case_questions
for each row execute function private.sync_fiscal_chat_inbox();

create or replace function private.prepare_case_explanation(p_case_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case public.fiscal_cases%rowtype;
  v_finding public.case_findings%rowtype;
  v_divergence public.divergences%rowtype;
  v_settings public.municipality_portal_settings%rowtype;
  v_title text;
  v_summary text;
  v_legal_summary text;
  v_citations jsonb;
  v_payload jsonb;
  v_hash text;
  v_existing_id uuid;
  v_version integer;
  v_id uuid;
  v_keys text[];
begin
  select fc.* into strict v_case
  from public.fiscal_cases fc
  where fc.id = p_case_id
  for share;

  select cf.* into strict v_finding
  from public.case_findings cf
  where cf.municipality_id = v_case.municipality_id
    and cf.case_id = v_case.id;

  select d.* into strict v_divergence
  from public.divergences d
  where d.municipality_id = v_case.municipality_id
    and d.id = v_case.divergence_id;

  select ps.* into strict v_settings
  from public.municipality_portal_settings ps
  where ps.municipality_id = v_case.municipality_id;

  if v_divergence.divergence_type = 'current_account_balance' then
    v_title := 'Débito municipal identificado para conferência';
    v_summary := format(
      'Foi identificado saldo municipal em aberto de R$ %s no período de %s a %s. A permanência da divergência pode motivar análise e eventual procedimento fiscal. Este registro ainda não é uma notificação fiscal formal.',
      v_finding.difference_amount::text,
      to_char(v_finding.period_start, 'MM/YYYY'),
      to_char(v_finding.period_end, 'MM/YYYY')
    );
    v_legal_summary := 'A Lei Complementar Municipal nº 399/2024, art. 215, fixa o recolhimento mensal do ISS de serviços prestados e tomados até o dia 15 do mês subsequente. Os arts. 103 e 104 disciplinam o início do procedimento fiscal e a formalização da exigência do crédito.';
    v_keys := array['lc399_art_103_106', 'lc399_art_215_218'];
  elsif v_divergence.divergence_type in ('factor_r', 'pgdasd_rbt12', 'pgdasd_sigiss_annex', 'pgdasd_sigiss_tax_base') then
    v_title := 'Divergência do Simples Nacional identificada para conferência';
    v_summary := format(
      'Foi identificada divergência do tipo %s na competência de %s a %s. O detalhamento utiliza o snapshot fiscal versionado do caso e não representa conclusão automática de infração.',
      v_divergence.divergence_type,
      to_char(v_finding.period_start, 'MM/YYYY'),
      to_char(v_finding.period_end, 'MM/YYYY')
    );
    v_legal_summary := 'O cálculo utiliza a Lei Complementar Federal nº 123/2006 e o Manual oficial do PGDAS-D, incluindo RBT12, FS12, Fator R e seleção dos Anexos III e V. A IA apenas explica o snapshot determinístico já calculado.';
    v_keys := array['lc123_art_18_simples', 'pgdas_manual_rbt12_factor_r'];
  else
    v_title := 'Divergência fiscal identificada para conferência';
    v_summary := 'O sistema identificou uma divergência fiscal que precisa de análise. Não há conclusão automática de infração.';
    v_legal_summary := 'A base legal deve ser confirmada pelo fiscal antes de qualquer comunicação formal.';
    v_keys := array['lc399_art_103_106'];
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'legal_section_id', ls.id,
    'section_key', ls.section_key,
    'heading', ls.heading,
    'excerpt', left(ls.content_text, 1200),
    'source_version_id', lsv.id,
    'source_status', lsv.status,
    'source_sha256', lsv.content_sha256,
    'source_title', lsrc.title,
    'official_identifier', lsrc.official_identifier,
    'official_url', lsrc.official_url
  ) order by ls.ordinal), '[]'::jsonb)
  into v_citations
  from public.legal_sections ls
  join public.legal_source_versions lsv
    on lsv.municipality_id = ls.municipality_id
   and lsv.id = ls.source_version_id
  join public.legal_sources lsrc
    on lsrc.municipality_id = lsv.municipality_id
   and lsrc.id = lsv.source_id
  where ls.municipality_id = v_case.municipality_id
    and ls.section_key = any(v_keys);

  v_payload := jsonb_build_object(
    'case_id', v_case.id,
    'case_number', v_case.case_number,
    'execution_mode', v_case.execution_mode,
    'divergence_type', v_divergence.divergence_type,
    'difference_amount', v_finding.difference_amount,
    'period_start', v_finding.period_start,
    'period_end', v_finding.period_end,
    'title', v_title,
    'summary', v_summary,
    'legal_basis_summary', v_legal_summary,
    'citations', v_citations,
    'official_system_url', v_settings.sigiss_login_url
  );
  v_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  select ce.id into v_existing_id
  from public.case_explanations ce
  where ce.municipality_id = v_case.municipality_id
    and ce.case_id = v_case.id
    and ce.is_current
    and ce.content_sha256 = v_hash;
  if v_existing_id is not null then
    return v_existing_id;
  end if;

  update public.case_explanations
     set is_current = false,
         status = 'superseded'
   where municipality_id = v_case.municipality_id
     and case_id = v_case.id
     and is_current;

  select coalesce(max(explanation_version), 0) + 1 into v_version
  from public.case_explanations
  where municipality_id = v_case.municipality_id
    and case_id = v_case.id;

  insert into public.case_explanations (
    municipality_id, case_id, explanation_version, is_current, status,
    title, summary, divergence_summary, legal_basis_summary,
    citations_snapshot, official_system_url, portal_path,
    legal_review_required, content_sha256
  )
  values (
    v_case.municipality_id, v_case.id, v_version, true,
    case when v_case.execution_mode = 'homologation_test' then 'ready_test' else 'draft_review' end,
    v_title, v_summary,
    jsonb_build_object(
      'divergence_type', v_divergence.divergence_type,
      'difference_amount', v_finding.difference_amount,
      'period_start', v_finding.period_start,
      'period_end', v_finding.period_end,
      'finding_id', v_finding.id,
      'finding_sha256', v_finding.content_sha256
    ),
    v_legal_summary, v_citations, v_settings.sigiss_login_url,
    '/casos/' || v_case.id::text,
    exists (
      select 1 from jsonb_array_elements(v_citations) c
      where c ->> 'source_status' <> 'published'
    ),
    v_hash
  )
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.ia_preview_initial_notice(
  p_case_id uuid,
  p_template_version_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_case public.fiscal_cases%rowtype;
  v_template public.notification_template_versions%rowtype;
  v_municipality public.municipalities%rowtype;
  v_settings public.municipality_portal_settings%rowtype;
  v_explanation public.case_explanations%rowtype;
  v_subject text;
  v_body text;
  v_portal_url text;
  v_blockers jsonb := '[]'::jsonb;
begin
  select fc.* into strict v_case from public.fiscal_cases fc where fc.id = p_case_id;
  if not (private.is_service_role() or private.can_access_case(v_case.municipality_id, v_case.id)) then
    raise exception 'case access denied';
  end if;
  select m.* into strict v_municipality from public.municipalities m where m.id = v_case.municipality_id;
  select ps.* into strict v_settings from public.municipality_portal_settings ps where ps.municipality_id = v_case.municipality_id;
  select ce.* into strict v_explanation from public.case_explanations ce
   where ce.municipality_id=v_case.municipality_id and ce.case_id=v_case.id and ce.is_current;

  if p_template_version_id is not null then
    select ntv.* into strict v_template
    from public.notification_template_versions ntv
    where ntv.municipality_id=v_case.municipality_id and ntv.id=p_template_version_id;
  else
    select ntv.* into strict v_template
    from public.notification_template_versions ntv
    join public.notification_templates nt
      on nt.municipality_id=ntv.municipality_id and nt.id=ntv.template_id
    where ntv.municipality_id=v_case.municipality_id
      and nt.code='initial_inspection_alert_sandbox'
    order by ntv.version desc limit 1;
  end if;

  v_portal_url := case when v_settings.case_portal_base_url is null then null
    else rtrim(v_settings.case_portal_base_url, '/') || v_explanation.portal_path end;
  v_subject := replace(v_template.subject, '{{municipality_name}}', v_municipality.name);
  v_body := replace(v_template.body_text, '{{municipality_name}}', v_municipality.name);
  v_body := replace(v_body, '{{sigiss_login_url}}', v_settings.sigiss_login_url);
  v_body := replace(v_body, '{{case_portal_url}}', coalesce(v_portal_url, '[portal ainda não configurado]'));

  if v_template.status <> 'active' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','template_not_active','status',v_template.status));
  end if;
  if v_settings.case_portal_base_url is null then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','case_portal_url_missing'));
  end if;
  if not v_settings.external_email_enabled then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','external_email_disabled'));
  end if;
  if v_explanation.legal_review_required then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','legal_review_required'));
  end if;

  return jsonb_build_object(
    'case_id', v_case.id,
    'case_number', v_case.case_number,
    'execution_mode', v_case.execution_mode,
    'template_version_id', v_template.id,
    'template_version', v_template.version,
    'subject', v_subject,
    'body_text', v_body,
    'sigiss_login_url', v_settings.sigiss_login_url,
    'case_portal_url', v_portal_url,
    'ready_for_external_delivery', jsonb_array_length(v_blockers)=0 and v_case.execution_mode='live',
    'blockers', v_blockers
  );
end;
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
  v_membership public.municipality_memberships%rowtype;
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
  select mm.* into strict v_membership
  from public.municipality_memberships mm
  where mm.municipality_id=v_question.municipality_id
    and mm.user_id=auth.uid()
    and mm.status='active'
    and mm.role in ('fiscal_auditor','supervisor','legal_reviewer')
  limit 1;

  if v_question.assigned_membership_id is not null
     and v_question.assigned_membership_id <> v_membership.id then
    raise exception 'question already claimed';
  end if;

  if not exists (
    select 1 from public.case_assignments ca
    where ca.municipality_id=v_question.municipality_id
      and ca.case_id=v_question.case_id
      and ca.membership_id=v_membership.id
      and ca.status='active'
  ) then
    insert into public.case_assignments (
      municipality_id,case_id,membership_id,assignment_role,status,assigned_by
    ) values (
      v_question.municipality_id,v_question.case_id,v_membership.id,
      'responsible_fiscal','active',auth.uid()
    );
  end if;

  update public.case_questions
     set status='awaiting_fiscal',
         assigned_membership_id=v_membership.id,
         handling_mode=p_handling_mode,
         claimed_at=coalesce(claimed_at,now()),
         last_activity_at=now()
   where municipality_id=v_question.municipality_id and id=v_question.id;

  insert into public.case_events (
    municipality_id,case_id,event_type,visibility,actor_type,actor_user_id,event_data
  ) values (
    v_question.municipality_id,v_question.case_id,'case_question_claimed','staff','staff',auth.uid(),
    jsonb_build_object('question_id',v_question.id,'membership_id',v_membership.id,'handling_mode',p_handling_mode)
  );
  return v_membership.id;
end;
$$;

create or replace function private.capture_answer_as_knowledge_candidate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_question public.case_questions%rowtype;
  v_question_message public.case_messages%rowtype;
  v_article_id uuid;
  v_revision_id uuid;
  v_normalized text;
  v_intent text;
begin
  if new.status <> 'published' or new.sender_type <> 'fiscal'
     or new.source_type not in ('human','approved_ai_draft') then
    return new;
  end if;

  if new.source_type='approved_ai_draft' then
    select cq.* into v_question
    from public.ai_draft_revisions adr
    join public.ai_drafts ad on ad.municipality_id=adr.municipality_id and ad.id=adr.draft_id
    join public.case_questions cq on cq.municipality_id=ad.municipality_id and cq.id=ad.question_id
    where adr.municipality_id=new.municipality_id and adr.id=new.source_draft_revision_id;
  elsif new.parent_message_id is not null then
    select cq.* into v_question
    from public.case_questions cq
    where cq.municipality_id=new.municipality_id and cq.message_id=new.parent_message_id;
  end if;
  if v_question.id is null then return new; end if;

  select cm.* into strict v_question_message
  from public.case_messages cm
  where cm.municipality_id=v_question.municipality_id and cm.id=v_question.message_id;
  v_normalized := private.ia_normalize_question(v_question_message.body);
  v_intent := 'qa-' || substr(encode(extensions.digest(v_normalized,'sha256'),'hex'),1,20);

  insert into public.knowledge_articles (
    municipality_id,intent_key,semantic_version,canonical_question,tax_scope,divergence_scope,
    status,current_revision_number,is_test,approval_basis,source_question_id,source_message_id,created_by
  ) values (
    new.municipality_id,v_intent,1,v_question_message.body,'fiscal_case_answer','case_chat',
    'under_review',1,false,'fiscal_review',v_question.id,new.id,new.author_user_id
  )
  on conflict (municipality_id,source_message_id) do nothing
  returning id into v_article_id;
  if v_article_id is null then return new; end if;

  insert into public.knowledge_article_revisions (
    municipality_id,article_id,revision_number,answer_body,allowed_placeholders,
    source_type,source_message_id,source_draft_revision_id,content_sha256,created_by
  ) values (
    new.municipality_id,v_article_id,1,new.body,'[]'::jsonb,
    case when new.source_type='approved_ai_draft' then 'approved_ai_draft' else 'fiscal_answer' end,
    new.id,new.source_draft_revision_id,new.content_sha256,new.author_user_id
  ) returning id into v_revision_id;

  insert into public.knowledge_article_patterns (
    municipality_id,article_id,phrase,normalized_phrase,match_mode
  ) values (new.municipality_id,v_article_id,v_question_message.body,v_normalized,'exact')
  on conflict (municipality_id,normalized_phrase) do nothing;

  if new.source_type='approved_ai_draft' then
    insert into public.knowledge_article_citations (
      municipality_id,revision_id,legal_section_id,source_version_id,
      citation_label,quoted_excerpt,source_sha256
    )
    select c.municipality_id,v_revision_id,c.legal_section_id,c.source_version_id,
           c.citation_label,c.quoted_excerpt,c.source_sha256
    from public.ai_draft_citations c
    where c.municipality_id=new.municipality_id
      and c.draft_revision_id=new.source_draft_revision_id
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists case_messages_capture_knowledge_candidate on public.case_messages;
create trigger case_messages_capture_knowledge_candidate
after insert on public.case_messages
for each row execute function private.capture_answer_as_knowledge_candidate();

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
  v_thread_id uuid;
  v_message_id uuid;
  v_body text := trim(coalesce(p_body,''));
  v_client_request_id text := nullif(trim(coalesce(p_client_request_id,'')),'');
begin
  if auth.uid() is null or not private.is_aal2() then raise exception 'aal2 authentication required'; end if;
  if char_length(v_body) not between 1 and 20000 then raise exception 'response must contain between 1 and 20000 characters'; end if;
  if v_client_request_id is null or char_length(v_client_request_id)>200 then raise exception 'valid client_request_id required'; end if;
  select cq.* into strict v_question from public.case_questions cq where cq.id=p_question_id for update;
  if not private.can_review_case(v_question.municipality_id,v_question.case_id) then raise exception 'response access denied'; end if;
  if v_question.status in ('answered','closed') then
    select cm.id into v_message_id from public.case_messages cm
    where cm.municipality_id=v_question.municipality_id and cm.client_request_id=v_client_request_id;
    if v_message_id is not null then return v_message_id; end if;
    raise exception 'question already answered';
  end if;
  select ct.id into strict v_thread_id from public.case_threads ct
   where ct.municipality_id=v_question.municipality_id and ct.case_id=v_question.case_id and ct.status='open';
  insert into public.case_messages (
    municipality_id,thread_id,case_id,parent_message_id,sender_type,author_user_id,
    source_type,visibility,body,content_sha256,status,client_request_id,published_at
  ) values (
    v_question.municipality_id,v_thread_id,v_question.case_id,v_question.message_id,
    'fiscal',auth.uid(),'human','participants',v_body,
    encode(extensions.digest(v_body,'sha256'),'hex'),'published',v_client_request_id,now()
  ) returning id into v_message_id;
  update public.case_questions set status='answered',handling_mode='human',answered_at=now(),last_activity_at=now()
   where municipality_id=v_question.municipality_id and id=v_question.id;
  update public.fiscal_cases set status='awaiting_taxpayer'
   where municipality_id=v_question.municipality_id and id=v_question.case_id
     and status not in ('resolved','closed','cancelled');
  insert into public.case_events (
    municipality_id,case_id,event_type,visibility,actor_type,actor_user_id,event_data
  ) values (
    v_question.municipality_id,v_question.case_id,'manual_response_published','participants','staff',auth.uid(),
    jsonb_build_object('question_id',v_question.id,'message_id',v_message_id)
  );
  return v_message_id;
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
  select mm.id into strict v_membership_id from public.municipality_memberships mm
   where mm.municipality_id=v_article.municipality_id and mm.user_id=auth.uid()
     and mm.status='active' and mm.role in ('fiscal_auditor','supervisor','legal_reviewer') limit 1;
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
begin
  if auth.uid() is null or not private.is_aal2() then raise exception 'aal2 authentication required'; end if;
  if p_confirmation <> 'PUBLICAR' then raise exception 'explicit publication confirmation required'; end if;
  select ka.* into strict v_article from public.knowledge_articles ka where ka.id=p_article_id for update;
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

create or replace view public.vw_reusable_knowledge_articles
with (security_invoker = true)
as
select
  ka.municipality_id,
  ka.id as article_id,
  ka.intent_key,
  ka.semantic_version,
  ka.canonical_question,
  ka.tax_scope,
  ka.divergence_scope,
  ka.is_test,
  kar.id as revision_id,
  kar.answer_body,
  kar.allowed_placeholders,
  kar.content_sha256,
  ka.valid_from,
  ka.valid_until,
  ka.published_at
from public.knowledge_articles ka
join public.knowledge_article_revisions kar
  on kar.municipality_id=ka.municipality_id and kar.article_id=ka.id
 and kar.revision_number=ka.current_revision_number
where ka.status='published'
  and (ka.valid_from is null or ka.valid_from<=now())
  and (ka.valid_until is null or ka.valid_until>now())
  and exists (
    select 1 from public.knowledge_article_citations kac
    where kac.municipality_id=ka.municipality_id and kac.revision_id=kar.id
  )
  and (
    (ka.is_test and ka.approval_basis='homologation_fixture')
    or (
      not ka.is_test
      and ka.approval_basis='fiscal_review'
      and exists (
        select 1 from public.knowledge_article_reviews kr
        where kr.municipality_id=ka.municipality_id and kr.article_id=ka.id
          and kr.revision_id=kar.id and kr.decision='approved'
          and kr.approved_content_sha256=kar.content_sha256
      )
      and not exists (
        select 1 from public.knowledge_article_citations kac
        join public.legal_source_versions lsv on lsv.municipality_id=kac.municipality_id and lsv.id=kac.source_version_id
        where kac.municipality_id=ka.municipality_id and kac.revision_id=kar.id
          and (lsv.status<>'published' or lsv.content_sha256<>kac.source_sha256
               or (lsv.valid_until is not null and lsv.valid_until<=current_date))
      )
    )
  );

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

create or replace view public.vw_case_portal_home
with (security_invoker = true)
as
select
  fc.municipality_id,
  fc.id as case_id,
  fc.case_number,
  fc.taxpayer_id,
  t.legal_name as taxpayer_name,
  fc.status as case_status,
  fc.execution_mode,
  ce.id as explanation_id,
  ce.explanation_version,
  ce.status as explanation_status,
  ce.title,
  ce.summary,
  ce.divergence_summary,
  ce.legal_basis_summary,
  ce.citations_snapshot,
  ce.official_system_url,
  ce.portal_path,
  ce.legal_review_required,
  ct.id as thread_id,
  ct.status as thread_status,
  ce.prepared_at
from public.fiscal_cases fc
join public.taxpayers t on t.municipality_id=fc.municipality_id and t.id=fc.taxpayer_id
join public.case_explanations ce on ce.municipality_id=fc.municipality_id and ce.case_id=fc.id and ce.is_current
left join public.case_threads ct on ct.municipality_id=fc.municipality_id and ct.case_id=fc.id;

create or replace view public.vw_taxpayer_history
with (security_invoker = true)
as
select fc.municipality_id,fc.taxpayer_id,ce.case_id,ce.occurred_at as event_at,
       'case_event'::text as item_type,ce.event_type as title,
       ce.event_type as summary,ce.visibility,ce.event_data as payload
from public.case_events ce
join public.fiscal_cases fc on fc.municipality_id=ce.municipality_id and fc.id=ce.case_id
union all
select fc.municipality_id,fc.taxpayer_id,n.case_id,n.prepared_at,
       'notification'::text,n.subject_snapshot,left(n.body_text_snapshot,500),'staff'::text,
       jsonb_build_object('notification_id',n.id,'status',n.status,'delivery_mode',n.delivery_mode,
         'external_delivery_attempted',n.external_delivery_attempted)
from public.notifications n
join public.fiscal_cases fc on fc.municipality_id=n.municipality_id and fc.id=n.case_id
union all
select fc.municipality_id,fc.taxpayer_id,cm.case_id,cm.created_at,
       'chat_message'::text,cm.sender_type,left(cm.body,500),cm.visibility,
       jsonb_build_object('message_id',cm.id,'sender_type',cm.sender_type,'source_type',cm.source_type,'status',cm.status)
from public.case_messages cm
join public.fiscal_cases fc on fc.municipality_id=cm.municipality_id and fc.id=cm.case_id
union all
select fc.municipality_id,fc.taxpayer_id,cd.case_id,cd.created_at,
       'document'::text,cd.original_file_name,cd.media_type,'staff'::text,
       jsonb_build_object('document_id',cd.id,'status',cd.status,'malware_scan_status',cd.malware_scan_status)
from public.case_documents cd
join public.fiscal_cases fc on fc.municipality_id=cd.municipality_id and fc.id=cd.case_id;

create or replace view public.vw_fiscal_chat_inbox
with (security_invoker = true)
as
select
  fi.municipality_id,fi.question_id,fi.case_id,fc.case_number,fi.taxpayer_id,
  t.legal_name as taxpayer_name,fi.status,fi.priority,fi.question_preview,
  fi.handling_mode,fi.assigned_membership_id,fi.routing_confidence,fi.routing_reason,
  fi.sla_due_at,fi.claimed_at,fi.answered_at,fi.created_at,fi.updated_at
from public.fiscal_chat_inbox fi
join public.fiscal_cases fc on fc.municipality_id=fi.municipality_id and fc.id=fi.case_id
join public.taxpayers t on t.municipality_id=fi.municipality_id and t.id=fi.taxpayer_id;

grant select on public.vw_case_portal_home,
                public.vw_taxpayer_history,
                public.vw_fiscal_chat_inbox,
                public.vw_reusable_knowledge_articles
to authenticated;
revoke all on public.vw_case_portal_home,
              public.vw_taxpayer_history,
              public.vw_fiscal_chat_inbox,
              public.vw_reusable_knowledge_articles
from anon;

revoke all on function public.ia_preview_initial_notice(uuid,uuid) from public,anon;
grant execute on function public.ia_preview_initial_notice(uuid,uuid) to authenticated,service_role;
revoke all on function public.ia_claim_case_question(uuid,text) from public,anon;
grant execute on function public.ia_claim_case_question(uuid,text) to authenticated;
revoke all on function public.ia_publish_manual_response(uuid,text,text) from public,anon;
grant execute on function public.ia_publish_manual_response(uuid,text,text) to authenticated;
revoke all on function public.ia_review_knowledge_article(uuid,uuid,text,text) from public,anon;
grant execute on function public.ia_review_knowledge_article(uuid,uuid,text,text) to authenticated;
revoke all on function public.ia_publish_knowledge_article(uuid,text) from public,anon;
grant execute on function public.ia_publish_knowledge_article(uuid,text) to authenticated;
revoke all on function public.ia_route_case_question_from_knowledge(uuid) from public,anon,authenticated;
grant execute on function public.ia_route_case_question_from_knowledge(uuid) to service_role;
revoke all on function private.prepare_case_explanation(uuid) from public,anon,authenticated;
revoke all on function private.sync_fiscal_chat_inbox() from public,anon,authenticated;
revoke all on function private.capture_answer_as_knowledge_candidate() from public,anon,authenticated;
revoke all on function private.ia_normalize_question(text) from public,anon,authenticated;

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
  v_without_allowed_hrefs text;
begin
  -- Literal URLs remain forbidden. HTML links are accepted only when their entire
  -- href is one of the two governed URL placeholders rendered from tenant settings.
  v_without_allowed_hrefs := replace(v_combined, 'href="{{sigiss_login_url}}"', '');
  v_without_allowed_hrefs := replace(v_without_allowed_hrefs, 'href="{{case_portal_url}}"', '');
  v_without_allowed_hrefs := replace(v_without_allowed_hrefs, 'href=''{{sigiss_login_url}}''', '');
  v_without_allowed_hrefs := replace(v_without_allowed_hrefs, 'href=''{{case_portal_url}}''', '');
  if v_without_allowed_hrefs ~ 'https?://' or v_without_allowed_hrefs ~ 'href[[:space:]]*=' then
    raise exception 'initial notice contains a non-governed link';
  end if;
  if v_combined ~ '\\{\\{[[:space:]]*(amount|value|difference|period|case_id|tax_id|cnpj|cpf)' then
    raise exception 'initial notice contains a prohibited placeholder';
  end if;
  if exists (
    select 1
    from unnest(new.allowed_placeholders) p
    where p not in ('municipality_name','sigiss_login_url','case_portal_url')
  ) then
    raise exception 'unsupported placeholder in initial notice template';
  end if;
  return new;
end;
$$;

insert into public.municipality_portal_settings (
  municipality_id,sigiss_login_url,case_portal_base_url,official_help_url,external_email_enabled
)
select id,'https://cordeiropolis.sigissweb.com/',null,
       'https://cordeiropolis.sp.gov.br/servicos/empresa/',false
from public.municipalities where slug='cordeiropolis-sp'
on conflict (municipality_id) do update
set sigiss_login_url=excluded.sigiss_login_url,
    official_help_url=excluded.official_help_url,
    external_email_enabled=false,
    updated_at=now();

insert into public.municipality_portal_settings (
  municipality_id,sigiss_login_url,case_portal_base_url,official_help_url,external_email_enabled
)
select id,'https://araras.sigissweb.com/',null,
       'https://araras.sp.gov.br/',false
from public.municipalities where slug='araras-sp'
on conflict (municipality_id) do update
set sigiss_login_url=excluded.sigiss_login_url,
    official_help_url=excluded.official_help_url,
    external_email_enabled=false,
    updated_at=now();

-- Targeted legal sections from official sources. They remain under review until a municipal reviewer publishes them.
with target as (
  select lsv.municipality_id,lsv.id source_version_id
  from public.legal_source_versions lsv
  join public.legal_sources ls on ls.municipality_id=lsv.municipality_id and ls.id=lsv.source_id
  join public.municipalities m on m.id=lsv.municipality_id
  where m.slug='cordeiropolis-sp' and ls.official_identifier='Lei Complementar nº 399/2024'
), sections(section_key,heading,ordinal,content_text) as (values
  ('lc399_art_98_102','LC 399/2024 — arts. 98 a 102 — ciência e notificação',1,
   'Art. 98: a ciência dos atos e decisões pode ocorrer pessoalmente, por carta registrada, no domicílio tributário eletrônico regularmente instituído ou por edital. O domicílio eletrônico depende de regulamentação por decreto, com requisitos de acesso, sigilo, segurança e comunicação. Art. 99: define quando a intimação se presume realizada. Arts. 101 e 102: a notificação de lançamento deve conter qualificação, valor e natureza do crédito, prazo para recolhimento e impugnação, disposição legal e penalidade quando cabíveis.'),
  ('lc399_art_103_106','LC 399/2024 — arts. 103 a 106 — procedimento fiscal',2,
   'Art. 103: o procedimento fiscal terá início por termo de início de fiscalização, termo de apreensão, notificação preliminar, auto de infração e imposição de multa ou qualquer ato da administração que caracterize o início de apuração do crédito tributário. Art. 104: a exigência do crédito será formalizada por notificação preliminar, notificação de lançamento ou auto de infração e imposição de multa, distinto por tributo. Art. 106: a autoridade que realizar exames e diligências lavrará termo circunstanciado com período fiscalizado, documentos examinados e demais fatos relevantes.'),
  ('lc399_art_214','LC 399/2024 — art. 214 — livros e documentos fiscais',3,
   'Art. 214, §§ 3º a 7º: livros, comprovantes e documentação de interesse tributário devem ser conservados até a decadência e prescrição; contribuintes, tomadores e intermediários devem exibir e permitir o exame de mercadorias, livros, arquivos, documentos e papéis de efeitos comerciais e fiscais; o regulamento definirá documentos, avisos, declarações, prazos e formas de escrituração.'),
  ('lc399_art_215_218','LC 399/2024 — arts. 215 a 218 — lançamento e recolhimento do ISS',4,
   'Art. 215: o ISS correspondente aos serviços prestados e tomados em cada mês será recolhido até o dia 15 do mês subsequente ao fato gerador, mediante guia própria e independentemente de aviso ou notificação. Os prestadores e tomadores também devem cumprir os encerramentos e escriturações previstos até o dia 15 do mês subsequente. Art. 216: trabalho pessoal e sociedades profissionais seguem o vencimento do aviso de lançamento. Art. 217: o ISS retido na fonte será recolhido até o dia 15 do mês subsequente. Art. 218: a Administração poderá adotar outra forma de recolhimento conforme a peculiaridade da atividade.'),
  ('lc399_art_275','LC 399/2024 — art. 275 — penalidades do ISSQN',5,
   'Art. 275: a inobservância das disposições relativas ao ISSQN sujeita o contribuinte ou responsável às penalidades legais. O dispositivo diferencia infrações de recolhimento, declarações, livros, documentos fiscais e procedimento fiscal. Qualquer penalidade depende da apuração e do procedimento aplicável; a existência de divergência sistêmica, isoladamente, não constitui conclusão automática de infração, fraude ou sonegação.')
)
insert into public.legal_sections (
  municipality_id,source_version_id,section_key,heading,ordinal,content_text,content_sha256
)
select t.municipality_id,t.source_version_id,s.section_key,s.heading,s.ordinal,s.content_text,
       encode(extensions.digest(s.content_text,'sha256'),'hex')
from target t cross join sections s
on conflict (municipality_id,source_version_id,section_key) do nothing;

with target as (
  select lsv.municipality_id,lsv.id source_version_id,lsv.content_text
  from public.legal_source_versions lsv
  join public.legal_sources ls on ls.municipality_id=lsv.municipality_id and ls.id=lsv.source_id
  join public.municipalities m on m.id=lsv.municipality_id
  where m.slug='cordeiropolis-sp' and ls.official_identifier like 'Lei Complementar nº 123/2006%'
)
insert into public.legal_sections (
  municipality_id,source_version_id,section_key,heading,ordinal,content_text,content_sha256
)
select municipality_id,source_version_id,'lc123_art_18_simples',
       'LC 123/2006 — art. 18 — alíquota efetiva, anexos e Fator R',1,content_text,
       encode(extensions.digest(content_text,'sha256'),'hex')
from target
on conflict (municipality_id,source_version_id,section_key) do nothing;

with target as (
  select lsv.municipality_id,lsv.id source_version_id,lsv.content_text
  from public.legal_source_versions lsv
  join public.legal_sources ls on ls.municipality_id=lsv.municipality_id and ls.id=lsv.source_id
  join public.municipalities m on m.id=lsv.municipality_id
  where m.slug='cordeiropolis-sp' and ls.official_identifier='Manual PGDAS-D 2018 v4'
)
insert into public.legal_sections (
  municipality_id,source_version_id,section_key,heading,ordinal,content_text,content_sha256
)
select municipality_id,source_version_id,'pgdas_manual_rbt12_factor_r',
       'Manual PGDAS-D — RBT12, FS12, Fator R e início de atividade',1,content_text,
       encode(extensions.digest(content_text,'sha256'),'hex')
from target
on conflict (municipality_id,source_version_id,section_key) do nothing;

insert into private.legal_chunks (
  municipality_id,legal_section_id,chunk_index,content_text,token_count,content_sha256
)
select ls.municipality_id,ls.id,0,ls.content_text,
       greatest(1,array_length(regexp_split_to_array(trim(ls.content_text),'\\s+'),1)),
       ls.content_sha256
from public.legal_sections ls
join public.legal_source_versions lsv on lsv.municipality_id=ls.municipality_id and lsv.id=ls.source_version_id
join public.legal_sources src on src.municipality_id=lsv.municipality_id and src.id=lsv.source_id
join public.municipalities m on m.id=ls.municipality_id
where m.slug='cordeiropolis-sp'
  and ls.section_key in ('lc399_art_98_102','lc399_art_103_106','lc399_art_214','lc399_art_215_218','lc399_art_275','lc123_art_18_simples','pgdas_manual_rbt12_factor_r')
on conflict (municipality_id,legal_section_id,chunk_index) do nothing;

-- Attach reviewed source candidates to the existing draft release and rule versions.
insert into public.knowledge_release_items (municipality_id,release_id,source_version_id)
select kr.municipality_id,kr.id,lsv.id
from public.knowledge_releases kr
join public.legal_source_versions lsv on lsv.municipality_id=kr.municipality_id
join public.legal_sources ls on ls.municipality_id=lsv.municipality_id and ls.id=lsv.source_id
join public.municipalities m on m.id=kr.municipality_id
where m.slug='cordeiropolis-sp'
  and kr.name='Base legal ISSQN — Conta Corrente'
  and ls.official_identifier='Lei Complementar nº 399/2024'
on conflict (municipality_id,release_id,source_version_id) do nothing;

insert into public.rule_legal_basis (
  municipality_id,rule_version_id,knowledge_release_id,legal_section_id,basis_type
)
select drv.municipality_id,drv.id,kr.id,ls.id,
       case when ls.section_key='lc399_art_215_218' then 'primary' else 'procedure' end
from public.divergence_rule_versions drv
join public.divergence_rules dr on dr.municipality_id=drv.municipality_id and dr.id=drv.rule_id
join public.knowledge_releases kr on kr.municipality_id=drv.municipality_id and kr.name='Base legal ISSQN — Conta Corrente'
join public.legal_sections ls on ls.municipality_id=drv.municipality_id and ls.section_key in ('lc399_art_103_106','lc399_art_215_218')
join public.municipalities m on m.id=drv.municipality_id
where m.slug='cordeiropolis-sp' and dr.code='current-account-balance-homologation-v1'
  and not exists (
    select 1 from public.rule_legal_basis rlb
    where rlb.municipality_id=drv.municipality_id and rlb.rule_version_id=drv.id
      and rlb.knowledge_release_id=kr.id and rlb.legal_section_id=ls.id
  );

-- Notification v3: simple email, official SIGISS link, secure case portal link, no fiscal detail in email.
with target as (
  select nt.municipality_id,nt.id template_id
  from public.notification_templates nt
  join public.municipalities m on m.id=nt.municipality_id
  where m.slug='cordeiropolis-sp' and nt.code='initial_inspection_alert_sandbox'
), content as (
  select
    'Aviso para conferência de débito municipal — {{municipality_name}}'::text subject,
    E'Prezado contribuinte ou representante,\n\nA Prefeitura de {{municipality_name}} identificou um débito municipal vencido que precisa ser conferido. A permanência da pendência pode resultar na abertura de procedimento fiscal, conforme a legislação municipal aplicável.\n\nAcesse o SIGISSWEB oficial para entrar com seu login:\n{{sigiss_login_url}}\n\nApós a autenticação, consulte no Portal IA Fiscal o motivo, as competências, os valores e a base legal do caso:\n{{case_portal_url}}\n\nEste e-mail é um aviso informativo e não substitui notificação fiscal formal. Se o débito já foi pago, parcelado, compensado, suspenso ou contestado, envie o comprovante pelo canal autenticado. Não responda com documentos fiscais ou dados pessoais por e-mail.'::text body_text,
    '<p>Prezado contribuinte ou representante,</p><p>A Prefeitura de <strong>{{municipality_name}}</strong> identificou um débito municipal vencido que precisa ser conferido. A permanência da pendência pode resultar na abertura de procedimento fiscal, conforme a legislação municipal aplicável.</p><p><a href="{{sigiss_login_url}}">Acessar o SIGISSWEB oficial</a></p><p><a href="{{case_portal_url}}">Consultar motivo, competências, valores e base legal no Portal IA Fiscal</a></p><p>Este e-mail é um aviso informativo e não substitui notificação fiscal formal. Não responda com documentos fiscais ou dados pessoais por e-mail.</p>'::text body_html
)
insert into public.notification_template_versions (
  municipality_id,template_id,version,status,subject,body_text,body_html,
  allowed_placeholders,content_sha256
)
select t.municipality_id,t.template_id,3,'draft',c.subject,c.body_text,c.body_html,
       array['municipality_name','sigiss_login_url','case_portal_url']::text[],
       encode(extensions.digest(c.subject||E'\n'||c.body_text||E'\n'||c.body_html,'sha256'),'hex')
from target t cross join content c
where not exists (
  select 1 from public.notification_template_versions v
  where v.municipality_id=t.municipality_id and v.template_id=t.template_id and v.version=3
);

-- Homologation-only supervised answers. They prove routing but are never eligible for live cases.
with municipality as (
  select id from public.municipalities where slug='cordeiropolis-sp'
)
insert into public.knowledge_articles (
  municipality_id,intent_key,semantic_version,canonical_question,tax_scope,divergence_scope,
  status,current_revision_number,is_test,approval_basis,valid_from,published_at
)
select id,'why-overdue-iss-may-trigger-inspection',1,
       'Por que posso sofrer fiscalização por causa deste débito municipal?',
       'ISSQN','current_account_balance','published',1,true,'homologation_fixture',now(),now()
from municipality
on conflict (municipality_id,intent_key,semantic_version) do nothing;

with article as (
  select ka.municipality_id,ka.id
  from public.knowledge_articles ka join public.municipalities m on m.id=ka.municipality_id
  where m.slug='cordeiropolis-sp' and ka.intent_key='why-overdue-iss-may-trigger-inspection' and ka.semantic_version=1
), body as (
  select E'{{case_summary}}\n\n{{legal_basis_summary}}\n\nVocê pode conferir os dados no ambiente autenticado. Se houver pagamento, parcelamento, compensação, suspensão ou contestação, apresente o comprovante ao fiscal. Esta resposta é informativa e não constitui lançamento, auto de infração ou conclusão de fraude.'::text value
)
insert into public.knowledge_article_revisions (
  municipality_id,article_id,revision_number,answer_body,allowed_placeholders,
  source_type,content_sha256
)
select a.municipality_id,a.id,1,b.value,
       '["case_summary","legal_basis_summary","official_system_url"]'::jsonb,
       'homologation_fixture',encode(extensions.digest(b.value,'sha256'),'hex')
from article a cross join body b
on conflict (municipality_id,article_id,revision_number) do nothing;

with article as (
  select ka.municipality_id,ka.id
  from public.knowledge_articles ka join public.municipalities m on m.id=ka.municipality_id
  where m.slug='cordeiropolis-sp' and ka.intent_key='why-overdue-iss-may-trigger-inspection' and ka.semantic_version=1
), phrases(phrase) as (values
  ('Por que posso sofrer fiscalização por causa deste débito municipal?'),
  ('Por que minha empresa pode sofrer fiscalização?'),
  ('Por que recebi este aviso de débito?'),
  ('O que está em atraso?')
)
insert into public.knowledge_article_patterns (
  municipality_id,article_id,phrase,normalized_phrase,match_mode
)
select a.municipality_id,a.id,p.phrase,private.ia_normalize_question(p.phrase),'exact'
from article a cross join phrases p
on conflict (municipality_id,normalized_phrase) do nothing;

with article as (
  select ka.municipality_id,ka.id
  from public.knowledge_articles ka join public.municipalities m on m.id=ka.municipality_id
  where m.slug='cordeiropolis-sp' and ka.intent_key='why-overdue-iss-may-trigger-inspection' and ka.semantic_version=1
), revision as (
  select kar.municipality_id,kar.id
  from public.knowledge_article_revisions kar join article a on a.municipality_id=kar.municipality_id and a.id=kar.article_id
  where kar.revision_number=1
)
insert into public.knowledge_article_citations (
  municipality_id,revision_id,legal_section_id,source_version_id,citation_label,quoted_excerpt,source_sha256
)
select r.municipality_id,r.id,ls.id,lsv.id,ls.heading,left(ls.content_text,1200),lsv.content_sha256
from revision r
join public.legal_sections ls on ls.municipality_id=r.municipality_id and ls.section_key in ('lc399_art_103_106','lc399_art_215_218')
join public.legal_source_versions lsv on lsv.municipality_id=ls.municipality_id and lsv.id=ls.source_version_id
on conflict (municipality_id,revision_id,legal_section_id) do nothing;

select private.prepare_case_explanation(fc.id)
from public.fiscal_cases fc
join public.municipalities m on m.id=fc.municipality_id
where m.slug='cordeiropolis-sp' and fc.execution_mode='homologation_test';

-- Existing questions, if any, receive inbox rows.
insert into public.fiscal_chat_inbox (
  question_id,municipality_id,case_id,taxpayer_id,status,priority,question_preview,
  handling_mode,assigned_membership_id,routing_confidence,routing_reason,sla_due_at,
  claimed_at,answered_at,created_at,updated_at
)
select cq.id,cq.municipality_id,cq.case_id,fc.taxpayer_id,
       case when cq.status='answered' then 'answered' when cq.status='closed' then 'closed'
            when cq.assigned_membership_id is not null then 'claimed' else 'waiting' end,
       100,left(cm.body,500),cq.handling_mode,cq.assigned_membership_id,
       cq.routing_confidence,cq.routing_reason,coalesce(cq.sla_due_at,cq.submitted_at+interval '4 hours'),
       cq.claimed_at,cq.answered_at,cq.created_at,now()
from public.case_questions cq
join public.fiscal_cases fc on fc.municipality_id=cq.municipality_id and fc.id=cq.case_id
join public.case_messages cm on cm.municipality_id=cq.municipality_id and cm.id=cq.message_id
on conflict (question_id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='case_questions'
  ) then alter publication supabase_realtime add table public.case_questions; end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='case_messages'
  ) then alter publication supabase_realtime add table public.case_messages; end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='fiscal_chat_inbox'
  ) then alter publication supabase_realtime add table public.fiscal_chat_inbox; end if;
end;
$$;

comment on table public.case_explanations is
  'Versioned first-page explanation for a fiscal case. Stores discrepancy and legal citation snapshots.';
comment on table public.knowledge_articles is
  'Supervised reusable fiscal answers. Live publication requires fiscal approval and current cited law.';
comment on table public.fiscal_chat_inbox is
  'Realtime minimal work queue visible to fiscal staff before a case is claimed.';
comment on function public.ia_route_case_question_from_knowledge(uuid) is
  'Service-only deterministic exact-match router. Auto-answers only from current approved knowledge; otherwise escalates.';

