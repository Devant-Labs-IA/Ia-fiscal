-- Segundo Cerebro Fiscal, fase 2b.
--
-- Catalog discovery and promotion are deliberately separate from canonical
-- publication.  A discovered ficha may create a draft source and collection
-- endpoint, but only the existing AAL2 review/publication workflow can make
-- extracted legal text citable.

begin;

drop index if exists private.legal_source_endpoints_one_active_source_uq;
create unique index legal_source_endpoints_one_active_legal_body_uq
  on private.legal_source_endpoints (municipality_id, source_id)
  where status = 'active' and content_mode = 'legal_body';
create unique index legal_source_endpoints_one_active_ficha_uq
  on private.legal_source_endpoints (municipality_id, source_id)
  where status = 'active'
    and content_mode = 'catalog_only'
    and endpoint_kind = 'document_page';

-- The canonical body and its ficha/relation graph are complementary.  Wave 1
-- paused these fichas while the old one-endpoint index existed; reactivate
-- them now without changing which body representation is citable.
update private.legal_source_endpoints endpoint
set status = 'active',
    metadata = endpoint.metadata - 'activation_blocker'
      || jsonb_build_object('coverage_status', 'relation_discovery_active'),
    updated_at = now()
from public.legal_sources source
join public.municipalities municipality on municipality.id = source.municipality_id
where endpoint.municipality_id = source.municipality_id
  and endpoint.source_id = source.id
  and endpoint.content_mode = 'catalog_only'
  and endpoint.endpoint_kind = 'document_page'
  -- A source can also carry secondary consolidation pages.  Only the official
  -- Siscam ficha is the active relation-discovery surface; alternatives such
  -- as LegislacaoDigital remain paused and can never collide with this slot.
  and endpoint.parser_hint = 'siscam_document'
  and endpoint.status = 'paused'
  and (
    (municipality.slug = 'cordeiropolis-sp'
      and source.official_identifier = 'Lei Complementar nº 399/2024')
    or
    (municipality.slug = 'araras-sp'
      and source.official_identifier = 'Lei nº 3.362/2001')
  );

alter table private.legal_source_discovered_assets
  add column link_label text check (
    link_label is null or char_length(link_label) between 1 and 300
  );

create table private.legal_source_canonical_identities (
  municipality_id uuid not null,
  source_id uuid not null,
  canonical_legal_key text not null
    check (canonical_legal_key ~ '^(law|complementary_law|decree):[0-9]{1,12}:[0-9]{4}$'),
  created_at timestamptz not null default now(),
  primary key (municipality_id, source_id),
  constraint legal_source_canonical_identity_key_uq
    unique (municipality_id, canonical_legal_key),
  constraint legal_source_canonical_identity_source_fk
    foreign key (municipality_id, source_id)
    references public.legal_sources(municipality_id, id)
);

with parsed as (
  select
    source.municipality_id,
    source.id as source_id,
    case
      when lower(source.official_identifier) like 'lei complementar%'
        then 'complementary_law'
      when lower(source.official_identifier) like 'lei%'
        then 'law'
      when lower(source.official_identifier) like 'decreto%'
        then 'decree'
    end as species,
    regexp_replace(
      coalesce((regexp_match(source.official_identifier, '([0-9][0-9.]*)[^0-9]+([12][0-9]{3})'))[1], ''),
      '[^0-9]', '', 'g'
    ) as legal_number,
    (regexp_match(source.official_identifier, '([0-9][0-9.]*)[^0-9]+([12][0-9]{3})'))[2]
      as legal_year
  from public.legal_sources source
  where source.official_identifier is not null
)
insert into private.legal_source_canonical_identities (
  municipality_id, source_id, canonical_legal_key
)
select municipality_id, source_id, species || ':' || legal_number || ':' || legal_year
from parsed
where species is not null and legal_number <> '' and legal_year is not null
on conflict do nothing;

create table private.legal_catalog_coverages (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  catalog_source_id uuid not null,
  coverage_key text not null check (coverage_key ~ '^[a-z0-9][a-z0-9_.:-]{2,119}$'),
  title text not null check (char_length(trim(title)) between 3 and 300),
  expected_document_count integer check (expected_document_count is null or expected_document_count >= 0),
  upstream_status text not null default 'unverified'
    check (upstream_status in ('unverified', 'available', 'blocked_403', 'blocked_502', 'blocked_503')),
  blocker_code text check (
    blocker_code is null or blocker_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'
  ),
  last_fetch_run_sequence bigint,
  last_checked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_catalog_coverages_source_fk
    foreign key (municipality_id, catalog_source_id)
    references public.legal_sources(municipality_id, id),
  constraint legal_catalog_coverages_key_uq unique (municipality_id, coverage_key),
  constraint legal_catalog_coverages_municipality_id_id_uq unique (municipality_id, id)
);

