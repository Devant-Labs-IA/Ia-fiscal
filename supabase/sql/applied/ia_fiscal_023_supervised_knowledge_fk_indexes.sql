-- Cover foreign-key access paths introduced by the supervised knowledge/chat module.

create index if not exists municipality_portal_settings_updated_by_idx
  on public.municipality_portal_settings(updated_by);

create index if not exists case_explanations_prepared_by_idx
  on public.case_explanations(prepared_by);
create index if not exists case_explanations_review_membership_idx
  on public.case_explanations(municipality_id, reviewed_by_membership_id);

create index if not exists case_messages_source_knowledge_revision_idx
  on public.case_messages(municipality_id, source_knowledge_revision_id);

create index if not exists fiscal_chat_inbox_assignment_idx
  on public.fiscal_chat_inbox(municipality_id, assigned_membership_id);
create index if not exists fiscal_chat_inbox_case_idx
  on public.fiscal_chat_inbox(municipality_id, case_id);
create index if not exists fiscal_chat_inbox_taxpayer_idx
  on public.fiscal_chat_inbox(municipality_id, taxpayer_id);

create index if not exists knowledge_articles_created_by_idx
  on public.knowledge_articles(created_by);
create index if not exists knowledge_articles_source_question_idx
  on public.knowledge_articles(municipality_id, source_question_id);

create index if not exists knowledge_article_revisions_created_by_idx
  on public.knowledge_article_revisions(created_by);
create index if not exists knowledge_article_revisions_source_draft_idx
  on public.knowledge_article_revisions(municipality_id, source_draft_revision_id);
create index if not exists knowledge_article_revisions_source_message_idx
  on public.knowledge_article_revisions(municipality_id, source_message_id);

create index if not exists knowledge_article_patterns_article_idx
  on public.knowledge_article_patterns(municipality_id, article_id);

create index if not exists knowledge_article_citations_section_idx
  on public.knowledge_article_citations(municipality_id, legal_section_id);
create index if not exists knowledge_article_citations_source_version_idx
  on public.knowledge_article_citations(municipality_id, source_version_id);

create index if not exists knowledge_article_reviews_article_idx
  on public.knowledge_article_reviews(municipality_id, article_id);
create index if not exists knowledge_article_reviews_membership_idx
  on public.knowledge_article_reviews(municipality_id, reviewer_membership_id);
