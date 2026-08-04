export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      accountant_user_links: {
        Row: {
          access_role: string
          accounting_firm_id: string
          created_at: string
          id: string
          municipality_id: string
          status: string
          updated_at: string
          user_id: string
          valid_from: string
          valid_until: string | null
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          access_role: string
          accounting_firm_id: string
          created_at?: string
          id?: string
          municipality_id: string
          status?: string
          updated_at?: string
          user_id: string
          valid_from?: string
          valid_until?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          access_role?: string
          accounting_firm_id?: string
          created_at?: string
          id?: string
          municipality_id?: string
          status?: string
          updated_at?: string
          user_id?: string
          valid_from?: string
          valid_until?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "accountant_user_links_firm_fk"
            columns: ["municipality_id", "accounting_firm_id"]
            isOneToOne: false
            referencedRelation: "accounting_firms"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      accounting_firms: {
        Row: {
          created_at: string
          id: string
          legal_name: string
          municipality_id: string
          registration_code: string | null
          source_key: string | null
          status: string
          tax_id: string | null
          trade_name: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          legal_name: string
          municipality_id: string
          registration_code?: string | null
          source_key?: string | null
          status?: string
          tax_id?: string | null
          trade_name?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          legal_name?: string
          municipality_id?: string
          registration_code?: string | null
          source_key?: string | null
          status?: string
          tax_id?: string | null
          trade_name?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "accounting_firms_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_draft_citations: {
        Row: {
          citation_label: string
          created_at: string
          draft_revision_id: string
          id: string
          legal_section_id: string
          municipality_id: string
          quoted_excerpt: string
          source_sha256: string
          source_version_id: string
        }
        Insert: {
          citation_label: string
          created_at?: string
          draft_revision_id: string
          id?: string
          legal_section_id: string
          municipality_id: string
          quoted_excerpt: string
          source_sha256: string
          source_version_id: string
        }
        Update: {
          citation_label?: string
          created_at?: string
          draft_revision_id?: string
          id?: string
          legal_section_id?: string
          municipality_id?: string
          quoted_excerpt?: string
          source_sha256?: string
          source_version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_draft_citations_revision_fk"
            columns: ["municipality_id", "draft_revision_id"]
            isOneToOne: false
            referencedRelation: "ai_draft_revisions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "ai_draft_citations_section_fk"
            columns: ["municipality_id", "legal_section_id"]
            isOneToOne: false
            referencedRelation: "legal_sections"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "ai_draft_citations_version_fk"
            columns: ["municipality_id", "source_version_id"]
            isOneToOne: false
            referencedRelation: "legal_source_versions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      ai_draft_revisions: {
        Row: {
          body: string
          content_sha256: string
          created_at: string
          created_by: string | null
          draft_id: string
          id: string
          municipality_id: string
          revision_number: number
          revision_type: string
        }
        Insert: {
          body: string
          content_sha256: string
          created_at?: string
          created_by?: string | null
          draft_id: string
          id?: string
          municipality_id: string
          revision_number: number
          revision_type: string
        }
        Update: {
          body?: string
          content_sha256?: string
          created_at?: string
          created_by?: string | null
          draft_id?: string
          id?: string
          municipality_id?: string
          revision_number?: number
          revision_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_draft_revisions_draft_fk"
            columns: ["municipality_id", "draft_id"]
            isOneToOne: false
            referencedRelation: "ai_drafts"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "ai_draft_revisions_draft_fk"
            columns: ["municipality_id", "draft_id"]
            isOneToOne: false
            referencedRelation: "api_ai_review_queue"
            referencedColumns: ["municipality_id", "draft_id"]
          },
        ]
      }
      ai_drafts: {
        Row: {
          ai_run_id: string
          case_id: string
          created_at: string
          current_revision_number: number
          id: string
          limitation_summary: string | null
          municipality_id: string
          question_id: string
          requires_human_attention: boolean
          status: string
          updated_at: string
        }
        Insert: {
          ai_run_id: string
          case_id: string
          created_at?: string
          current_revision_number?: number
          id?: string
          limitation_summary?: string | null
          municipality_id: string
          question_id: string
          requires_human_attention?: boolean
          status?: string
          updated_at?: string
        }
        Update: {
          ai_run_id?: string
          case_id?: string
          created_at?: string
          current_revision_number?: number
          id?: string
          limitation_summary?: string | null
          municipality_id?: string
          question_id?: string
          requires_human_attention?: boolean
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      ai_prompt_templates: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          municipality_id: string
          name: string
          purpose: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id: string
          name: string
          purpose: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id?: string
          name?: string
          purpose?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_prompt_templates_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_prompt_versions: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          content_sha256: string
          created_at: string
          created_by: string | null
          id: string
          municipality_id: string
          output_schema: Json
          prompt_template_id: string
          status: string
          system_prompt: string
          updated_at: string
          version: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          content_sha256: string
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id: string
          output_schema: Json
          prompt_template_id: string
          status?: string
          system_prompt: string
          updated_at?: string
          version: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          content_sha256?: string
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id?: string
          output_schema?: Json
          prompt_template_id?: string
          status?: string
          system_prompt?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "ai_prompt_versions_template_fk"
            columns: ["municipality_id", "prompt_template_id"]
            isOneToOne: false
            referencedRelation: "ai_prompt_templates"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      backend_validation_results: {
        Row: {
          area: string
          created_at: string
          evidence: Json
          id: number
          municipality_id: string
          run_id: string
          status: string
          summary: string
          test_code: string
        }
        Insert: {
          area: string
          created_at?: string
          evidence?: Json
          id?: never
          municipality_id: string
          run_id: string
          status: string
          summary: string
          test_code: string
        }
        Update: {
          area?: string
          created_at?: string
          evidence?: Json
          id?: never
          municipality_id?: string
          run_id?: string
          status?: string
          summary?: string
          test_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "backend_validation_results_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "backend_validation_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "backend_validation_results_run_tenant_fk"
            columns: ["municipality_id", "run_id"]
            isOneToOne: false
            referencedRelation: "backend_validation_runs"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      backend_validation_runs: {
        Row: {
          blocked_count: number
          created_by: string | null
          failed_count: number
          finished_at: string | null
          id: string
          municipality_id: string
          passed_count: number
          result_sha256: string | null
          started_at: string
          status: string
          suite_version: string
          warning_count: number
        }
        Insert: {
          blocked_count?: number
          created_by?: string | null
          failed_count?: number
          finished_at?: string | null
          id?: string
          municipality_id: string
          passed_count?: number
          result_sha256?: string | null
          started_at?: string
          status: string
          suite_version: string
          warning_count?: number
        }
        Update: {
          blocked_count?: number
          created_by?: string | null
          failed_count?: number
          finished_at?: string | null
          id?: string
          municipality_id?: string
          passed_count?: number
          result_sha256?: string | null
          started_at?: string
          status?: string
          suite_version?: string
          warning_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "backend_validation_runs_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      case_assignments: {
        Row: {
          assigned_at: string
          assigned_by: string | null
          assignment_role: string
          case_id: string
          completed_at: string | null
          created_at: string
          id: string
          membership_id: string
          municipality_id: string
          status: string
          updated_at: string
        }
        Insert: {
          assigned_at?: string
          assigned_by?: string | null
          assignment_role: string
          case_id: string
          completed_at?: string | null
          created_at?: string
          id?: string
          membership_id: string
          municipality_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          assigned_at?: string
          assigned_by?: string | null
          assignment_role?: string
          case_id?: string
          completed_at?: string | null
          created_at?: string
          id?: string
          membership_id?: string
          municipality_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "case_assignments_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_assignments_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_assignments_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_assignments_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_assignments_membership_fk"
            columns: ["municipality_id", "membership_id"]
            isOneToOne: false
            referencedRelation: "municipality_memberships"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      case_documents: {
        Row: {
          case_id: string
          created_at: string
          id: string
          malware_scan_status: string
          media_type: string
          municipality_id: string
          original_file_name: string
          sha256: string
          size_bytes: number
          status: string
          storage_bucket: string
          storage_path: string
          uploaded_by: string | null
        }
        Insert: {
          case_id: string
          created_at?: string
          id?: string
          malware_scan_status?: string
          media_type: string
          municipality_id: string
          original_file_name: string
          sha256: string
          size_bytes: number
          status?: string
          storage_bucket: string
          storage_path: string
          uploaded_by?: string | null
        }
        Update: {
          case_id?: string
          created_at?: string
          id?: string
          malware_scan_status?: string
          media_type?: string
          municipality_id?: string
          original_file_name?: string
          sha256?: string
          size_bytes?: number
          status?: string
          storage_bucket?: string
          storage_path?: string
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "case_documents_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_documents_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_documents_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_documents_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
        ]
      }
      case_events: {
        Row: {
          actor_type: string
          actor_user_id: string | null
          case_id: string
          correlation_id: string
          event_data: Json
          event_type: string
          id: number
          municipality_id: string
          occurred_at: string
          visibility: string
        }
        Insert: {
          actor_type: string
          actor_user_id?: string | null
          case_id: string
          correlation_id?: string
          event_data?: Json
          event_type: string
          id?: never
          municipality_id: string
          occurred_at?: string
          visibility?: string
        }
        Update: {
          actor_type?: string
          actor_user_id?: string | null
          case_id?: string
          correlation_id?: string
          event_data?: Json
          event_type?: string
          id?: never
          municipality_id?: string
          occurred_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "case_events_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_events_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_events_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_events_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
        ]
      }
      case_explanations: {
        Row: {
          case_id: string
          citations_snapshot: Json
          content_sha256: string
          created_at: string
          divergence_summary: Json
          explanation_version: number
          id: string
          is_current: boolean
          legal_basis_summary: string
          legal_review_required: boolean
          municipality_id: string
          official_system_url: string
          portal_path: string
          prepared_at: string
          prepared_by: string | null
          reviewed_at: string | null
          reviewed_by_membership_id: string | null
          status: string
          summary: string
          title: string
        }
        Insert: {
          case_id: string
          citations_snapshot?: Json
          content_sha256: string
          created_at?: string
          divergence_summary?: Json
          explanation_version: number
          id?: string
          is_current?: boolean
          legal_basis_summary: string
          legal_review_required?: boolean
          municipality_id: string
          official_system_url: string
          portal_path: string
          prepared_at?: string
          prepared_by?: string | null
          reviewed_at?: string | null
          reviewed_by_membership_id?: string | null
          status?: string
          summary: string
          title: string
        }
        Update: {
          case_id?: string
          citations_snapshot?: Json
          content_sha256?: string
          created_at?: string
          divergence_summary?: Json
          explanation_version?: number
          id?: string
          is_current?: boolean
          legal_basis_summary?: string
          legal_review_required?: boolean
          municipality_id?: string
          official_system_url?: string
          portal_path?: string
          prepared_at?: string
          prepared_by?: string | null
          reviewed_at?: string | null
          reviewed_by_membership_id?: string | null
          status?: string
          summary?: string
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "case_explanations_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_explanations_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_explanations_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_explanations_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_explanations_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "case_explanations_review_membership_fk"
            columns: ["municipality_id", "reviewed_by_membership_id"]
            isOneToOne: false
            referencedRelation: "municipality_memberships"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      case_findings: {
        Row: {
          assessed_amount: number
          case_id: string
          content_sha256: string
          created_at: string
          difference_amount: number
          divergence_id: string
          finding_snapshot: Json
          id: string
          municipality_id: string
          other_credits_amount: number
          paid_amount: number
          period_end: string
          period_start: string
          revalidation_id: string
          rule_version_id: string
        }
        Insert: {
          assessed_amount: number
          case_id: string
          content_sha256: string
          created_at?: string
          difference_amount: number
          divergence_id: string
          finding_snapshot: Json
          id?: string
          municipality_id: string
          other_credits_amount: number
          paid_amount: number
          period_end: string
          period_start: string
          revalidation_id: string
          rule_version_id: string
        }
        Update: {
          assessed_amount?: number
          case_id?: string
          content_sha256?: string
          created_at?: string
          difference_amount?: number
          divergence_id?: string
          finding_snapshot?: Json
          id?: string
          municipality_id?: string
          other_credits_amount?: number
          paid_amount?: number
          period_end?: string
          period_start?: string
          revalidation_id?: string
          rule_version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "case_findings_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: true
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_findings_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: true
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_findings_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: true
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_findings_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: true
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_findings_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "api_divergence_queue"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_findings_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "divergences"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_findings_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "vw_fiscal_divergence_search"
            referencedColumns: ["municipality_id", "divergence_id"]
          },
          {
            foreignKeyName: "case_findings_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_divergences"
            referencedColumns: ["municipality_id", "divergence_id"]
          },
          {
            foreignKeyName: "case_findings_revalidation_fk"
            columns: ["municipality_id", "revalidation_id"]
            isOneToOne: false
            referencedRelation: "divergence_revalidations"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_findings_rule_fk"
            columns: ["municipality_id", "rule_version_id"]
            isOneToOne: false
            referencedRelation: "divergence_rule_versions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      case_messages: {
        Row: {
          author_user_id: string | null
          body: string
          case_id: string
          client_request_id: string | null
          content_sha256: string
          created_at: string
          id: string
          municipality_id: string
          parent_message_id: string | null
          published_at: string | null
          read_at: string | null
          sender_type: string
          source_draft_revision_id: string | null
          source_knowledge_revision_id: string | null
          source_type: string
          status: string
          thread_id: string
          updated_at: string
          visibility: string
        }
        Insert: {
          author_user_id?: string | null
          body: string
          case_id: string
          client_request_id?: string | null
          content_sha256: string
          created_at?: string
          id?: string
          municipality_id: string
          parent_message_id?: string | null
          published_at?: string | null
          read_at?: string | null
          sender_type: string
          source_draft_revision_id?: string | null
          source_knowledge_revision_id?: string | null
          source_type?: string
          status?: string
          thread_id: string
          updated_at?: string
          visibility?: string
        }
        Update: {
          author_user_id?: string | null
          body?: string
          case_id?: string
          client_request_id?: string | null
          content_sha256?: string
          created_at?: string
          id?: string
          municipality_id?: string
          parent_message_id?: string | null
          published_at?: string | null
          read_at?: string | null
          sender_type?: string
          source_draft_revision_id?: string | null
          source_knowledge_revision_id?: string | null
          source_type?: string
          status?: string
          thread_id?: string
          updated_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "case_messages_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_messages_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_messages_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_messages_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_messages_parent_fk"
            columns: ["municipality_id", "parent_message_id"]
            isOneToOne: false
            referencedRelation: "case_messages"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_messages_source_knowledge_revision_fk"
            columns: ["municipality_id", "source_knowledge_revision_id"]
            isOneToOne: false
            referencedRelation: "knowledge_article_revisions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_messages_source_revision_fk"
            columns: ["municipality_id", "source_draft_revision_id"]
            isOneToOne: false
            referencedRelation: "ai_draft_revisions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_messages_thread_case_fk"
            columns: ["municipality_id", "thread_id", "case_id"]
            isOneToOne: false
            referencedRelation: "case_threads"
            referencedColumns: ["municipality_id", "id", "case_id"]
          },
          {
            foreignKeyName: "case_messages_thread_fk"
            columns: ["municipality_id", "thread_id"]
            isOneToOne: false
            referencedRelation: "case_threads"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      case_opening_batch_items: {
        Row: {
          assigned_membership_id: string | null
          batch_id: string
          created_at: string
          divergence_id: string
          exclusion_reason: string | null
          id: string
          last_error_code: string | null
          municipality_id: string
          processed_at: string | null
          selection_rank: number | null
          status: string
          updated_at: string
        }
        Insert: {
          assigned_membership_id?: string | null
          batch_id: string
          created_at?: string
          divergence_id: string
          exclusion_reason?: string | null
          id?: string
          last_error_code?: string | null
          municipality_id: string
          processed_at?: string | null
          selection_rank?: number | null
          status?: string
          updated_at?: string
        }
        Update: {
          assigned_membership_id?: string | null
          batch_id?: string
          created_at?: string
          divergence_id?: string
          exclusion_reason?: string | null
          id?: string
          last_error_code?: string | null
          municipality_id?: string
          processed_at?: string | null
          selection_rank?: number | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "case_opening_batch_items_assignment_fk"
            columns: ["municipality_id", "assigned_membership_id"]
            isOneToOne: false
            referencedRelation: "municipality_memberships"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_opening_batch_items_batch_fk"
            columns: ["municipality_id", "batch_id"]
            isOneToOne: false
            referencedRelation: "case_opening_batches"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_opening_batch_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "api_divergence_queue"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_opening_batch_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "divergences"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_opening_batch_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "vw_fiscal_divergence_search"
            referencedColumns: ["municipality_id", "divergence_id"]
          },
          {
            foreignKeyName: "case_opening_batch_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_divergences"
            referencedColumns: ["municipality_id", "divergence_id"]
          },
        ]
      }
      case_opening_batches: {
        Row: {
          approval_notes: string | null
          approved_at: string | null
          approved_by: string | null
          approved_count: number
          approved_system_actor: string | null
          blocked_count: number
          created_at: string
          detection_run_id: string
          execution_mode: string
          id: string
          idempotency_key: string
          municipality_id: string
          opened_count: number
          policy_version_id: string
          request_sha256: string | null
          requested_count: number
          status: string
          submitted_at: string | null
          submitted_by: string | null
          updated_at: string
        }
        Insert: {
          approval_notes?: string | null
          approved_at?: string | null
          approved_by?: string | null
          approved_count?: number
          approved_system_actor?: string | null
          blocked_count?: number
          created_at?: string
          detection_run_id: string
          execution_mode?: string
          id?: string
          idempotency_key: string
          municipality_id: string
          opened_count?: number
          policy_version_id: string
          request_sha256?: string | null
          requested_count?: number
          status?: string
          submitted_at?: string | null
          submitted_by?: string | null
          updated_at?: string
        }
        Update: {
          approval_notes?: string | null
          approved_at?: string | null
          approved_by?: string | null
          approved_count?: number
          approved_system_actor?: string | null
          blocked_count?: number
          created_at?: string
          detection_run_id?: string
          execution_mode?: string
          id?: string
          idempotency_key?: string
          municipality_id?: string
          opened_count?: number
          policy_version_id?: string
          request_sha256?: string | null
          requested_count?: number
          status?: string
          submitted_at?: string | null
          submitted_by?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "case_opening_batches_policy_fk"
            columns: ["municipality_id", "policy_version_id"]
            isOneToOne: false
            referencedRelation: "municipality_policy_versions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_opening_batches_run_fk"
            columns: ["municipality_id", "detection_run_id"]
            isOneToOne: false
            referencedRelation: "detection_runs"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      case_questions: {
        Row: {
          answered_at: string | null
          assigned_membership_id: string | null
          case_id: string
          claimed_at: string | null
          created_at: string
          handling_mode: string
          id: string
          last_activity_at: string
          message_id: string
          municipality_id: string
          routing_confidence: number | null
          routing_reason: string | null
          sla_due_at: string | null
          status: string
          submitted_at: string
          updated_at: string
        }
        Insert: {
          answered_at?: string | null
          assigned_membership_id?: string | null
          case_id: string
          claimed_at?: string | null
          created_at?: string
          handling_mode?: string
          id?: string
          last_activity_at?: string
          message_id: string
          municipality_id: string
          routing_confidence?: number | null
          routing_reason?: string | null
          sla_due_at?: string | null
          status?: string
          submitted_at?: string
          updated_at?: string
        }
        Update: {
          answered_at?: string | null
          assigned_membership_id?: string | null
          case_id?: string
          claimed_at?: string | null
          created_at?: string
          handling_mode?: string
          id?: string
          last_activity_at?: string
          message_id?: string
          municipality_id?: string
          routing_confidence?: number | null
          routing_reason?: string | null
          sla_due_at?: string | null
          status?: string
          submitted_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "case_questions_assignment_fk"
            columns: ["municipality_id", "assigned_membership_id"]
            isOneToOne: false
            referencedRelation: "municipality_memberships"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_questions_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_questions_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_questions_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_questions_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_questions_message_case_fk"
            columns: ["municipality_id", "message_id", "case_id"]
            isOneToOne: false
            referencedRelation: "case_messages"
            referencedColumns: ["municipality_id", "id", "case_id"]
          },
          {
            foreignKeyName: "case_questions_message_fk"
            columns: ["municipality_id", "message_id"]
            isOneToOne: true
            referencedRelation: "case_messages"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      case_threads: {
        Row: {
          case_id: string
          created_at: string
          id: string
          municipality_id: string
          status: string
          updated_at: string
        }
        Insert: {
          case_id: string
          created_at?: string
          id?: string
          municipality_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          case_id?: string
          created_at?: string
          id?: string
          municipality_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "case_threads_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: true
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_threads_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: true
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_threads_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: true
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_threads_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: true
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
        ]
      }
      current_account_entries: {
        Row: {
          amount: number
          competence_month: string
          created_at: string
          direction: string
          document_reference: string | null
          due_date_evidence: Json
          due_date_rule_version_id: string | null
          due_date_status: string
          due_on: string | null
          entry_kind: string
          external_record_id: string
          id: string
          import_batch_id: string | null
          imported_at: string
          municipality_id: string
          nominal_due_on: string | null
          occurred_on: string
          payload_sha256: string | null
          source_snapshot: Json
          source_system_id: string
          status: string
          tax_code: string | null
          taxpayer_id: string
          updated_at: string
        }
        Insert: {
          amount: number
          competence_month: string
          created_at?: string
          direction: string
          document_reference?: string | null
          due_date_evidence?: Json
          due_date_rule_version_id?: string | null
          due_date_status?: string
          due_on?: string | null
          entry_kind: string
          external_record_id: string
          id?: string
          import_batch_id?: string | null
          imported_at?: string
          municipality_id: string
          nominal_due_on?: string | null
          occurred_on: string
          payload_sha256?: string | null
          source_snapshot?: Json
          source_system_id: string
          status?: string
          tax_code?: string | null
          taxpayer_id: string
          updated_at?: string
        }
        Update: {
          amount?: number
          competence_month?: string
          created_at?: string
          direction?: string
          document_reference?: string | null
          due_date_evidence?: Json
          due_date_rule_version_id?: string | null
          due_date_status?: string
          due_on?: string | null
          entry_kind?: string
          external_record_id?: string
          id?: string
          import_batch_id?: string | null
          imported_at?: string
          municipality_id?: string
          nominal_due_on?: string | null
          occurred_on?: string
          payload_sha256?: string | null
          source_snapshot?: Json
          source_system_id?: string
          status?: string
          tax_code?: string | null
          taxpayer_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "current_account_entries_batch_fk"
            columns: ["municipality_id", "import_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "current_account_entries_due_date_rule_fk"
            columns: ["municipality_id", "due_date_rule_version_id"]
            isOneToOne: false
            referencedRelation: "due_date_rule_versions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "current_account_entries_source_fk"
            columns: ["municipality_id", "source_system_id"]
            isOneToOne: false
            referencedRelation: "source_systems"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "current_account_entries_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "current_account_entries_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "current_account_entries_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      current_account_maturity_classifications: {
        Row: {
          classification_source: string
          classification_status: string
          created_at: string
          current_account_entry_id: string
          evidence_sha256: string
          evidence_snapshot: Json
          exception_assessment: Json
          id: string
          maturity_class: string
          municipality_id: string
          version: number
        }
        Insert: {
          classification_source: string
          classification_status: string
          created_at?: string
          current_account_entry_id: string
          evidence_sha256: string
          evidence_snapshot: Json
          exception_assessment: Json
          id?: string
          maturity_class: string
          municipality_id: string
          version: number
        }
        Update: {
          classification_source?: string
          classification_status?: string
          created_at?: string
          current_account_entry_id?: string
          evidence_sha256?: string
          evidence_snapshot?: Json
          exception_assessment?: Json
          id?: string
          maturity_class?: string
          municipality_id?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "current_account_maturity_clas_municipality_id_current_acco_fkey"
            columns: ["municipality_id", "current_account_entry_id"]
            isOneToOne: false
            referencedRelation: "current_account_entries"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "current_account_maturity_classifications_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      detection_runs: {
        Row: {
          as_of: string
          blocked_count: number
          candidate_count: number
          created_at: string
          divergence_count: number
          error_code: string | null
          error_detail: string | null
          execution_mode: string
          finished_at: string | null
          id: string
          idempotency_key: string
          import_batch_id: string | null
          municipality_id: string
          period_end: string
          period_start: string
          rule_version_id: string
          started_at: string | null
          started_by: string | null
          status: string
          updated_at: string
        }
        Insert: {
          as_of: string
          blocked_count?: number
          candidate_count?: number
          created_at?: string
          divergence_count?: number
          error_code?: string | null
          error_detail?: string | null
          execution_mode?: string
          finished_at?: string | null
          id?: string
          idempotency_key: string
          import_batch_id?: string | null
          municipality_id: string
          period_end: string
          period_start: string
          rule_version_id: string
          started_at?: string | null
          started_by?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          as_of?: string
          blocked_count?: number
          candidate_count?: number
          created_at?: string
          divergence_count?: number
          error_code?: string | null
          error_detail?: string | null
          execution_mode?: string
          finished_at?: string | null
          id?: string
          idempotency_key?: string
          import_batch_id?: string | null
          municipality_id?: string
          period_end?: string
          period_start?: string
          rule_version_id?: string
          started_at?: string | null
          started_by?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "detection_runs_batch_fk"
            columns: ["municipality_id", "import_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "detection_runs_rule_fk"
            columns: ["municipality_id", "rule_version_id"]
            isOneToOne: false
            referencedRelation: "divergence_rule_versions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      divergence_items: {
        Row: {
          amount_snapshot: number
          competence_month: string
          created_at: string
          current_account_entry_id: string
          direction: string
          divergence_id: string
          entry_kind: string
          id: number
          municipality_id: string
          source_sha256: string | null
        }
        Insert: {
          amount_snapshot: number
          competence_month: string
          created_at?: string
          current_account_entry_id: string
          direction: string
          divergence_id: string
          entry_kind: string
          id?: never
          municipality_id: string
          source_sha256?: string | null
        }
        Update: {
          amount_snapshot?: number
          competence_month?: string
          created_at?: string
          current_account_entry_id?: string
          direction?: string
          divergence_id?: string
          entry_kind?: string
          id?: never
          municipality_id?: string
          source_sha256?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "divergence_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "api_divergence_queue"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergence_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "divergences"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergence_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "vw_fiscal_divergence_search"
            referencedColumns: ["municipality_id", "divergence_id"]
          },
          {
            foreignKeyName: "divergence_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_divergences"
            referencedColumns: ["municipality_id", "divergence_id"]
          },
          {
            foreignKeyName: "divergence_items_entry_fk"
            columns: ["municipality_id", "current_account_entry_id"]
            isOneToOne: false
            referencedRelation: "current_account_entries"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      divergence_revalidations: {
        Row: {
          assessed_amount: number
          block_reasons: Json
          difference_amount: number
          divergence_id: string
          eligible: boolean
          id: string
          municipality_id: string
          other_credits_amount: number
          paid_amount: number
          performed_at: string
          performed_by: string | null
          revalidation_number: number
          snapshot_sha256: string
          source_snapshot: Json
        }
        Insert: {
          assessed_amount: number
          block_reasons?: Json
          difference_amount: number
          divergence_id: string
          eligible: boolean
          id?: string
          municipality_id: string
          other_credits_amount: number
          paid_amount: number
          performed_at?: string
          performed_by?: string | null
          revalidation_number: number
          snapshot_sha256: string
          source_snapshot: Json
        }
        Update: {
          assessed_amount?: number
          block_reasons?: Json
          difference_amount?: number
          divergence_id?: string
          eligible?: boolean
          id?: string
          municipality_id?: string
          other_credits_amount?: number
          paid_amount?: number
          performed_at?: string
          performed_by?: string | null
          revalidation_number?: number
          snapshot_sha256?: string
          source_snapshot?: Json
        }
        Relationships: [
          {
            foreignKeyName: "divergence_revalidations_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "api_divergence_queue"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergence_revalidations_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "divergences"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergence_revalidations_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "vw_fiscal_divergence_search"
            referencedColumns: ["municipality_id", "divergence_id"]
          },
          {
            foreignKeyName: "divergence_revalidations_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_divergences"
            referencedColumns: ["municipality_id", "divergence_id"]
          },
        ]
      }
      divergence_rule_versions: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          checksum_sha256: string
          created_at: string
          created_by: string | null
          effective_from: string | null
          effective_until: string | null
          id: string
          implementation_key: string
          implementation_version: string
          municipality_id: string
          parameters: Json
          rule_id: string
          status: string
          updated_at: string
          version: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          checksum_sha256: string
          created_at?: string
          created_by?: string | null
          effective_from?: string | null
          effective_until?: string | null
          id?: string
          implementation_key: string
          implementation_version: string
          municipality_id: string
          parameters?: Json
          rule_id: string
          status?: string
          updated_at?: string
          version: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          checksum_sha256?: string
          created_at?: string
          created_by?: string | null
          effective_from?: string | null
          effective_until?: string | null
          id?: string
          implementation_key?: string
          implementation_version?: string
          municipality_id?: string
          parameters?: Json
          rule_id?: string
          status?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "divergence_rule_versions_rule_fk"
            columns: ["municipality_id", "rule_id"]
            isOneToOne: false
            referencedRelation: "divergence_rules"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      divergence_rules: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          description: string | null
          divergence_type: string
          id: string
          municipality_id: string
          name: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          divergence_type: string
          id?: string
          municipality_id: string
          name: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          divergence_type?: string
          id?: string
          municipality_id?: string
          name?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "divergence_rules_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      divergences: {
        Row: {
          as_of: string
          assessed_amount: number
          block_reasons: Json
          created_at: string
          detection_run_id: string
          difference_amount: number
          divergence_type: string
          execution_mode: string
          id: string
          last_revalidated_at: string | null
          municipality_id: string
          other_credits_amount: number
          paid_amount: number
          period_end: string
          period_start: string
          priority_score: number
          resolved_at: string | null
          resolved_reason: string | null
          rule_version_id: string
          snapshot_sha256: string
          source_snapshot: Json
          status: string
          taxpayer_id: string
          threshold_amount: number
          updated_at: string
        }
        Insert: {
          as_of: string
          assessed_amount?: number
          block_reasons?: Json
          created_at?: string
          detection_run_id: string
          difference_amount: number
          divergence_type: string
          execution_mode?: string
          id?: string
          last_revalidated_at?: string | null
          municipality_id: string
          other_credits_amount?: number
          paid_amount?: number
          period_end: string
          period_start: string
          priority_score?: number
          resolved_at?: string | null
          resolved_reason?: string | null
          rule_version_id: string
          snapshot_sha256: string
          source_snapshot: Json
          status?: string
          taxpayer_id: string
          threshold_amount: number
          updated_at?: string
        }
        Update: {
          as_of?: string
          assessed_amount?: number
          block_reasons?: Json
          created_at?: string
          detection_run_id?: string
          difference_amount?: number
          divergence_type?: string
          execution_mode?: string
          id?: string
          last_revalidated_at?: string | null
          municipality_id?: string
          other_credits_amount?: number
          paid_amount?: number
          period_end?: string
          period_start?: string
          priority_score?: number
          resolved_at?: string | null
          resolved_reason?: string | null
          rule_version_id?: string
          snapshot_sha256?: string
          source_snapshot?: Json
          status?: string
          taxpayer_id?: string
          threshold_amount?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "divergences_rule_fk"
            columns: ["municipality_id", "rule_version_id"]
            isOneToOne: false
            referencedRelation: "divergence_rule_versions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergences_run_fk"
            columns: ["municipality_id", "detection_run_id"]
            isOneToOne: false
            referencedRelation: "detection_runs"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      draft_reviews: {
        Row: {
          approved_content_sha256: string | null
          created_at: string
          decision: string
          draft_id: string
          draft_revision_id: string
          id: string
          municipality_id: string
          notes: string | null
          reviewed_at: string
          reviewer_membership_id: string
        }
        Insert: {
          approved_content_sha256?: string | null
          created_at?: string
          decision: string
          draft_id: string
          draft_revision_id: string
          id?: string
          municipality_id: string
          notes?: string | null
          reviewed_at?: string
          reviewer_membership_id: string
        }
        Update: {
          approved_content_sha256?: string | null
          created_at?: string
          decision?: string
          draft_id?: string
          draft_revision_id?: string
          id?: string
          municipality_id?: string
          notes?: string | null
          reviewed_at?: string
          reviewer_membership_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "draft_reviews_draft_fk"
            columns: ["municipality_id", "draft_id"]
            isOneToOne: false
            referencedRelation: "ai_drafts"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "draft_reviews_draft_fk"
            columns: ["municipality_id", "draft_id"]
            isOneToOne: false
            referencedRelation: "api_ai_review_queue"
            referencedColumns: ["municipality_id", "draft_id"]
          },
          {
            foreignKeyName: "draft_reviews_membership_fk"
            columns: ["municipality_id", "reviewer_membership_id"]
            isOneToOne: false
            referencedRelation: "municipality_memberships"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "draft_reviews_revision_fk"
            columns: ["municipality_id", "draft_revision_id"]
            isOneToOne: false
            referencedRelation: "ai_draft_revisions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      due_date_rule_versions: {
        Row: {
          business_day_adjustment: string
          code: string
          collection_regime: string
          competence_month_offset: number
          created_at: string
          due_day: number | null
          exception_policy: string
          id: string
          legal_source_version_id: string
          municipality_id: string
          rule_payload: Json
          rule_sha256: string
          status: string
          tax_code: string
          updated_at: string
          valid_from: string
          valid_until: string | null
          version: number
        }
        Insert: {
          business_day_adjustment: string
          code: string
          collection_regime: string
          competence_month_offset?: number
          created_at?: string
          due_day?: number | null
          exception_policy: string
          id?: string
          legal_source_version_id: string
          municipality_id: string
          rule_payload: Json
          rule_sha256: string
          status?: string
          tax_code: string
          updated_at?: string
          valid_from: string
          valid_until?: string | null
          version: number
        }
        Update: {
          business_day_adjustment?: string
          code?: string
          collection_regime?: string
          competence_month_offset?: number
          created_at?: string
          due_day?: number | null
          exception_policy?: string
          id?: string
          legal_source_version_id?: string
          municipality_id?: string
          rule_payload?: Json
          rule_sha256?: string
          status?: string
          tax_code?: string
          updated_at?: string
          valid_from?: string
          valid_until?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "due_date_rule_versions_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "due_date_rule_versions_municipality_id_legal_source_versio_fkey"
            columns: ["municipality_id", "legal_source_version_id"]
            isOneToOne: false
            referencedRelation: "legal_source_versions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      factor_r_payroll_periods: {
        Row: {
          competence_month: string
          created_at: string
          data_origin: string
          employee_remuneration: number
          employer_social_security: number
          external_record_id: string
          fgts: number
          fs_month: number | null
          id: string
          import_batch_id: string | null
          individual_contributors: number
          is_test: boolean
          municipality_id: string
          other_eligible_payroll: number
          payload_sha256: string | null
          pro_labore: number
          source_snapshot: Json
          source_system_id: string
          taxpayer_id: string
          thirteenth_salary: number
          updated_at: string
        }
        Insert: {
          competence_month: string
          created_at?: string
          data_origin?: string
          employee_remuneration?: number
          employer_social_security?: number
          external_record_id: string
          fgts?: number
          fs_month?: number | null
          id?: string
          import_batch_id?: string | null
          individual_contributors?: number
          is_test?: boolean
          municipality_id: string
          other_eligible_payroll?: number
          payload_sha256?: string | null
          pro_labore?: number
          source_snapshot?: Json
          source_system_id: string
          taxpayer_id: string
          thirteenth_salary?: number
          updated_at?: string
        }
        Update: {
          competence_month?: string
          created_at?: string
          data_origin?: string
          employee_remuneration?: number
          employer_social_security?: number
          external_record_id?: string
          fgts?: number
          fs_month?: number | null
          id?: string
          import_batch_id?: string | null
          individual_contributors?: number
          is_test?: boolean
          municipality_id?: string
          other_eligible_payroll?: number
          payload_sha256?: string | null
          pro_labore?: number
          source_snapshot?: Json
          source_system_id?: string
          taxpayer_id?: string
          thirteenth_salary?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "factor_r_payroll_periods_batch_fk"
            columns: ["municipality_id", "import_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "factor_r_payroll_periods_source_fk"
            columns: ["municipality_id", "source_system_id"]
            isOneToOne: false
            referencedRelation: "source_systems"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "factor_r_payroll_periods_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "factor_r_payroll_periods_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "factor_r_payroll_periods_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      fiscal_cases: {
        Row: {
          batch_item_id: string
          case_number: string
          closed_at: string | null
          closure_reason: string | null
          confidentiality: string
          created_at: string
          divergence_id: string
          execution_mode: string
          first_accessed_at: string | null
          id: string
          municipality_id: string
          opened_at: string
          opened_by: string | null
          status: string
          taxpayer_id: string
          updated_at: string
          version: number
        }
        Insert: {
          batch_item_id: string
          case_number: string
          closed_at?: string | null
          closure_reason?: string | null
          confidentiality?: string
          created_at?: string
          divergence_id: string
          execution_mode?: string
          first_accessed_at?: string | null
          id?: string
          municipality_id: string
          opened_at?: string
          opened_by?: string | null
          status?: string
          taxpayer_id: string
          updated_at?: string
          version?: number
        }
        Update: {
          batch_item_id?: string
          case_number?: string
          closed_at?: string | null
          closure_reason?: string | null
          confidentiality?: string
          created_at?: string
          divergence_id?: string
          execution_mode?: string
          first_accessed_at?: string | null
          id?: string
          municipality_id?: string
          opened_at?: string
          opened_by?: string | null
          status?: string
          taxpayer_id?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_cases_batch_item_divergence_fk"
            columns: ["municipality_id", "batch_item_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "case_opening_batch_items"
            referencedColumns: ["municipality_id", "id", "divergence_id"]
          },
          {
            foreignKeyName: "fiscal_cases_divergence_taxpayer_fk"
            columns: ["municipality_id", "divergence_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "api_divergence_queue"
            referencedColumns: ["municipality_id", "id", "taxpayer_id"]
          },
          {
            foreignKeyName: "fiscal_cases_divergence_taxpayer_fk"
            columns: ["municipality_id", "divergence_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "divergences"
            referencedColumns: ["municipality_id", "id", "taxpayer_id"]
          },
          {
            foreignKeyName: "fiscal_cases_divergence_taxpayer_fk"
            columns: ["municipality_id", "divergence_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_fiscal_divergence_search"
            referencedColumns: [
              "municipality_id",
              "divergence_id",
              "taxpayer_id",
            ]
          },
          {
            foreignKeyName: "fiscal_cases_divergence_taxpayer_fk"
            columns: ["municipality_id", "divergence_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_divergences"
            referencedColumns: [
              "municipality_id",
              "divergence_id",
              "taxpayer_id",
            ]
          },
        ]
      }
      fiscal_chat_inbox: {
        Row: {
          answered_at: string | null
          assigned_membership_id: string | null
          case_id: string
          claimed_at: string | null
          created_at: string
          handling_mode: string
          municipality_id: string
          priority: number
          question_id: string
          question_preview: string
          routing_confidence: number | null
          routing_reason: string | null
          sla_due_at: string | null
          status: string
          taxpayer_id: string
          updated_at: string
        }
        Insert: {
          answered_at?: string | null
          assigned_membership_id?: string | null
          case_id: string
          claimed_at?: string | null
          created_at?: string
          handling_mode?: string
          municipality_id: string
          priority?: number
          question_id: string
          question_preview: string
          routing_confidence?: number | null
          routing_reason?: string | null
          sla_due_at?: string | null
          status?: string
          taxpayer_id: string
          updated_at?: string
        }
        Update: {
          answered_at?: string | null
          assigned_membership_id?: string | null
          case_id?: string
          claimed_at?: string | null
          created_at?: string
          handling_mode?: string
          municipality_id?: string
          priority?: number
          question_id?: string
          question_preview?: string
          routing_confidence?: number | null
          routing_reason?: string | null
          sla_due_at?: string | null
          status?: string
          taxpayer_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_chat_inbox_assignment_fk"
            columns: ["municipality_id", "assigned_membership_id"]
            isOneToOne: false
            referencedRelation: "municipality_memberships"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_question_fk"
            columns: ["municipality_id", "question_id"]
            isOneToOne: false
            referencedRelation: "case_questions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      fiscal_search_golden_cases: {
        Row: {
          case_code: string
          created_at: string
          enabled: boolean
          expected_intent: string
          expected_properties: Json
          id: number
          prompt: string
          updated_at: string
        }
        Insert: {
          case_code: string
          created_at?: string
          enabled?: boolean
          expected_intent: string
          expected_properties?: Json
          id?: never
          prompt: string
          updated_at?: string
        }
        Update: {
          case_code?: string
          created_at?: string
          enabled?: boolean
          expected_intent?: string
          expected_properties?: Json
          id?: never
          prompt?: string
          updated_at?: string
        }
        Relationships: []
      }
      fiscal_search_requests: {
        Row: {
          created_at: string
          execution_ms: number
          execution_plan: Json
          id: string
          intent: string
          municipality_id: string
          normalized_query: string
          parsed_filters: Json
          raw_query: string
          request_sha256: string
          requested_by: string | null
          result_count: number
          status: string
        }
        Insert: {
          created_at?: string
          execution_ms?: number
          execution_plan?: Json
          id?: string
          intent: string
          municipality_id: string
          normalized_query: string
          parsed_filters?: Json
          raw_query: string
          request_sha256: string
          requested_by?: string | null
          result_count?: number
          status?: string
        }
        Update: {
          created_at?: string
          execution_ms?: number
          execution_plan?: Json
          id?: string
          intent?: string
          municipality_id?: string
          normalized_query?: string
          parsed_filters?: Json
          raw_query?: string
          request_sha256?: string
          requested_by?: string | null
          result_count?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_search_requests_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      import_batch_errors: {
        Row: {
          created_at: string
          error_code: string
          field_name: string | null
          id: number
          import_batch_id: string
          municipality_id: string
          row_number: number | null
          safe_message: string
          severity: string
        }
        Insert: {
          created_at?: string
          error_code: string
          field_name?: string | null
          id?: never
          import_batch_id: string
          municipality_id: string
          row_number?: number | null
          safe_message: string
          severity?: string
        }
        Update: {
          created_at?: string
          error_code?: string
          field_name?: string | null
          id?: never
          import_batch_id?: string
          municipality_id?: string
          row_number?: number | null
          safe_message?: string
          severity?: string
        }
        Relationships: [
          {
            foreignKeyName: "import_batch_errors_batch_fk"
            columns: ["municipality_id", "import_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      import_batches: {
        Row: {
          accepted_count: number
          created_at: string
          error_summary: Json
          finished_at: string | null
          id: string
          idempotency_key: string
          import_type: string
          municipality_id: string
          received_at: string
          rejected_count: number
          requested_by: string | null
          row_count: number
          source_file_name: string | null
          source_sha256: string | null
          source_storage_path: string | null
          source_system_id: string
          started_at: string | null
          status: string
          updated_at: string
        }
        Insert: {
          accepted_count?: number
          created_at?: string
          error_summary?: Json
          finished_at?: string | null
          id?: string
          idempotency_key: string
          import_type: string
          municipality_id: string
          received_at?: string
          rejected_count?: number
          requested_by?: string | null
          row_count?: number
          source_file_name?: string | null
          source_sha256?: string | null
          source_storage_path?: string | null
          source_system_id: string
          started_at?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          accepted_count?: number
          created_at?: string
          error_summary?: Json
          finished_at?: string | null
          id?: string
          idempotency_key?: string
          import_type?: string
          municipality_id?: string
          received_at?: string
          rejected_count?: number
          requested_by?: string | null
          row_count?: number
          source_file_name?: string | null
          source_sha256?: string | null
          source_storage_path?: string | null
          source_system_id?: string
          started_at?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "import_batches_source_fk"
            columns: ["municipality_id", "source_system_id"]
            isOneToOne: false
            referencedRelation: "source_systems"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      integrations: {
        Row: {
          created_at: string
          created_by: string | null
          display_name: string
          id: string
          integration_type: string
          last_error_code: string | null
          last_tested_at: string | null
          municipality_id: string
          non_secret_config: Json
          provider_code: string
          secret_reference: string | null
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          display_name: string
          id?: string
          integration_type: string
          last_error_code?: string | null
          last_tested_at?: string | null
          municipality_id: string
          non_secret_config?: Json
          provider_code: string
          secret_reference?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          display_name?: string
          id?: string
          integration_type?: string
          last_error_code?: string | null
          last_tested_at?: string | null
          municipality_id?: string
          non_secret_config?: Json
          provider_code?: string
          secret_reference?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "integrations_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_article_citations: {
        Row: {
          citation_label: string
          created_at: string
          id: string
          legal_section_id: string
          municipality_id: string
          quoted_excerpt: string
          revision_id: string
          source_sha256: string
          source_version_id: string
        }
        Insert: {
          citation_label: string
          created_at?: string
          id?: string
          legal_section_id: string
          municipality_id: string
          quoted_excerpt: string
          revision_id: string
          source_sha256: string
          source_version_id: string
        }
        Update: {
          citation_label?: string
          created_at?: string
          id?: string
          legal_section_id?: string
          municipality_id?: string
          quoted_excerpt?: string
          revision_id?: string
          source_sha256?: string
          source_version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_article_citations_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_article_citations_revision_fk"
            columns: ["municipality_id", "revision_id"]
            isOneToOne: false
            referencedRelation: "knowledge_article_revisions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "knowledge_article_citations_section_fk"
            columns: ["municipality_id", "legal_section_id"]
            isOneToOne: false
            referencedRelation: "legal_sections"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "knowledge_article_citations_version_fk"
            columns: ["municipality_id", "source_version_id"]
            isOneToOne: false
            referencedRelation: "legal_source_versions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      knowledge_article_patterns: {
        Row: {
          article_id: string
          created_at: string
          id: string
          match_mode: string
          municipality_id: string
          normalized_phrase: string
          phrase: string
        }
        Insert: {
          article_id: string
          created_at?: string
          id?: string
          match_mode?: string
          municipality_id: string
          normalized_phrase: string
          phrase: string
        }
        Update: {
          article_id?: string
          created_at?: string
          id?: string
          match_mode?: string
          municipality_id?: string
          normalized_phrase?: string
          phrase?: string
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_article_patterns_article_fk"
            columns: ["municipality_id", "article_id"]
            isOneToOne: false
            referencedRelation: "knowledge_articles"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "knowledge_article_patterns_article_fk"
            columns: ["municipality_id", "article_id"]
            isOneToOne: false
            referencedRelation: "vw_reusable_knowledge_articles"
            referencedColumns: ["municipality_id", "article_id"]
          },
          {
            foreignKeyName: "knowledge_article_patterns_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_article_reviews: {
        Row: {
          approved_content_sha256: string | null
          article_id: string
          created_at: string
          decision: string
          id: string
          municipality_id: string
          notes: string | null
          reviewed_at: string
          reviewer_membership_id: string
          revision_id: string
        }
        Insert: {
          approved_content_sha256?: string | null
          article_id: string
          created_at?: string
          decision: string
          id?: string
          municipality_id: string
          notes?: string | null
          reviewed_at?: string
          reviewer_membership_id: string
          revision_id: string
        }
        Update: {
          approved_content_sha256?: string | null
          article_id?: string
          created_at?: string
          decision?: string
          id?: string
          municipality_id?: string
          notes?: string | null
          reviewed_at?: string
          reviewer_membership_id?: string
          revision_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_article_reviews_article_fk"
            columns: ["municipality_id", "article_id"]
            isOneToOne: false
            referencedRelation: "knowledge_articles"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "knowledge_article_reviews_article_fk"
            columns: ["municipality_id", "article_id"]
            isOneToOne: false
            referencedRelation: "vw_reusable_knowledge_articles"
            referencedColumns: ["municipality_id", "article_id"]
          },
          {
            foreignKeyName: "knowledge_article_reviews_membership_fk"
            columns: ["municipality_id", "reviewer_membership_id"]
            isOneToOne: false
            referencedRelation: "municipality_memberships"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "knowledge_article_reviews_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_article_reviews_revision_fk"
            columns: ["municipality_id", "revision_id"]
            isOneToOne: false
            referencedRelation: "knowledge_article_revisions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      knowledge_article_revisions: {
        Row: {
          allowed_placeholders: Json
          answer_body: string
          article_id: string
          content_sha256: string
          created_at: string
          created_by: string | null
          id: string
          municipality_id: string
          revision_number: number
          source_draft_revision_id: string | null
          source_message_id: string | null
          source_type: string
        }
        Insert: {
          allowed_placeholders?: Json
          answer_body: string
          article_id: string
          content_sha256: string
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id: string
          revision_number: number
          source_draft_revision_id?: string | null
          source_message_id?: string | null
          source_type: string
        }
        Update: {
          allowed_placeholders?: Json
          answer_body?: string
          article_id?: string
          content_sha256?: string
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id?: string
          revision_number?: number
          source_draft_revision_id?: string | null
          source_message_id?: string | null
          source_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_article_revisions_article_fk"
            columns: ["municipality_id", "article_id"]
            isOneToOne: false
            referencedRelation: "knowledge_articles"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "knowledge_article_revisions_article_fk"
            columns: ["municipality_id", "article_id"]
            isOneToOne: false
            referencedRelation: "vw_reusable_knowledge_articles"
            referencedColumns: ["municipality_id", "article_id"]
          },
          {
            foreignKeyName: "knowledge_article_revisions_draft_fk"
            columns: ["municipality_id", "source_draft_revision_id"]
            isOneToOne: false
            referencedRelation: "ai_draft_revisions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "knowledge_article_revisions_message_fk"
            columns: ["municipality_id", "source_message_id"]
            isOneToOne: false
            referencedRelation: "case_messages"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "knowledge_article_revisions_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_articles: {
        Row: {
          approval_basis: string
          canonical_question: string
          created_at: string
          created_by: string | null
          current_revision_number: number
          divergence_scope: string
          id: string
          intent_key: string
          is_test: boolean
          municipality_id: string
          published_at: string | null
          semantic_version: number
          source_message_id: string | null
          source_question_id: string | null
          status: string
          tax_scope: string
          updated_at: string
          valid_from: string | null
          valid_until: string | null
        }
        Insert: {
          approval_basis?: string
          canonical_question: string
          created_at?: string
          created_by?: string | null
          current_revision_number?: number
          divergence_scope: string
          id?: string
          intent_key: string
          is_test?: boolean
          municipality_id: string
          published_at?: string | null
          semantic_version?: number
          source_message_id?: string | null
          source_question_id?: string | null
          status?: string
          tax_scope: string
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Update: {
          approval_basis?: string
          canonical_question?: string
          created_at?: string
          created_by?: string | null
          current_revision_number?: number
          divergence_scope?: string
          id?: string
          intent_key?: string
          is_test?: boolean
          municipality_id?: string
          published_at?: string | null
          semantic_version?: number
          source_message_id?: string | null
          source_question_id?: string | null
          status?: string
          tax_scope?: string
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_articles_message_fk"
            columns: ["municipality_id", "source_message_id"]
            isOneToOne: true
            referencedRelation: "case_messages"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "knowledge_articles_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_articles_question_fk"
            columns: ["municipality_id", "source_question_id"]
            isOneToOne: false
            referencedRelation: "case_questions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      knowledge_release_items: {
        Row: {
          created_at: string
          id: string
          municipality_id: string
          release_id: string
          source_version_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          municipality_id: string
          release_id: string
          source_version_id: string
        }
        Update: {
          created_at?: string
          id?: string
          municipality_id?: string
          release_id?: string
          source_version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_release_items_release_fk"
            columns: ["municipality_id", "release_id"]
            isOneToOne: false
            referencedRelation: "knowledge_releases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "knowledge_release_items_version_fk"
            columns: ["municipality_id", "source_version_id"]
            isOneToOne: false
            referencedRelation: "legal_source_versions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      knowledge_releases: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          created_by: string | null
          divergence_scope: string
          effective_from: string | null
          effective_until: string | null
          id: string
          municipality_id: string
          name: string
          published_at: string | null
          release_sha256: string | null
          status: string
          tax_scope: string
          updated_at: string
          version: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by?: string | null
          divergence_scope?: string
          effective_from?: string | null
          effective_until?: string | null
          id?: string
          municipality_id: string
          name: string
          published_at?: string | null
          release_sha256?: string | null
          status?: string
          tax_scope?: string
          updated_at?: string
          version: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by?: string | null
          divergence_scope?: string
          effective_from?: string | null
          effective_until?: string | null
          id?: string
          municipality_id?: string
          name?: string
          published_at?: string | null
          release_sha256?: string | null
          status?: string
          tax_scope?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_releases_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      legal_holds: {
        Row: {
          case_id: string | null
          created_at: string
          created_by: string | null
          id: string
          municipality_id: string
          reason: string
          released_at: string | null
          released_by: string | null
          scope_type: string
          status: string
        }
        Insert: {
          case_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id: string
          reason: string
          released_at?: string | null
          released_by?: string | null
          scope_type: string
          status?: string
        }
        Update: {
          case_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id?: string
          reason?: string
          released_at?: string | null
          released_by?: string | null
          scope_type?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "legal_holds_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "legal_holds_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "legal_holds_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "legal_holds_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "legal_holds_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      legal_sections: {
        Row: {
          content_sha256: string
          content_text: string
          created_at: string
          heading: string | null
          id: string
          municipality_id: string
          ordinal: number
          section_key: string
          source_version_id: string
        }
        Insert: {
          content_sha256: string
          content_text: string
          created_at?: string
          heading?: string | null
          id?: string
          municipality_id: string
          ordinal: number
          section_key: string
          source_version_id: string
        }
        Update: {
          content_sha256?: string
          content_text?: string
          created_at?: string
          heading?: string | null
          id?: string
          municipality_id?: string
          ordinal?: number
          section_key?: string
          source_version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "legal_sections_version_fk"
            columns: ["municipality_id", "source_version_id"]
            isOneToOne: false
            referencedRelation: "legal_source_versions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      legal_source_versions: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          content_sha256: string
          content_text: string
          created_at: string
          created_by: string | null
          id: string
          municipality_id: string
          publication_date: string | null
          published_at: string | null
          source_id: string
          status: string
          supersedes_version_id: string | null
          updated_at: string
          valid_from: string | null
          valid_until: string | null
          version: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          content_sha256: string
          content_text: string
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id: string
          publication_date?: string | null
          published_at?: string | null
          source_id: string
          status?: string
          supersedes_version_id?: string | null
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
          version: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          content_sha256?: string
          content_text?: string
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id?: string
          publication_date?: string | null
          published_at?: string | null
          source_id?: string
          status?: string
          supersedes_version_id?: string | null
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "legal_source_versions_source_fk"
            columns: ["municipality_id", "source_id"]
            isOneToOne: false
            referencedRelation: "legal_sources"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "legal_source_versions_supersedes_fk"
            columns: ["municipality_id", "supersedes_version_id"]
            isOneToOne: false
            referencedRelation: "legal_source_versions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      legal_sources: {
        Row: {
          created_at: string
          created_by: string | null
          divergence_scope: string
          id: string
          issuing_authority: string
          jurisdiction: string
          municipality_id: string
          official_identifier: string | null
          official_url: string | null
          source_type: string
          status: string
          tax_scope: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          divergence_scope?: string
          id?: string
          issuing_authority: string
          jurisdiction: string
          municipality_id: string
          official_identifier?: string | null
          official_url?: string | null
          source_type: string
          status?: string
          tax_scope?: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          divergence_scope?: string
          id?: string
          issuing_authority?: string
          jurisdiction?: string
          municipality_id?: string
          official_identifier?: string | null
          official_url?: string | null
          source_type?: string
          status?: string
          tax_scope?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "legal_sources_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      municipalities: {
        Row: {
          created_at: string
          data_classification: string
          ibge_code: string | null
          id: string
          name: string
          slug: string
          state_code: string
          status: string
          timezone: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          data_classification?: string
          ibge_code?: string | null
          id?: string
          name: string
          slug: string
          state_code: string
          status?: string
          timezone?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          data_classification?: string
          ibge_code?: string | null
          id?: string
          name?: string
          slug?: string
          state_code?: string
          status?: string
          timezone?: string
          updated_at?: string
        }
        Relationships: []
      }
      municipality_business_calendar: {
        Row: {
          calendar_date: string
          calendar_scope: string
          created_at: string
          day_type: string
          description: string | null
          id: string
          is_business_day: boolean
          legal_source_version_id: string | null
          municipality_id: string
          source_snapshot: Json
          updated_at: string
          verification_status: string
        }
        Insert: {
          calendar_date: string
          calendar_scope: string
          created_at?: string
          day_type: string
          description?: string | null
          id?: string
          is_business_day: boolean
          legal_source_version_id?: string | null
          municipality_id: string
          source_snapshot?: Json
          updated_at?: string
          verification_status?: string
        }
        Update: {
          calendar_date?: string
          calendar_scope?: string
          created_at?: string
          day_type?: string
          description?: string | null
          id?: string
          is_business_day?: boolean
          legal_source_version_id?: string | null
          municipality_id?: string
          source_snapshot?: Json
          updated_at?: string
          verification_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "municipality_business_calenda_municipality_id_legal_source_fkey"
            columns: ["municipality_id", "legal_source_version_id"]
            isOneToOne: false
            referencedRelation: "legal_source_versions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "municipality_business_calendar_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      municipality_memberships: {
        Row: {
          activated_at: string | null
          created_at: string
          id: string
          invited_by: string | null
          municipality_id: string
          role: string
          status: string
          updated_at: string
          user_id: string
          valid_from: string
          valid_until: string | null
        }
        Insert: {
          activated_at?: string | null
          created_at?: string
          id?: string
          invited_by?: string | null
          municipality_id: string
          role: string
          status?: string
          updated_at?: string
          user_id: string
          valid_from?: string
          valid_until?: string | null
        }
        Update: {
          activated_at?: string | null
          created_at?: string
          id?: string
          invited_by?: string | null
          municipality_id?: string
          role?: string
          status?: string
          updated_at?: string
          user_id?: string
          valid_from?: string
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "municipality_memberships_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      municipality_policy_versions: {
        Row: {
          accountant_notice_enabled: boolean
          ai_drafting_enabled: boolean
          approved_at: string | null
          approved_by: string | null
          auto_case_creation_enabled: boolean
          auto_initial_notice_enabled: boolean
          created_at: string
          created_by: string | null
          daily_initial_notice_limit: number
          effective_from: string | null
          effective_until: string | null
          id: string
          lookback_months: number
          minimum_divergence_amount: number
          municipality_id: string
          operational_config: Json
          require_fiscal_review: boolean
          revalidation_max_age_minutes: number
          status: string
          top_debtors_limit: number
          updated_at: string
          version: number
        }
        Insert: {
          accountant_notice_enabled?: boolean
          ai_drafting_enabled?: boolean
          approved_at?: string | null
          approved_by?: string | null
          auto_case_creation_enabled?: boolean
          auto_initial_notice_enabled?: boolean
          created_at?: string
          created_by?: string | null
          daily_initial_notice_limit?: number
          effective_from?: string | null
          effective_until?: string | null
          id?: string
          lookback_months?: number
          minimum_divergence_amount?: number
          municipality_id: string
          operational_config?: Json
          require_fiscal_review?: boolean
          revalidation_max_age_minutes?: number
          status?: string
          top_debtors_limit?: number
          updated_at?: string
          version: number
        }
        Update: {
          accountant_notice_enabled?: boolean
          ai_drafting_enabled?: boolean
          approved_at?: string | null
          approved_by?: string | null
          auto_case_creation_enabled?: boolean
          auto_initial_notice_enabled?: boolean
          created_at?: string
          created_by?: string | null
          daily_initial_notice_limit?: number
          effective_from?: string | null
          effective_until?: string | null
          id?: string
          lookback_months?: number
          minimum_divergence_amount?: number
          municipality_id?: string
          operational_config?: Json
          require_fiscal_review?: boolean
          revalidation_max_age_minutes?: number
          status?: string
          top_debtors_limit?: number
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "municipality_policy_versions_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      municipality_portal_settings: {
        Row: {
          case_portal_base_url: string | null
          created_at: string
          external_email_enabled: boolean
          municipality_id: string
          official_help_url: string | null
          sandbox_response_publication_enabled: boolean
          sigiss_login_url: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          case_portal_base_url?: string | null
          created_at?: string
          external_email_enabled?: boolean
          municipality_id: string
          official_help_url?: string | null
          sandbox_response_publication_enabled?: boolean
          sigiss_login_url: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          case_portal_base_url?: string | null
          created_at?: string
          external_email_enabled?: boolean
          municipality_id?: string
          official_help_url?: string | null
          sandbox_response_publication_enabled?: boolean
          sigiss_login_url?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "municipality_portal_settings_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: true
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_batches: {
        Row: {
          captured_notifications: number
          case_opening_batch_id: string
          created_at: string
          failed_notifications: number
          id: string
          idempotency_key: string
          municipality_id: string
          sent_notifications: number
          status: string
          total_notifications: number
          updated_at: string
        }
        Insert: {
          captured_notifications?: number
          case_opening_batch_id: string
          created_at?: string
          failed_notifications?: number
          id?: string
          idempotency_key: string
          municipality_id: string
          sent_notifications?: number
          status?: string
          total_notifications?: number
          updated_at?: string
        }
        Update: {
          captured_notifications?: number
          case_opening_batch_id?: string
          created_at?: string
          failed_notifications?: number
          id?: string
          idempotency_key?: string
          municipality_id?: string
          sent_notifications?: number
          status?: string
          total_notifications?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_batches_case_batch_fk"
            columns: ["municipality_id", "case_opening_batch_id"]
            isOneToOne: false
            referencedRelation: "case_opening_batches"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      notification_channel_settings: {
        Row: {
          channel: string
          created_at: string
          created_by: string | null
          daily_limit: number
          id: string
          initial_template_version_id: string | null
          integration_id: string | null
          kill_switch: boolean
          monthly_limit: number
          municipality_id: string
          reply_to_email: string | null
          sender_email: string | null
          sender_name: string | null
          status: string
          updated_at: string
        }
        Insert: {
          channel?: string
          created_at?: string
          created_by?: string | null
          daily_limit?: number
          id?: string
          initial_template_version_id?: string | null
          integration_id?: string | null
          kill_switch?: boolean
          monthly_limit?: number
          municipality_id: string
          reply_to_email?: string | null
          sender_email?: string | null
          sender_name?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          channel?: string
          created_at?: string
          created_by?: string | null
          daily_limit?: number
          id?: string
          initial_template_version_id?: string | null
          integration_id?: string | null
          kill_switch?: boolean
          monthly_limit?: number
          municipality_id?: string
          reply_to_email?: string | null
          sender_email?: string | null
          sender_name?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_channel_settings_integration_fk"
            columns: ["municipality_id", "integration_id"]
            isOneToOne: false
            referencedRelation: "integrations"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notification_channel_settings_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_channel_settings_template_fk"
            columns: ["municipality_id", "initial_template_version_id"]
            isOneToOne: false
            referencedRelation: "notification_template_versions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      notification_recipient_candidates: {
        Row: {
          candidate_status: string
          contact_id: string
          created_at: string
          delivery_block_reason: string | null
          id: string
          municipality_id: string
          priority: number
          proposed_for: string
          recipient_type: string
          relationship_snapshot: Json
          taxpayer_accountant_link_id: string | null
          taxpayer_id: string
          updated_at: string
        }
        Insert: {
          candidate_status?: string
          contact_id: string
          created_at?: string
          delivery_block_reason?: string | null
          id?: string
          municipality_id: string
          priority?: number
          proposed_for: string
          recipient_type: string
          relationship_snapshot?: Json
          taxpayer_accountant_link_id?: string | null
          taxpayer_id: string
          updated_at?: string
        }
        Update: {
          candidate_status?: string
          contact_id?: string
          created_at?: string
          delivery_block_reason?: string | null
          id?: string
          municipality_id?: string
          priority?: number
          proposed_for?: string
          recipient_type?: string
          relationship_snapshot?: Json
          taxpayer_accountant_link_id?: string | null
          taxpayer_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_recipient_candid_municipality_id_taxpayer_acc_fkey"
            columns: ["municipality_id", "taxpayer_accountant_link_id"]
            isOneToOne: false
            referencedRelation: "taxpayer_accountant_links"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notification_recipient_candid_municipality_id_taxpayer_acc_fkey"
            columns: ["municipality_id", "taxpayer_accountant_link_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_responsibles"
            referencedColumns: ["municipality_id", "link_id"]
          },
          {
            foreignKeyName: "notification_recipient_candid_municipality_id_taxpayer_acc_fkey"
            columns: ["municipality_id", "taxpayer_accountant_link_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_responsibilities_visible"
            referencedColumns: ["municipality_id", "link_id"]
          },
          {
            foreignKeyName: "notification_recipient_candida_municipality_id_taxpayer_id_fkey"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notification_recipient_candida_municipality_id_taxpayer_id_fkey"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "notification_recipient_candida_municipality_id_taxpayer_id_fkey"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "notification_recipient_candidat_municipality_id_contact_id_fkey"
            columns: ["municipality_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "party_contacts"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notification_recipient_candidat_municipality_id_contact_id_fkey"
            columns: ["municipality_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "vw_quarantined_contacts"
            referencedColumns: ["municipality_id", "contact_id"]
          },
          {
            foreignKeyName: "notification_recipient_candidat_municipality_id_contact_id_fkey"
            columns: ["municipality_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_contacts"
            referencedColumns: ["municipality_id", "contact_id"]
          },
        ]
      }
      notification_recipients: {
        Row: {
          contact_id: string
          created_at: string
          delivered_at: string | null
          delivery_mode: string
          email_snapshot: string
          external_delivery_attempted: boolean
          id: string
          idempotency_key: string
          last_error_code: string | null
          municipality_id: string
          notification_id: string
          recipient_type: string
          relationship_snapshot: Json
          resolved_at: string
          sent_at: string | null
          status: string
          taxpayer_accountant_link_id: string | null
          updated_at: string
        }
        Insert: {
          contact_id: string
          created_at?: string
          delivered_at?: string | null
          delivery_mode?: string
          email_snapshot: string
          external_delivery_attempted?: boolean
          id?: string
          idempotency_key: string
          last_error_code?: string | null
          municipality_id: string
          notification_id: string
          recipient_type: string
          relationship_snapshot?: Json
          resolved_at?: string
          sent_at?: string | null
          status?: string
          taxpayer_accountant_link_id?: string | null
          updated_at?: string
        }
        Update: {
          contact_id?: string
          created_at?: string
          delivered_at?: string | null
          delivery_mode?: string
          email_snapshot?: string
          external_delivery_attempted?: boolean
          id?: string
          idempotency_key?: string
          last_error_code?: string | null
          municipality_id?: string
          notification_id?: string
          recipient_type?: string
          relationship_snapshot?: Json
          resolved_at?: string
          sent_at?: string | null
          status?: string
          taxpayer_accountant_link_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_recipients_accountant_link_fk"
            columns: ["municipality_id", "taxpayer_accountant_link_id"]
            isOneToOne: false
            referencedRelation: "taxpayer_accountant_links"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notification_recipients_accountant_link_fk"
            columns: ["municipality_id", "taxpayer_accountant_link_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_responsibles"
            referencedColumns: ["municipality_id", "link_id"]
          },
          {
            foreignKeyName: "notification_recipients_accountant_link_fk"
            columns: ["municipality_id", "taxpayer_accountant_link_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_responsibilities_visible"
            referencedColumns: ["municipality_id", "link_id"]
          },
          {
            foreignKeyName: "notification_recipients_contact_fk"
            columns: ["municipality_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "party_contacts"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notification_recipients_contact_fk"
            columns: ["municipality_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "vw_quarantined_contacts"
            referencedColumns: ["municipality_id", "contact_id"]
          },
          {
            foreignKeyName: "notification_recipients_contact_fk"
            columns: ["municipality_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_contacts"
            referencedColumns: ["municipality_id", "contact_id"]
          },
          {
            foreignKeyName: "notification_recipients_notification_fk"
            columns: ["municipality_id", "notification_id"]
            isOneToOne: false
            referencedRelation: "api_notification_delivery"
            referencedColumns: ["municipality_id", "notification_id"]
          },
          {
            foreignKeyName: "notification_recipients_notification_fk"
            columns: ["municipality_id", "notification_id"]
            isOneToOne: false
            referencedRelation: "notifications"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      notification_template_versions: {
        Row: {
          allowed_placeholders: string[]
          approved_at: string | null
          approved_by: string | null
          body_html: string | null
          body_text: string
          content_sha256: string
          created_at: string
          created_by: string | null
          id: string
          municipality_id: string
          status: string
          subject: string
          template_id: string
          updated_at: string
          version: number
        }
        Insert: {
          allowed_placeholders?: string[]
          approved_at?: string | null
          approved_by?: string | null
          body_html?: string | null
          body_text: string
          content_sha256: string
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id: string
          status?: string
          subject: string
          template_id: string
          updated_at?: string
          version: number
        }
        Update: {
          allowed_placeholders?: string[]
          approved_at?: string | null
          approved_by?: string | null
          body_html?: string | null
          body_text?: string
          content_sha256?: string
          created_at?: string
          created_by?: string | null
          id?: string
          municipality_id?: string
          status?: string
          subject?: string
          template_id?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "notification_template_versions_template_fk"
            columns: ["municipality_id", "template_id"]
            isOneToOne: false
            referencedRelation: "notification_templates"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      notification_templates: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          legal_nature: string
          municipality_id: string
          name: string
          notification_type: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          legal_nature?: string
          municipality_id: string
          name: string
          notification_type: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          legal_nature?: string
          municipality_id?: string
          name?: string
          notification_type?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_templates_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body_html_snapshot: string | null
          body_text_snapshot: string
          cancelled_at: string | null
          case_id: string
          content_sha256: string
          created_at: string
          delivery_mode: string
          execution_mode: string
          external_delivery_attempted: boolean
          id: string
          idempotency_key: string
          legal_nature: string
          municipality_id: string
          notification_batch_id: string | null
          notification_type: string
          prepared_at: string
          queued_at: string | null
          sent_at: string | null
          status: string
          subject_snapshot: string
          template_version_id: string
          updated_at: string
        }
        Insert: {
          body_html_snapshot?: string | null
          body_text_snapshot: string
          cancelled_at?: string | null
          case_id: string
          content_sha256: string
          created_at?: string
          delivery_mode?: string
          execution_mode?: string
          external_delivery_attempted?: boolean
          id?: string
          idempotency_key: string
          legal_nature: string
          municipality_id: string
          notification_batch_id?: string | null
          notification_type: string
          prepared_at?: string
          queued_at?: string | null
          sent_at?: string | null
          status?: string
          subject_snapshot: string
          template_version_id: string
          updated_at?: string
        }
        Update: {
          body_html_snapshot?: string | null
          body_text_snapshot?: string
          cancelled_at?: string | null
          case_id?: string
          content_sha256?: string
          created_at?: string
          delivery_mode?: string
          execution_mode?: string
          external_delivery_attempted?: boolean
          id?: string
          idempotency_key?: string
          legal_nature?: string
          municipality_id?: string
          notification_batch_id?: string | null
          notification_type?: string
          prepared_at?: string
          queued_at?: string | null
          sent_at?: string | null
          status?: string
          subject_snapshot?: string
          template_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_batch_fk"
            columns: ["municipality_id", "notification_batch_id"]
            isOneToOne: false
            referencedRelation: "notification_batches"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notifications_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notifications_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notifications_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "notifications_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "notifications_template_fk"
            columns: ["municipality_id", "template_version_id"]
            isOneToOne: false
            referencedRelation: "notification_template_versions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      party_contacts: {
        Row: {
          accounting_firm_id: string | null
          contact_type: string
          created_at: string
          id: string
          is_primary: boolean
          label: string | null
          municipality_id: string
          normalized_value: string
          quarantine_reason: string | null
          source: string
          status: string
          taxpayer_id: string | null
          updated_at: string
          valid_from: string
          valid_until: string | null
          value: string
          verification_metadata: Json
          verified_at: string | null
          verified_by: string | null
          visible_in_homologation: boolean
        }
        Insert: {
          accounting_firm_id?: string | null
          contact_type: string
          created_at?: string
          id?: string
          is_primary?: boolean
          label?: string | null
          municipality_id: string
          normalized_value: string
          quarantine_reason?: string | null
          source?: string
          status?: string
          taxpayer_id?: string | null
          updated_at?: string
          valid_from?: string
          valid_until?: string | null
          value: string
          verification_metadata?: Json
          verified_at?: string | null
          verified_by?: string | null
          visible_in_homologation?: boolean
        }
        Update: {
          accounting_firm_id?: string | null
          contact_type?: string
          created_at?: string
          id?: string
          is_primary?: boolean
          label?: string | null
          municipality_id?: string
          normalized_value?: string
          quarantine_reason?: string | null
          source?: string
          status?: string
          taxpayer_id?: string | null
          updated_at?: string
          valid_from?: string
          valid_until?: string | null
          value?: string
          verification_metadata?: Json
          verified_at?: string | null
          verified_by?: string | null
          visible_in_homologation?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "party_contacts_firm_fk"
            columns: ["municipality_id", "accounting_firm_id"]
            isOneToOne: false
            referencedRelation: "accounting_firms"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "party_contacts_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "party_contacts_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "party_contacts_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      pgdasd_annex_items: {
        Row: {
          activity_code: string | null
          annex_code: string
          created_at: string
          declaration_id: string
          effective_rate: number | null
          external_line_id: string
          factor_r_applicable: boolean
          gross_revenue: number
          id: string
          iss_amount: number
          iss_rate: number | null
          municipality_id: string
          revenue_type: string | null
          source_snapshot: Json
          tax_base: number
          taxpayer_id: string
        }
        Insert: {
          activity_code?: string | null
          annex_code: string
          created_at?: string
          declaration_id: string
          effective_rate?: number | null
          external_line_id: string
          factor_r_applicable?: boolean
          gross_revenue?: number
          id?: string
          iss_amount?: number
          iss_rate?: number | null
          municipality_id: string
          revenue_type?: string | null
          source_snapshot?: Json
          tax_base?: number
          taxpayer_id: string
        }
        Update: {
          activity_code?: string | null
          annex_code?: string
          created_at?: string
          declaration_id?: string
          effective_rate?: number | null
          external_line_id?: string
          factor_r_applicable?: boolean
          gross_revenue?: number
          id?: string
          iss_amount?: number
          iss_rate?: number | null
          municipality_id?: string
          revenue_type?: string | null
          source_snapshot?: Json
          tax_base?: number
          taxpayer_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pgdasd_annex_items_declaration_fk"
            columns: ["municipality_id", "declaration_id"]
            isOneToOne: false
            referencedRelation: "pgdasd_declarations"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "pgdasd_annex_items_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "pgdasd_annex_items_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "pgdasd_annex_items_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      pgdasd_declarations: {
        Row: {
          accounting_regime: string
          competence_month: string
          created_at: string
          data_origin: string
          declaration_status: string
          external_record_id: string
          factor_r_declared: number | null
          fs12_declared: number | null
          id: string
          import_batch_id: string | null
          is_test: boolean
          iss_due_declared: number
          iss_tax_base_declared: number
          municipality_id: string
          payload_sha256: string | null
          rbt12_declared: number | null
          receipt_number: string | null
          source_snapshot: Json
          source_system_id: string
          taxpayer_id: string
          total_revenue_declared: number
          total_tax_base_declared: number
          transmitted_at: string | null
          updated_at: string
        }
        Insert: {
          accounting_regime?: string
          competence_month: string
          created_at?: string
          data_origin?: string
          declaration_status?: string
          external_record_id: string
          factor_r_declared?: number | null
          fs12_declared?: number | null
          id?: string
          import_batch_id?: string | null
          is_test?: boolean
          iss_due_declared?: number
          iss_tax_base_declared?: number
          municipality_id: string
          payload_sha256?: string | null
          rbt12_declared?: number | null
          receipt_number?: string | null
          source_snapshot?: Json
          source_system_id: string
          taxpayer_id: string
          total_revenue_declared?: number
          total_tax_base_declared?: number
          transmitted_at?: string | null
          updated_at?: string
        }
        Update: {
          accounting_regime?: string
          competence_month?: string
          created_at?: string
          data_origin?: string
          declaration_status?: string
          external_record_id?: string
          factor_r_declared?: number | null
          fs12_declared?: number | null
          id?: string
          import_batch_id?: string | null
          is_test?: boolean
          iss_due_declared?: number
          iss_tax_base_declared?: number
          municipality_id?: string
          payload_sha256?: string | null
          rbt12_declared?: number | null
          receipt_number?: string | null
          source_snapshot?: Json
          source_system_id?: string
          taxpayer_id?: string
          total_revenue_declared?: number
          total_tax_base_declared?: number
          transmitted_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "pgdasd_declarations_batch_fk"
            columns: ["municipality_id", "import_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "pgdasd_declarations_source_fk"
            columns: ["municipality_id", "source_system_id"]
            isOneToOne: false
            referencedRelation: "source_systems"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "pgdasd_declarations_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "pgdasd_declarations_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "pgdasd_declarations_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      platform_administrators: {
        Row: {
          active: boolean
          created_at: string
          granted_by: string | null
          reason: string
          revoked_at: string | null
          user_id: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          granted_by?: string | null
          reason: string
          revoked_at?: string | null
          user_id: string
        }
        Update: {
          active?: boolean
          created_at?: string
          granted_by?: string | null
          reason?: string
          revoked_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      privacy_requests: {
        Row: {
          assigned_membership_id: string | null
          completed_at: string | null
          created_at: string
          decision_basis: string | null
          description: string
          due_at: string | null
          id: string
          municipality_id: string
          received_at: string
          request_type: string
          requester_user_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          assigned_membership_id?: string | null
          completed_at?: string | null
          created_at?: string
          decision_basis?: string | null
          description: string
          due_at?: string | null
          id?: string
          municipality_id: string
          received_at?: string
          request_type: string
          requester_user_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          assigned_membership_id?: string | null
          completed_at?: string | null
          created_at?: string
          decision_basis?: string | null
          description?: string
          due_at?: string | null
          id?: string
          municipality_id?: string
          received_at?: string
          request_type?: string
          requester_user_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "privacy_requests_assignment_fk"
            columns: ["municipality_id", "assigned_membership_id"]
            isOneToOne: false
            referencedRelation: "municipality_memberships"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "privacy_requests_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          email: string | null
          full_name: string | null
          last_seen_at: string | null
          locale: string
          phone: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          last_seen_at?: string | null
          locale?: string
          phone?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          last_seen_at?: string | null
          locale?: string
          phone?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      project_source_documents: {
        Row: {
          classification: string
          created_at: string
          drive_file_id: string
          drive_url: string
          extraction_metadata: Json
          id: string
          ingestion_status: string
          mime_type: string
          modified_at: string | null
          municipality_id: string
          scope_status: string
          size_bytes: number | null
          source_kind: string
          source_sha256: string | null
          title: string
          updated_at: string
        }
        Insert: {
          classification?: string
          created_at?: string
          drive_file_id: string
          drive_url: string
          extraction_metadata?: Json
          id?: string
          ingestion_status?: string
          mime_type: string
          modified_at?: string | null
          municipality_id: string
          scope_status?: string
          size_bytes?: number | null
          source_kind: string
          source_sha256?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          classification?: string
          created_at?: string
          drive_file_id?: string
          drive_url?: string
          extraction_metadata?: Json
          id?: string
          ingestion_status?: string
          mime_type?: string
          modified_at?: string | null
          municipality_id?: string
          scope_status?: string
          size_bytes?: number | null
          source_kind?: string
          source_sha256?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "project_source_documents_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      retention_policies: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          data_category: string
          id: string
          legal_basis: string
          municipality_id: string
          retention_days: number
          status: string
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          data_category: string
          id?: string
          legal_basis: string
          municipality_id: string
          retention_days: number
          status?: string
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          data_category?: string
          id?: string
          legal_basis?: string
          municipality_id?: string
          retention_days?: number
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "retention_policies_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      rule_legal_basis: {
        Row: {
          basis_type: string
          created_at: string
          id: string
          knowledge_release_id: string
          legal_section_id: string | null
          municipality_id: string
          rule_version_id: string
        }
        Insert: {
          basis_type?: string
          created_at?: string
          id?: string
          knowledge_release_id: string
          legal_section_id?: string | null
          municipality_id: string
          rule_version_id: string
        }
        Update: {
          basis_type?: string
          created_at?: string
          id?: string
          knowledge_release_id?: string
          legal_section_id?: string | null
          municipality_id?: string
          rule_version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "rule_legal_basis_release_fk"
            columns: ["municipality_id", "knowledge_release_id"]
            isOneToOne: false
            referencedRelation: "knowledge_releases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "rule_legal_basis_rule_fk"
            columns: ["municipality_id", "rule_version_id"]
            isOneToOne: false
            referencedRelation: "divergence_rule_versions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "rule_legal_basis_section_fk"
            columns: ["municipality_id", "legal_section_id"]
            isOneToOne: false
            referencedRelation: "legal_sections"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      sigiss_tax_base_periods: {
        Row: {
          competence_month: string
          created_at: string
          data_origin: string
          declared_annex_code: string | null
          external_record_id: string
          id: string
          import_batch_id: string | null
          is_test: boolean
          iss_due: number
          iss_tax_base: number
          municipality_id: string
          payload_sha256: string | null
          retained_iss: number
          service_code_summary: Json
          services_revenue: number
          source_snapshot: Json
          source_system_id: string
          taxpayer_id: string
          taxpayer_role: string
          updated_at: string
        }
        Insert: {
          competence_month: string
          created_at?: string
          data_origin?: string
          declared_annex_code?: string | null
          external_record_id: string
          id?: string
          import_batch_id?: string | null
          is_test?: boolean
          iss_due?: number
          iss_tax_base?: number
          municipality_id: string
          payload_sha256?: string | null
          retained_iss?: number
          service_code_summary?: Json
          services_revenue?: number
          source_snapshot?: Json
          source_system_id: string
          taxpayer_id: string
          taxpayer_role: string
          updated_at?: string
        }
        Update: {
          competence_month?: string
          created_at?: string
          data_origin?: string
          declared_annex_code?: string | null
          external_record_id?: string
          id?: string
          import_batch_id?: string | null
          is_test?: boolean
          iss_due?: number
          iss_tax_base?: number
          municipality_id?: string
          payload_sha256?: string | null
          retained_iss?: number
          service_code_summary?: Json
          services_revenue?: number
          source_snapshot?: Json
          source_system_id?: string
          taxpayer_id?: string
          taxpayer_role?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sigiss_tax_base_periods_batch_fk"
            columns: ["municipality_id", "import_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "sigiss_tax_base_periods_source_fk"
            columns: ["municipality_id", "source_system_id"]
            isOneToOne: false
            referencedRelation: "source_systems"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "sigiss_tax_base_periods_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "sigiss_tax_base_periods_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "sigiss_tax_base_periods_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      simple_national_annex_line_checks: {
        Row: {
          activity_code: string | null
          annex_item_id: string
          calculation_snapshot_id: string
          calculation_snapshot_sha256: string
          competence_month: string
          created_at: string
          declaration_id: string
          evidence_snapshot: Json
          expected_annex_code: string
          factor_r: number
          id: number
          mismatch: boolean
          municipality_id: string
          observed_annex_code: string
          snapshot_sha256: string
          taxpayer_id: string
        }
        Insert: {
          activity_code?: string | null
          annex_item_id: string
          calculation_snapshot_id: string
          calculation_snapshot_sha256: string
          competence_month: string
          created_at?: string
          declaration_id: string
          evidence_snapshot: Json
          expected_annex_code: string
          factor_r: number
          id?: never
          mismatch: boolean
          municipality_id: string
          observed_annex_code: string
          snapshot_sha256: string
          taxpayer_id: string
        }
        Update: {
          activity_code?: string | null
          annex_item_id?: string
          calculation_snapshot_id?: string
          calculation_snapshot_sha256?: string
          competence_month?: string
          created_at?: string
          declaration_id?: string
          evidence_snapshot?: Json
          expected_annex_code?: string
          factor_r?: number
          id?: never
          mismatch?: boolean
          municipality_id?: string
          observed_annex_code?: string
          snapshot_sha256?: string
          taxpayer_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "simple_national_annex_line_checks_annex_item_fk"
            columns: ["municipality_id", "annex_item_id"]
            isOneToOne: false
            referencedRelation: "pgdasd_annex_items"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_annex_line_checks_declaration_fk"
            columns: ["municipality_id", "declaration_id"]
            isOneToOne: false
            referencedRelation: "pgdasd_declarations"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_annex_line_checks_snapshot_fk"
            columns: ["municipality_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "simple_national_calculation_snapshots"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_annex_line_checks_snapshot_fk"
            columns: ["municipality_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "vw_simple_national_cross_checks"
            referencedColumns: ["municipality_id", "calculation_snapshot_id"]
          },
          {
            foreignKeyName: "simple_national_annex_line_checks_snapshot_fk"
            columns: ["municipality_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_calculations"
            referencedColumns: ["municipality_id", "calculation_snapshot_id"]
          },
          {
            foreignKeyName: "simple_national_annex_line_checks_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_annex_line_checks_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "simple_national_annex_line_checks_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      simple_national_calculation_snapshots: {
        Row: {
          annex_mismatch: boolean
          block_reasons: Json
          calculated_at: string
          calculated_factor_r: number
          calculated_fs12: number
          calculated_rbt12: number
          calculation_version: string
          competence_month: string
          created_at: string
          declared_annex_code: string | null
          declared_factor_r: number | null
          declared_fs12: number | null
          declared_rbt12: number | null
          evidence_snapshot: Json
          expected_annex_code: string | null
          factor_r_applicable: boolean
          factor_r_difference: number
          id: string
          is_test: boolean
          municipality_id: string
          pgdasd_tax_base: number
          rbt12_difference: number
          sigiss_tax_base: number
          snapshot_sha256: string
          status: string
          tax_base_difference: number
          taxpayer_id: string
          updated_at: string
        }
        Insert: {
          annex_mismatch?: boolean
          block_reasons?: Json
          calculated_at?: string
          calculated_factor_r: number
          calculated_fs12: number
          calculated_rbt12: number
          calculation_version: string
          competence_month: string
          created_at?: string
          declared_annex_code?: string | null
          declared_factor_r?: number | null
          declared_fs12?: number | null
          declared_rbt12?: number | null
          evidence_snapshot: Json
          expected_annex_code?: string | null
          factor_r_applicable?: boolean
          factor_r_difference?: number
          id?: string
          is_test?: boolean
          municipality_id: string
          pgdasd_tax_base?: number
          rbt12_difference?: number
          sigiss_tax_base?: number
          snapshot_sha256: string
          status?: string
          tax_base_difference?: number
          taxpayer_id: string
          updated_at?: string
        }
        Update: {
          annex_mismatch?: boolean
          block_reasons?: Json
          calculated_at?: string
          calculated_factor_r?: number
          calculated_fs12?: number
          calculated_rbt12?: number
          calculation_version?: string
          competence_month?: string
          created_at?: string
          declared_annex_code?: string | null
          declared_factor_r?: number | null
          declared_fs12?: number | null
          declared_rbt12?: number | null
          evidence_snapshot?: Json
          expected_annex_code?: string | null
          factor_r_applicable?: boolean
          factor_r_difference?: number
          id?: string
          is_test?: boolean
          municipality_id?: string
          pgdasd_tax_base?: number
          rbt12_difference?: number
          sigiss_tax_base?: number
          snapshot_sha256?: string
          status?: string
          tax_base_difference?: number
          taxpayer_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "simple_national_snapshots_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_snapshots_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "simple_national_snapshots_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      simple_national_divergence_items: {
        Row: {
          calculation_snapshot_id: string
          created_at: string
          divergence_id: string
          evidence_snapshot: Json
          expected_value: string | null
          id: number
          metric_code: string
          municipality_id: string
          numeric_difference: number
          observed_value: string | null
        }
        Insert: {
          calculation_snapshot_id: string
          created_at?: string
          divergence_id: string
          evidence_snapshot?: Json
          expected_value?: string | null
          id?: never
          metric_code: string
          municipality_id: string
          numeric_difference?: number
          observed_value?: string | null
        }
        Update: {
          calculation_snapshot_id?: string
          created_at?: string
          divergence_id?: string
          evidence_snapshot?: Json
          expected_value?: string | null
          id?: never
          metric_code?: string
          municipality_id?: string
          numeric_difference?: number
          observed_value?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "simple_national_divergence_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "api_divergence_queue"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_divergence_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "divergences"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_divergence_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "vw_fiscal_divergence_search"
            referencedColumns: ["municipality_id", "divergence_id"]
          },
          {
            foreignKeyName: "simple_national_divergence_items_divergence_fk"
            columns: ["municipality_id", "divergence_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_divergences"
            referencedColumns: ["municipality_id", "divergence_id"]
          },
          {
            foreignKeyName: "simple_national_divergence_items_snapshot_fk"
            columns: ["municipality_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "simple_national_calculation_snapshots"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_divergence_items_snapshot_fk"
            columns: ["municipality_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "vw_simple_national_cross_checks"
            referencedColumns: ["municipality_id", "calculation_snapshot_id"]
          },
          {
            foreignKeyName: "simple_national_divergence_items_snapshot_fk"
            columns: ["municipality_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_calculations"
            referencedColumns: ["municipality_id", "calculation_snapshot_id"]
          },
        ]
      }
      simple_national_effective_rate_calculations: {
        Row: {
          activity_code: string | null
          annex_item_id: string | null
          block_reasons: Json
          calculated_at: string
          calculation_snapshot_id: string
          competence_month: string
          created_at: string
          declaration_id: string | null
          declared_annex_code: string | null
          deduction_amount: number | null
          effective_rate: number | null
          evidence_snapshot: Json
          expected_annex_code: string | null
          factor_r: number | null
          factor_r_applicable: boolean | null
          id: string
          is_test: boolean
          iss_effective_rate: number | null
          line_tax_base: number | null
          municipality_id: string
          nominal_rate: number | null
          rate_band_id: number | null
          rbt12_basis: number | null
          rbt12_mode: string | null
          result_key: string
          revenue_type: string | null
          rule_version_id: string
          snapshot_sha256: string
          source_line_key: string
          status: string
          taxpayer_id: string
        }
        Insert: {
          activity_code?: string | null
          annex_item_id?: string | null
          block_reasons?: Json
          calculated_at?: string
          calculation_snapshot_id: string
          competence_month: string
          created_at?: string
          declaration_id?: string | null
          declared_annex_code?: string | null
          deduction_amount?: number | null
          effective_rate?: number | null
          evidence_snapshot: Json
          expected_annex_code?: string | null
          factor_r?: number | null
          factor_r_applicable?: boolean | null
          id?: string
          is_test?: boolean
          iss_effective_rate?: number | null
          line_tax_base?: number | null
          municipality_id: string
          nominal_rate?: number | null
          rate_band_id?: number | null
          rbt12_basis?: number | null
          rbt12_mode?: string | null
          result_key: string
          revenue_type?: string | null
          rule_version_id: string
          snapshot_sha256: string
          source_line_key: string
          status: string
          taxpayer_id: string
        }
        Update: {
          activity_code?: string | null
          annex_item_id?: string | null
          block_reasons?: Json
          calculated_at?: string
          calculation_snapshot_id?: string
          competence_month?: string
          created_at?: string
          declaration_id?: string | null
          declared_annex_code?: string | null
          deduction_amount?: number | null
          effective_rate?: number | null
          evidence_snapshot?: Json
          expected_annex_code?: string | null
          factor_r?: number | null
          factor_r_applicable?: boolean | null
          id?: string
          is_test?: boolean
          iss_effective_rate?: number | null
          line_tax_base?: number | null
          municipality_id?: string
          nominal_rate?: number | null
          rate_band_id?: number | null
          rbt12_basis?: number | null
          rbt12_mode?: string | null
          result_key?: string
          revenue_type?: string | null
          rule_version_id?: string
          snapshot_sha256?: string
          source_line_key?: string
          status?: string
          taxpayer_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_annex_item_i_fkey"
            columns: ["municipality_id", "annex_item_id"]
            isOneToOne: false
            referencedRelation: "pgdasd_annex_items"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_calculation__fkey"
            columns: ["municipality_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "simple_national_calculation_snapshots"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_calculation__fkey"
            columns: ["municipality_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "vw_simple_national_cross_checks"
            referencedColumns: ["municipality_id", "calculation_snapshot_id"]
          },
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_calculation__fkey"
            columns: ["municipality_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_calculations"
            referencedColumns: ["municipality_id", "calculation_snapshot_id"]
          },
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_declaration__fkey"
            columns: ["municipality_id", "declaration_id"]
            isOneToOne: false
            referencedRelation: "pgdasd_declarations"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_rate_band_id_fkey"
            columns: ["municipality_id", "rate_band_id"]
            isOneToOne: false
            referencedRelation: "simple_national_rate_bands"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_rule_version_fkey"
            columns: ["municipality_id", "rule_version_id"]
            isOneToOne: false
            referencedRelation: "simple_national_rate_rule_versions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_effective_rate_municipality_id_taxpayer_id_fkey"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_effective_rate_municipality_id_taxpayer_id_fkey"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "simple_national_effective_rate_municipality_id_taxpayer_id_fkey"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      simple_national_rate_bands: {
        Row: {
          annex_code: string
          band_number: number
          created_at: string
          deduction_amount: number
          id: number
          iss_distribution_rate: number | null
          iss_effective_cap: number | null
          iss_fixed_effective_rate: number | null
          municipality_id: string
          nominal_rate: number
          rbt12_lower: number
          rbt12_upper: number
          rule_version_id: string
          source_snapshot: Json
        }
        Insert: {
          annex_code: string
          band_number: number
          created_at?: string
          deduction_amount?: number
          id?: number
          iss_distribution_rate?: number | null
          iss_effective_cap?: number | null
          iss_fixed_effective_rate?: number | null
          municipality_id: string
          nominal_rate: number
          rbt12_lower: number
          rbt12_upper: number
          rule_version_id: string
          source_snapshot?: Json
        }
        Update: {
          annex_code?: string
          band_number?: number
          created_at?: string
          deduction_amount?: number
          id?: number
          iss_distribution_rate?: number | null
          iss_effective_cap?: number | null
          iss_fixed_effective_rate?: number | null
          municipality_id?: string
          nominal_rate?: number
          rbt12_lower?: number
          rbt12_upper?: number
          rule_version_id?: string
          source_snapshot?: Json
        }
        Relationships: [
          {
            foreignKeyName: "simple_national_rate_bands_municipality_id_rule_version_id_fkey"
            columns: ["municipality_id", "rule_version_id"]
            isOneToOne: false
            referencedRelation: "simple_national_rate_rule_versions"
            referencedColumns: ["municipality_id", "id"]
          },
        ]
      }
      simple_national_rate_rule_versions: {
        Row: {
          code: string
          created_at: string
          formula_code: string
          id: string
          legal_source_version_id: string
          municipality_id: string
          rule_payload: Json
          rule_sha256: string
          status: string
          updated_at: string
          valid_from: string
          valid_until: string | null
          version: number
        }
        Insert: {
          code: string
          created_at?: string
          formula_code: string
          id?: string
          legal_source_version_id: string
          municipality_id: string
          rule_payload: Json
          rule_sha256: string
          status?: string
          updated_at?: string
          valid_from: string
          valid_until?: string | null
          version: number
        }
        Update: {
          code?: string
          created_at?: string
          formula_code?: string
          id?: string
          legal_source_version_id?: string
          municipality_id?: string
          rule_payload?: Json
          rule_sha256?: string
          status?: string
          updated_at?: string
          valid_from?: string
          valid_until?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "simple_national_rate_rule_ver_municipality_id_legal_source_fkey"
            columns: ["municipality_id", "legal_source_version_id"]
            isOneToOne: false
            referencedRelation: "legal_source_versions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_rate_rule_versions_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      source_systems: {
        Row: {
          code: string
          created_at: string
          data_contract_version: string | null
          id: string
          integration_id: string | null
          municipality_id: string
          name: string
          non_secret_config: Json
          source_type: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          data_contract_version?: string | null
          id?: string
          integration_id?: string | null
          municipality_id: string
          name: string
          non_secret_config?: Json
          source_type: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          data_contract_version?: string | null
          id?: string
          integration_id?: string | null
          municipality_id?: string
          name?: string
          non_secret_config?: Json
          source_type?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "source_systems_integration_fk"
            columns: ["municipality_id", "integration_id"]
            isOneToOne: false
            referencedRelation: "integrations"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "source_systems_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      taxpayer_accountant_links: {
        Row: {
          accounting_firm_id: string
          authorization_basis: string | null
          can_access_portal: boolean
          can_receive_initial_notice: boolean
          created_at: string
          delivery_status: string
          evidence_reference: string | null
          id: string
          municipality_id: string
          quarantine_reason: string | null
          relationship_status: string
          status: string
          taxpayer_id: string
          updated_at: string
          valid_from: string
          valid_until: string | null
          validation_metadata: Json
          verification_status: string
          verified_at: string | null
          verified_by: string | null
          visible_in_homologation: boolean
        }
        Insert: {
          accounting_firm_id: string
          authorization_basis?: string | null
          can_access_portal?: boolean
          can_receive_initial_notice?: boolean
          created_at?: string
          delivery_status?: string
          evidence_reference?: string | null
          id?: string
          municipality_id: string
          quarantine_reason?: string | null
          relationship_status?: string
          status?: string
          taxpayer_id: string
          updated_at?: string
          valid_from: string
          valid_until?: string | null
          validation_metadata?: Json
          verification_status?: string
          verified_at?: string | null
          verified_by?: string | null
          visible_in_homologation?: boolean
        }
        Update: {
          accounting_firm_id?: string
          authorization_basis?: string | null
          can_access_portal?: boolean
          can_receive_initial_notice?: boolean
          created_at?: string
          delivery_status?: string
          evidence_reference?: string | null
          id?: string
          municipality_id?: string
          quarantine_reason?: string | null
          relationship_status?: string
          status?: string
          taxpayer_id?: string
          updated_at?: string
          valid_from?: string
          valid_until?: string | null
          validation_metadata?: Json
          verification_status?: string
          verified_at?: string | null
          verified_by?: string | null
          visible_in_homologation?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "taxpayer_accountant_links_firm_fk"
            columns: ["municipality_id", "accounting_firm_id"]
            isOneToOne: false
            referencedRelation: "accounting_firms"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      taxpayer_fiscal_conditions: {
        Row: {
          blocks_automation: boolean
          condition_type: string
          created_at: string
          created_by: string | null
          effective_from: string
          effective_until: string | null
          id: string
          municipality_id: string
          period_end: string | null
          period_start: string | null
          reason: string | null
          source_reference: string | null
          status: string
          taxpayer_id: string
          updated_at: string
        }
        Insert: {
          blocks_automation?: boolean
          condition_type: string
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_until?: string | null
          id?: string
          municipality_id: string
          period_end?: string | null
          period_start?: string | null
          reason?: string | null
          source_reference?: string | null
          status?: string
          taxpayer_id: string
          updated_at?: string
        }
        Update: {
          blocks_automation?: boolean
          condition_type?: string
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_until?: string | null
          id?: string
          municipality_id?: string
          period_end?: string | null
          period_start?: string | null
          reason?: string | null
          source_reference?: string | null
          status?: string
          taxpayer_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "taxpayer_fiscal_conditions_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "taxpayer_fiscal_conditions_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "taxpayer_fiscal_conditions_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      taxpayer_fiscal_profiles: {
        Row: {
          activity_date_source: string | null
          activity_date_verified: boolean
          activity_started_on: string | null
          created_at: string
          municipality_id: string
          simples_opted_from: string | null
          simples_opted_until: string | null
          source_snapshot: Json
          taxpayer_id: string
          updated_at: string
        }
        Insert: {
          activity_date_source?: string | null
          activity_date_verified?: boolean
          activity_started_on?: string | null
          created_at?: string
          municipality_id: string
          simples_opted_from?: string | null
          simples_opted_until?: string | null
          source_snapshot?: Json
          taxpayer_id: string
          updated_at?: string
        }
        Update: {
          activity_date_source?: string | null
          activity_date_verified?: boolean
          activity_started_on?: string | null
          created_at?: string
          municipality_id?: string
          simples_opted_from?: string | null
          simples_opted_until?: string | null
          source_snapshot?: Json
          taxpayer_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "taxpayer_fiscal_profiles_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: true
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "taxpayer_fiscal_profiles_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: true
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "taxpayer_fiscal_profiles_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: true
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      taxpayer_user_links: {
        Row: {
          access_role: string
          created_at: string
          evidence_reference: string | null
          id: string
          municipality_id: string
          status: string
          taxpayer_id: string
          updated_at: string
          user_id: string
          valid_from: string
          valid_until: string | null
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          access_role: string
          created_at?: string
          evidence_reference?: string | null
          id?: string
          municipality_id: string
          status?: string
          taxpayer_id: string
          updated_at?: string
          user_id: string
          valid_from?: string
          valid_until?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          access_role?: string
          created_at?: string
          evidence_reference?: string | null
          id?: string
          municipality_id?: string
          status?: string
          taxpayer_id?: string
          updated_at?: string
          user_id?: string
          valid_from?: string
          valid_until?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "taxpayer_user_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "taxpayer_user_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "taxpayer_user_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      taxpayers: {
        Row: {
          created_at: string
          id: string
          legal_name: string
          municipal_registration: string
          municipality_id: string
          source_key: string | null
          source_metadata: Json
          status: string
          tax_id: string | null
          taxpayer_type: string
          trade_name: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          legal_name: string
          municipal_registration: string
          municipality_id: string
          source_key?: string | null
          source_metadata?: Json
          status?: string
          tax_id?: string | null
          taxpayer_type?: string
          trade_name?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          legal_name?: string
          municipal_registration?: string
          municipality_id?: string
          source_key?: string | null
          source_metadata?: Json
          status?: string
          tax_id?: string | null
          taxpayer_type?: string
          trade_name?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "taxpayers_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      worker_health: {
        Row: {
          dead_letter_jobs: number
          last_claimed_count: number
          last_completed_at: string | null
          last_error_at: string | null
          last_result: Json
          last_started_at: string | null
          last_success_at: string | null
          last_worker_id: string | null
          oldest_pending_age: string | null
          pending_jobs: number
          status: string
          updated_at: string
          worker_name: string
        }
        Insert: {
          dead_letter_jobs?: number
          last_claimed_count?: number
          last_completed_at?: string | null
          last_error_at?: string | null
          last_result?: Json
          last_started_at?: string | null
          last_success_at?: string | null
          last_worker_id?: string | null
          oldest_pending_age?: string | null
          pending_jobs?: number
          status?: string
          updated_at?: string
          worker_name: string
        }
        Update: {
          dead_letter_jobs?: number
          last_claimed_count?: number
          last_completed_at?: string | null
          last_error_at?: string | null
          last_result?: Json
          last_started_at?: string | null
          last_success_at?: string | null
          last_worker_id?: string | null
          oldest_pending_age?: string | null
          pending_jobs?: number
          status?: string
          updated_at?: string
          worker_name?: string
        }
        Relationships: []
      }
    }
    Views: {
      api_ai_review_queue: {
        Row: {
          body: string | null
          case_id: string | null
          case_number: string | null
          content_sha256: string | null
          created_at: string | null
          current_revision_id: string | null
          current_revision_number: number | null
          draft_id: string | null
          draft_status: string | null
          legal_name: string | null
          limitation_summary: string | null
          municipality_id: string | null
          question_id: string | null
          question_status: string | null
          updated_at: string | null
        }
        Relationships: []
      }
      api_case_dashboard: {
        Row: {
          assessed_amount: number | null
          case_number: string | null
          confidentiality: string | null
          difference_amount: number | null
          first_accessed_at: string | null
          has_pending_question: boolean | null
          id: string | null
          legal_name: string | null
          municipal_registration: string | null
          municipality_id: string | null
          opened_at: string | null
          other_credits_amount: number | null
          paid_amount: number | null
          period_end: string | null
          period_start: string | null
          status: string | null
          taxpayer_id: string | null
          trade_name: string | null
          updated_at: string | null
        }
        Relationships: []
      }
      api_divergence_queue: {
        Row: {
          assessed_amount: number | null
          block_reasons: Json | null
          detected_at: string | null
          difference_amount: number | null
          id: string | null
          last_revalidated_at: string | null
          legal_name: string | null
          municipal_registration: string | null
          municipality_id: string | null
          other_credits_amount: number | null
          paid_amount: number | null
          period_end: string | null
          period_start: string | null
          status: string | null
          taxpayer_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      api_notification_delivery: {
        Row: {
          case_id: string | null
          delivered_at: string | null
          last_error_code: string | null
          municipality_id: string | null
          notification_id: string | null
          notification_status: string | null
          prepared_at: string | null
          queued_at: string | null
          recipient_id: string | null
          recipient_sent_at: string | null
          recipient_status: string | null
          recipient_type: string | null
          sent_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notifications_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notifications_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notifications_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "notifications_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
        ]
      }
      api_worker_health: {
        Row: {
          dead_letter_jobs: number | null
          last_claimed_count: number | null
          last_completed_at: string | null
          last_error_at: string | null
          last_result: Json | null
          last_started_at: string | null
          last_success_at: string | null
          oldest_pending_age: string | null
          pending_jobs: number | null
          status: string | null
          updated_at: string | null
          worker_name: string | null
        }
        Insert: {
          dead_letter_jobs?: number | null
          last_claimed_count?: number | null
          last_completed_at?: string | null
          last_error_at?: string | null
          last_result?: Json | null
          last_started_at?: string | null
          last_success_at?: string | null
          oldest_pending_age?: string | null
          pending_jobs?: number | null
          status?: string | null
          updated_at?: string | null
          worker_name?: string | null
        }
        Update: {
          dead_letter_jobs?: number | null
          last_claimed_count?: number | null
          last_completed_at?: string | null
          last_error_at?: string | null
          last_result?: Json | null
          last_started_at?: string | null
          last_success_at?: string | null
          oldest_pending_age?: string | null
          pending_jobs?: number | null
          status?: string | null
          updated_at?: string | null
          worker_name?: string | null
        }
        Relationships: []
      }
      vw_case_portal_home: {
        Row: {
          case_id: string | null
          case_number: string | null
          case_status: string | null
          citations_snapshot: Json | null
          divergence_summary: Json | null
          execution_mode: string | null
          explanation_id: string | null
          explanation_status: string | null
          explanation_version: number | null
          legal_basis_summary: string | null
          legal_review_required: boolean | null
          municipality_id: string | null
          official_system_url: string | null
          portal_path: string | null
          prepared_at: string | null
          summary: string | null
          taxpayer_id: string | null
          taxpayer_name: string | null
          thread_id: string | null
          thread_status: string | null
          title: string | null
        }
        Relationships: []
      }
      vw_current_account_period: {
        Row: {
          competencia: string | null
          contribuinte_id: string | null
          data_base: string | null
          divergencia_conta_corrente: number | null
          elegivel: boolean | null
          municipio_id: string | null
          primeiro_vencimento: string | null
          qtd_fontes: number | null
          razao_social: string | null
          regra_versao: string | null
          saldo_em_aberto: number | null
          saldo_reportado: number | null
          status: string | null
          tax_id: string | null
          ultimo_vencimento: string | null
          valor_a_vencer: number | null
          valor_emitido: number | null
          valor_pago: number | null
          valor_sem_vencimento: number | null
          valor_vencido: number | null
        }
        Relationships: [
          {
            foreignKeyName: "current_account_entries_taxpayer_fk"
            columns: ["municipio_id", "contribuinte_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "current_account_entries_taxpayer_fk"
            columns: ["municipio_id", "contribuinte_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "current_account_entries_taxpayer_fk"
            columns: ["municipio_id", "contribuinte_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_fiscal_chat_inbox: {
        Row: {
          answered_at: string | null
          assigned_membership_id: string | null
          case_id: string | null
          case_number: string | null
          claimed_at: string | null
          created_at: string | null
          handling_mode: string | null
          municipality_id: string | null
          operational_priority: number | null
          priority: number | null
          question_id: string | null
          question_preview: string | null
          routing_confidence: number | null
          routing_reason: string | null
          sla_due_at: string | null
          status: string | null
          taxpayer_id: string | null
          taxpayer_name: string | null
          updated_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_chat_inbox_assignment_fk"
            columns: ["municipality_id", "assigned_membership_id"]
            isOneToOne: false
            referencedRelation: "municipality_memberships"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_question_fk"
            columns: ["municipality_id", "question_id"]
            isOneToOne: false
            referencedRelation: "case_questions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "fiscal_chat_inbox_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_fiscal_divergence_search: {
        Row: {
          as_of: string | null
          block_reasons: Json | null
          case_finding_count: number | null
          detection_run_id: string | null
          difference_amount: number | null
          divergence_id: string | null
          divergence_type: string | null
          execution_mode: string | null
          has_case_finding: boolean | null
          legal_name: string | null
          municipality_id: string | null
          period_end: string | null
          period_start: string | null
          priority_score: number | null
          rule_code: string | null
          rule_version_id: string | null
          rule_version_number: number | null
          rule_version_status: string | null
          status: string | null
          tax_id: string | null
          taxpayer_id: string | null
          threshold_amount: number | null
        }
        Relationships: [
          {
            foreignKeyName: "divergences_rule_fk"
            columns: ["municipality_id", "rule_version_id"]
            isOneToOne: false
            referencedRelation: "divergence_rule_versions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergences_run_fk"
            columns: ["municipality_id", "detection_run_id"]
            isOneToOne: false
            referencedRelation: "detection_runs"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_notification_recipient_candidates: {
        Row: {
          candidate_id: string | null
          candidate_status: string | null
          contact_id: string | null
          created_at: string | null
          delivery_block_reason: string | null
          external_delivery_authorized: boolean | null
          masked_email: string | null
          municipality_id: string | null
          priority: number | null
          proposed_for: string | null
          ready_pending_external_authorization: boolean | null
          recipient_type: string | null
          safe_for_delivery: boolean | null
          taxpayer_accountant_link_id: string | null
          taxpayer_id: string | null
          updated_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notification_recipient_candid_municipality_id_taxpayer_acc_fkey"
            columns: ["municipality_id", "taxpayer_accountant_link_id"]
            isOneToOne: false
            referencedRelation: "taxpayer_accountant_links"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notification_recipient_candid_municipality_id_taxpayer_acc_fkey"
            columns: ["municipality_id", "taxpayer_accountant_link_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_responsibles"
            referencedColumns: ["municipality_id", "link_id"]
          },
          {
            foreignKeyName: "notification_recipient_candid_municipality_id_taxpayer_acc_fkey"
            columns: ["municipality_id", "taxpayer_accountant_link_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_responsibilities_visible"
            referencedColumns: ["municipality_id", "link_id"]
          },
          {
            foreignKeyName: "notification_recipient_candida_municipality_id_taxpayer_id_fkey"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notification_recipient_candida_municipality_id_taxpayer_id_fkey"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "notification_recipient_candida_municipality_id_taxpayer_id_fkey"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "notification_recipient_candidat_municipality_id_contact_id_fkey"
            columns: ["municipality_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "party_contacts"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "notification_recipient_candidat_municipality_id_contact_id_fkey"
            columns: ["municipality_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "vw_quarantined_contacts"
            referencedColumns: ["municipality_id", "contact_id"]
          },
          {
            foreignKeyName: "notification_recipient_candidat_municipality_id_contact_id_fkey"
            columns: ["municipality_id", "contact_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_contacts"
            referencedColumns: ["municipality_id", "contact_id"]
          },
        ]
      }
      vw_quarantined_contacts: {
        Row: {
          accounting_firm_id: string | null
          contact_id: string | null
          contact_type: string | null
          created_at: string | null
          municipality_id: string | null
          normalized_value: string | null
          quarantine_reason: string | null
          source: string | null
          status: string | null
          taxpayer_id: string | null
          value: string | null
          visible_in_homologation: boolean | null
        }
        Insert: {
          accounting_firm_id?: string | null
          contact_id?: string | null
          contact_type?: string | null
          created_at?: string | null
          municipality_id?: string | null
          normalized_value?: string | null
          quarantine_reason?: string | null
          source?: string | null
          status?: string | null
          taxpayer_id?: string | null
          value?: string | null
          visible_in_homologation?: boolean | null
        }
        Update: {
          accounting_firm_id?: string | null
          contact_id?: string | null
          contact_type?: string | null
          created_at?: string | null
          municipality_id?: string | null
          normalized_value?: string | null
          quarantine_reason?: string | null
          source?: string | null
          status?: string | null
          taxpayer_id?: string | null
          value?: string | null
          visible_in_homologation?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "party_contacts_firm_fk"
            columns: ["municipality_id", "accounting_firm_id"]
            isOneToOne: false
            referencedRelation: "accounting_firms"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "party_contacts_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "party_contacts_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "party_contacts_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_responsaveis_ativos: {
        Row: {
          contribuinte_id: string | null
          documento_mascarado: string | null
          email_mascarado: string | null
          fonte_vinculo: string | null
          municipio_id: string | null
          nome: string | null
          responsavel_id: string | null
          tipo: string | null
          vigencia_fim: string | null
          vigencia_inicio: string | null
          vinculo_status: string | null
        }
        Relationships: [
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipio_id", "contribuinte_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipio_id", "contribuinte_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipio_id", "contribuinte_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_reusable_knowledge_articles: {
        Row: {
          allowed_placeholders: Json | null
          answer_body: string | null
          article_id: string | null
          canonical_question: string | null
          content_sha256: string | null
          divergence_scope: string | null
          intent_key: string | null
          is_test: boolean | null
          municipality_id: string | null
          published_at: string | null
          revision_id: string | null
          semantic_version: number | null
          tax_scope: string | null
          valid_from: string | null
          valid_until: string | null
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_articles_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_simple_national_cross_checks: {
        Row: {
          annex_mismatch: boolean | null
          calculated_at: string | null
          calculated_factor_r: number | null
          calculated_fs12: number | null
          calculated_rbt12: number | null
          calculation_snapshot_id: string | null
          calculation_version: string | null
          competence_month: string | null
          declared_annex_code: string | null
          declared_factor_r: number | null
          declared_fs12: number | null
          declared_rbt12: number | null
          expected_annex_code: string | null
          factor_r_difference: number | null
          is_test: boolean | null
          legal_name: string | null
          municipality_id: string | null
          pgdasd_tax_base: number | null
          rbt12_difference: number | null
          sigiss_tax_base: number | null
          status: string | null
          tax_base_difference: number | null
          tax_id: string | null
          taxpayer_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "simple_national_snapshots_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_snapshots_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "simple_national_snapshots_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_simple_national_effective_rates: {
        Row: {
          aliquota_efetiva: number | null
          aliquota_efetiva_iss: number | null
          aliquota_nominal: number | null
          anexo_declarado: string | null
          anexo_esperado: string | null
          annex_item_id: string | null
          atividade: string | null
          base_linha: number | null
          block_reasons: Json | null
          calculated_at: string | null
          calculation_snapshot_id: string | null
          competencia: string | null
          contribuinte_id: string | null
          declaration_id: string | null
          faixa: number | null
          fator_r: number | null
          fator_r_aplicavel: boolean | null
          is_current: boolean | null
          is_test: boolean | null
          municipio_id: string | null
          parcela_deduzir: number | null
          rbt12: number | null
          rbt12_mode: string | null
          result_key: string | null
          snapshot_sha256: string | null
          status: string | null
          tipo_receita: string | null
        }
        Relationships: [
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_annex_item_i_fkey"
            columns: ["municipio_id", "annex_item_id"]
            isOneToOne: false
            referencedRelation: "pgdasd_annex_items"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_calculation__fkey"
            columns: ["municipio_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "simple_national_calculation_snapshots"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_calculation__fkey"
            columns: ["municipio_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "vw_simple_national_cross_checks"
            referencedColumns: ["municipality_id", "calculation_snapshot_id"]
          },
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_calculation__fkey"
            columns: ["municipio_id", "calculation_snapshot_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_calculations"
            referencedColumns: ["municipality_id", "calculation_snapshot_id"]
          },
          {
            foreignKeyName: "simple_national_effective_rat_municipality_id_declaration__fkey"
            columns: ["municipio_id", "declaration_id"]
            isOneToOne: false
            referencedRelation: "pgdasd_declarations"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_effective_rate_municipality_id_taxpayer_id_fkey"
            columns: ["municipio_id", "contribuinte_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_effective_rate_municipality_id_taxpayer_id_fkey"
            columns: ["municipio_id", "contribuinte_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "simple_national_effective_rate_municipality_id_taxpayer_id_fkey"
            columns: ["municipio_id", "contribuinte_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_taxpayer_360_calculations: {
        Row: {
          annex_mismatch: boolean | null
          calculated_at: string | null
          calculated_factor_r: number | null
          calculated_fs12: number | null
          calculated_rbt12: number | null
          calculation_snapshot_id: string | null
          calculation_version: string | null
          competence_month: string | null
          declared_annex_code: string | null
          declared_factor_r: number | null
          declared_fs12: number | null
          declared_rbt12: number | null
          expected_annex_code: string | null
          factor_r_difference: number | null
          is_test: boolean | null
          municipality_id: string | null
          pgdasd_tax_base: number | null
          rbt12_difference: number | null
          sigiss_tax_base: number | null
          status: string | null
          tax_base_difference: number | null
          taxpayer_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "simple_national_snapshots_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "simple_national_snapshots_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "simple_national_snapshots_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_taxpayer_360_cases: {
        Row: {
          active_assignment_count: number | null
          active_assignment_roles: string[] | null
          case_id: string | null
          case_number: string | null
          closed_at: string | null
          closure_reason: string | null
          confidentiality: string | null
          current_explanation_summary: string | null
          current_explanation_title: string | null
          divergence_id: string | null
          execution_mode: string | null
          first_accessed_at: string | null
          legal_basis_summary: string | null
          legal_review_required: boolean | null
          municipality_id: string | null
          opened_at: string | null
          status: string | null
          taxpayer_id: string | null
          updated_at: string | null
          version: number | null
          waiting_question_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fiscal_cases_divergence_taxpayer_fk"
            columns: ["municipality_id", "divergence_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "api_divergence_queue"
            referencedColumns: ["municipality_id", "id", "taxpayer_id"]
          },
          {
            foreignKeyName: "fiscal_cases_divergence_taxpayer_fk"
            columns: ["municipality_id", "divergence_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "divergences"
            referencedColumns: ["municipality_id", "id", "taxpayer_id"]
          },
          {
            foreignKeyName: "fiscal_cases_divergence_taxpayer_fk"
            columns: ["municipality_id", "divergence_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_fiscal_divergence_search"
            referencedColumns: [
              "municipality_id",
              "divergence_id",
              "taxpayer_id",
            ]
          },
          {
            foreignKeyName: "fiscal_cases_divergence_taxpayer_fk"
            columns: ["municipality_id", "divergence_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_divergences"
            referencedColumns: [
              "municipality_id",
              "divergence_id",
              "taxpayer_id",
            ]
          },
        ]
      }
      vw_taxpayer_360_communications: {
        Row: {
          case_id: string | null
          channel_or_source: string | null
          communication_id: string | null
          communication_type: string | null
          created_at: string | null
          delivery_mode: string | null
          direction: string | null
          external_delivery_attempted: boolean | null
          municipality_id: string | null
          occurred_at: string | null
          status: string | null
          summary: string | null
          taxpayer_id: string | null
          title: string | null
          updated_at: string | null
          visibility: string | null
        }
        Relationships: []
      }
      vw_taxpayer_360_contacts: {
        Row: {
          contact_id: string | null
          contact_type: string | null
          created_at: string | null
          is_primary: boolean | null
          label: string | null
          municipality_id: string | null
          normalized_value: string | null
          quarantine_reason: string | null
          source: string | null
          status: string | null
          taxpayer_id: string | null
          updated_at: string | null
          valid_from: string | null
          valid_until: string | null
          value: string | null
          verified_at: string | null
          visible_in_homologation: boolean | null
        }
        Insert: {
          contact_id?: string | null
          contact_type?: string | null
          created_at?: string | null
          is_primary?: boolean | null
          label?: string | null
          municipality_id?: string | null
          normalized_value?: string | null
          quarantine_reason?: string | null
          source?: string | null
          status?: string | null
          taxpayer_id?: string | null
          updated_at?: string | null
          valid_from?: string | null
          valid_until?: string | null
          value?: string | null
          verified_at?: string | null
          visible_in_homologation?: boolean | null
        }
        Update: {
          contact_id?: string | null
          contact_type?: string | null
          created_at?: string | null
          is_primary?: boolean | null
          label?: string | null
          municipality_id?: string | null
          normalized_value?: string | null
          quarantine_reason?: string | null
          source?: string | null
          status?: string | null
          taxpayer_id?: string | null
          updated_at?: string | null
          valid_from?: string | null
          valid_until?: string | null
          value?: string | null
          verified_at?: string | null
          visible_in_homologation?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "party_contacts_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "party_contacts_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "party_contacts_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_taxpayer_360_debts: {
        Row: {
          applied_credits_derived: number | null
          competencia: string | null
          data_base: string | null
          divergencia_conta_corrente: number | null
          elegivel: boolean | null
          municipality_id: string | null
          primeiro_vencimento: string | null
          qtd_fontes: number | null
          regra_versao: string | null
          saldo_em_aberto: number | null
          saldo_reportado: number | null
          status: string | null
          taxpayer_id: string | null
          ultimo_vencimento: string | null
          valor_a_vencer: number | null
          valor_emitido: number | null
          valor_pago: number | null
          valor_sem_vencimento: number | null
          valor_vencido: number | null
        }
        Relationships: [
          {
            foreignKeyName: "current_account_entries_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "current_account_entries_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "current_account_entries_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_taxpayer_360_divergences: {
        Row: {
          as_of: string | null
          block_reasons: Json | null
          case_finding_count: number | null
          difference_amount: number | null
          divergence_id: string | null
          divergence_type: string | null
          execution_mode: string | null
          has_case_finding: boolean | null
          legal_name: string | null
          municipality_id: string | null
          period_end: string | null
          period_start: string | null
          priority_score: number | null
          rule_code: string | null
          rule_version_id: string | null
          rule_version_number: number | null
          rule_version_status: string | null
          status: string | null
          tax_id: string | null
          taxpayer_id: string | null
          threshold_amount: number | null
        }
        Relationships: [
          {
            foreignKeyName: "divergences_rule_fk"
            columns: ["municipality_id", "rule_version_id"]
            isOneToOne: false
            referencedRelation: "divergence_rule_versions"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "divergences_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_taxpayer_360_documents: {
        Row: {
          case_id: string | null
          created_at: string | null
          document_id: string | null
          malware_scan_status: string | null
          media_type: string | null
          municipality_id: string | null
          original_file_name: string | null
          sha256: string | null
          size_bytes: number | null
          status: string | null
          taxpayer_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "case_documents_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "api_case_dashboard"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_documents_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "fiscal_cases"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "case_documents_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_case_portal_home"
            referencedColumns: ["municipality_id", "case_id"]
          },
          {
            foreignKeyName: "case_documents_case_fk"
            columns: ["municipality_id", "case_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_cases"
            referencedColumns: ["municipality_id", "case_id"]
          },
        ]
      }
      vw_taxpayer_360_next_actions: {
        Row: {
          action_code: string | null
          action_label: string | null
          case_id: string | null
          created_at: string | null
          due_at: string | null
          municipality_id: string | null
          operational_priority: string | null
          priority_rank: number | null
          reason: string | null
          source_id: string | null
          source_type: string | null
          taxpayer_id: string | null
        }
        Relationships: []
      }
      vw_taxpayer_360_primary_action: {
        Row: {
          action_code: string | null
          action_label: string | null
          case_id: string | null
          created_at: string | null
          due_at: string | null
          municipality_id: string | null
          operational_priority: string | null
          priority_rank: number | null
          reason: string | null
          source_id: string | null
          source_type: string | null
          taxpayer_id: string | null
        }
        Relationships: []
      }
      vw_taxpayer_360_responsibles: {
        Row: {
          accounting_firm_id: string | null
          contact_quarantine_reason: string | null
          contact_verified_at: string | null
          delivery_status: string | null
          link_id: string | null
          link_quarantine_reason: string | null
          link_status: string | null
          link_verified_at: string | null
          masked_document: string | null
          masked_email: string | null
          municipality_id: string | null
          relationship_status: string | null
          responsible_name: string | null
          safe_for_delivery: boolean | null
          taxpayer_id: string | null
          valid_from: string | null
          valid_until: string | null
          verification_status: string | null
          visible_in_homologation: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "taxpayer_accountant_links_firm_fk"
            columns: ["municipality_id", "accounting_firm_id"]
            isOneToOne: false
            referencedRelation: "accounting_firms"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
      vw_taxpayer_360_summary: {
        Row: {
          active_case_count: number | null
          active_divergence_count: number | null
          awaiting_fiscal_case_count: number | null
          blocked_calculation_count: number | null
          blocked_divergence_count: number | null
          calculation_count: number | null
          case_count: number | null
          communication_count: number | null
          contact_count: number | null
          debt_period_count: number | null
          delivery_ready_responsible_count: number | null
          divergence_amount_total: number | null
          divergence_count: number | null
          document_count: number | null
          highest_priority_score: number | null
          incomplete_debt_period_count: number | null
          last_account_import_at: string | null
          latest_calculation_at: string | null
          latest_case_activity_at: string | null
          latest_communication_at: string | null
          latest_document_at: string | null
          legal_name: string | null
          municipal_registration: string | null
          municipality_id: string | null
          next_chat_sla_due_at: string | null
          oldest_open_due_on: string | null
          open_balance_total: number | null
          operational_attention_level: string | null
          overdue_period_count: number | null
          primary_action_case_id: string | null
          primary_action_code: string | null
          primary_action_due_at: string | null
          primary_action_label: string | null
          primary_action_priority: string | null
          primary_action_reason: string | null
          primary_action_source_id: string | null
          primary_action_source_type: string | null
          responsible_count: number | null
          source_key: string | null
          tax_id: string | null
          taxpayer_id: string | null
          taxpayer_status: string | null
          taxpayer_type: string | null
          taxpayer_updated_at: string | null
          trade_name: string | null
          verified_contact_count: number | null
          waiting_question_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "taxpayers_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_taxpayer_360_summary_base: {
        Row: {
          active_case_count: number | null
          active_divergence_count: number | null
          awaiting_fiscal_case_count: number | null
          blocked_calculation_count: number | null
          blocked_divergence_count: number | null
          calculation_count: number | null
          case_count: number | null
          debt_period_count: number | null
          divergence_amount_total: number | null
          divergence_count: number | null
          highest_priority_score: number | null
          incomplete_debt_period_count: number | null
          last_account_import_at: string | null
          latest_calculation_at: string | null
          latest_case_activity_at: string | null
          legal_name: string | null
          municipal_registration: string | null
          municipality_id: string | null
          oldest_open_due_on: string | null
          open_balance_total: number | null
          operational_attention_level: string | null
          overdue_period_count: number | null
          source_key: string | null
          tax_id: string | null
          taxpayer_id: string | null
          taxpayer_status: string | null
          taxpayer_type: string | null
          taxpayer_updated_at: string | null
          trade_name: string | null
        }
        Relationships: [
          {
            foreignKeyName: "taxpayers_municipality_id_fkey"
            columns: ["municipality_id"]
            isOneToOne: false
            referencedRelation: "municipalities"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_taxpayer_360_timeline: {
        Row: {
          case_id: string | null
          event_at: string | null
          item_type: string | null
          municipality_id: string | null
          payload: Json | null
          summary: string | null
          taxpayer_id: string | null
          title: string | null
          visibility: string | null
        }
        Relationships: []
      }
      vw_taxpayer_history: {
        Row: {
          case_id: string | null
          event_at: string | null
          item_type: string | null
          municipality_id: string | null
          payload: Json | null
          summary: string | null
          taxpayer_id: string | null
          title: string | null
          visibility: string | null
        }
        Relationships: []
      }
      vw_taxpayer_responsibilities_visible: {
        Row: {
          accounting_firm_id: string | null
          contact_quarantine_reason: string | null
          contact_status: string | null
          contact_verified_at: string | null
          delivery_status: string | null
          link_id: string | null
          link_quarantine_reason: string | null
          link_status: string | null
          link_verified_at: string | null
          masked_document: string | null
          masked_email: string | null
          municipality_id: string | null
          relationship_status: string | null
          responsible_name: string | null
          safe_for_delivery: boolean | null
          taxpayer_id: string | null
          valid_from: string | null
          valid_until: string | null
          verification_status: string | null
          visible_in_homologation: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "taxpayer_accountant_links_firm_fk"
            columns: ["municipality_id", "accounting_firm_id"]
            isOneToOne: false
            referencedRelation: "accounting_firms"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "taxpayers"
            referencedColumns: ["municipality_id", "id"]
          },
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
          {
            foreignKeyName: "taxpayer_accountant_links_taxpayer_fk"
            columns: ["municipality_id", "taxpayer_id"]
            isOneToOne: false
            referencedRelation: "vw_taxpayer_360_summary_base"
            referencedColumns: ["municipality_id", "taxpayer_id"]
          },
        ]
      }
    }
    Functions: {
      ia_activate_ai_prompt: {
        Args: { p_confirmation: string; p_prompt_version_id: string }
        Returns: undefined
      }
      ia_activate_notification_template: {
        Args: { p_confirmation: string; p_template_version_id: string }
        Returns: undefined
      }
      ia_activate_policy_version: {
        Args: { p_confirmation: string; p_policy_version_id: string }
        Returns: undefined
      }
      ia_activate_rule_version: {
        Args: { p_confirmation: string; p_rule_version_id: string }
        Returns: undefined
      }
      ia_approve_case_opening_batch: {
        Args: { p_approval_notes?: string; p_batch_id: string }
        Returns: number
      }
      ia_block_job: {
        Args: {
          p_job_id: number
          p_reason_code: string
          p_safe_detail?: string
          p_worker_id: string
        }
        Returns: undefined
      }
      ia_bootstrap_municipality_admin: {
        Args: { p_municipality_slug: string; p_user_id: string }
        Returns: string
      }
      ia_claim_case_question: {
        Args: {
          p_expected_membership_id: string
          p_expected_municipality_id: string
          p_handling_mode?: string
          p_question_id: string
        }
        Returns: string
      }
      ia_claim_jobs: {
        Args: {
          p_lease_seconds?: number
          p_limit?: number
          p_worker_id: string
        }
        Returns: {
          aggregate_id: string
          aggregate_type: string
          attempt_number: number
          correlation_id: string
          job_id: number
          job_type: string
          municipality_id: string
          payload: Json
        }[]
      }
      ia_complete_job: {
        Args: { p_job_id: number; p_worker_id: string }
        Returns: undefined
      }
      ia_create_case_opening_batch: {
        Args: {
          p_assigned_membership_id?: string
          p_detection_run_id: string
          p_divergence_ids: string[]
          p_idempotency_key: string
        }
        Returns: string
      }
      ia_edit_ai_draft: {
        Args: { p_body: string; p_change_note?: string; p_draft_id: string }
        Returns: string
      }
      ia_execute_homologation_case_test: {
        Args: { p_divergence_id: string }
        Returns: Json
      }
      ia_fail_job: {
        Args: {
          p_error_code: string
          p_job_id: number
          p_safe_error_detail?: string
          p_worker_id: string
        }
        Returns: string
      }
      ia_get_ai_job_context: { Args: { p_job_id: number }; Returns: Json }
      ia_get_notification_job_context: {
        Args: { p_job_id: number }
        Returns: Json
      }
      ia_list_my_context: { Args: never; Returns: Json }
      ia_mark_ai_job_blocked: {
        Args: { p_job_id: number; p_reason: string }
        Returns: undefined
      }
      ia_mark_email_delivery_attempted: {
        Args: { p_job_id: number; p_worker_id: string }
        Returns: undefined
      }
      ia_mark_notification_job_blocked: {
        Args: { p_job_id: number; p_reason: string }
        Returns: undefined
      }
      ia_preview_initial_notice: {
        Args: { p_case_id: string; p_template_version_id?: string }
        Returns: Json
      }
      ia_process_case_batch_item: {
        Args: { p_batch_item_id: string }
        Returns: string
      }
      ia_publish_approved_response: {
        Args: { p_client_request_id: string; p_draft_id: string }
        Returns: string
      }
      ia_publish_knowledge_article: {
        Args: { p_article_id: string; p_confirmation: string }
        Returns: undefined
      }
      ia_publish_knowledge_release: {
        Args: { p_confirmation: string; p_release_id: string }
        Returns: undefined
      }
      ia_publish_legal_source_version: {
        Args: { p_confirmation: string; p_source_version_id: string }
        Returns: undefined
      }
      ia_publish_manual_response: {
        Args: {
          p_body: string
          p_client_request_id: string
          p_question_id: string
        }
        Returns: string
      }
      ia_rebuild_simple_national_effective_rates: {
        Args: {
          p_is_test?: boolean
          p_municipality_id: string
          p_period_end: string
          p_period_start: string
        }
        Returns: number
      }
      ia_rebuild_simple_national_snapshots: {
        Args: {
          p_is_test?: boolean
          p_municipality_id: string
          p_period_end: string
          p_period_start: string
        }
        Returns: number
      }
      ia_record_email_delivery: {
        Args: {
          p_job_id: number
          p_next_attempt_at?: string
          p_provider_code: string
          p_provider_message_id: string
          p_response_code?: number
          p_safe_error_code?: string
          p_safe_error_detail?: string
          p_status: string
        }
        Returns: undefined
      }
      ia_record_worker_heartbeat: {
        Args: {
          p_claimed_count?: number
          p_result?: Json
          p_stage: string
          p_worker_id: string
          p_worker_name: string
        }
        Returns: undefined
      }
      ia_review_ai_draft: {
        Args: {
          p_decision: string
          p_draft_id: string
          p_notes?: string
          p_revision_id: string
        }
        Returns: string
      }
      ia_review_knowledge_article: {
        Args: {
          p_article_id: string
          p_decision: string
          p_notes?: string
          p_revision_id: string
        }
        Returns: string
      }
      ia_route_case_question_from_knowledge: {
        Args: { p_question_id: string }
        Returns: Json
      }
      ia_run_backend_validation: {
        Args: { p_municipality_id: string }
        Returns: string
      }
      ia_run_current_account_detection: {
        Args: {
          p_as_of: string
          p_idempotency_key: string
          p_import_batch_id?: string
          p_municipality_id: string
          p_rule_version_id: string
        }
        Returns: string
      }
      ia_run_homologation_current_account_detection: {
        Args: {
          p_as_of: string
          p_idempotency_key: string
          p_import_batch_id?: string
          p_municipality_id: string
          p_rule_version_id: string
        }
        Returns: string
      }
      ia_run_simple_national_detection: {
        Args: {
          p_as_of: string
          p_idempotency_key: string
          p_import_batch_id?: string
          p_municipality_id: string
          p_rule_version_id: string
          p_test_mode?: boolean
        }
        Returns: string
      }
      ia_search_fiscal: {
        Args: {
          p_limit?: number
          p_municipality_id: string
          p_offset?: number
          p_query: string
        }
        Returns: Json
      }
      ia_set_integration_operational_state: {
        Args: {
          p_integration_id: string
          p_non_secret_config: Json
          p_secret_reference?: string
          p_status: string
        }
        Returns: undefined
      }
      ia_store_ai_draft: {
        Args: {
          p_ai_run_id: string
          p_body: string
          p_citations: Json
          p_input_tokens?: number
          p_job_id: number
          p_latency_ms?: number
          p_limitation_summary?: string
          p_output_tokens?: number
          p_provider_response_id?: string
        }
        Returns: string
      }
      ia_submit_case_question: {
        Args: { p_body: string; p_case_id: string; p_client_request_id: string }
        Returns: string
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