create table private.legal_source_promotion_candidates (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  catalog_source_id uuid not null,
  promoted_source_id uuid,
  document_url text not null check (document_url ~ '^https://[^[:space:]]+$'),
  link_label text check (link_label is null or char_length(link_label) between 1 and 300),
  legal_species text check (legal_species is null or legal_species in ('law', 'complementary_law', 'decree')),
  legal_number text check (legal_number is null or legal_number ~ '^[0-9]{1,12}$'),
  legal_year integer check (legal_year is null or legal_year between 1800 and 2200),
  canonical_legal_key text check (
    canonical_legal_key is null or canonical_legal_key ~ '^(law|complementary_law|decree):[0-9]{1,12}:[0-9]{4}$'
  ),
  external_document_id text check (
    external_document_id is null or external_document_id ~ '^[0-9]{1,20}$'
  ),
  status text not null default 'discovered'
    check (status in ('discovered', 'identity_verified', 'ficha_queued', 'extraction_queued', 'reviewable', 'blocked')),
  blocker_code text check (
    blocker_code is null or blocker_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'
  ),
  first_observed_at timestamptz not null,
  last_observed_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_source_promotion_catalog_fk
    foreign key (municipality_id, catalog_source_id)
    references public.legal_sources(municipality_id, id),
  constraint legal_source_promotion_source_fk
    foreign key (municipality_id, promoted_source_id)
    references public.legal_sources(municipality_id, id),
  constraint legal_source_promotion_url_uq unique (municipality_id, document_url),
  constraint legal_source_promotion_municipality_id_id_uq unique (municipality_id, id)
);

create unique index legal_source_promotion_canonical_uq
  on private.legal_source_promotion_candidates (municipality_id, canonical_legal_key)
  where canonical_legal_key is not null;
create index legal_source_promotion_queue_idx
  on private.legal_source_promotion_candidates (municipality_id, status, first_observed_at, id)
  where status in ('discovered', 'identity_verified', 'ficha_queued', 'extraction_queued', 'blocked');

-- One canonical law may appear in several fiscal classifications.  Coverage
-- ownership is therefore N:N and cannot be inferred from the candidate's
-- first catalog alone.
create table private.legal_catalog_coverage_candidates (
  municipality_id uuid not null,
  coverage_id uuid not null,
  candidate_id uuid not null,
  first_observed_at timestamptz not null,
  last_observed_at timestamptz not null,
  primary key (municipality_id, coverage_id, candidate_id),
  constraint legal_catalog_coverage_candidates_coverage_fk
    foreign key (municipality_id, coverage_id)
    references private.legal_catalog_coverages(municipality_id, id),
  constraint legal_catalog_coverage_candidates_candidate_fk
    foreign key (municipality_id, candidate_id)
    references private.legal_source_promotion_candidates(municipality_id, id)
);

create table private.legal_source_relationship_candidates (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null,
  from_source_id uuid not null,
  to_source_id uuid not null,
  relation_type text not null
    check (relation_type in ('amends', 'revokes', 'supersedes', 'related')),
  evidence_asset_id uuid,
  status text not null default 'pending_review'
    check (status in ('pending_review', 'confirmed', 'rejected')),
  created_at timestamptz not null default now(),
  constraint legal_source_relationship_from_fk
    foreign key (municipality_id, from_source_id)
    references public.legal_sources(municipality_id, id),
  constraint legal_source_relationship_to_fk
    foreign key (municipality_id, to_source_id)
    references public.legal_sources(municipality_id, id),
  constraint legal_source_relationship_asset_fk
    foreign key (municipality_id, evidence_asset_id)
    references private.legal_source_discovered_assets(municipality_id, id),
  constraint legal_source_relationship_no_self_ck check (from_source_id <> to_source_id),
  constraint legal_source_relationship_uq unique (
    municipality_id, from_source_id, to_source_id, relation_type
  )
);

create table private.legal_body_endpoint_cutovers (
  id bigint generated always as identity primary key,
  municipality_id uuid not null,
  source_id uuid not null,
  previous_endpoint_id uuid,
  candidate_endpoint_id uuid not null,
  candidate_url text not null check (candidate_url ~ '^https://[^[:space:]]+$'),
  status text not null check (status in ('activated_for_collection', 'blocked')),
  reason_code text not null check (reason_code ~ '^[a-z0-9][a-z0-9_.:-]{1,119}$'),
  created_at timestamptz not null default now(),
  constraint legal_body_endpoint_cutovers_source_fk
    foreign key (municipality_id, source_id)
    references public.legal_sources(municipality_id, id),
  constraint legal_body_endpoint_cutovers_previous_fk
    foreign key (municipality_id, previous_endpoint_id)
    references private.legal_source_endpoints(municipality_id, id),
  constraint legal_body_endpoint_cutovers_candidate_fk
    foreign key (municipality_id, candidate_endpoint_id)
    references private.legal_source_endpoints(municipality_id, id),
  constraint legal_body_endpoint_cutovers_candidate_uq
    unique (municipality_id, candidate_endpoint_id)
);

create or replace function private.refresh_legal_catalog_coverage_health()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_coverage_key text;
begin
  select endpoint.metadata ->> 'coverage_key' into v_coverage_key
  from private.legal_source_endpoints endpoint
  where endpoint.municipality_id = new.municipality_id
    and endpoint.id = new.endpoint_id;
  if nullif(v_coverage_key, '') is null then
    return new;
  end if;

  update private.legal_catalog_coverages coverage
  set upstream_status = case
        when new.status in ('completed_unchanged', 'completed_changed') then 'available'
        when new.http_status = 403 then 'blocked_403'
        when new.http_status = 502 then 'blocked_502'
        when new.http_status = 503 then 'blocked_503'
        else 'unverified'
      end,
      blocker_code = case
        when new.status in ('completed_unchanged', 'completed_changed') then null
        when new.http_status = 403 then 'upstream_http_403'
        when new.http_status = 502 then 'upstream_http_502'
        when new.http_status = 503 then 'upstream_http_503'
        else coalesce(new.safe_error_code, 'upstream_fetch_failed')
      end,
      last_fetch_run_sequence = new.run_sequence,
      last_checked_at = new.completed_at,
      updated_at = now()
  where coverage.municipality_id = new.municipality_id
    and coverage.coverage_key = v_coverage_key
    and coalesce(coverage.last_fetch_run_sequence, 0) < new.run_sequence;
  return new;
