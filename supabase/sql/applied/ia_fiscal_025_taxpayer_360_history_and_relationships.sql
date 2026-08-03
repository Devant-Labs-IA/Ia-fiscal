-- IA Fiscal: taxpayer 360 dossier — contacts, responsible parties, communications,
-- documents and a paginable operational timeline.

create or replace view public.vw_taxpayer_360_contacts
with (security_invoker = true)
as
select
  pc.municipality_id,
  pc.taxpayer_id,
  pc.id as contact_id,
  pc.contact_type,
  pc.label,
  pc.value,
  pc.normalized_value,
  pc.is_primary,
  pc.status,
  pc.source,
  pc.valid_from,
  pc.valid_until,
  pc.verified_at,
  pc.quarantine_reason,
  pc.visible_in_homologation,
  pc.created_at,
  pc.updated_at
from public.party_contacts pc
where pc.taxpayer_id is not null
  and private.has_municipality_role(
    pc.municipality_id,
    array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
  );

create or replace view public.vw_taxpayer_360_responsibles
with (security_invoker = true)
as
select
  r.municipality_id,
  r.taxpayer_id,
  r.link_id,
  r.accounting_firm_id,
  r.responsible_name,
  r.masked_document,
  r.masked_email,
  r.link_status,
  r.relationship_status,
  r.verification_status,
  r.delivery_status,
  r.link_quarantine_reason,
  r.contact_quarantine_reason,
  r.safe_for_delivery,
  r.visible_in_homologation,
  r.valid_from,
  r.valid_until,
  r.link_verified_at,
  r.contact_verified_at
from public.vw_taxpayer_responsibilities_visible r
where private.has_municipality_role(
  r.municipality_id,
  array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
);

create or replace view public.vw_taxpayer_360_communications
with (security_invoker = true)
as
select
  n.municipality_id,
  fc.taxpayer_id,
  n.case_id,
  n.id as communication_id,
  'notification'::text as communication_type,
  'outbound'::text as direction,
  n.notification_type as channel_or_source,
  n.subject_snapshot as title,
  left(n.body_text_snapshot, 1000) as summary,
  n.status,
  'staff'::text as visibility,
  n.delivery_mode,
  n.external_delivery_attempted,
  n.prepared_at as occurred_at,
  n.created_at,
  n.updated_at
from public.notifications n
join public.fiscal_cases fc
  on fc.municipality_id = n.municipality_id
 and fc.id = n.case_id
where private.can_view_case_staff(n.municipality_id, n.case_id)

union all

select
  cm.municipality_id,
  fc.taxpayer_id,
  cm.case_id,
  cm.id as communication_id,
  'chat_message'::text as communication_type,
  case when cm.sender_type in ('taxpayer', 'accountant') then 'inbound' else 'outbound' end
    as direction,
  cm.source_type as channel_or_source,
  cm.sender_type as title,
  left(cm.body, 1000) as summary,
  cm.status,
  cm.visibility,
  null::text as delivery_mode,
  false as external_delivery_attempted,
  coalesce(cm.published_at, cm.created_at) as occurred_at,
  cm.created_at,
  cm.updated_at
from public.case_messages cm
join public.fiscal_cases fc
  on fc.municipality_id = cm.municipality_id
 and fc.id = cm.case_id
where private.can_view_case_staff(cm.municipality_id, cm.case_id);

create or replace view public.vw_taxpayer_360_documents
with (security_invoker = true)
as
select
  cd.municipality_id,
  fc.taxpayer_id,
  cd.case_id,
  cd.id as document_id,
  cd.original_file_name,
  cd.media_type,
  cd.size_bytes,
  cd.status,
  cd.malware_scan_status,
  cd.sha256,
  cd.created_at
from public.case_documents cd
join public.fiscal_cases fc
  on fc.municipality_id = cd.municipality_id
 and fc.id = cd.case_id
where private.can_view_case_staff(cd.municipality_id, cd.case_id);

create or replace view public.vw_taxpayer_360_timeline
with (security_invoker = true)
as
select
  h.municipality_id,
  h.taxpayer_id,
  h.case_id,
  h.event_at,
  h.item_type,
  h.title,
  h.summary,
  h.visibility,
  h.payload
from public.vw_taxpayer_history h
where private.has_municipality_role(
  h.municipality_id,
  array['municipal_admin', 'supervisor', 'fiscal_auditor', 'legal_reviewer']::text[]
)
and (
  h.case_id is null
  or private.can_view_case_staff(h.municipality_id, h.case_id)
);

revoke all on
  public.vw_taxpayer_360_contacts,
  public.vw_taxpayer_360_responsibles,
  public.vw_taxpayer_360_communications,
  public.vw_taxpayer_360_documents,
  public.vw_taxpayer_360_timeline
from public, anon;

grant select on
  public.vw_taxpayer_360_contacts,
  public.vw_taxpayer_360_responsibles,
  public.vw_taxpayer_360_communications,
  public.vw_taxpayer_360_documents,
  public.vw_taxpayer_360_timeline
to authenticated, service_role;

