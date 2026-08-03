
create or replace function private.guard_governed_content()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  old_row jsonb := to_jsonb(old);
  new_row jsonb := to_jsonb(new);
  row_status text := old_row ->> 'status';
begin
  if tg_table_name = 'divergence_rule_versions'
     and row_status in ('approved', 'active', 'retired')
     and (
       old_row -> 'implementation_key' is distinct from new_row -> 'implementation_key'
       or old_row -> 'implementation_version' is distinct from new_row -> 'implementation_version'
       or old_row -> 'parameters' is distinct from new_row -> 'parameters'
       or old_row -> 'checksum_sha256' is distinct from new_row -> 'checksum_sha256'
     ) then
    raise exception 'approved rule content is immutable';
  elsif tg_table_name = 'municipality_policy_versions'
     and row_status in ('approved', 'active', 'retired')
     and (
       old_row -> 'minimum_divergence_amount' is distinct from new_row -> 'minimum_divergence_amount'
       or old_row -> 'lookback_months' is distinct from new_row -> 'lookback_months'
       or old_row -> 'top_debtors_limit' is distinct from new_row -> 'top_debtors_limit'
       or old_row -> 'daily_initial_notice_limit' is distinct from new_row -> 'daily_initial_notice_limit'
       or old_row -> 'revalidation_max_age_minutes' is distinct from new_row -> 'revalidation_max_age_minutes'
       or old_row -> 'auto_case_creation_enabled' is distinct from new_row -> 'auto_case_creation_enabled'
       or old_row -> 'auto_initial_notice_enabled' is distinct from new_row -> 'auto_initial_notice_enabled'
       or old_row -> 'accountant_notice_enabled' is distinct from new_row -> 'accountant_notice_enabled'
       or old_row -> 'ai_drafting_enabled' is distinct from new_row -> 'ai_drafting_enabled'
       or old_row -> 'require_fiscal_review' is distinct from new_row -> 'require_fiscal_review'
       or old_row -> 'operational_config' is distinct from new_row -> 'operational_config'
     ) then
    raise exception 'approved policy content is immutable';
  elsif tg_table_name = 'knowledge_releases'
     and row_status in ('approved', 'published', 'retired', 'revoked')
     and (
       old_row -> 'name' is distinct from new_row -> 'name'
       or old_row -> 'version' is distinct from new_row -> 'version'
       or old_row -> 'tax_scope' is distinct from new_row -> 'tax_scope'
       or old_row -> 'divergence_scope' is distinct from new_row -> 'divergence_scope'
       or old_row -> 'release_sha256' is distinct from new_row -> 'release_sha256'
     ) then
    raise exception 'approved knowledge release content is immutable';
  end if;
  return new;
end;
$$;