end;
$$;

create trigger legal_source_fetch_runs_refresh_catalog_coverage
after insert on private.legal_source_fetch_runs
for each row execute function private.refresh_legal_catalog_coverage_health();

-- Replace the Phase 2 discovery recorder to support bounded catalog-page
-- expansion and governed ficha/attachment promotion.
create or replace function public.ia_fiscal_record_knowledge_discoveries(
  p_endpoint_id uuid,
  p_assets jsonb,
  p_observed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_endpoint private.legal_source_endpoints%rowtype;
  v_source public.legal_sources%rowtype;
  v_municipality public.municipalities%rowtype;
  v_asset jsonb;
  v_url text;
  v_host text;
  v_relation_kind text;
  v_mime_type text;
  v_label text;
  v_byte_size bigint;
  v_blocker text;
  v_match text[];
  v_species text;
  v_number text;
  v_year integer;
  v_canonical_key text;
  v_official_identifier text;
  v_promoted_source_id uuid;
  v_candidate_id uuid;
  v_discovered_asset_id uuid;
  v_external_document_id text;
  v_current_body_endpoint_id uuid;
  v_candidate_body_endpoint_id uuid;
  v_attachment_promoted boolean := false;
  v_count integer := 0;
  v_pages_queued integer := 0;
  v_promotions_queued integer := 0;
  v_relationships_queued integer := 0;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
  if p_assets is null
     or jsonb_typeof(p_assets) <> 'array'
     or jsonb_array_length(p_assets) not between 1 and 100 then
    raise exception 'discoveries must contain 1 to 100 assets';
  end if;
  if p_observed_at is null or p_observed_at > now() + interval '5 minutes' then
    raise exception 'invalid discovery timestamp';
  end if;

  select endpoint.* into strict v_endpoint
  from private.legal_source_endpoints endpoint
  where endpoint.id = p_endpoint_id and endpoint.status <> 'retired';
  select source.* into strict v_source
  from public.legal_sources source
  where source.municipality_id = v_endpoint.municipality_id
    and source.id = v_endpoint.source_id;
  select municipality.* into strict v_municipality
  from public.municipalities municipality
  where municipality.id = v_endpoint.municipality_id;

  for v_asset in select value from jsonb_array_elements(p_assets)
  loop
    if jsonb_typeof(v_asset) <> 'object' then
      raise exception 'every discovery must be a JSON object';
    end if;
    v_url := trim(coalesce(v_asset ->> 'url', ''));
    v_host := lower(split_part(split_part(v_url, '://', 2), '/', 1));
    v_relation_kind := coalesce(v_asset ->> 'relation_kind', 'attachment');
    v_mime_type := nullif(lower(trim(coalesce(v_asset ->> 'mime_type', ''))), '');
    v_label := nullif(left(trim(coalesce(v_asset ->> 'label', '')), 300), '');
    begin
      v_byte_size := nullif(v_asset ->> 'byte_size', '')::bigint;
    exception when others then
      raise exception 'discovery byte size must be an integer';
    end;
    if v_url !~ '^https://[^[:space:]]+$'
       or not (v_host = any(v_endpoint.allowed_hosts))
       or v_relation_kind not in (
         'attachment', 'previous_version', 'related_document', 'publication_copy', 'catalog_page'
       )
       or (v_byte_size is not null and v_byte_size < 0) then
      raise exception 'discovered asset is outside the endpoint allowlist';
    end if;

    if v_relation_kind = 'catalog_page' then
      if v_endpoint.endpoint_kind <> 'catalog'
         or v_url !~* '/Documentos/Pesquisa/' then
        raise exception 'catalog page discovery requires a catalog endpoint';
      end if;
      insert into private.legal_source_endpoints (
        municipality_id, source_id, endpoint_kind, trust_tier, content_mode,
        citable_body, url, allowed_hosts, expected_content_types, parser_hint,
        poll_interval, priority, status, metadata
      ) values (
        v_endpoint.municipality_id, v_endpoint.source_id, 'catalog',
        v_endpoint.trust_tier, 'catalog_only', false, v_url,
        v_endpoint.allowed_hosts, array['text/html', 'application/xhtml+xml']::text[],
        'siscam_catalog', v_endpoint.poll_interval,
        least(1000, v_endpoint.priority + 1), 'active',
        v_endpoint.metadata || jsonb_build_object(
          'discovered_from_endpoint_id', v_endpoint.id,
          'coverage_status', 'catalog_page_discovered'
        )
      ) on conflict (municipality_id, source_id, url) do update set
        status = case when private.legal_source_endpoints.status = 'retired'
          then 'retired' else 'active' end,
        updated_at = now();
      v_pages_queued := v_pages_queued + 1;
      v_count := v_count + 1;
      continue;
    end if;

    v_blocker := case
      when v_byte_size > 50 * 1024 * 1024 then 'external_large_file_extractor_required'
      when v_mime_type in ('application/rtf', 'text/rtf', 'application/msword')
        then 'legacy_document_extractor_required'
      else null
    end;

    insert into private.legal_source_discovered_assets (
      municipality_id, source_id, endpoint_id, asset_url, relation_kind,
      declared_mime_type, declared_byte_size, link_label, status, blocker_code,
      first_observed_at, last_observed_at
    ) values (
      v_endpoint.municipality_id, v_endpoint.source_id, v_endpoint.id, v_url,
      v_relation_kind, v_mime_type, v_byte_size, v_label,
      case when v_blocker is null then 'discovered' else 'blocked' end,
      v_blocker, p_observed_at, p_observed_at
    ) on conflict (municipality_id, source_id, asset_url) do update set
      last_observed_at = greatest(
        private.legal_source_discovered_assets.last_observed_at,
        excluded.last_observed_at
      ),
      declared_mime_type = coalesce(
        excluded.declared_mime_type,
        private.legal_source_discovered_assets.declared_mime_type
      ),
      declared_byte_size = coalesce(
        excluded.declared_byte_size,
        private.legal_source_discovered_assets.declared_byte_size
      ),
      link_label = coalesce(excluded.link_label, private.legal_source_discovered_assets.link_label),
      updated_at = now()
    returning id into v_discovered_asset_id;

    if v_relation_kind = 'related_document' then
      v_match := regexp_match(
        lower(coalesce(v_label, '')),
        '(lei complementar|lei|decreto)[^0-9]{0,30}([0-9][0-9.]*)[^0-9]+([12][0-9]{3})'
      );
      v_species := case v_match[1]
        when 'lei complementar' then 'complementary_law'
        when 'lei' then 'law'
        when 'decreto' then 'decree'
        else null
      end;
      v_number := nullif(regexp_replace(coalesce(v_match[2], ''), '[^0-9]', '', 'g'), '');
      v_year := nullif(coalesce(v_match[3], ''), '')::integer;
      v_canonical_key := case when v_species is not null and v_number is not null and v_year is not null
        then v_species || ':' || v_number || ':' || v_year::text else null end;
      v_external_document_id := (regexp_match(v_url, '/Documento/([0-9]+)', 'i'))[1];
      v_official_identifier := case v_species
        when 'complementary_law' then 'Lei Complementar nº ' || v_number || '/' || v_year::text
        when 'law' then 'Lei nº ' || v_number || '/' || v_year::text
        when 'decree' then 'Decreto nº ' || v_number || '/' || v_year::text
        else null
      end;
      v_promoted_source_id := null;

      if v_canonical_key is not null then
        -- Catalog classifications are dispatched independently and may expose
        -- the same law at the same time.  Serialize by legal identity before
        -- looking up or creating its source so textual authority differences
        -- and concurrent crawls cannot manufacture duplicate canonical laws.
        perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
          v_endpoint.municipality_id::text || ':canonical-law:' || v_canonical_key,
          0
        ));
        select identity.source_id into v_promoted_source_id
        from private.legal_source_canonical_identities identity
        where identity.municipality_id = v_endpoint.municipality_id
          and identity.canonical_legal_key = v_canonical_key;
        if v_promoted_source_id is null then
          select source.id into v_promoted_source_id
          from public.legal_sources source
          where source.municipality_id = v_endpoint.municipality_id
            and source.official_identifier = v_official_identifier
          order by source.created_at, source.id
          limit 1;
        end if;
        if v_promoted_source_id is null then
          insert into public.legal_sources (
            municipality_id, source_type, jurisdiction, issuing_authority,
            title, official_identifier, official_url, tax_scope,
            divergence_scope, status
          ) values (
            v_endpoint.municipality_id,
            case when v_species = 'decree' then 'decree' else 'law' end,
            'municipal', v_municipality.name, coalesce(v_label, v_official_identifier),
            v_official_identifier, v_url, 'Tributos municipais',
            'fiscal_knowledge', 'draft'
          ) returning id into v_promoted_source_id;
        end if;
        insert into private.legal_source_canonical_identities (
          municipality_id, source_id, canonical_legal_key
        ) values (
          v_endpoint.municipality_id, v_promoted_source_id, v_canonical_key
        ) on conflict do nothing;
      end if;

      select candidate.id into v_candidate_id
      from private.legal_source_promotion_candidates candidate
      where candidate.municipality_id = v_endpoint.municipality_id
        and (
          candidate.document_url = v_url
          or (
            v_canonical_key is not null
            and candidate.canonical_legal_key = v_canonical_key
          )
        )
      order by (candidate.canonical_legal_key = v_canonical_key) desc, candidate.created_at
      limit 1
      for update;

      if v_candidate_id is null then
        insert into private.legal_source_promotion_candidates (
          municipality_id, catalog_source_id, promoted_source_id, document_url,
          link_label, legal_species, legal_number, legal_year, canonical_legal_key,
          external_document_id, status, blocker_code, first_observed_at, last_observed_at
        ) values (
          v_endpoint.municipality_id, v_endpoint.source_id, v_promoted_source_id, v_url,
          v_label, v_species, v_number, v_year, v_canonical_key, v_external_document_id,
          case when v_canonical_key is null then 'blocked' else 'ficha_queued' end,
          case when v_canonical_key is null then 'identity_metadata_required' end,
          p_observed_at, p_observed_at
        ) on conflict do nothing
        returning id into v_candidate_id;
        if v_candidate_id is null then
          select candidate.id into strict v_candidate_id
          from private.legal_source_promotion_candidates candidate
          where candidate.municipality_id = v_endpoint.municipality_id
            and (
              candidate.document_url = v_url
              or (
                v_canonical_key is not null
                and candidate.canonical_legal_key = v_canonical_key
              )
            )
          order by (candidate.canonical_legal_key = v_canonical_key) desc, candidate.created_at
          limit 1;
        end if;
      end if;

      update private.legal_source_promotion_candidates
      set link_label = coalesce(v_label, link_label),
          promoted_source_id = coalesce(v_promoted_source_id, promoted_source_id),
          legal_species = coalesce(v_species, legal_species),
          legal_number = coalesce(v_number, legal_number),
          legal_year = coalesce(v_year, legal_year),
          canonical_legal_key = coalesce(v_canonical_key, canonical_legal_key),
          external_document_id = coalesce(v_external_document_id, external_document_id),
          status = case when v_canonical_key is null then status else 'ficha_queued' end,
          blocker_code = case when v_canonical_key is null
            then coalesce(blocker_code, 'identity_metadata_required') else null end,
          last_observed_at = greatest(last_observed_at, p_observed_at),
          updated_at = now()
      where id = v_candidate_id;

      insert into private.legal_catalog_coverage_candidates (
        municipality_id, coverage_id, candidate_id,
        first_observed_at, last_observed_at
      )
      select
        v_endpoint.municipality_id, coverage.id, v_candidate_id,
        p_observed_at, p_observed_at
      from private.legal_catalog_coverages coverage
      where coverage.municipality_id = v_endpoint.municipality_id
        and coverage.coverage_key = v_endpoint.metadata ->> 'coverage_key'
      on conflict (municipality_id, coverage_id, candidate_id) do update set
        last_observed_at = greatest(
          private.legal_catalog_coverage_candidates.last_observed_at,
          excluded.last_observed_at
        );

      if v_endpoint.endpoint_kind = 'document_page'
         and v_source.source_type <> 'official_guidance'
         and v_promoted_source_id is not null
         and v_promoted_source_id <> v_source.id then
        insert into private.legal_source_relationship_candidates (
          municipality_id, from_source_id, to_source_id, relation_type,
          evidence_asset_id, status
        ) values (
          v_endpoint.municipality_id, v_source.id, v_promoted_source_id,
          'related', v_discovered_asset_id, 'pending_review'
        ) on conflict (
          municipality_id, from_source_id, to_source_id, relation_type
        ) do nothing;
        if found then
          v_relationships_queued := v_relationships_queued + 1;
        end if;
      end if;


      if v_promoted_source_id is not null then
        if not exists (
          select 1 from private.legal_source_endpoints ficha
          where ficha.municipality_id = v_endpoint.municipality_id
            and ficha.source_id = v_promoted_source_id
            and ficha.endpoint_kind = 'document_page'
            and ficha.content_mode = 'catalog_only'
            and ficha.status = 'active'
            and ficha.url <> v_url
        ) then
          insert into private.legal_source_endpoints (
            municipality_id, source_id, endpoint_kind, trust_tier, content_mode,
            citable_body, url, allowed_hosts, expected_content_types, parser_hint,
            poll_interval, priority, status, metadata
          ) values (
            v_endpoint.municipality_id, v_promoted_source_id, 'document_page',
            'primary_publication', 'catalog_only', false, v_url,
            v_endpoint.allowed_hosts, array['text/html', 'application/xhtml+xml']::text[],
            'siscam_ficha', interval '6 hours', 20, 'active',
            jsonb_build_object(
              'promotion_candidate_id', v_candidate_id,
              'canonical_legal_key', v_canonical_key,
              'coverage_key', v_endpoint.metadata ->> 'coverage_key',
              'coverage_status', 'ficha_queued'
            )
          ) on conflict (municipality_id, source_id, url) do update set
            status = case when private.legal_source_endpoints.status = 'retired'
              then 'retired' else 'active' end,
            updated_at = now();
        end if;
        v_promotions_queued := v_promotions_queued + 1;
      end if;
    elsif v_relation_kind in ('attachment', 'publication_copy')
          and v_endpoint.metadata ? 'promotion_candidate_id' then
      v_candidate_id := (v_endpoint.metadata ->> 'promotion_candidate_id')::uuid;
      if v_source.official_identifier ~* '^Lei Complementar[^0-9]*36/2013$' then
        update private.legal_source_promotion_candidates
        set status = 'blocked',
            blocker_code = 'large_or_legacy_attachment_extractor_required',
            last_observed_at = p_observed_at,
            updated_at = now()
        where id = v_candidate_id and municipality_id = v_endpoint.municipality_id;
      elsif not v_attachment_promoted and v_blocker is null and (
        v_mime_type is null
        or v_mime_type in (
          'application/pdf',
          'application/octet-stream',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
      ) then
        -- Discovery is not evidence.  Keep the last-known-good legal body
        -- active and register a non-runnable candidate.  A future governed
        -- promotion RPC may swap the endpoints only after a successful fetch,
        -- signature/MIME verification, complete extraction and staging.  This
        -- Phase 2 release deliberately fails closed instead of dethroning the
        -- current source merely because an official page exposed a new link.
        perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
          v_endpoint.municipality_id::text || ':legal-body:' || v_endpoint.source_id::text,
          0
        ));
        select body.id into v_current_body_endpoint_id
        from private.legal_source_endpoints body
        where body.municipality_id = v_endpoint.municipality_id
          and body.source_id = v_endpoint.source_id
          and body.content_mode = 'legal_body'
          and body.status = 'active'
        for update;

        insert into private.legal_source_endpoints (
          municipality_id, source_id, endpoint_kind, trust_tier, content_mode,
          citable_body, url, allowed_hosts, expected_content_types, parser_hint,
          poll_interval, priority, status, metadata
        ) values (
          v_endpoint.municipality_id, v_endpoint.source_id, 'document_file',
          'primary_publication', 'legal_body', true, v_url,
          v_endpoint.allowed_hosts,
          array[
            'application/pdf', 'application/octet-stream',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
          ]::text[],
          'official_attachment', interval '6 hours', 10, 'paused',
          jsonb_build_object(
            'promotion_candidate_id', v_candidate_id,
            'coverage_key', v_endpoint.metadata ->> 'coverage_key',
            'coverage_status', 'safe_cutover_pending',
            'activation_blocker', 'validated_cutover_required',
            'manual_pause_preserved', true
          )
        ) on conflict (municipality_id, source_id, url) do update set
          content_mode = 'legal_body',
          citable_body = true,
          parser_hint = 'official_attachment',
          -- Never reactivate a retired or manually paused endpoint through
          -- rediscovery.  Only refresh non-authoritative discovery metadata.
          metadata = private.legal_source_endpoints.metadata
            || jsonb_build_object(
              'promotion_candidate_id', v_candidate_id,
              'coverage_key', v_endpoint.metadata ->> 'coverage_key',
              'coverage_status', 'safe_cutover_pending',
              'activation_blocker', 'validated_cutover_required'
            ),
          updated_at = now()
        returning id into v_candidate_body_endpoint_id;

        if v_current_body_endpoint_id is distinct from v_candidate_body_endpoint_id then
          insert into private.legal_body_endpoint_cutovers (
            municipality_id, source_id, previous_endpoint_id,
            candidate_endpoint_id, candidate_url, status, reason_code
          ) values (
            v_endpoint.municipality_id, v_endpoint.source_id,
            v_current_body_endpoint_id, v_candidate_body_endpoint_id, v_url,
            'blocked', 'validated_cutover_required'
          ) on conflict (municipality_id, candidate_endpoint_id) do nothing;
        end if;
        v_attachment_promoted := false;
        update private.legal_source_promotion_candidates
        set status = 'blocked', blocker_code = 'validated_cutover_required',
            last_observed_at = p_observed_at, updated_at = now()
        where id = v_candidate_id and municipality_id = v_endpoint.municipality_id;
      end if;
    end if;
    v_count := v_count + 1;
  end loop;

  -- Discovery happens asynchronously after the dispatcher has calculated its
  -- remaining due work.  Bring the tenant cursor forward so newly discovered
  -- catalog pages, fichas and bodies are collected in the next bounded batch
  -- instead of waiting for the following daily window.
  if v_pages_queued > 0 or v_promotions_queued > 0 or v_attachment_promoted then
    update private.knowledge_automation_settings setting
    set next_run_at = least(
          coalesce(setting.next_run_at, now() + interval '5 minutes'),
          now() + interval '5 minutes'
        ),
        last_run_status = 'partial',
        updated_at = now()
    where setting.municipality_id = v_endpoint.municipality_id
      and setting.enabled;
  end if;

  return jsonb_build_object(
    'endpoint_id', v_endpoint.id,
    'recorded_assets', v_count,
    'catalog_pages_queued', v_pages_queued,
    'promotions_queued', v_promotions_queued,
    'relationships_queued', v_relationships_queued
  );
