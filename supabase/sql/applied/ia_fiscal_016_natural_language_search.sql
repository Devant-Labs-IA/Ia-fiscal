-- Whitelist-based natural-language fiscal search. User text is never SQL.

create table if not exists public.fiscal_search_requests (
  id uuid primary key default gen_random_uuid(),
  municipality_id uuid not null
    references public.municipalities(id) on delete cascade,
  requested_by uuid references auth.users(id) on delete set null,
  raw_query text not null,
  normalized_query text not null,
  intent text not null check (
    intent in (
      'largest_debtors',
      'taxpayer_lookup',
      'fiscal_divergences',
      'open_cases',
      'unsupported'
    )
  ),
  parsed_filters jsonb not null default '{}'::jsonb,
  execution_plan jsonb not null default '{}'::jsonb,
  status text not null default 'completed'
    check (status in ('completed', 'unsupported', 'failed')),
  result_count integer not null default 0 check (result_count >= 0),
  execution_ms integer not null default 0 check (execution_ms >= 0),
  request_sha256 text not null check (request_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  constraint fiscal_search_requests_query_length_ck
    check (char_length(raw_query) between 2 and 500),
  constraint fiscal_search_requests_filters_ck
    check (jsonb_typeof(parsed_filters) = 'object'),
  constraint fiscal_search_requests_plan_ck
    check (jsonb_typeof(execution_plan) = 'object')
);

create index if not exists fiscal_search_requests_user_idx
  on public.fiscal_search_requests (
    municipality_id, requested_by, created_at desc
  );

alter table public.fiscal_search_requests enable row level security;

drop policy if exists fiscal_search_requests_select
  on public.fiscal_search_requests;
create policy fiscal_search_requests_select
on public.fiscal_search_requests
for select
to authenticated
using (
  requested_by = (select auth.uid())
  or (select private.has_municipality_role(
    municipality_id,
    array['municipal_admin', 'supervisor']::text[]
  ))
);

revoke all on public.fiscal_search_requests
  from public, anon, authenticated;
grant select on public.fiscal_search_requests to authenticated;
grant all on public.fiscal_search_requests to service_role;

drop trigger if exists fiscal_search_requests_audit
  on public.fiscal_search_requests;
create trigger fiscal_search_requests_audit
after insert or update or delete on public.fiscal_search_requests
for each row execute function private.audit_row_change();

create or replace function private.normalize_fiscal_search(p_value text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select trim(
    regexp_replace(
      translate(
        lower(coalesce(p_value, '')),
        'áàâãäéèêëíìîïóòôõöúùûüç',
        'aaaaaeeeeiiiiooooouuuuc'
      ),
      '[[:space:]]+',
      ' ',
      'g'
    )
  );
$function$;

revoke all on function private.normalize_fiscal_search(text)
  from public, anon, authenticated;

create or replace view public.vw_taxpayer_responsibilities_visible
with (security_invoker = true)
as
select
  l.municipality_id,
  l.taxpayer_id,
  l.id as link_id,
  l.accounting_firm_id,
  af.legal_name as responsible_name,
  case
    when af.tax_id is null then null
    else
      left(regexp_replace(af.tax_id, '[^0-9]', '', 'g'), 2)
      || '********'
      || right(regexp_replace(af.tax_id, '[^0-9]', '', 'g'), 4)
  end as masked_document,
  case
    when pc.value is null then null
    when position('@' in pc.value) > 2 then
      left(pc.value, 2) || '***@'
      || split_part(pc.value, '@', 2)
    else '***'
  end as masked_email,
  l.status as link_status,
  l.quarantine_reason as link_quarantine_reason,
  l.visible_in_homologation,
  l.valid_from,
  l.valid_until,
  l.verified_at as link_verified_at,
  pc.status as contact_status,
  pc.quarantine_reason as contact_quarantine_reason,
  pc.verified_at as contact_verified_at,
  (
    l.status = 'active'
    and l.verified_at is not null
    and pc.status = 'verified'
    and pc.verified_at is not null
  ) as safe_for_delivery
from public.taxpayer_accountant_links l
join public.accounting_firms af
  on af.municipality_id = l.municipality_id
 and af.id = l.accounting_firm_id
left join lateral (
  select c.*
  from public.party_contacts c
  where c.municipality_id = l.municipality_id
    and c.accounting_firm_id = l.accounting_firm_id
    and c.contact_type = 'email'
    and (
      c.status = 'verified'
      or c.visible_in_homologation
    )
  order by
    (c.status = 'verified') desc,
    c.is_primary desc,
    c.created_at desc
  limit 1
) pc on true
where l.status = 'active'
   or l.visible_in_homologation;

revoke all on public.vw_taxpayer_responsibilities_visible
  from public, anon, authenticated;
grant select on public.vw_taxpayer_responsibilities_visible
  to authenticated, service_role;

create or replace function public.ia_search_fiscal(
  p_municipality_id uuid,
  p_query text,
  p_limit integer default 30,
  p_offset integer default 0
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_started_at timestamptz := clock_timestamp();
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_normalized text;
  v_document text;
  v_intent text;
  v_years integer := 5;
  v_limit integer;
  v_offset integer;
  v_period_start date;
  v_period_end date := current_date;
  v_filters jsonb;
  v_plan jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_quality jsonb := '{}'::jsonb;
  v_count integer := 0;
  v_execution_ms integer;
begin
  if not (
    private.is_service_role()
    or (
      v_user_id is not null
      and private.has_municipality_role(
        p_municipality_id,
        array[
          'municipal_admin',
          'supervisor',
          'fiscal_auditor',
          'legal_reviewer'
        ]::text[]
      )
    )
  ) then
    raise exception 'municipality search access denied';
  end if;

  if p_query is null
     or char_length(trim(p_query)) < 2
     or char_length(p_query) > 500 then
    raise exception 'search query length must be between 2 and 500';
  end if;

  v_normalized := private.normalize_fiscal_search(p_query);
  v_document := regexp_replace(v_normalized, '[^0-9]', '', 'g');
  v_limit := least(greatest(coalesce(p_limit, 30), 1), 100);
  v_offset := least(greatest(coalesce(p_offset, 0), 0), 10000);

  if v_normalized ~ '(maior|maiores|ranking|top).*(devedor|devedores|debito|divida)'
     or v_normalized ~ '(devedor|devedores|debito|divida).*(maior|maiores|ranking|top)'
  then
    v_intent := 'largest_debtors';
  elsif v_normalized ~ '(fator r|rbt12|pgdas|divergenc|anexo|base de calculo)'
  then
    v_intent := 'fiscal_divergences';
  elsif v_normalized ~ '(processo|processos|caso|casos).*(aberto|pendente|andamento)'
     or v_normalized ~ '(aberto|pendente|andamento).*(processo|processos|caso|casos)'
  then
    v_intent := 'open_cases';
  elsif char_length(v_document) in (11, 14)
     or v_normalized ~ '(cnpj|cpf|contribuinte|empresa)'
  then
    v_intent := 'taxpayer_lookup';
  else
    v_intent := 'unsupported';
  end if;

  if v_intent = 'largest_debtors' then
    begin
      v_years := least(
        greatest(
          ((regexp_match(
            v_normalized,
            '([1-9][0-9]?) (ano|anos)'
          ))[1])::integer,
          1
        ),
        10
      );
    exception
      when others then
        v_years := 5;
    end;
  end if;

  v_period_start := (
    date_trunc('month', current_date)
    - make_interval(months => v_years * 12 - 1)
  )::date;

  v_filters := jsonb_build_object(
    'years', v_years,
    'period_start', v_period_start,
    'period_end', v_period_end,
    'limit', v_limit,
    'offset', v_offset,
    'responsibility_reference_date', current_date
  );

  v_plan := case v_intent
    when 'largest_debtors' then jsonb_build_object(
      'steps', jsonb_build_array(
        'filter municipal current account by period',
        'exclude debts without official due date or not yet mature',
        'aggregate debt by taxpayer',
        'rank after aggregation',
        'attach masked responsibility links by current registry date'
      ),
      'formula', 'sum(eligible_mature_balance) by taxpayer',
      'external_actions', false
    )
    when 'fiscal_divergences' then jsonb_build_object(
      'steps', jsonb_build_array(
        'filter typed fiscal divergences',
        'preserve rule version and execution mode',
        'order by priority and amount'
      ),
      'external_actions', false
    )
    when 'open_cases' then jsonb_build_object(
      'steps', jsonb_build_array(
        'filter non-closed fiscal cases',
        'join taxpayer and immutable finding count',
        'order by opening date'
      ),
      'external_actions', false
    )
    when 'taxpayer_lookup' then jsonb_build_object(
      'steps', jsonb_build_array(
        'match document or taxpayer name',
        'mask document',
        'attach visible responsibility quality'
      ),
      'external_actions', false
    )
    else jsonb_build_object(
      'supported_intents', jsonb_build_array(
        'largest debtors',
        'taxpayer lookup by CNPJ or CPF',
        'fiscal divergences',
        'open fiscal cases'
      ),
      'external_actions', false
    )
  end;

  if v_intent = 'largest_debtors' then
    with debt_by_taxpayer as (
      select
        v.municipio_id,
        v.contribuinte_id,
        min(v.tax_id) as tax_id,
        min(v.razao_social) as legal_name,
        sum(v.saldo_em_aberto) as eligible_balance,
        min(v.competencia) as first_competence,
        max(v.competencia) as last_competence,
        count(*) as eligible_competences
      from public.vw_current_account_period v
      where v.municipio_id = p_municipality_id
        and v.competencia between v_period_start
                              and date_trunc('month', v_period_end)::date
        and v.elegivel
        and v.saldo_em_aberto > 0
      group by v.municipio_id, v.contribuinte_id
    ),
    ranked as (
      select
        d.*,
        row_number() over (
          order by d.eligible_balance desc, d.contribuinte_id
        ) as rank_position
      from debt_by_taxpayer d
    ),
    page as (
      select *
      from ranked
      order by rank_position
      limit v_limit offset v_offset
    ),
    enriched as (
      select
        p.rank_position,
        p.contribuinte_id as taxpayer_id,
        case
          when p.tax_id is null then null
          else left(
            regexp_replace(p.tax_id, '[^0-9]', '', 'g'),
            2
          ) || '********' || right(
            regexp_replace(p.tax_id, '[^0-9]', '', 'g'),
            4
          )
        end as masked_tax_id,
        p.legal_name,
        p.eligible_balance,
        p.first_competence,
        p.last_competence,
        p.eligible_competences,
        coalesce(resp.responsibilities, '[]'::jsonb)
          as responsibilities,
        coalesce(resp.has_quarantine, false)
          as has_quarantined_responsibility,
        coalesce(resp.has_safe_delivery, false)
          as has_safe_delivery_recipient
      from page p
      left join lateral (
        select
          jsonb_agg(
            jsonb_build_object(
              'responsible_name', r.responsible_name,
              'masked_document', r.masked_document,
              'masked_email', r.masked_email,
              'link_status', r.link_status,
              'contact_status', r.contact_status,
              'quarantine_reason', coalesce(
                r.link_quarantine_reason,
                r.contact_quarantine_reason
              ),
              'safe_for_delivery', r.safe_for_delivery
            )
            order by
              r.safe_for_delivery desc,
              r.responsible_name
          ) as responsibilities,
          bool_or(
            r.link_status = 'quarantined'
            or r.contact_status = 'quarantined'
          ) as has_quarantine,
          bool_or(r.safe_for_delivery) as has_safe_delivery
        from public.vw_taxpayer_responsibilities_visible r
        where r.municipality_id = p.municipio_id
          and r.taxpayer_id = p.contribuinte_id
          and r.valid_from::date <= current_date
          and (
            r.valid_until is null
            or r.valid_until::date >= current_date
          )
      ) resp on true
    )
    select
      coalesce(
        jsonb_agg(to_jsonb(e) order by e.rank_position),
        '[]'::jsonb
      ),
      count(*)::integer
    into v_rows, v_count
    from enriched e;

    select jsonb_build_object(
      'eligible_taxpayers', count(distinct v.contribuinte_id)
        filter (where v.elegivel and v.saldo_em_aberto > 0),
      'taxpayers_with_missing_due_date',
        count(distinct v.contribuinte_id)
          filter (where v.valor_sem_vencimento > 0),
      'amount_without_due_date',
        coalesce(sum(v.valor_sem_vencimento), 0),
      'warning', case
        when coalesce(sum(v.valor_sem_vencimento), 0) > 0
          then 'Amounts without official due dates were not ranked.'
        else null
      end
    )
    into v_quality
    from public.vw_current_account_period v
    where v.municipio_id = p_municipality_id
      and v.competencia between v_period_start
                            and date_trunc('month', v_period_end)::date;

  elsif v_intent = 'fiscal_divergences' then
    with selected as (
      select
        v.divergence_id,
        v.taxpayer_id,
        case
          when v.tax_id is null then null
          else left(
            regexp_replace(v.tax_id, '[^0-9]', '', 'g'),
            2
          ) || '********' || right(
            regexp_replace(v.tax_id, '[^0-9]', '', 'g'),
            4
          )
        end as masked_tax_id,
        v.legal_name,
        v.divergence_type,
        v.period_start,
        v.period_end,
        v.difference_amount,
        v.status,
        v.execution_mode,
        v.rule_version_id,
        v.rule_version_number,
        v.rule_version_status,
        v.has_case_finding,
        v.case_finding_count,
        v.block_reasons
      from public.vw_fiscal_divergence_search v
      where v.municipality_id = p_municipality_id
        and (
          (v_normalized like '%fator r%'
            and v.divergence_type = 'factor_r')
          or (v_normalized like '%rbt12%'
            and v.divergence_type = 'pgdasd_rbt12')
          or (v_normalized like '%anexo%'
            and v.divergence_type = 'pgdasd_sigiss_annex')
          or (v_normalized like '%base de calculo%'
            and v.divergence_type = 'pgdasd_sigiss_tax_base')
          or (
            v_normalized not like '%fator r%'
            and v_normalized not like '%rbt12%'
            and v_normalized not like '%anexo%'
            and v_normalized not like '%base de calculo%'
          )
        )
      order by v.priority_score desc, v.difference_amount desc
      limit v_limit offset v_offset
    )
    select
      coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb),
      count(*)::integer
    into v_rows, v_count
    from selected s;

    v_quality := jsonb_build_object(
      'calculation_version',
        'simple-national-v2-effective-declaration',
      'blocked_results_are_visible', true
    );

  elsif v_intent = 'open_cases' then
    with selected as (
      select
        c.id as case_id,
        c.case_number,
        c.status,
        c.execution_mode,
        c.opened_at,
        t.id as taxpayer_id,
        t.legal_name,
        case
          when t.tax_id is null then null
          else left(
            regexp_replace(t.tax_id, '[^0-9]', '', 'g'),
            2
          ) || '********' || right(
            regexp_replace(t.tax_id, '[^0-9]', '', 'g'),
            4
          )
        end as masked_tax_id,
        d.divergence_type,
        d.difference_amount,
        (
          select count(*)::integer
          from public.case_findings cf
          where cf.municipality_id = c.municipality_id
            and cf.case_id = c.id
        ) as immutable_finding_count
      from public.fiscal_cases c
      join public.taxpayers t
        on t.municipality_id = c.municipality_id
       and t.id = c.taxpayer_id
      join public.divergences d
        on d.municipality_id = c.municipality_id
       and d.id = c.divergence_id
      where c.municipality_id = p_municipality_id
        and c.status not in ('closed', 'cancelled')
      order by c.opened_at desc
      limit v_limit offset v_offset
    )
    select
      coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb),
      count(*)::integer
    into v_rows, v_count
    from selected s;

    v_quality := jsonb_build_object(
      'cases_without_findings', (
        select count(*)
        from public.fiscal_cases c
        where c.municipality_id = p_municipality_id
          and c.status not in ('closed', 'cancelled')
          and not exists (
            select 1
            from public.case_findings cf
            where cf.municipality_id = c.municipality_id
              and cf.case_id = c.id
          )
      )
    );

  elsif v_intent = 'taxpayer_lookup' then
    with selected as (
      select
        t.id as taxpayer_id,
        t.legal_name,
        t.trade_name,
        t.municipal_registration,
        t.status,
        case
          when t.tax_id is null then null
          else left(
            regexp_replace(t.tax_id, '[^0-9]', '', 'g'),
            2
          ) || '********' || right(
            regexp_replace(t.tax_id, '[^0-9]', '', 'g'),
            4
          )
        end as masked_tax_id,
        coalesce(resp.responsibilities, '[]'::jsonb)
          as responsibilities
      from public.taxpayers t
      left join lateral (
        select jsonb_agg(
          jsonb_build_object(
            'responsible_name', r.responsible_name,
            'masked_document', r.masked_document,
            'masked_email', r.masked_email,
            'link_status', r.link_status,
            'contact_status', r.contact_status,
            'quarantine_reason', coalesce(
              r.link_quarantine_reason,
              r.contact_quarantine_reason
            ),
            'safe_for_delivery', r.safe_for_delivery
          )
          order by r.safe_for_delivery desc, r.responsible_name
        ) as responsibilities
        from public.vw_taxpayer_responsibilities_visible r
        where r.municipality_id = t.municipality_id
          and r.taxpayer_id = t.id
      ) resp on true
      where t.municipality_id = p_municipality_id
        and (
          (
            char_length(v_document) in (11, 14)
            and regexp_replace(t.tax_id, '[^0-9]', '', 'g') = v_document
          )
          or (
            char_length(v_document) not in (11, 14)
            and (
              private.normalize_fiscal_search(t.legal_name)
                like '%' || v_normalized || '%'
              or private.normalize_fiscal_search(
                coalesce(t.trade_name, '')
              ) like '%' || v_normalized || '%'
            )
          )
        )
      order by t.legal_name
      limit v_limit offset v_offset
    )
    select
      coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb),
      count(*)::integer
    into v_rows, v_count
    from selected s;

    v_quality := jsonb_build_object(
      'identifiers_masked', true,
      'quarantined_responsibilities_visible', true,
      'quarantined_responsibilities_safe_for_delivery', false
    );
  end if;

  v_execution_ms := greatest(
    0,
    round(
      extract(epoch from (clock_timestamp() - v_started_at))
      * 1000
    )::integer
  );

  insert into public.fiscal_search_requests (
    id,
    municipality_id,
    requested_by,
    raw_query,
    normalized_query,
    intent,
    parsed_filters,
    execution_plan,
    status,
    result_count,
    execution_ms,
    request_sha256
  ) values (
    v_request_id,
    p_municipality_id,
    v_user_id,
    p_query,
    v_normalized,
    v_intent,
    v_filters,
    v_plan,
    case
      when v_intent = 'unsupported' then 'unsupported'
      else 'completed'
    end,
    v_count,
    v_execution_ms,
    encode(
      extensions.digest(
        jsonb_build_object(
          'municipality_id', p_municipality_id,
          'requested_by', v_user_id,
          'query', v_normalized,
          'filters', v_filters
        )::text,
        'sha256'
      ),
      'hex'
    )
  );

  return jsonb_build_object(
    'request_id', v_request_id,
    'intent', v_intent,
    'understood_as', case v_intent
      when 'largest_debtors'
        then 'Rank eligible mature debtors and attach current responsibility links.'
      when 'taxpayer_lookup'
        then 'Find a taxpayer and show masked, quality-labelled responsibility links.'
      when 'fiscal_divergences'
        then 'List typed fiscal divergences with rule and evidence status.'
      when 'open_cases'
        then 'List open fiscal cases and immutable finding coverage.'
      else 'The request did not match a supported fiscal search intent.'
    end,
    'filters', v_filters,
    'plan', v_plan,
    'rows', v_rows,
    'result_count', v_count,
    'data_quality', v_quality,
    'execution_ms', v_execution_ms,
    'external_actions_performed', false
  );
end;
$function$;

revoke all on function public.ia_search_fiscal(
  uuid, text, integer, integer
) from public, anon;
grant execute on function public.ia_search_fiscal(
  uuid, text, integer, integer
) to authenticated, service_role;

comment on table public.fiscal_search_requests is
  'Auditable natural-language search requests compiled only to whitelisted deterministic query plans.';

comment on function public.ia_search_fiscal(
  uuid, text, integer, integer
) is
  'Safe fiscal search compiler: no dynamic SQL, no arbitrary model-generated filters and no external actions.';

