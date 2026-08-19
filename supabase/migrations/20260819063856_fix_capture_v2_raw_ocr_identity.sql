-- Fix the capture-v2 identity contract for raw official evidence.
--
-- A raw catalog or scanned-PDF capture has a change set but intentionally no
-- candidate version until extraction/OCR completes.  The previous symmetric
-- null check rolled the whole capture back even though this is a valid,
-- governed state.

create or replace function public.ia_fiscal_capture_knowledge_source_v2(
  p_source_id uuid,
  p_requested_url text,
  p_final_url text,
  p_content_sha256 text,
  p_mime_type text,
  p_byte_size bigint,
  p_storage_bucket text,
  p_storage_path text,
  p_extracted_text text,
  p_sections jsonb,
  p_etag text,
  p_last_modified text,
  p_http_status integer,
  p_observed_at timestamptz,
  p_correlation_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_capture jsonb;
  v_stage jsonb;
  v_change_set_id uuid;
  v_candidate_version_id uuid;
  v_stage_status text := 'not_applicable';
  v_section_count integer := 0;
  v_chunk_count integer := 0;
begin
  if not private.is_service_role() then
    raise exception using errcode = '42501', message = 'service role required';
  end if;

  if nullif(trim(coalesce(p_extracted_text, '')), '') is null then
    if p_sections is not null then
      raise exception 'raw capture cannot submit staged sections';
    end if;
  else
    if p_sections is null
       or jsonb_typeof(p_sections) <> 'array'
       or jsonb_array_length(p_sections) <> 1
       or coalesce(jsonb_typeof(p_sections -> 0), 'null') <> 'object'
       or p_sections -> 0 ->> 'section_key' <> 'integral'
       or coalesce(p_sections -> 0 ->> 'content_text', '') <> p_extracted_text
       or coalesce(p_sections -> 0 ->> 'ordinal', '') <> '1'
       or coalesce(jsonb_typeof(p_sections -> 0 -> 'chunks'), 'null') <> 'array'
       or jsonb_array_length(p_sections -> 0 -> 'chunks') > 5000
       or exists (
         select 1
         from jsonb_array_elements(p_sections -> 0 -> 'chunks')
           with ordinality input(chunk, ordinality)
         where jsonb_typeof(input.chunk) <> 'object'
            or char_length(coalesce(input.chunk ->> 'content_text', '')) not between 1 and 8000
            or position(
              coalesce(input.chunk ->> 'content_text', '') in p_extracted_text
            ) = 0
            or coalesce(input.chunk ->> 'chunk_index', '') <> input.ordinality::text
            or coalesce(input.chunk ->> 'token_count', '') !~ '^[1-9][0-9]*$'
       ) then
      raise exception 'one bounded integral section exactly derived from extraction is required';
    end if;
  end if;

  perform set_config(
    'ia_fiscal.knowledge_staging_mode',
    'defer-for-capture-v2',
    true
  );
  v_capture := public.ia_fiscal_capture_knowledge_source(
    p_source_id,
    p_requested_url,
    p_final_url,
    p_content_sha256,
    p_mime_type,
    p_byte_size,
    p_storage_bucket,
    p_storage_path,
    p_extracted_text,
    p_etag,
    p_last_modified,
    p_http_status,
    p_observed_at,
    p_correlation_id,
    p_metadata
  );
  perform set_config('ia_fiscal.knowledge_staging_mode', 'off', true);

  begin
    v_change_set_id := nullif(v_capture ->> 'change_set_id', '')::uuid;
    v_candidate_version_id := nullif(v_capture ->> 'candidate_version_id', '')::uuid;
  exception when others then
    raise exception 'capture v2 received an invalid staging identity';
  end;

  -- Raw catalog/PDF captures legitimately create an auditable change set
  -- before a candidate version exists.  Only extracted content requires the
  -- change-set/candidate pair used by the atomic staging step.
  if v_candidate_version_id is not null and v_change_set_id is null then
    raise exception 'capture v2 received a candidate without its change set';
  end if;
  if nullif(trim(coalesce(p_extracted_text, '')), '') is null then
    if v_candidate_version_id is not null then
      raise exception 'raw capture cannot create a candidate version';
    end if;
  elsif v_change_set_id is not null and v_candidate_version_id is null then
    raise exception 'extracted capture received an incomplete staging identity';
  end if;
  if v_candidate_version_id is not null then
    if p_sections is null then
      raise exception 'capture v2 candidate is missing its integral evidence';
    end if;
    v_stage := public.ia_fiscal_stage_knowledge_sections_legacy_impl(
      v_change_set_id,
      p_sections
    );
    if not private.knowledge_staging_matches_payload(
      v_candidate_version_id,
      p_sections
    ) then
      raise exception 'staged evidence does not exactly match the capture v2 payload';
    end if;
    begin
      v_stage_status := v_stage ->> 'status';
      v_section_count := (v_stage ->> 'section_count')::integer;
      v_chunk_count := (v_stage ->> 'chunk_count')::integer;
    exception when others then
      raise exception 'capture v2 received an invalid staging result';
    end;
    if v_stage_status not in ('staged', 'already_staged')
       or v_section_count <> 1
       or v_chunk_count < 1 then
      raise exception 'capture v2 staging result is incomplete';
    end if;
  end if;

  return v_capture || jsonb_build_object(
    'staging_status', v_stage_status,
    'staged_sections', v_section_count,
    'staged_chunks', v_chunk_count
  );
end;
$$;

revoke all on function public.ia_fiscal_capture_knowledge_source_v2(
  uuid, text, text, text, text, bigint, text, text, text, jsonb,
  text, text, integer, timestamptz, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.ia_fiscal_capture_knowledge_source_v2(
  uuid, text, text, text, text, bigint, text, text, text, jsonb,
  text, text, integer, timestamptz, uuid, jsonb
) to service_role;

comment on function public.ia_fiscal_capture_knowledge_source_v2(
  uuid, text, text, text, text, bigint, text, text, text, jsonb,
  text, text, integer, timestamptz, uuid, jsonb
) is
  'Service-only atomic capture. Extracted bodies stage one integral section and exact chunks; raw official evidence may retain a change set without a candidate until governed extraction.';