end;
$$;

create or replace view public.vw_knowledge_catalog_coverage
with (security_invoker = true)
as
select
  coverage.municipality_id,
  coverage.coverage_key,
  coverage.title,
  coverage.expected_document_count,
  coverage.upstream_status,
  coverage.blocker_code,
  count(candidate.id)::integer as discovered_count,
  count(candidate.id) filter (where candidate.promoted_source_id is not null)::integer
    as identity_verified_count,
  count(candidate.id) filter (where candidate.status = 'extraction_queued')::integer
    as extraction_queued_count,
  count(candidate.id) filter (where exists (
    select 1 from private.legal_source_change_sets change_set
    where change_set.municipality_id = candidate.municipality_id
      and change_set.source_id = candidate.promoted_source_id
      and change_set.status in ('detected', 'changes_requested', 'accepted')
      and change_set.change_type <> 'legacy_import'
      and change_set.candidate_version_id is not null
      and private.legal_version_has_complete_evidence(
        change_set.municipality_id,
        change_set.candidate_version_id
      )
  ))::integer as reviewable_count,
  count(candidate.id) filter (where exists (
    select 1 from public.legal_source_versions version
    where version.municipality_id = candidate.municipality_id
      and version.source_id = candidate.promoted_source_id
      and private.legal_source_version_is_current_citable(
        version.municipality_id,
        version.id
      )
  ))::integer as published_count,
  (
    coverage.expected_document_count is not null
    -- Integral means the discovered canonical set is exactly the declared
    -- official set.  Extra, duplicate or unresolved candidates keep the
    -- result fail-closed instead of being hidden by independent >= counts.
    and count(candidate.id) = coverage.expected_document_count
    and count(candidate.id) filter (
      where candidate.promoted_source_id is not null
        and candidate.canonical_legal_key is not null
    ) = coverage.expected_document_count
    and count(candidate.id) filter (where exists (
      select 1 from public.legal_source_versions version
      where version.municipality_id = candidate.municipality_id
        and version.source_id = candidate.promoted_source_id
        and private.legal_source_version_is_current_citable(
          version.municipality_id,
          version.id
        )
    )) = coverage.expected_document_count
  ) as corpus_integral,
  coverage.updated_at
