begin;

create or replace function private.guard_governed_content()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_table_name = 'divergence_rule_versions'
     and old.status in ('approved', 'active', 'retired')
     and (
       old.implementation_key is distinct from new.implementation_key
       or old.implementation_version is distinct from new.implementation_version
       or old.parameters is distinct from new.parameters
       or old.checksum_sha256 is distinct from new.checksum_sha256
     ) then
    raise exception 'approved rule content is immutable';
  elsif tg_table_name = 'municipality_policy_versions'
     and old.status in ('approved', 'active', 'retired')
     and (
       old.minimum_divergence_amount is distinct from new.minimum_divergence_amount
       or old.lookback_months is distinct from new.lookback_months
       or old.top_debtors_limit is distinct from new.top_debtors_limit
       or old.daily_initial_notice_limit is distinct from new.daily_initial_notice_limit
       or old.revalidation_max_age_minutes is distinct from new.revalidation_max_age_minutes
       or old.auto_case_creation_enabled is distinct from new.auto_case_creation_enabled
       or old.auto_initial_notice_enabled is distinct from new.auto_initial_notice_enabled
       or old.accountant_notice_enabled is distinct from new.accountant_notice_enabled
       or old.ai_drafting_enabled is distinct from new.ai_drafting_enabled
       or old.require_fiscal_review is distinct from new.require_fiscal_review
       or old.operational_config is distinct from new.operational_config
     ) then
    raise exception 'approved policy content is immutable';
  elsif tg_table_name = 'knowledge_releases'
     and old.status in ('approved', 'published', 'retired', 'revoked')
     and (
       old.name is distinct from new.name
       or old.version is distinct from new.version
       or old.tax_scope is distinct from new.tax_scope
       or old.divergence_scope is distinct from new.divergence_scope
       or old.release_sha256 is distinct from new.release_sha256
     ) then
    raise exception 'approved knowledge release content is immutable';
  end if;
  return new;
end;
$$;

create trigger divergence_rule_versions_governed
  before update on public.divergence_rule_versions
  for each row execute function private.guard_governed_content();
create trigger municipality_policy_versions_governed
  before update on public.municipality_policy_versions
  for each row execute function private.guard_governed_content();
create trigger knowledge_releases_governed
  before update on public.knowledge_releases
  for each row execute function private.guard_governed_content();

create or replace function private.guard_legal_structure()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_municipality_id uuid;
  v_source_version_id uuid;
  v_release_id uuid;
  v_rule_version_id uuid;
  v_status text;
begin
  if tg_op = 'DELETE' then
    v_municipality_id := old.municipality_id;
  else
    v_municipality_id := new.municipality_id;
  end if;

  if tg_table_name = 'legal_sections' then
    v_source_version_id := coalesce(new.source_version_id, old.source_version_id);
  elsif tg_table_name = 'legal_chunks' then
    select ls.source_version_id into strict v_source_version_id
    from public.legal_sections ls
    where ls.municipality_id = v_municipality_id
      and ls.id = coalesce(new.legal_section_id, old.legal_section_id);
  elsif tg_table_name = 'knowledge_release_items' then
    v_release_id := coalesce(new.release_id, old.release_id);
    select kr.status into strict v_status
    from public.knowledge_releases kr
    where kr.municipality_id = v_municipality_id
      and kr.id = v_release_id;
    if v_status not in ('draft', 'under_review') then
      raise exception 'published knowledge release membership is immutable';
    end if;
    if tg_op = 'DELETE' then return old; else return new; end if;
  elsif tg_table_name = 'rule_legal_basis' then
    v_rule_version_id := coalesce(new.rule_version_id, old.rule_version_id);
    select drv.status into strict v_status
    from public.divergence_rule_versions drv
    where drv.municipality_id = v_municipality_id
      and drv.id = v_rule_version_id;
    if v_status not in ('draft', 'approved') then
      raise exception 'active rule legal basis is immutable';
    end if;
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  select lsv.status into strict v_status
  from public.legal_source_versions lsv
  where lsv.municipality_id = v_municipality_id
    and lsv.id = v_source_version_id;

  if v_status not in ('draft', 'under_review') then
    raise exception 'published legal source structure is immutable';
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

