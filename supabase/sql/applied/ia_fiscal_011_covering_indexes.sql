create index if not exists sandbox_message_outbox_case_idx
  on private.sandbox_message_outbox (municipality_id, case_id);

create index if not exists sandbox_message_outbox_contact_idx
  on private.sandbox_message_outbox (municipality_id, contact_id);

create index if not exists factor_r_payroll_periods_batch_idx
  on public.factor_r_payroll_periods (municipality_id, import_batch_id);

create index if not exists pgdasd_annex_items_taxpayer_idx
  on public.pgdasd_annex_items (municipality_id, taxpayer_id);

create index if not exists pgdasd_declarations_batch_idx
  on public.pgdasd_declarations (municipality_id, import_batch_id);

create index if not exists sigiss_tax_base_periods_batch_idx
  on public.sigiss_tax_base_periods (municipality_id, import_batch_id);

create index if not exists simple_national_divergence_items_snapshot_idx
  on public.simple_national_divergence_items (
    municipality_id,
    calculation_snapshot_id
  );