from private.legal_catalog_coverages coverage
left join private.legal_catalog_coverage_candidates coverage_candidate
  on coverage_candidate.municipality_id = coverage.municipality_id
 and coverage_candidate.coverage_id = coverage.id
left join private.legal_source_promotion_candidates candidate
  on candidate.municipality_id = coverage_candidate.municipality_id
 and candidate.id = coverage_candidate.candidate_id
group by coverage.id;

-- Catalog source identities are intentionally operational and non-citable.
with catalog_seed (
  municipality_slug, coverage_key, title, official_identifier, url,
  expected_count, upstream_status, blocker_code
) as (
  values
    (
      'cordeiropolis-sp', 'siscam.classification.424',
      'Pesquisa fiscal Siscam — classificação 424',
      'Catálogo fiscal Siscam — classificação 424',
      'https://cordeiropolis.siscam.com.br/Documentos/Pesquisa/81?Classificacao=424&Modulo=8&Pagina=1&Pesquisa=Avancada&Situacao=428',
      null::integer, 'blocked_503', 'upstream_siscam_503'
    ),
    (
      'araras-sp', 'siscam.classification.752',
      'Pesquisa tributária Siscam — classificação 752',
      'Catálogo tributário Siscam — classificação 752',
      'https://araras.siscam.com.br/Documentos/Pesquisa/75?Classificacao=752&Modulo=8&Pagina=1&Pesquisa=Avancada&Situacao=18',
      151, 'unverified', null
    ),
    (
      'araras-sp', 'siscam.classification.951',
      'Pesquisa de códigos Siscam — classificação 951',
      'Catálogo de códigos Siscam — classificação 951',
      'https://araras.siscam.com.br/Documentos/Pesquisa/75?Classificacao=951&Modulo=8&Pagina=1&Pesquisa=Avancada&Situacao=18',
      10, 'unverified', null
    ),
    (
      'araras-sp', 'siscam.classification.1228',
      'Pesquisa de PGV Siscam — classificação 1228',
      'Catálogo de PGV Siscam — classificação 1228',
      'https://araras.siscam.com.br/Documentos/Pesquisa/75?Classificacao=1228&Modulo=8&Pagina=1&Pesquisa=Avancada&Situacao=18',
      8, 'unverified', null
    )
), inserted_sources as (
  insert into public.legal_sources (
    municipality_id, source_type, jurisdiction, issuing_authority, title,
    official_identifier, official_url, tax_scope, divergence_scope, status
  )
  select
    municipality.id, 'official_guidance', 'municipal', municipality.name,
    seed.title, seed.official_identifier, seed.url, 'Tributos municipais',
    'source_catalog', 'draft'
  from catalog_seed seed
  join public.municipalities municipality on municipality.slug = seed.municipality_slug
  where not exists (
    select 1 from public.legal_sources source
    where source.municipality_id = municipality.id
      and source.issuing_authority = municipality.name
      and source.official_identifier = seed.official_identifier
  )
  returning id
)
select count(*) from inserted_sources;