create trigger legal_sections_structure_guard
  before insert or update or delete on public.legal_sections
  for each row execute function private.guard_legal_structure();
create trigger legal_chunks_structure_guard
  before insert or update or delete on private.legal_chunks
  for each row execute function private.guard_legal_structure();
create trigger knowledge_release_items_structure_guard
  before insert or update or delete on public.knowledge_release_items
  for each row execute function private.guard_legal_structure();
create trigger rule_legal_basis_structure_guard
  before insert or update or delete on public.rule_legal_basis
  for each row execute function private.guard_legal_structure();

create or replace function public.ia_publish_legal_source_version(
  p_source_version_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version public.legal_source_versions%rowtype;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if p_confirmation <> 'PUBLICAR' then
    raise exception 'explicit publication confirmation required';
  end if;

  select lsv.* into strict v_version
  from public.legal_source_versions lsv
  where lsv.id = p_source_version_id
  for update;

  if not private.has_municipality_role(
    v_version.municipality_id,
    array['legal_reviewer']::text[]
  ) then
    raise exception 'legal reviewer role required';
  end if;
  if v_version.status not in ('draft', 'under_review', 'approved') then
    raise exception 'legal source version is not publishable';
  end if;
  if not exists (
    select 1
    from public.legal_sections ls
    join private.legal_chunks lc
      on lc.municipality_id = ls.municipality_id
     and lc.legal_section_id = ls.id
    where ls.municipality_id = v_version.municipality_id
      and ls.source_version_id = v_version.id
  ) then
    raise exception 'reviewed sections and chunks are required before publication';
  end if;

  update public.legal_source_versions
     set status = 'retired'
   where municipality_id = v_version.municipality_id
     and source_id = v_version.source_id
     and id <> v_version.id
     and status = 'published';

  update public.legal_source_versions
     set status = 'published',
         approved_by = auth.uid(),
         approved_at = now(),
         published_at = now()
   where municipality_id = v_version.municipality_id
     and id = v_version.id;

  update public.legal_sources
     set status = 'active'
   where municipality_id = v_version.municipality_id
     and id = v_version.source_id;
end;
$$;

create or replace function public.ia_publish_knowledge_release(
  p_release_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_release public.knowledge_releases%rowtype;
  v_release_hash text;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if p_confirmation <> 'PUBLICAR' then
    raise exception 'explicit publication confirmation required';
  end if;

  select kr.* into strict v_release
  from public.knowledge_releases kr
  where kr.id = p_release_id
  for update;

  if not private.has_municipality_role(
    v_release.municipality_id,
    array['legal_reviewer']::text[]
  ) then
    raise exception 'legal reviewer role required';
  end if;
  if v_release.status not in ('draft', 'under_review', 'approved') then
    raise exception 'knowledge release is not publishable';
  end if;
  if not exists (
    select 1
    from public.knowledge_release_items kri
    where kri.municipality_id = v_release.municipality_id
      and kri.release_id = v_release.id
  ) then
    raise exception 'knowledge release must contain at least one source version';
  end if;
  if exists (
    select 1
    from public.knowledge_release_items kri
    join public.legal_source_versions lsv
      on lsv.municipality_id = kri.municipality_id
     and lsv.id = kri.source_version_id
    where kri.municipality_id = v_release.municipality_id
      and kri.release_id = v_release.id
      and lsv.status <> 'published'
  ) then
    raise exception 'all source versions must be published';
  end if;

  select pg_catalog.encode(
    extensions.digest(
      string_agg(
        lsv.id::text || ':' || lsv.content_sha256,
        '|' order by lsv.id
      ),
      'sha256'
    ),
    'hex'
  )
  into strict v_release_hash
  from public.knowledge_release_items kri
  join public.legal_source_versions lsv
    on lsv.municipality_id = kri.municipality_id
   and lsv.id = kri.source_version_id
  where kri.municipality_id = v_release.municipality_id
    and kri.release_id = v_release.id;

  update public.knowledge_releases
     set status = 'retired'
   where municipality_id = v_release.municipality_id
     and tax_scope = v_release.tax_scope
     and divergence_scope = v_release.divergence_scope
     and id <> v_release.id
     and status = 'published';

  update public.knowledge_releases
     set status = 'published',
         release_sha256 = v_release_hash,
         approved_by = auth.uid(),
         approved_at = now(),
         published_at = now(),
         effective_from = coalesce(effective_from, now())
   where municipality_id = v_release.municipality_id
     and id = v_release.id;
end;
$$;

create or replace function public.ia_activate_rule_version(
  p_rule_version_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule public.divergence_rule_versions%rowtype;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if p_confirmation <> 'ATIVAR' then
    raise exception 'explicit activation confirmation required';
  end if;

  select drv.* into strict v_rule
  from public.divergence_rule_versions drv
  where drv.id = p_rule_version_id
  for update;

  if not private.has_municipality_role(
    v_rule.municipality_id,
    array['supervisor', 'legal_reviewer']::text[]
  ) then
    raise exception 'supervisor or legal reviewer role required';
  end if;
  if v_rule.status not in ('draft', 'approved') then
    raise exception 'rule version is not activatable';
  end if;
  if coalesce((v_rule.parameters ->> 'formula_approved')::boolean, false) is not true then
    raise exception 'fiscal formula must be explicitly approved';
  end if;
  if not exists (
    select 1
    from public.rule_legal_basis rlb
    join public.knowledge_releases kr
      on kr.municipality_id = rlb.municipality_id
     and kr.id = rlb.knowledge_release_id
    where rlb.municipality_id = v_rule.municipality_id
      and rlb.rule_version_id = v_rule.id
      and kr.status = 'published'
  ) then
    raise exception 'published legal basis is required';
  end if;

  update public.divergence_rule_versions
     set status = 'retired',
         effective_until = coalesce(effective_until, now())
   where municipality_id = v_rule.municipality_id
     and rule_id = v_rule.rule_id
     and id <> v_rule.id
     and status = 'active';

  update public.divergence_rule_versions
     set status = 'active',
         approved_by = auth.uid(),
         approved_at = now(),
         effective_from = coalesce(effective_from, now())
   where municipality_id = v_rule.municipality_id
     and id = v_rule.id;

  update public.divergence_rules
     set status = 'active'
   where municipality_id = v_rule.municipality_id
     and id = v_rule.rule_id;
end;
$$;

create or replace function public.ia_activate_notification_template(
  p_template_version_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_template public.notification_template_versions%rowtype;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if p_confirmation <> 'ATIVAR' then
    raise exception 'explicit activation confirmation required';
  end if;

  select ntv.* into strict v_template
  from public.notification_template_versions ntv
  where ntv.id = p_template_version_id
  for update;

  if not private.has_municipality_role(
    v_template.municipality_id,
    array['supervisor', 'legal_reviewer']::text[]
  ) then
    raise exception 'supervisor or legal reviewer role required';
  end if;
  if v_template.status not in ('draft', 'approved') then
    raise exception 'template version is not activatable';
  end if;

  update public.notification_template_versions
     set status = 'retired'
   where municipality_id = v_template.municipality_id
     and template_id = v_template.template_id
     and id <> v_template.id
     and status = 'active';

  update public.notification_template_versions
     set status = 'active',
         approved_by = auth.uid(),
         approved_at = now()
   where municipality_id = v_template.municipality_id
     and id = v_template.id;

  update public.notification_templates
     set status = 'active'
   where municipality_id = v_template.municipality_id
     and id = v_template.template_id;
end;
$$;

create or replace function public.ia_activate_ai_prompt(
  p_prompt_version_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prompt public.ai_prompt_versions%rowtype;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if p_confirmation <> 'ATIVAR' then
    raise exception 'explicit activation confirmation required';
  end if;

  select apv.* into strict v_prompt
  from public.ai_prompt_versions apv
  where apv.id = p_prompt_version_id
  for update;

  if not private.has_municipality_role(
    v_prompt.municipality_id,
    array['supervisor', 'legal_reviewer']::text[]
  ) then
    raise exception 'supervisor or legal reviewer role required';
  end if;
  if v_prompt.status not in ('draft', 'approved') then
    raise exception 'prompt version is not activatable';
  end if;
  if not (
    v_prompt.output_schema ? 'properties'
    and v_prompt.output_schema -> 'properties' ? 'body'
    and v_prompt.output_schema -> 'properties' ? 'citations'
  ) then
    raise exception 'prompt output schema must require body and citations';
  end if;

  update public.ai_prompt_versions
     set status = 'retired'
   where municipality_id = v_prompt.municipality_id
     and prompt_template_id = v_prompt.prompt_template_id
     and id <> v_prompt.id
     and status = 'active';

  update public.ai_prompt_versions
     set status = 'active',
         approved_by = auth.uid(),
         approved_at = now()
   where municipality_id = v_prompt.municipality_id
     and id = v_prompt.id;

  update public.ai_prompt_templates
     set status = 'active'
   where municipality_id = v_prompt.municipality_id
     and id = v_prompt.prompt_template_id;
end;
$$;

create or replace function public.ia_activate_policy_version(
  p_policy_version_id uuid,
  p_confirmation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_policy public.municipality_policy_versions%rowtype;
begin
  if auth.uid() is null or not private.is_aal2() then
    raise exception 'aal2 authentication required';
  end if;
  if p_confirmation <> 'ATIVAR' then
    raise exception 'explicit activation confirmation required';
  end if;

  select pv.* into strict v_policy
  from public.municipality_policy_versions pv
  where pv.id = p_policy_version_id
  for update;

  if not private.has_municipality_role(
    v_policy.municipality_id,
    array['supervisor']::text[]
  ) then
    raise exception 'supervisor role required';
  end if;
  if v_policy.status not in ('draft', 'approved') then
    raise exception 'policy version is not activatable';
  end if;
  if not v_policy.require_fiscal_review then
    raise exception 'fiscal review cannot be disabled for the MVP';
  end if;
  if v_policy.auto_case_creation_enabled and not exists (
    select 1
    from public.divergence_rule_versions drv
    where drv.municipality_id = v_policy.municipality_id
      and drv.status = 'active'
      and coalesce((drv.parameters ->> 'formula_approved')::boolean, false)
  ) then
    raise exception 'an active approved fiscal rule is required';
  end if;
  if v_policy.auto_initial_notice_enabled and not exists (
    select 1
    from public.notification_channel_settings ncs
    join public.notification_template_versions ntv
      on ntv.municipality_id = ncs.municipality_id
     and ntv.id = ncs.initial_template_version_id
    join public.integrations i
      on i.municipality_id = ncs.municipality_id
     and i.id = ncs.integration_id
    where ncs.municipality_id = v_policy.municipality_id
      and ncs.status = 'active'
      and not ncs.kill_switch
      and ntv.status = 'active'
      and i.integration_type = 'email'
      and i.status = 'active'
  ) then
    raise exception 'active email channel, template and integration are required';
  end if;
  if v_policy.ai_drafting_enabled and (
    not exists (
      select 1
      from public.ai_prompt_versions apv
      join public.ai_prompt_templates apt
        on apt.municipality_id = apv.municipality_id
       and apt.id = apv.prompt_template_id
      where apv.municipality_id = v_policy.municipality_id
        and apv.status = 'active'
        and apt.status = 'active'
    )
    or not exists (
      select 1
      from public.knowledge_releases kr
      where kr.municipality_id = v_policy.municipality_id
        and kr.status = 'published'
    )
    or not exists (
      select 1
      from public.integrations i
      where i.municipality_id = v_policy.municipality_id
        and i.integration_type = 'ai_provider'
        and i.status = 'active'
        and nullif(i.non_secret_config ->> 'model', '') is not null
    )
  ) then
    raise exception 'active prompt, knowledge release and AI integration are required';
  end if;

  update public.municipality_policy_versions
     set status = 'retired',
         effective_until = coalesce(effective_until, now())
   where municipality_id = v_policy.municipality_id
     and id <> v_policy.id
     and status = 'active';

  update public.municipality_policy_versions
     set status = 'active',
         approved_by = auth.uid(),
         approved_at = now(),
         effective_from = coalesce(effective_from, now())
   where municipality_id = v_policy.municipality_id
     and id = v_policy.id;
end;
$$;

create or replace function public.ia_set_integration_operational_state(
  p_integration_id uuid,
  p_status text,
  p_non_secret_config jsonb,
  p_secret_reference text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_integration public.integrations%rowtype;
begin
  if not private.is_service_role() then
    raise exception 'service role required';
  end if;
  if p_status not in ('not_configured', 'configured', 'testing', 'active', 'error', 'disabled') then
    raise exception 'invalid integration status';
  end if;
  if jsonb_typeof(p_non_secret_config) <> 'object' then
    raise exception 'non_secret_config must be an object';
  end if;

  select i.* into strict v_integration
  from public.integrations i
  where i.id = p_integration_id
  for update;

  if p_status = 'active'
     and nullif(trim(coalesce(p_secret_reference, v_integration.secret_reference)), '') is null then
    raise exception 'a secret reference is required before activation';
  end if;

  update public.integrations
     set status = p_status,
         non_secret_config = p_non_secret_config,
         secret_reference = coalesce(nullif(trim(p_secret_reference), ''), secret_reference),
         last_tested_at = case when p_status in ('testing', 'active') then now() else last_tested_at end,
         last_error_code = null
   where id = v_integration.id;
end;
$$;

create view public.api_case_dashboard
with (security_invoker = true)
as
select
  fc.id,
  fc.municipality_id,
  fc.case_number,
  fc.status,
  fc.confidentiality,
  fc.opened_at,
  fc.first_accessed_at,
  fc.updated_at,
  t.id as taxpayer_id,
  t.municipal_registration,
  t.legal_name,
  t.trade_name,
  cf.period_start,
  cf.period_end,
  cf.assessed_amount,
  cf.paid_amount,
  cf.other_credits_amount,
  cf.difference_amount,
  exists (
    select 1
    from public.case_questions cq
    where cq.municipality_id = fc.municipality_id
      and cq.case_id = fc.id
      and cq.status in ('submitted', 'queued_for_ai', 'researching', 'awaiting_fiscal', 'needs_manual_answer')
  ) as has_pending_question
from public.fiscal_cases fc
join public.taxpayers t
  on t.municipality_id = fc.municipality_id
 and t.id = fc.taxpayer_id
join public.case_findings cf
  on cf.municipality_id = fc.municipality_id
 and cf.case_id = fc.id;

create view public.api_divergence_queue
with (security_invoker = true)
as
select
  d.id,
  d.municipality_id,
  d.taxpayer_id,
  t.municipal_registration,
  t.legal_name,
  d.status,
  d.period_start,
  d.period_end,
  d.assessed_amount,
  d.paid_amount,
  d.other_credits_amount,
  d.difference_amount,
  d.last_revalidated_at,
  d.block_reasons,
  d.created_at as detected_at
from public.divergences d
join public.taxpayers t
  on t.municipality_id = d.municipality_id
 and t.id = d.taxpayer_id;

create view public.api_ai_review_queue
with (security_invoker = true)
as
select
  ad.id as draft_id,
  ad.municipality_id,
  ad.case_id,
  fc.case_number,
  t.legal_name,
  ad.question_id,
  cq.status as question_status,
  ad.status as draft_status,
  ad.current_revision_number,
  adr.id as current_revision_id,
  adr.body,
  adr.content_sha256,
  ad.limitation_summary,
  ad.created_at,
  ad.updated_at
from public.ai_drafts ad
join public.fiscal_cases fc
  on fc.municipality_id = ad.municipality_id
 and fc.id = ad.case_id
join public.taxpayers t
  on t.municipality_id = fc.municipality_id
 and t.id = fc.taxpayer_id
join public.case_questions cq
  on cq.municipality_id = ad.municipality_id
 and cq.id = ad.question_id
join public.ai_draft_revisions adr
  on adr.municipality_id = ad.municipality_id
 and adr.draft_id = ad.id
 and adr.revision_number = ad.current_revision_number
where ad.status in ('awaiting_fiscal_review', 'revision_requested', 'needs_manual_answer', 'approved');

create view public.api_notification_delivery
with (security_invoker = true)
as
select
  n.id as notification_id,
  n.municipality_id,
  n.case_id,
  n.status as notification_status,
  n.prepared_at,
  n.queued_at,
  n.sent_at,
  nr.id as recipient_id,
  nr.recipient_type,
  nr.status as recipient_status,
  nr.sent_at as recipient_sent_at,
  nr.delivered_at,
  nr.last_error_code
from public.notifications n
join public.notification_recipients nr
  on nr.municipality_id = n.municipality_id
 and nr.notification_id = n.id;

grant select on public.api_case_dashboard to authenticated, service_role;
grant select on public.api_divergence_queue to authenticated, service_role;
grant select on public.api_ai_review_queue to authenticated, service_role;
grant select on public.api_notification_delivery to authenticated, service_role;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values
  (
    'ia-fiscal-imports',
    'ia-fiscal-imports',
    false,
    52428800,
    array[
      'text/csv',
      'text/plain',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ]::text[]
  ),
  (
    'ia-fiscal-case-documents',
    'ia-fiscal-case-documents',
    false,
    52428800,
    array[
      'application/pdf',
      'image/jpeg',
      'image/png'
    ]::text[]
  ),
  (
    'ia-fiscal-legal-sources',
    'ia-fiscal-legal-sources',
    false,
    52428800,
    array[
      'application/pdf',
      'text/plain',
      'text/html'
    ]::text[]
  )
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

with municipality as (
  insert into public.municipalities (
    slug,
    name,
    state_code,
    ibge_code,
    status,
    data_classification
  )
  values (
    'araras-sp',
    'Prefeitura Municipal de Araras',
    'SP',
    '3503307',
    'homologation',
    'highly_restricted'
  )
  on conflict (slug) do update
  set name = excluded.name,
      state_code = excluded.state_code,
      ibge_code = excluded.ibge_code,
      status = case
        when public.municipalities.status = 'setup' then 'homologation'
        else public.municipalities.status
      end,
      data_classification = 'highly_restricted'
  returning id
)
insert into public.municipality_policy_versions (
  municipality_id,
  version,
  status,
  minimum_divergence_amount,
  lookback_months,
  top_debtors_limit,
  daily_initial_notice_limit,
  revalidation_max_age_minutes,
  auto_case_creation_enabled,
  auto_initial_notice_enabled,
  accountant_notice_enabled,
  ai_drafting_enabled,
  require_fiscal_review,
  operational_config
)
select
  id,
  1,
  'draft',
  1000,
  60,
  30,
  30,
  15,
  false,
  false,
  false,
  false,
  true,
  jsonb_build_object(
    'formula_status', 'pending_legal_and_fiscal_approval',
    'initial_alert_status', 'pending_template_and_provider_approval',
    'ai_status', 'pending_knowledge_prompt_and_provider_approval',
    'environment', 'homologation'
  )
from municipality
on conflict (municipality_id, version) do nothing;

with municipality as (
  select id from public.municipalities where slug = 'araras-sp'
),
rule as (
  insert into public.divergence_rules (
    municipality_id,
    code,
    name,
    description,
    divergence_type,
    status
  )
  select
    id,
    'current_account_balance',
    'Divergência de Conta Corrente',
    'Compara lançamentos de débito válidos com pagamentos e outros créditos válidos.',
    'current_account_balance',
    'draft'
  from municipality
  on conflict (municipality_id, code) do update
  set name = excluded.name,
      description = excluded.description
  returning id, municipality_id
),
parameters as (
  select jsonb_build_object(
    'formula_approved', false,
    'threshold_comparator', 'gte',
    'debit_source', 'valid_current_account_debits',
    'payment_source', 'valid_current_account_payment_credits',
    'other_credit_source', 'valid_current_account_non_payment_credits'
  ) as value
)
insert into public.divergence_rule_versions (
  municipality_id,
  rule_id,
  version,
  status,
  implementation_key,
  implementation_version,
  parameters,
  checksum_sha256
)
select
  r.municipality_id,
  r.id,
  1,
  'draft',
  'current_account_balance_v1',
  '1.0.0',
  p.value,
  pg_catalog.encode(extensions.digest(p.value::text, 'sha256'), 'hex')
from rule r
cross join parameters p
on conflict (municipality_id, rule_id, version) do nothing;

with municipality as (
  select id from public.municipalities where slug = 'araras-sp'
),
template as (
  insert into public.notification_templates (
    municipality_id,
    code,
    name,
    notification_type,
    legal_nature,
    status
  )
  select
    id,
    'initial_inspection_alert',
    'Alerta inicial de abertura de fiscalização',
    'initial_inspection_alert',
    'informational_alert',
    'draft'
  from municipality
  on conflict (municipality_id, code) do update
  set name = excluded.name
  returning id, municipality_id
),
content as (
  select
    'Aviso de abertura de procedimento de fiscalização — {{municipality_name}}'::text as subject,
    (
      'A Prefeitura de {{municipality_name}} informa que foi instaurado um procedimento de fiscalização relacionado às informações declaradas. ' ||
      'Para consultar o objeto e acompanhar o procedimento, acesse manualmente o ambiente oficial do município pelo endereço que você já utiliza. ' ||
      'Por segurança, esta mensagem não contém links, anexos, valores ou detalhes fiscais. ' ||
      'Em caso de dúvida, utilize os canais disponíveis dentro do ambiente oficial.'
    )::text as body_text
)
insert into public.notification_template_versions (
  municipality_id,
  template_id,
  version,
  status,
  subject,
  body_text,
  allowed_placeholders,
  content_sha256
)
select
  t.municipality_id,
  t.id,
  1,
  'draft',
  c.subject,
  c.body_text,
  array['municipality_name']::text[],
  pg_catalog.encode(
    extensions.digest(c.subject || E'\n' || c.body_text || E'\n', 'sha256'),
    'hex'
  )
from template t
cross join content c
on conflict (municipality_id, template_id, version) do nothing;

with municipality as (
  select id from public.municipalities where slug = 'araras-sp'
),
email_integration as (
  insert into public.integrations (
    municipality_id,
    integration_type,
    provider_code,
    display_name,
    status,
    non_secret_config
  )
  select
    id,
    'email',
    'resend',
    'Provedor de e-mail transacional',
    'not_configured',
    jsonb_build_object('environment', 'homologation')
  from municipality
  on conflict (municipality_id, integration_type, provider_code) do nothing
  returning id, municipality_id
),
template_version as (
  select ntv.id, ntv.municipality_id
  from public.notification_template_versions ntv
  join public.notification_templates nt
    on nt.municipality_id = ntv.municipality_id
   and nt.id = ntv.template_id
  where nt.code = 'initial_inspection_alert'
    and ntv.version = 1
)
insert into public.notification_channel_settings (
  municipality_id,
  integration_id,
  channel,
  status,
  initial_template_version_id,
  daily_limit,
  monthly_limit,
  kill_switch
)
select
  e.municipality_id,
  e.id,
  'email',
  'disabled',
  tv.id,
  30,
  500,
  true
from email_integration e
join template_version tv
  on tv.municipality_id = e.municipality_id
on conflict (municipality_id, channel) do nothing;

with municipality as (
  select id from public.municipalities where slug = 'araras-sp'
)
insert into public.integrations (
  municipality_id,
  integration_type,
  provider_code,
  display_name,
  status,
  non_secret_config
)
select id, integration_type, provider_code, display_name, status, config
from municipality
cross join (
  values
    (
      'source_system'::text,
      'sigissweb'::text,
      'SIGISSWEB Araras'::text,
      'not_configured'::text,
      jsonb_build_object('mode', 'file_import_first', 'environment', 'homologation')
    ),
    (
      'ai_provider'::text,
      'openai'::text,
      'OpenAI Responses API'::text,
      'not_configured'::text,
      jsonb_build_object('environment', 'homologation')
    )
) seed(integration_type, provider_code, display_name, status, config)
on conflict (municipality_id, integration_type, provider_code) do nothing;

with municipality as (
  select id from public.municipalities where slug = 'araras-sp'
),
prompt as (
  insert into public.ai_prompt_templates (
    municipality_id,
    code,
    name,
    purpose,
    status
  )
  select
    id,
    'fiscal_response_draft',
    'Minuta fundamentada de resposta fiscal',
    'fiscal_response_draft',
    'draft'
  from municipality
  on conflict (municipality_id, code) do update
  set name = excluded.name
  returning id, municipality_id
),
prompt_content as (
  select
    (
      'Você prepara uma minuta para revisão humana de um fiscal municipal. ' ||
      'Use exclusivamente os trechos de fontes oficiais fornecidos. ' ||
      'Não recalcule o débito, não crie legislação, prazos ou consequências e não decida contestações. ' ||
      'Explique o caso em português claro e cite somente legal_chunk_id recebido. ' ||
      'Se as fontes forem insuficientes ou conflitantes, declare a limitação e peça análise manual. ' ||
      'A saída nunca é enviada automaticamente ao contribuinte.'
    )::text as system_prompt,
    jsonb_build_object(
      'type', 'object',
      'additionalProperties', false,
      'properties', jsonb_build_object(
        'body', jsonb_build_object('type', 'string'),
        'citations', jsonb_build_object(
          'type', 'array',
          'minItems', 1,
          'maxItems', 20,
          'items', jsonb_build_object(
            'type', 'object',
            'additionalProperties', false,
            'properties', jsonb_build_object(
              'legal_chunk_id', jsonb_build_object('type', 'string', 'format', 'uuid'),
              'citation_label', jsonb_build_object('type', 'string')
            ),
            'required', jsonb_build_array('legal_chunk_id', 'citation_label')
          )
        ),
        'limitation_summary', jsonb_build_object('type', array['string', 'null'])
      ),
      'required', jsonb_build_array('body', 'citations', 'limitation_summary')
    ) as output_schema
)
insert into public.ai_prompt_versions (
  municipality_id,
  prompt_template_id,
  version,
  status,
  system_prompt,
  output_schema,
  content_sha256
)
select
  p.municipality_id,
  p.id,
  1,
  'draft',
  pc.system_prompt,
  pc.output_schema,
  pg_catalog.encode(
    extensions.digest(pc.system_prompt || ':' || pc.output_schema::text, 'sha256'),
    'hex'
  )
from prompt p
cross join prompt_content pc
on conflict (municipality_id, prompt_template_id, version) do nothing;

with municipality as (
  select id from public.municipalities where slug = 'araras-sp'
)
insert into public.knowledge_releases (
  municipality_id,
  name,
  version,
  status,
  tax_scope,
  divergence_scope
)
select
  id,
  'Base legal ISSQN — Conta Corrente',
  1,
  'draft',
  'ISSQN',
  'current_account_balance'
from municipality
on conflict (municipality_id, name, version) do nothing;

with municipality as (
  select id from public.municipalities where slug = 'araras-sp'
)
insert into public.retention_policies (
  municipality_id,
  data_category,
  retention_days,
  legal_basis,
  status
)
select
  id,
  data_category,
  retention_days,
  'Prazo provisório para homologação; depende de validação jurídica e arquivística municipal.',
  'draft'
from municipality
cross join (
  values
    ('fiscal_case'::text, 3650),
    ('audit_event'::text, 3650),
    ('ai_trace'::text, 1825),
    ('notification_delivery'::text, 1825)
) seed(data_category, retention_days)
on conflict (municipality_id, data_category, status) do nothing;

revoke all on function public.ia_set_integration_operational_state(
  uuid, text, jsonb, text
) from public, anon, authenticated;
grant execute on function public.ia_set_integration_operational_state(
  uuid, text, jsonb, text
) to service_role;

revoke all on function public.ia_publish_legal_source_version(uuid, text)
  from public, anon;
revoke all on function public.ia_publish_knowledge_release(uuid, text)
  from public, anon;
revoke all on function public.ia_activate_rule_version(uuid, text)
  from public, anon;
revoke all on function public.ia_activate_notification_template(uuid, text)
  from public, anon;
revoke all on function public.ia_activate_ai_prompt(uuid, text)
  from public, anon;
revoke all on function public.ia_activate_policy_version(uuid, text)
  from public, anon;

grant execute on function public.ia_publish_legal_source_version(uuid, text)
  to authenticated, service_role;
grant execute on function public.ia_publish_knowledge_release(uuid, text)
  to authenticated, service_role;
grant execute on function public.ia_activate_rule_version(uuid, text)
  to authenticated, service_role;
grant execute on function public.ia_activate_notification_template(uuid, text)
  to authenticated, service_role;
grant execute on function public.ia_activate_ai_prompt(uuid, text)
  to authenticated, service_role;
grant execute on function public.ia_activate_policy_version(uuid, text)
  to authenticated, service_role;

commit;

