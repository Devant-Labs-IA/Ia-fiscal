create index if not exists backend_validation_results_run_tenant_idx
  on public.backend_validation_results (municipality_id, run_id);

create index if not exists backend_validation_runs_created_by_idx
  on public.backend_validation_runs (created_by)
  where created_by is not null;

create index if not exists fiscal_search_requests_requested_by_idx
  on public.fiscal_search_requests (requested_by)
  where requested_by is not null;

create index if not exists simple_national_annex_checks_annex_item_idx
  on public.simple_national_annex_line_checks (
    municipality_id, annex_item_id
  );

create index if not exists simple_national_annex_checks_declaration_idx
  on public.simple_national_annex_line_checks (
    municipality_id, declaration_id
  );

create index if not exists simple_national_annex_checks_taxpayer_idx
  on public.simple_national_annex_line_checks (
    municipality_id, taxpayer_id
  );
