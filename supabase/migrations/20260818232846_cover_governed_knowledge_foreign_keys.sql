create index if not exists legal_source_artifact_versions_source_version_idx
  on private.legal_source_artifact_versions (municipality_id, source_version_id);

create index if not exists legal_source_artifacts_endpoint_idx
  on private.legal_source_artifacts (municipality_id, endpoint_id);

create index if not exists legal_source_artifacts_fetch_run_idx
  on private.legal_source_artifacts (municipality_id, fetch_run_id);

create index if not exists legal_source_change_sets_from_artifact_idx
  on private.legal_source_change_sets (municipality_id, from_artifact_id);

create index if not exists legal_source_change_sets_reviewer_idx
  on private.legal_source_change_sets (municipality_id, reviewer_membership_id);

create index if not exists legal_source_change_sets_source_idx
  on private.legal_source_change_sets (municipality_id, source_id);

create index if not exists legal_source_fetch_runs_endpoint_idx
  on private.legal_source_fetch_runs (municipality_id, endpoint_id);

create index if not exists legal_source_version_reviews_membership_idx
  on private.legal_source_version_reviews (municipality_id, reviewer_membership_id);

create index if not exists legal_source_version_reviews_change_set_idx
  on private.legal_source_version_reviews (municipality_id, change_set_id);
