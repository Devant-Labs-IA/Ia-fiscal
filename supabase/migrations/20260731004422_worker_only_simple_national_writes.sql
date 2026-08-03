revoke execute on function public.ia_rebuild_simple_national_snapshots(
  uuid, date, date, boolean
) from authenticated;

revoke execute on function public.ia_run_simple_national_detection(
  uuid, uuid, timestamptz, text, uuid, boolean
) from authenticated;

grant execute on function public.ia_rebuild_simple_national_snapshots(
  uuid, date, date, boolean
) to service_role;

grant execute on function public.ia_run_simple_national_detection(
  uuid, uuid, timestamptz, text, uuid, boolean
) to service_role;

