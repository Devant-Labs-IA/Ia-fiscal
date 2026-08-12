-- RLS decides which municipal rows can be maintained; table privileges enable
-- the authenticated client to reach those policies.
grant insert, update on table public.taxpayers to authenticated;