
create or replace function private.guard_frozen_content()
returns trigger
language plpgsql
set search_path=''
as $$
declare
  old_row jsonb := to_jsonb(old);
  new_row jsonb := to_jsonb(new);
  row_status text := old_row->>'status';
begin
  if tg_op='DELETE' then raise exception '% cannot be deleted after creation',tg_table_name; end if;
  if tg_table_name='notification_template_versions'
     and row_status in ('approved','active','retired')
     and (old_row->'subject' is distinct from new_row->'subject'
       or old_row->'body_text' is distinct from new_row->'body_text'
       or old_row->'body_html' is distinct from new_row->'body_html'
       or old_row->'content_sha256' is distinct from new_row->'content_sha256') then
    raise exception 'approved notification template content is immutable';
  elsif tg_table_name='legal_source_versions'
     and row_status in ('approved','published','revoked','retired')
     and (old_row->'content_text' is distinct from new_row->'content_text'
       or old_row->'content_sha256' is distinct from new_row->'content_sha256'
       or old_row->'source_id' is distinct from new_row->'source_id'
       or old_row->'version' is distinct from new_row->'version') then
    raise exception 'approved legal source content is immutable';
  elsif tg_table_name='ai_prompt_versions'
     and row_status in ('approved','active','retired')
     and (old_row->'system_prompt' is distinct from new_row->'system_prompt'
       or old_row->'output_schema' is distinct from new_row->'output_schema'
       or old_row->'content_sha256' is distinct from new_row->'content_sha256') then
    raise exception 'approved prompt content is immutable';
  elsif tg_table_name='notifications'
     and row_status in ('queued','processing','sent','simulated','partially_failed')
     and (old_row->'subject_snapshot' is distinct from new_row->'subject_snapshot'
       or old_row->'body_text_snapshot' is distinct from new_row->'body_text_snapshot'
       or old_row->'body_html_snapshot' is distinct from new_row->'body_html_snapshot'
       or old_row->'content_sha256' is distinct from new_row->'content_sha256'
       or old_row->'template_version_id' is distinct from new_row->'template_version_id') then
    raise exception 'queued notification content is immutable';
  elsif tg_table_name='case_messages'
     and row_status='published'
     and (old_row->'body' is distinct from new_row->'body'
       or old_row->'content_sha256' is distinct from new_row->'content_sha256'
       or old_row->'source_draft_revision_id' is distinct from new_row->'source_draft_revision_id'
       or old_row->'author_user_id' is distinct from new_row->'author_user_id') then
    raise exception 'published message content is immutable';
  end if;
  return new;
end;
$$;