with catalog_seed (
  municipality_slug, coverage_key, title, official_identifier, url,
  expected_count, upstream_status, blocker_code
) as (
  values
    ('cordeiropolis-sp', 'siscam.classification.424', 'Pesquisa fiscal Siscam — classificação 424', 'Catálogo fiscal Siscam — classificação 424', 'https://cordeiropolis.siscam.com.br/Documentos/Pesquisa/81?Classificacao=424&Modulo=8&Pagina=1&Pesquisa=Avancada&Situacao=428', null::integer, 'blocked_503', 'upstream_siscam_503'),
    ('araras-sp', 'siscam.classification.752', 'Pesquisa tributária Siscam — classificação 752', 'Catálogo tributário Siscam — classificação 752', 'https://araras.siscam.com.br/Documentos/Pesquisa/75?Classificacao=752&Modulo=8&Pagina=1&Pesquisa=Avancada&Situacao=18', 151, 'unverified', null),
    ('araras-sp', 'siscam.classification.951', 'Pesquisa de códigos Siscam — classificação 951', 'Catálogo de códigos Siscam — classificação 951', 'https://araras.siscam.com.br/Documentos/Pesquisa/75?Classificacao=951&Modulo=8&Pagina=1&Pesquisa=Avancada&Situacao=18', 10, 'unverified', null),
    ('araras-sp', 'siscam.classification.1228', 'Pesquisa de PGV Siscam — classificação 1228', 'Catálogo de PGV Siscam — classificação 1228', 'https://araras.siscam.com.br/Documentos/Pesquisa/75?Classificacao=1228&Modulo=8&Pagina=1&Pesquisa=Avancada&Situacao=18', 8, 'unverified', null)
)
insert into private.legal_catalog_coverages (
  municipality_id, catalog_source_id, coverage_key, title,
  expected_document_count, upstream_status, blocker_code
)
select
  municipality.id, source.id, seed.coverage_key, seed.title,
  seed.expected_count, seed.upstream_status, seed.blocker_code
