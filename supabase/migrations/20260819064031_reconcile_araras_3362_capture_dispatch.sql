-- Reconcile the completed pg_net response for the controlled Araras capture
-- into the append-only scheduler dispatch ledger.

do $$
declare
  v_result jsonb;
begin
  v_result := private.ia_fiscal_reconcile_knowledge_scheduler_dispatches(200);

  if not exists (
    select 1
    from private.knowledge_scheduler_dispatches dispatch
    join private.legal_source_endpoints endpoint
      on endpoint.municipality_id = dispatch.municipality_id
     and endpoint.id = dispatch.endpoint_id
    join private.knowledge_scheduler_dispatch_events event
      on event.dispatch_id = dispatch.id
     and event.event_type = 'succeeded'
    where endpoint.url = 'https://araras.siscam.com.br/arquivo?Id=43123'
      and dispatch.scope = 'ingest'
      and event.http_status = 201
  ) then
    raise exception 'successful Araras capture dispatch was not reconciled';
  end if;
end;
$$;
