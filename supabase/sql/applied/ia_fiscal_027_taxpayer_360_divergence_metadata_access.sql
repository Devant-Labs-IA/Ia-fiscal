-- IA Fiscal: allow municipal fiscal staff to read governed divergence rule metadata
-- required by the taxpayer 360 divergence tab. Write/activation permissions are unchanged.

drop policy if exists divergence_rules_select_supervisor
  on public.divergence_rules;
drop policy if exists divergence_rules_select_staff
  on public.divergence_rules;
create policy divergence_rules_select_staff
on public.divergence_rules
for select
to authenticated
using (
  (select private.has_municipality_role(
    divergence_rules.municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  ))
);

drop policy if exists divergence_rule_versions_select_supervisor
  on public.divergence_rule_versions;
drop policy if exists divergence_rule_versions_select_staff
  on public.divergence_rule_versions;
create policy divergence_rule_versions_select_staff
on public.divergence_rule_versions
for select
to authenticated
using (
  (select private.has_municipality_role(
    divergence_rule_versions.municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  ))
);