from catalog_seed seed
join public.municipalities municipality on municipality.slug = seed.municipality_slug
join public.legal_sources source
  on source.municipality_id = municipality.id
 and source.issuing_authority = municipality.name
 and source.official_identifier = seed.official_identifier
on conflict (municipality_id, coverage_key) do update set
  expected_document_count = excluded.expected_document_count,
  upstream_status = excluded.upstream_status,
  blocker_code = excluded.blocker_code,
  updated_at = now();

insert into private.legal_source_endpoints (
  municipality_id, source_id, endpoint_kind, trust_tier, content_mode,
  citable_body, url, allowed_hosts, expected_content_types, parser_hint,
  poll_interval, priority, status, metadata
)
select
  coverage.municipality_id, coverage.catalog_source_id, 'catalog',
  'primary_publication', 'catalog_only', false, source.official_url,
  array[lower(split_part(split_part(source.official_url, '://', 2), '/', 1))]::text[],
  array['text/html', 'application/xhtml+xml']::text[], 'siscam_catalog',
  interval '6 hours', 50, 'active', jsonb_build_object(
    'coverage_key', coverage.coverage_key,
    'expected_document_count', coverage.expected_document_count,
    'coverage_status', 'initial_discovery'
  )
from private.legal_catalog_coverages coverage
join public.legal_sources source
  on source.municipality_id = coverage.municipality_id
 and source.id = coverage.catalog_source_id
on conflict (municipality_id, source_id, url) do update set
  content_mode = 'catalog_only', citable_body = false,
  parser_hint = 'siscam_catalog', poll_interval = interval '6 hours',
  status = 'active', metadata = excluded.metadata, updated_at = now();

-- Snapshot v3 exposes coverage counts and never claims integral coverage until
-- every expected document has reached the published, evidence-backed state.
alter function public.ia_get_knowledge_operations_snapshot(uuid)
  rename to ia_get_knowledge_operations_snapshot_phase2_core;

create or replace function public.ia_get_knowledge_operations_snapshot(
  p_municipality_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base jsonb;
  v_coverage jsonb;
begin
  v_base := public.ia_get_knowledge_operations_snapshot_phase2_core(p_municipality_id);
  select coalesce(jsonb_agg(jsonb_build_object(
    'coverage_key', coverage.coverage_key,
    'title', coverage.title,
    'expected', coverage.expected_document_count,
    'discovered', coverage.discovered_count,
    'identity_verified', coverage.identity_verified_count,
    'extraction_queued', coverage.extraction_queued_count,
    'reviewable', coverage.reviewable_count,
    'published', coverage.published_count,
    'corpus_integral', coverage.corpus_integral,
    'upstream_status', coverage.upstream_status,
    'blocker', coverage.blocker_code
  ) order by coverage.coverage_key), '[]'::jsonb)
    into v_coverage
  from public.vw_knowledge_catalog_coverage coverage
  where coverage.municipality_id = p_municipality_id;
  return v_base || jsonb_build_object(
    'coverage', v_coverage,
    'coverage_label', 'Cobertura inicial governada',
    'corpus_integral', coalesce(
      jsonb_array_length(v_coverage) > 0
      and not exists (
        select 1 from public.vw_knowledge_catalog_coverage coverage
        where coverage.municipality_id = p_municipality_id
          and not coverage.corpus_integral
      ), false
    )
  );
end;
$$;

create trigger legal_catalog_coverages_set_updated_at
before update on private.legal_catalog_coverages
for each row execute function private.set_updated_at();
create trigger legal_source_promotion_candidates_set_updated_at
before update on private.legal_source_promotion_candidates
for each row execute function private.set_updated_at();
create trigger legal_source_relationship_candidates_append_only
before update or delete on private.legal_source_relationship_candidates
for each row execute function private.prevent_any_mutation();
create trigger legal_source_canonical_identities_append_only
before update or delete on private.legal_source_canonical_identities
for each row execute function private.prevent_any_mutation();
create trigger legal_body_endpoint_cutovers_append_only
before update or delete on private.legal_body_endpoint_cutovers
for each row execute function private.prevent_any_mutation();

alter table private.legal_source_canonical_identities enable row level security;
alter table private.legal_catalog_coverages enable row level security;
alter table private.legal_source_promotion_candidates enable row level security;
alter table private.legal_catalog_coverage_candidates enable row level security;
alter table private.legal_source_relationship_candidates enable row level security;
alter table private.legal_body_endpoint_cutovers enable row level security;
revoke all on
  private.legal_source_canonical_identities,
  private.legal_catalog_coverages,
  private.legal_source_promotion_candidates,
  private.legal_catalog_coverage_candidates,
  private.legal_source_relationship_candidates,
  private.legal_body_endpoint_cutovers
from public, anon, authenticated, service_role;

revoke all on public.vw_knowledge_catalog_coverage
  from public, anon, authenticated, service_role;

revoke all on function private.refresh_legal_catalog_coverage_health()
  from public, anon, authenticated, service_role;

revoke all on function public.ia_fiscal_record_knowledge_discoveries(uuid, jsonb, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_record_knowledge_discoveries(uuid, jsonb, timestamptz)
  to service_role;

revoke all on function public.ia_get_knowledge_operations_snapshot_phase2_core(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_get_knowledge_operations_snapshot(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ia_get_knowledge_operations_snapshot(uuid)
  to authenticated;

comment on view public.vw_knowledge_catalog_coverage is
  'Coverage reconciliation; corpus_integral is false until every expected item is published.';

commit;
