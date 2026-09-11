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
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      addon_orders: {
        Row: {
          addon_product_id: string
          cancelled_at: string | null
          created_at: string
          currency: string
          expires_on: string | null
          id: string
          idempotency_key: string | null
          initial_session_id: string | null
          member_id: string
          payment_id: string | null
          quantity: number
          sale_request: Json | null
          sale_snapshot: Json | null
          sessions_total: number | null
          sessions_used: number
          sold_at: string | null
          sold_by_staff_id: string | null
          starts_on: string | null
          status: Database["public"]["Enums"]["addon_order_status"]
          tenant_id: string
          total_paise: number
          trainer_staff_id: string | null
          unit_price_paise: number
          updated_at: string
        }
        Insert: {
          addon_product_id: string
          cancelled_at?: string | null
          created_at?: string
          currency?: string
          expires_on?: string | null
          id?: string
          idempotency_key?: string | null
          initial_session_id?: string | null
          member_id: string
          payment_id?: string | null
          quantity?: number
          sale_request?: Json | null
          sale_snapshot?: Json | null
          sessions_total?: number | null
          sessions_used?: number
          sold_at?: string | null
          sold_by_staff_id?: string | null
          starts_on?: string | null
          status?: Database["public"]["Enums"]["addon_order_status"]
          tenant_id: string
          total_paise: number
          trainer_staff_id?: string | null
          unit_price_paise: number
          updated_at?: string
        }
        Update: {
          addon_product_id?: string
          cancelled_at?: string | null
          created_at?: string
          currency?: string
          expires_on?: string | null
          id?: string
          idempotency_key?: string | null
          initial_session_id?: string | null
          member_id?: string
          payment_id?: string | null
          quantity?: number
          sale_request?: Json | null
          sale_snapshot?: Json | null
          sessions_total?: number | null
          sessions_used?: number
          sold_at?: string | null
          sold_by_staff_id?: string | null
          starts_on?: string | null
          status?: Database["public"]["Enums"]["addon_order_status"]
          tenant_id?: string
          total_paise?: number
          trainer_staff_id?: string | null
          unit_price_paise?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "addon_orders_addon_product_id_fkey"
            columns: ["tenant_id", "addon_product_id"]
            isOneToOne: false
            referencedRelation: "addon_products"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "addon_orders_member_id_fkey"
            columns: ["tenant_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "addon_orders_payment_id_fkey"
            columns: ["tenant_id", "payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "addon_orders_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "addon_orders_tenant_id_initial_session_id_fkey"
            columns: ["tenant_id", "initial_session_id"]
            isOneToOne: false
            referencedRelation: "pt_sessions"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "addon_orders_tenant_id_sold_by_staff_id_fkey"
            columns: ["tenant_id", "sold_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "addon_orders_trainer_staff_id_fkey"
            columns: ["tenant_id", "trainer_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
        ]
      }
      addon_products: {
        Row: {
          cancellation_terms: string | null
          created_at: string
          currency: string
          description: string | null
          gst_rate_bp: number
          id: string
          is_active: boolean
          kind: Database["public"]["Enums"]["addon_kind"]
          name: string
          price_paise: number
          quote_version: string
          session_count: number | null
          sort_order: number
          stock_quantity: number | null
          tenant_id: string
          trainer_qualification: string | null
          trainer_staff_id: string | null
          updated_at: string
          validity_days: number | null
        }
        Insert: {
          cancellation_terms?: string | null
          created_at?: string
          currency?: string
          description?: string | null
          gst_rate_bp?: number
          id?: string
          is_active?: boolean
          kind: Database["public"]["Enums"]["addon_kind"]
          name: string
          price_paise: number
          quote_version: string
          session_count?: number | null
          sort_order?: number
          stock_quantity?: number | null
          tenant_id: string
          trainer_qualification?: string | null
          trainer_staff_id?: string | null
          updated_at?: string
          validity_days?: number | null
        }
        Update: {
          cancellation_terms?: string | null
          created_at?: string
          currency?: string
          description?: string | null
          gst_rate_bp?: number
          id?: string
          is_active?: boolean
          kind?: Database["public"]["Enums"]["addon_kind"]
          name?: string
          price_paise?: number
          quote_version?: string
          session_count?: number | null
          sort_order?: number
          stock_quantity?: number | null
          tenant_id?: string
          trainer_qualification?: string | null
          trainer_staff_id?: string | null
          updated_at?: string
          validity_days?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "addon_products_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "addon_products_trainer_staff_id_fkey"
            columns: ["tenant_id", "trainer_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
        ]
      }
      attendance: {
        Row: {
          assist_reason: string | null
          assisted_by_staff_id: string | null
          branch_id: string
          checked_in_at: string
          checked_out_at: string | null
          client_event_id: string | null
          created_at: string
          id: string
          member_id: string
          membership_id: string | null
          offline_recorded_at: string | null
          qr_session_id: string | null
          replayed_at: string | null
          source: Database["public"]["Enums"]["attendance_source"]
          tenant_id: string
        }
        Insert: {
          assist_reason?: string | null
          assisted_by_staff_id?: string | null
          branch_id: string
          checked_in_at?: string
          checked_out_at?: string | null
          client_event_id?: string | null
          created_at?: string
          id?: string
          member_id: string
          membership_id?: string | null
          offline_recorded_at?: string | null
          qr_session_id?: string | null
          replayed_at?: string | null
          source: Database["public"]["Enums"]["attendance_source"]
          tenant_id: string
        }
        Update: {
          assist_reason?: string | null
          assisted_by_staff_id?: string | null
          branch_id?: string
          checked_in_at?: string
          checked_out_at?: string | null
          client_event_id?: string | null
          created_at?: string
          id?: string
          member_id?: string
          membership_id?: string | null
          offline_recorded_at?: string | null
          qr_session_id?: string | null
          replayed_at?: string | null
          source?: Database["public"]["Enums"]["attendance_source"]
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "attendance_assisted_by_staff_id_fkey"
            columns: ["tenant_id", "assisted_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "attendance_branch_id_fkey"
            columns: ["tenant_id", "branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "attendance_member_id_fkey"
            columns: ["tenant_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "attendance_membership_id_fkey"
            columns: ["tenant_id", "membership_id"]
            isOneToOne: false
            referencedRelation: "memberships"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "attendance_qr_session_id_fkey"
            columns: ["tenant_id", "qr_session_id"]
            isOneToOne: false
            referencedRelation: "qr_sessions"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "attendance_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      attendance_corrections: {
        Row: {
          after: Json
          attendance_id: string
          before: Json
          corrected_by_staff_id: string
          created_at: string
          id: string
          reason: string
          tenant_id: string
        }
        Insert: {
          after: Json
          attendance_id: string
          before: Json
          corrected_by_staff_id: string
          created_at?: string
          id?: string
          reason: string
          tenant_id: string
        }
        Update: {
          after?: Json
          attendance_id?: string
          before?: Json
          corrected_by_staff_id?: string
          created_at?: string
          id?: string
          reason?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "attendance_corrections_attendance_id_fkey"
            columns: ["tenant_id", "attendance_id"]
            isOneToOne: false
            referencedRelation: "attendance"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "attendance_corrections_corrected_by_staff_id_fkey"
            columns: ["tenant_id", "corrected_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "attendance_corrections_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_log: {
        Row: {
          action: string
          actor_role: Database["public"]["Enums"]["app_role"] | null
          actor_user_id: string | null
          after: Json | null
          before: Json | null
          created_at: string
          id: string
          impersonation_session_id: string | null
          occurred_at: string
          reason: string | null
          record_id: string | null
          record_type: string
          tenant_id: string | null
        }
        Insert: {
          action: string
          actor_role?: Database["public"]["Enums"]["app_role"] | null
          actor_user_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          id?: string
          impersonation_session_id?: string | null
          occurred_at?: string
          reason?: string | null
          record_id?: string | null
          record_type: string
          tenant_id?: string | null
        }
        Update: {
          action?: string
          actor_role?: Database["public"]["Enums"]["app_role"] | null
          actor_user_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          id?: string
          impersonation_session_id?: string | null
          occurred_at?: string
          reason?: string | null
          record_id?: string | null
          record_type?: string
          tenant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_impersonation_session_id_fkey"
            columns: ["impersonation_session_id"]
            isOneToOne: false
            referencedRelation: "impersonation_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_log_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      branches: {
        Row: {
          address: string | null
          created_at: string
          id: string
          is_default: boolean
          name: string
          tenant_id: string
          timezone: string | null
          updated_at: string
        }
        Insert: {
          address?: string | null
          created_at?: string
          id?: string
          is_default?: boolean
          name: string
          tenant_id: string
          timezone?: string | null
          updated_at?: string
        }
        Update: {
          address?: string | null
          created_at?: string
          id?: string
          is_default?: boolean
          name?: string
          tenant_id?: string
          timezone?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "branches_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      consents: {
        Row: {
          created_at: string
          granted: boolean
          id: string
          member_id: string
          purpose: Database["public"]["Enums"]["consent_purpose"]
          recorded_at: string
          recorded_by_staff_id: string | null
          source: string
          tenant_id: string
          version: string
        }
        Insert: {
          created_at?: string
          granted: boolean
          id?: string
          member_id: string
          purpose: Database["public"]["Enums"]["consent_purpose"]
          recorded_at?: string
          recorded_by_staff_id?: string | null
          source: string
          tenant_id: string
          version: string
        }
        Update: {
          created_at?: string
          granted?: boolean
          id?: string
          member_id?: string
          purpose?: Database["public"]["Enums"]["consent_purpose"]
          recorded_at?: string
          recorded_by_staff_id?: string | null
          source?: string
          tenant_id?: string
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "consents_member_id_fkey"
            columns: ["tenant_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "consents_recorded_by_staff_id_fkey"
            columns: ["tenant_id", "recorded_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "consents_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      coupons: {
        Row: {
          applies_to_addons: boolean
          applies_to_plans: boolean
          code: string
          created_at: string
          currency: string
          flat_paise: number | null
          id: string
          is_active: boolean
          max_redemptions: number | null
          percent_bp: number | null
          redeemed_count: number
          tenant_id: string
          updated_at: string
          valid_from: string | null
          valid_until: string | null
        }
        Insert: {
          applies_to_addons?: boolean
          applies_to_plans?: boolean
          code: string
          created_at?: string
          currency?: string
          flat_paise?: number | null
          id?: string
          is_active?: boolean
          max_redemptions?: number | null
          percent_bp?: number | null
          redeemed_count?: number
          tenant_id: string
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Update: {
          applies_to_addons?: boolean
          applies_to_plans?: boolean
          code?: string
          created_at?: string
          currency?: string
          flat_paise?: number | null
          id?: string
          is_active?: boolean
          max_redemptions?: number | null
          percent_bp?: number | null
          redeemed_count?: number
          tenant_id?: string
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "coupons_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      document_counters: {
        Row: {
          created_at: string
          financial_year: string
          kind: string
          next_number: number
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          financial_year: string
          kind: string
          next_number?: number
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          financial_year?: string
          kind?: string
          next_number?: number
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_counters_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      follow_ups: {
        Row: {
          case_id: string
          channel: Database["public"]["Enums"]["contact_channel"]
          corrects_follow_up_id: string | null
          created_at: string
          id: string
          next_action: string | null
          next_follow_up_at: string | null
          notes: string | null
          outcome: Database["public"]["Enums"]["follow_up_outcome"]
          staff_id: string
          tenant_id: string
        }
        Insert: {
          case_id: string
          channel: Database["public"]["Enums"]["contact_channel"]
          corrects_follow_up_id?: string | null
          created_at?: string
          id?: string
          next_action?: string | null
          next_follow_up_at?: string | null
          notes?: string | null
          outcome: Database["public"]["Enums"]["follow_up_outcome"]
          staff_id: string
          tenant_id: string
        }
        Update: {
          case_id?: string
          channel?: Database["public"]["Enums"]["contact_channel"]
          corrects_follow_up_id?: string | null
          created_at?: string
          id?: string
          next_action?: string | null
          next_follow_up_at?: string | null
          notes?: string | null
          outcome?: Database["public"]["Enums"]["follow_up_outcome"]
          staff_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "follow_ups_case_id_fkey"
            columns: ["tenant_id", "case_id"]
            isOneToOne: false
            referencedRelation: "no_show_cases"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "follow_ups_case_id_fkey"
            columns: ["tenant_id", "case_id"]
            isOneToOne: false
            referencedRelation: "red_list_cases"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "follow_ups_corrects_follow_up_id_fkey"
            columns: ["tenant_id", "corrects_follow_up_id"]
            isOneToOne: false
            referencedRelation: "follow_ups"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "follow_ups_staff_id_fkey"
            columns: ["tenant_id", "staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "follow_ups_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      impersonation_sessions: {
        Row: {
          actor_user_id: string
          created_at: string
          ended_at: string | null
          expires_at: string
          id: string
          reason: string
          started_at: string
          tenant_id: string
        }
        Insert: {
          actor_user_id: string
          created_at?: string
          ended_at?: string | null
          expires_at: string
          id?: string
          reason: string
          started_at?: string
          tenant_id: string
        }
        Update: {
          actor_user_id?: string
          created_at?: string
          ended_at?: string | null
          expires_at?: string
          id?: string
          reason?: string
          started_at?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "impersonation_sessions_actor_user_id_fkey"
            columns: ["actor_user_id"]
            isOneToOne: false
            referencedRelation: "platform_users"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "impersonation_sessions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      invoices: {
        Row: {
          buyer_gstin: string | null
          buyer_name: string
          cgst_paise: number
          created_at: string
          currency: string
          financial_year: string
          id: string
          igst_paise: number
          invoice_number: string
          issued_at: string
          line_items: Json
          payment_id: string
          pdf_url: string | null
          place_of_supply: string | null
          seller_gstin: string | null
          sgst_paise: number
          taxable_paise: number
          tenant_id: string
          total_paise: number
          updated_at: string
        }
        Insert: {
          buyer_gstin?: string | null
          buyer_name: string
          cgst_paise?: number
          created_at?: string
          currency?: string
          financial_year: string
          id?: string
          igst_paise?: number
          invoice_number: string
          issued_at?: string
          line_items?: Json
          payment_id: string
          pdf_url?: string | null
          place_of_supply?: string | null
          seller_gstin?: string | null
          sgst_paise?: number
          taxable_paise: number
          tenant_id: string
          total_paise: number
          updated_at?: string
        }
        Update: {
          buyer_gstin?: string | null
          buyer_name?: string
          cgst_paise?: number
          created_at?: string
          currency?: string
          financial_year?: string
          id?: string
          igst_paise?: number
          invoice_number?: string
          issued_at?: string
          line_items?: Json
          payment_id?: string
          pdf_url?: string | null
          place_of_supply?: string | null
          seller_gstin?: string | null
          sgst_paise?: number
          taxable_paise?: number
          tenant_id?: string
          total_paise?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoices_payment_id_fkey"
            columns: ["tenant_id", "payment_id"]
            isOneToOne: true
            referencedRelation: "payments"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "invoices_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      leads: {
        Row: {
          assigned_to_staff_id: string | null
          branch_id: string
          conversion_request_facts: Json | null
          conversion_request_key: string | null
          converted_at: string | null
          converted_member_id: string | null
          created_at: string
          created_by_staff_id: string | null
          creation_request_facts: Json | null
          creation_request_key: string | null
          email: string | null
          full_name: string
          id: string
          lost_reason: string | null
          notes: string | null
          phone: string
          revision: string
          source: Database["public"]["Enums"]["lead_source"]
          stage: Database["public"]["Enums"]["lead_stage"]
          tenant_id: string
          trial_at: string | null
          updated_at: string
        }
        Insert: {
          assigned_to_staff_id?: string | null
          branch_id: string
          conversion_request_facts?: Json | null
          conversion_request_key?: string | null
          converted_at?: string | null
          converted_member_id?: string | null
          created_at?: string
          created_by_staff_id?: string | null
          creation_request_facts?: Json | null
          creation_request_key?: string | null
          email?: string | null
          full_name: string
          id?: string
          lost_reason?: string | null
          notes?: string | null
          phone: string
          revision?: string
          source: Database["public"]["Enums"]["lead_source"]
          stage?: Database["public"]["Enums"]["lead_stage"]
          tenant_id: string
          trial_at?: string | null
          updated_at?: string
        }
        Update: {
          assigned_to_staff_id?: string | null
          branch_id?: string
          conversion_request_facts?: Json | null
          conversion_request_key?: string | null
          converted_at?: string | null
          converted_member_id?: string | null
          created_at?: string
          created_by_staff_id?: string | null
          creation_request_facts?: Json | null
          creation_request_key?: string | null
          email?: string | null
          full_name?: string
          id?: string
          lost_reason?: string | null
          notes?: string | null
          phone?: string
          revision?: string
          source?: Database["public"]["Enums"]["lead_source"]
          stage?: Database["public"]["Enums"]["lead_stage"]
          tenant_id?: string
          trial_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "leads_assigned_to_staff_id_fkey"
            columns: ["tenant_id", "assigned_to_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "leads_branch_id_fkey"
            columns: ["tenant_id", "branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "leads_converted_member_id_fkey"
            columns: ["tenant_id", "converted_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "leads_tenant_id_created_by_staff_id_fkey"
            columns: ["tenant_id", "created_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "leads_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      member_devices: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          last_seen_at: string
          member_id: string
          platform: string
          push_token: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          last_seen_at?: string
          member_id: string
          platform: string
          push_token: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          last_seen_at?: string
          member_id?: string
          platform?: string
          push_token?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "member_devices_member_id_fkey"
            columns: ["tenant_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "member_devices_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      member_imports: {
        Row: {
          branch_id: string | null
          candidate_payload_sha256: string | null
          column_mapping: Json
          created_at: string
          duplicate_count: number | null
          effective_on: string | null
          error_report: Json | null
          file_name: string
          file_sha256: string | null
          id: string
          imported_count: number | null
          parser_contract: string | null
          phone_default_country: string | null
          request_key: string | null
          row_count: number | null
          status: Database["public"]["Enums"]["import_status"]
          tenant_id: string
          updated_at: string
          uploaded_by_staff_id: string
          uploaded_by_user_id: string | null
        }
        Insert: {
          branch_id?: string | null
          candidate_payload_sha256?: string | null
          column_mapping: Json
          created_at?: string
          duplicate_count?: number | null
          effective_on?: string | null
          error_report?: Json | null
          file_name: string
          file_sha256?: string | null
          id?: string
          imported_count?: number | null
          parser_contract?: string | null
          phone_default_country?: string | null
          request_key?: string | null
          row_count?: number | null
          status?: Database["public"]["Enums"]["import_status"]
          tenant_id: string
          updated_at?: string
          uploaded_by_staff_id: string
          uploaded_by_user_id?: string | null
        }
        Update: {
          branch_id?: string | null
          candidate_payload_sha256?: string | null
          column_mapping?: Json
          created_at?: string
          duplicate_count?: number | null
          effective_on?: string | null
          error_report?: Json | null
          file_name?: string
          file_sha256?: string | null
          id?: string
          imported_count?: number | null
          parser_contract?: string | null
          phone_default_country?: string | null
          request_key?: string | null
          row_count?: number | null
          status?: Database["public"]["Enums"]["import_status"]
          tenant_id?: string
          updated_at?: string
          uploaded_by_staff_id?: string
          uploaded_by_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "member_imports_tenant_id_branch_id_fkey"
            columns: ["tenant_id", "branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "member_imports_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_imports_uploaded_by_staff_id_fkey"
            columns: ["tenant_id", "uploaded_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
        ]
      }
      members: {
        Row: {
          branch_id: string
          created_at: string
          date_of_birth: string | null
          email: string | null
          erased_at: string | null
          full_name: string
          gender: string | null
          id: string
          joined_on: string
          member_code: string | null
          motivation_push_enabled: boolean
          notes: string | null
          phone: string
          photo_url: string | null
          rest_days: number[]
          status: Database["public"]["Enums"]["member_status"]
          tenant_id: string
          updated_at: string
          user_id: string | null
          weekly_goal_visits: number | null
        }
        Insert: {
          branch_id: string
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          erased_at?: string | null
          full_name: string
          gender?: string | null
          id?: string
          joined_on?: string
          member_code?: string | null
          motivation_push_enabled?: boolean
          notes?: string | null
          phone: string
          photo_url?: string | null
          rest_days?: number[]
          status?: Database["public"]["Enums"]["member_status"]
          tenant_id: string
          updated_at?: string
          user_id?: string | null
          weekly_goal_visits?: number | null
        }
        Update: {
          branch_id?: string
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          erased_at?: string | null
          full_name?: string
          gender?: string | null
          id?: string
          joined_on?: string
          member_code?: string | null
          motivation_push_enabled?: boolean
          notes?: string | null
          phone?: string
          photo_url?: string | null
          rest_days?: number[]
          status?: Database["public"]["Enums"]["member_status"]
          tenant_id?: string
          updated_at?: string
          user_id?: string | null
          weekly_goal_visits?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "members_branch_id_fkey"
            columns: ["tenant_id", "branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "members_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      membership_pauses: {
        Row: {
          approved_at: string | null
          approved_by_staff_id: string | null
          created_at: string
          ends_on: string
          id: string
          membership_id: string
          reason: string
          rejected_at: string | null
          requested_by_staff_id: string | null
          starts_on: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by_staff_id?: string | null
          created_at?: string
          ends_on: string
          id?: string
          membership_id: string
          reason: string
          rejected_at?: string | null
          requested_by_staff_id?: string | null
          starts_on: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by_staff_id?: string | null
          created_at?: string
          ends_on?: string
          id?: string
          membership_id?: string
          reason?: string
          rejected_at?: string | null
          requested_by_staff_id?: string | null
          starts_on?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "membership_pauses_approved_by_staff_id_fkey"
            columns: ["tenant_id", "approved_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "membership_pauses_membership_id_fkey"
            columns: ["tenant_id", "membership_id"]
            isOneToOne: false
            referencedRelation: "memberships"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "membership_pauses_requested_by_staff_id_fkey"
            columns: ["tenant_id", "requested_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "membership_pauses_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      memberships: {
        Row: {
          activated_at: string | null
          cancel_reason: string | null
          cancelled_at: string | null
          coupon_id: string | null
          created_at: string
          currency: string
          discount_paise: number
          duration_days: number
          ends_on: string | null
          id: string
          member_id: string
          periods_granted: number
          plan_id: string
          price_paise: number
          renewal_of_membership_id: string | null
          starts_on: string | null
          status: Database["public"]["Enums"]["membership_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          activated_at?: string | null
          cancel_reason?: string | null
          cancelled_at?: string | null
          coupon_id?: string | null
          created_at?: string
          currency?: string
          discount_paise?: number
          duration_days?: number
          ends_on?: string | null
          id?: string
          member_id: string
          periods_granted?: number
          plan_id: string
          price_paise: number
          renewal_of_membership_id?: string | null
          starts_on?: string | null
          status?: Database["public"]["Enums"]["membership_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          activated_at?: string | null
          cancel_reason?: string | null
          cancelled_at?: string | null
          coupon_id?: string | null
          created_at?: string
          currency?: string
          discount_paise?: number
          duration_days?: number
          ends_on?: string | null
          id?: string
          member_id?: string
          periods_granted?: number
          plan_id?: string
          price_paise?: number
          renewal_of_membership_id?: string | null
          starts_on?: string | null
          status?: Database["public"]["Enums"]["membership_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "memberships_coupon_id_fkey"
            columns: ["tenant_id", "coupon_id"]
            isOneToOne: false
            referencedRelation: "coupons"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "memberships_member_id_fkey"
            columns: ["tenant_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "memberships_plan_id_fkey"
            columns: ["tenant_id", "plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "memberships_renewal_of_membership_id_fkey"
            columns: ["tenant_id", "renewal_of_membership_id"]
            isOneToOne: false
            referencedRelation: "memberships"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "memberships_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      message_templates: {
        Row: {
          body: string
          channel: Database["public"]["Enums"]["notification_channel"]
          created_at: string
          id: string
          is_active: boolean
          key: string
          locale: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          body: string
          channel: Database["public"]["Enums"]["notification_channel"]
          created_at?: string
          id?: string
          is_active?: boolean
          key: string
          locale?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          body?: string
          channel?: Database["public"]["Enums"]["notification_channel"]
          created_at?: string
          id?: string
          is_active?: boolean
          key?: string
          locale?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_templates_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      messaging_wallet_ledger: {
        Row: {
          created_at: string
          delta_credits: number
          id: string
          notification_id: string | null
          reason: string
          tenant_id: string
        }
        Insert: {
          created_at?: string
          delta_credits: number
          id?: string
          notification_id?: string | null
          reason: string
          tenant_id: string
        }
        Update: {
          created_at?: string
          delta_credits?: number
          id?: string
          notification_id?: string | null
          reason?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "messaging_wallet_ledger_notification_id_fkey"
            columns: ["tenant_id", "notification_id"]
            isOneToOne: false
            referencedRelation: "notifications"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "messaging_wallet_ledger_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      messaging_wallets: {
        Row: {
          balance_credits: number
          created_at: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          balance_credits?: number
          created_at?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          balance_credits?: number
          created_at?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "messaging_wallets_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      no_show_cases: {
        Row: {
          absent_days_at_open: number
          assigned_to_staff_id: string | null
          closed_at: string | null
          contacted_at: string | null
          created_at: string
          id: string
          last_attended_on: string | null
          member_id: string
          next_follow_up_at: string | null
          opened_on: string
          returned_at: string | null
          status: Database["public"]["Enums"]["no_show_case_status"]
          tenant_id: string
          threshold_days: number
          updated_at: string
        }
        Insert: {
          absent_days_at_open: number
          assigned_to_staff_id?: string | null
          closed_at?: string | null
          contacted_at?: string | null
          created_at?: string
          id?: string
          last_attended_on?: string | null
          member_id: string
          next_follow_up_at?: string | null
          opened_on?: string
          returned_at?: string | null
          status?: Database["public"]["Enums"]["no_show_case_status"]
          tenant_id: string
          threshold_days: number
          updated_at?: string
        }
        Update: {
          absent_days_at_open?: number
          assigned_to_staff_id?: string | null
          closed_at?: string | null
          contacted_at?: string | null
          created_at?: string
          id?: string
          last_attended_on?: string | null
          member_id?: string
          next_follow_up_at?: string | null
          opened_on?: string
          returned_at?: string | null
          status?: Database["public"]["Enums"]["no_show_case_status"]
          tenant_id?: string
          threshold_days?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "no_show_cases_assigned_to_staff_id_fkey"
            columns: ["tenant_id", "assigned_to_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "no_show_cases_member_id_fkey"
            columns: ["tenant_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "no_show_cases_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          channel: Database["public"]["Enums"]["notification_channel"]
          clicked_at: string | null
          converted_at: string | null
          created_at: string
          dedupe_key: string | null
          delivered_at: string | null
          failed_reason: string | null
          id: string
          member_id: string
          payload: Json
          related_id: string | null
          related_type: string | null
          scheduled_for: string
          sent_at: string | null
          status: Database["public"]["Enums"]["notification_status"]
          template_key: string | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          channel: Database["public"]["Enums"]["notification_channel"]
          clicked_at?: string | null
          converted_at?: string | null
          created_at?: string
          dedupe_key?: string | null
          delivered_at?: string | null
          failed_reason?: string | null
          id?: string
          member_id: string
          payload?: Json
          related_id?: string | null
          related_type?: string | null
          scheduled_for?: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          template_key?: string | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          channel?: Database["public"]["Enums"]["notification_channel"]
          clicked_at?: string | null
          converted_at?: string | null
          created_at?: string
          dedupe_key?: string | null
          delivered_at?: string | null
          failed_reason?: string | null
          id?: string
          member_id?: string
          payload?: Json
          related_id?: string | null
          related_type?: string | null
          scheduled_for?: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          template_key?: string | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_member_id_fkey"
            columns: ["tenant_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "notifications_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_holidays: {
        Row: {
          created_at: string
          holiday_on: string
          id: string
          name: string | null
          tenant_id: string
        }
        Insert: {
          created_at?: string
          holiday_on: string
          id?: string
          name?: string | null
          tenant_id: string
        }
        Update: {
          created_at?: string
          holiday_on?: string
          id?: string
          name?: string | null
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_holidays_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_settings: {
        Row: {
          address_line1: string | null
          address_line2: string | null
          brand_accent: string | null
          checkin_dedupe_seconds: number
          city: string | null
          created_at: string
          financial_year_start_month: number
          grace_period_days: number
          gstin: string | null
          invoice_prefix: string
          logo_url: string | null
          max_freeze_days_per_year: number
          no_show_threshold_days: number
          opening_hours: Json
          pause_approver_role: Database["public"]["Enums"]["app_role"]
          pause_reasons: string[]
          pincode: string | null
          preset: Database["public"]["Enums"]["gym_preset"] | null
          receipt_prefix: string
          renewal_reminder_days_from_expiry: number[] | null
          state: string | null
          streak_rule_type: Database["public"]["Enums"]["streak_rule_type"]
          tenant_id: string
          trainer_member_cap: number | null
          updated_at: string
          week_start_day: number
          weekly_goal_default: number
        }
        Insert: {
          address_line1?: string | null
          address_line2?: string | null
          brand_accent?: string | null
          checkin_dedupe_seconds?: number
          city?: string | null
          created_at?: string
          financial_year_start_month?: number
          grace_period_days?: number
          gstin?: string | null
          invoice_prefix?: string
          logo_url?: string | null
          max_freeze_days_per_year?: number
          no_show_threshold_days?: number
          opening_hours?: Json
          pause_approver_role?: Database["public"]["Enums"]["app_role"]
          pause_reasons?: string[]
          pincode?: string | null
          preset?: Database["public"]["Enums"]["gym_preset"] | null
          receipt_prefix?: string
          renewal_reminder_days_from_expiry?: number[] | null
          state?: string | null
          streak_rule_type?: Database["public"]["Enums"]["streak_rule_type"]
          tenant_id: string
          trainer_member_cap?: number | null
          updated_at?: string
          week_start_day?: number
          weekly_goal_default?: number
        }
        Update: {
          address_line1?: string | null
          address_line2?: string | null
          brand_accent?: string | null
          checkin_dedupe_seconds?: number
          city?: string | null
          created_at?: string
          financial_year_start_month?: number
          grace_period_days?: number
          gstin?: string | null
          invoice_prefix?: string
          logo_url?: string | null
          max_freeze_days_per_year?: number
          no_show_threshold_days?: number
          opening_hours?: Json
          pause_approver_role?: Database["public"]["Enums"]["app_role"]
          pause_reasons?: string[]
          pincode?: string | null
          preset?: Database["public"]["Enums"]["gym_preset"] | null
          receipt_prefix?: string
          renewal_reminder_days_from_expiry?: number[] | null
          state?: string | null
          streak_rule_type?: Database["public"]["Enums"]["streak_rule_type"]
          tenant_id?: string
          trainer_member_cap?: number | null
          updated_at?: string
          week_start_day?: number
          weekly_goal_default?: number
        }
        Relationships: [
          {
            foreignKeyName: "organization_settings_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          activated_at: string | null
          created_at: string
          currency: string
          gym_code: string
          id: string
          name: string
          status: Database["public"]["Enums"]["organization_status"]
          tier: string | null
          timezone: string
          trial_ends_at: string | null
          updated_at: string
        }
        Insert: {
          activated_at?: string | null
          created_at?: string
          currency?: string
          gym_code: string
          id?: string
          name: string
          status?: Database["public"]["Enums"]["organization_status"]
          tier?: string | null
          timezone?: string
          trial_ends_at?: string | null
          updated_at?: string
        }
        Update: {
          activated_at?: string | null
          created_at?: string
          currency?: string
          gym_code?: string
          id?: string
          name?: string
          status?: Database["public"]["Enums"]["organization_status"]
          tier?: string | null
          timezone?: string
          trial_ends_at?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      payments: {
        Row: {
          amount_paise: number
          coupon_id: string | null
          created_at: string
          currency: string
          failed_reason: string | null
          id: string
          idempotency_key: string | null
          mandate_id: string | null
          member_id: string
          membership_id: string | null
          method: Database["public"]["Enums"]["payment_method"]
          notes: string | null
          paid_at: string | null
          provider: string | null
          provider_order_id: string | null
          provider_payment_id: string | null
          receipt_number: string | null
          recorded_by_staff_id: string | null
          status: Database["public"]["Enums"]["payment_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          amount_paise: number
          coupon_id?: string | null
          created_at?: string
          currency?: string
          failed_reason?: string | null
          id?: string
          idempotency_key?: string | null
          mandate_id?: string | null
          member_id: string
          membership_id?: string | null
          method: Database["public"]["Enums"]["payment_method"]
          notes?: string | null
          paid_at?: string | null
          provider?: string | null
          provider_order_id?: string | null
          provider_payment_id?: string | null
          receipt_number?: string | null
          recorded_by_staff_id?: string | null
          status?: Database["public"]["Enums"]["payment_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          amount_paise?: number
          coupon_id?: string | null
          created_at?: string
          currency?: string
          failed_reason?: string | null
          id?: string
          idempotency_key?: string | null
          mandate_id?: string | null
          member_id?: string
          membership_id?: string | null
          method?: Database["public"]["Enums"]["payment_method"]
          notes?: string | null
          paid_at?: string | null
          provider?: string | null
          provider_order_id?: string | null
          provider_payment_id?: string | null
          receipt_number?: string | null
          recorded_by_staff_id?: string | null
          status?: Database["public"]["Enums"]["payment_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payments_coupon_id_fkey"
            columns: ["tenant_id", "coupon_id"]
            isOneToOne: false
            referencedRelation: "coupons"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "payments_mandate_id_fkey"
            columns: ["tenant_id", "mandate_id"]
            isOneToOne: false
            referencedRelation: "razorpay_mandates"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "payments_member_id_fkey"
            columns: ["tenant_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "payments_membership_id_fkey"
            columns: ["tenant_id", "membership_id"]
            isOneToOne: false
            referencedRelation: "memberships"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "payments_recorded_by_staff_id_fkey"
            columns: ["tenant_id", "recorded_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "payments_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      plans: {
        Row: {
          created_at: string
          currency: string
          description: string | null
          duration_days: number
          gst_rate_bp: number
          id: string
          is_active: boolean
          max_freeze_days: number
          name: string
          price_paise: number
          sort_order: number
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          currency?: string
          description?: string | null
          duration_days: number
          gst_rate_bp?: number
          id?: string
          is_active?: boolean
          max_freeze_days?: number
          name: string
          price_paise: number
          sort_order?: number
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          currency?: string
          description?: string | null
          duration_days?: number
          gst_rate_bp?: number
          id?: string
          is_active?: boolean
          max_freeze_days?: number
          name?: string
          price_paise?: number
          sort_order?: number
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "plans_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_users: {
        Row: {
          created_at: string
          email: string
          full_name: string
          is_active: boolean
          role: Database["public"]["Enums"]["app_role"]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email: string
          full_name: string
          is_active?: boolean
          role: Database["public"]["Enums"]["app_role"]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          email?: string
          full_name?: string
          is_active?: boolean
          role?: Database["public"]["Enums"]["app_role"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      pt_sessions: {
        Row: {
          addon_order_id: string
          created_at: string
          ends_at: string
          id: string
          member_id: string
          notes: string | null
          starts_at: string
          status: Database["public"]["Enums"]["pt_session_status"]
          tenant_id: string
          trainer_staff_id: string
          updated_at: string
        }
        Insert: {
          addon_order_id: string
          created_at?: string
          ends_at: string
          id?: string
          member_id: string
          notes?: string | null
          starts_at: string
          status?: Database["public"]["Enums"]["pt_session_status"]
          tenant_id: string
          trainer_staff_id: string
          updated_at?: string
        }
        Update: {
          addon_order_id?: string
          created_at?: string
          ends_at?: string
          id?: string
          member_id?: string
          notes?: string | null
          starts_at?: string
          status?: Database["public"]["Enums"]["pt_session_status"]
          tenant_id?: string
          trainer_staff_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "pt_sessions_addon_order_id_fkey"
            columns: ["tenant_id", "addon_order_id"]
            isOneToOne: false
            referencedRelation: "addon_orders"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "pt_sessions_member_id_fkey"
            columns: ["tenant_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "pt_sessions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pt_sessions_trainer_staff_id_fkey"
            columns: ["tenant_id", "trainer_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
        ]
      }
      qr_sessions: {
        Row: {
          branch_id: string
          created_at: string
          created_by_staff_id: string | null
          expires_at: string
          id: string
          issued_at: string
          revoked_at: string | null
          tenant_id: string
          token_hash: string
        }
        Insert: {
          branch_id: string
          created_at?: string
          created_by_staff_id?: string | null
          expires_at: string
          id?: string
          issued_at?: string
          revoked_at?: string | null
          tenant_id: string
          token_hash: string
        }
        Update: {
          branch_id?: string
          created_at?: string
          created_by_staff_id?: string | null
          expires_at?: string
          id?: string
          issued_at?: string
          revoked_at?: string | null
          tenant_id?: string
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "qr_sessions_branch_id_fkey"
            columns: ["tenant_id", "branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "qr_sessions_created_by_staff_id_fkey"
            columns: ["tenant_id", "created_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "qr_sessions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      razorpay_accounts: {
        Row: {
          created_at: string
          is_enabled: boolean
          key_id: string
          key_secret_vault_id: string
          tenant_id: string
          updated_at: string
          verified_at: string | null
          webhook_secret_vault_id: string
        }
        Insert: {
          created_at?: string
          is_enabled?: boolean
          key_id: string
          key_secret_vault_id: string
          tenant_id: string
          updated_at?: string
          verified_at?: string | null
          webhook_secret_vault_id: string
        }
        Update: {
          created_at?: string
          is_enabled?: boolean
          key_id?: string
          key_secret_vault_id?: string
          tenant_id?: string
          updated_at?: string
          verified_at?: string | null
          webhook_secret_vault_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "razorpay_accounts_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      razorpay_mandates: {
        Row: {
          authenticated_at: string | null
          cancelled_at: string | null
          created_at: string
          currency: string
          ends_at: string | null
          id: string
          max_amount_paise: number
          member_id: string
          next_charge_at: string | null
          provider_customer_id: string | null
          provider_plan_id: string | null
          provider_subscription_id: string
          raw: Json | null
          status: Database["public"]["Enums"]["mandate_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          authenticated_at?: string | null
          cancelled_at?: string | null
          created_at?: string
          currency?: string
          ends_at?: string | null
          id?: string
          max_amount_paise: number
          member_id: string
          next_charge_at?: string | null
          provider_customer_id?: string | null
          provider_plan_id?: string | null
          provider_subscription_id: string
          raw?: Json | null
          status?: Database["public"]["Enums"]["mandate_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          authenticated_at?: string | null
          cancelled_at?: string | null
          created_at?: string
          currency?: string
          ends_at?: string | null
          id?: string
          max_amount_paise?: number
          member_id?: string
          next_charge_at?: string | null
          provider_customer_id?: string | null
          provider_plan_id?: string | null
          provider_subscription_id?: string
          raw?: Json | null
          status?: Database["public"]["Enums"]["mandate_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "razorpay_mandates_member_id_fkey"
            columns: ["tenant_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "razorpay_mandates_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      refunds: {
        Row: {
          amount_paise: number
          created_at: string
          currency: string
          id: string
          idempotency_key: string | null
          initiated_by_staff_id: string | null
          kind: Database["public"]["Enums"]["refund_kind"]
          payment_id: string
          processed_at: string | null
          provider_refund_id: string | null
          reason: string
          status: Database["public"]["Enums"]["refund_status"]
          tenant_id: string
          updated_at: string
        }
        Insert: {
          amount_paise: number
          created_at?: string
          currency?: string
          id?: string
          idempotency_key?: string | null
          initiated_by_staff_id?: string | null
          kind: Database["public"]["Enums"]["refund_kind"]
          payment_id: string
          processed_at?: string | null
          provider_refund_id?: string | null
          reason: string
          status?: Database["public"]["Enums"]["refund_status"]
          tenant_id: string
          updated_at?: string
        }
        Update: {
          amount_paise?: number
          created_at?: string
          currency?: string
          id?: string
          idempotency_key?: string | null
          initiated_by_staff_id?: string | null
          kind?: Database["public"]["Enums"]["refund_kind"]
          payment_id?: string
          processed_at?: string | null
          provider_refund_id?: string | null
          reason?: string
          status?: Database["public"]["Enums"]["refund_status"]
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "refunds_initiated_by_staff_id_fkey"
            columns: ["tenant_id", "initiated_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "refunds_payment_id_fkey"
            columns: ["tenant_id", "payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "refunds_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      staff: {
        Row: {
          branch_id: string | null
          created_at: string
          email: string | null
          full_name: string
          id: string
          is_active: boolean
          max_active_clients: number | null
          phone: string | null
          qualification: string | null
          role: Database["public"]["Enums"]["app_role"]
          tenant_id: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          branch_id?: string | null
          created_at?: string
          email?: string | null
          full_name: string
          id?: string
          is_active?: boolean
          max_active_clients?: number | null
          phone?: string | null
          qualification?: string | null
          role: Database["public"]["Enums"]["app_role"]
          tenant_id: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          branch_id?: string | null
          created_at?: string
          email?: string | null
          full_name?: string
          id?: string
          is_active?: boolean
          max_active_clients?: number | null
          phone?: string | null
          qualification?: string | null
          role?: Database["public"]["Enums"]["app_role"]
          tenant_id?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "staff_branch_id_fkey"
            columns: ["tenant_id", "branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "staff_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      webhook_events: {
        Row: {
          created_at: string
          event_id: string
          event_type: string
          id: string
          payload: Json
          processed_at: string | null
          processing_error: string | null
          provider: string
          received_at: string
          signature_valid: boolean
          tenant_id: string
        }
        Insert: {
          created_at?: string
          event_id: string
          event_type: string
          id?: string
          payload: Json
          processed_at?: string | null
          processing_error?: string | null
          provider?: string
          received_at?: string
          signature_valid: boolean
          tenant_id: string
        }
        Update: {
          created_at?: string
          event_id?: string
          event_type?: string
          id?: string
          payload?: Json
          processed_at?: string | null
          processing_error?: string | null
          provider?: string
          received_at?: string
          signature_valid?: boolean
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "webhook_events_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      red_list_cases: {
        Row: {
          absent_days_at_open: number | null
          assigned_to_staff_id: string | null
          contacted_at: string | null
          days_absent: number | null
          id: string | null
          last_attended_on: string | null
          last_follow_up_at: string | null
          last_follow_up_by: string | null
          last_follow_up_channel:
            | Database["public"]["Enums"]["contact_channel"]
            | null
          last_follow_up_outcome:
            | Database["public"]["Enums"]["follow_up_outcome"]
            | null
          member_id: string | null
          member_name: string | null
          member_phone: string | null
          next_follow_up_at: string | null
          opened_on: string | null
          status: Database["public"]["Enums"]["no_show_case_status"] | null
          tenant_id: string | null
          threshold_days: number | null
        }
        Relationships: [
          {
            foreignKeyName: "no_show_cases_assigned_to_staff_id_fkey"
            columns: ["tenant_id", "assigned_to_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "no_show_cases_member_id_fkey"
            columns: ["tenant_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "no_show_cases_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      commit_member_import: {
        Args: { p_file_sha256: string; p_import_id: string; p_rows: Json }
        Returns: Json
      }
      complete_addon_order: {
        Args: { p_order_id: string }
        Returns: {
          order_id: string
          order_status: Database["public"]["Enums"]["addon_order_status"]
          replayed: boolean
        }[]
      }
      complete_manual_addon_refund: {
        Args: {
          p_expected_amount_paise: number
          p_expected_currency: string
          p_expected_reason: string
          p_refund_id: string
        }
        Returns: {
          order_id: string
          order_status: Database["public"]["Enums"]["addon_order_status"]
          processed_at: string
          refund_id: string
          refund_status: Database["public"]["Enums"]["refund_status"]
          replayed: boolean
        }[]
      }
      convert_lead: {
        Args: {
          p_expected_revision: string
          p_lead_id: string
          p_member_id?: string
          p_mode: string
          p_request_key: string
        }
        Returns: Json
      }
      create_lead: {
        Args: {
          p_assigned_to_staff_id: string
          p_branch_id: string
          p_email: string
          p_full_name: string
          p_notes: string
          p_phone: string
          p_request_key: string
          p_source: Database["public"]["Enums"]["lead_source"]
        }
        Returns: Json
      }
      finish_pt_session: {
        Args: {
          p_session_id: string
          p_status: Database["public"]["Enums"]["pt_session_status"]
        }
        Returns: {
          order_id: string
          order_status: Database["public"]["Enums"]["addon_order_status"]
          replayed: boolean
          session_id: string
          session_status: Database["public"]["Enums"]["pt_session_status"]
        }[]
      }
      list_leads: {
        Args: {
          p_after_id?: string
          p_after_updated_at?: string
          p_assignee?: string
          p_branch_id?: string
          p_limit?: number
          p_query?: string
          p_source?: Database["public"]["Enums"]["lead_source"]
          p_stage?: Database["public"]["Enums"]["lead_stage"]
        }
        Returns: Json
      }
      prepare_member_import: {
        Args: {
          p_branch_id: string
          p_column_mapping: Json
          p_file_name: string
          p_file_sha256: string
          p_parser_contract: string
          p_phone_default_country: string
          p_preclassified_report: Json
          p_request_key: string
          p_row_count: number
          p_rows: Json
        }
        Returns: Json
      }
      read_member_addon_returns: { Args: { p_order_id: string }; Returns: Json }
      read_member_addon_trainer_names: {
        Args: never
        Returns: {
          product_id: string
          trainer_name: string
        }[]
      }
      record_addon_sale: {
        Args: {
          p_idempotency_key: string
          p_initial_ends_at: string
          p_initial_starts_at: string
          p_member_id: string
          p_method: Database["public"]["Enums"]["payment_method"]
          p_product_id: string
          p_quantity: number
          p_quote_version: string
          p_reason: string
          p_trainer_staff_id: string
        }
        Returns: {
          initial_session_id: string
          order_id: string
          payment_id: string
          replayed: boolean
        }[]
      }
      record_refund: {
        Args: {
          p_amount_paise: number
          p_currency: string
          p_idempotency_key: string
          p_kind: Database["public"]["Enums"]["refund_kind"]
          p_payment_id: string
          p_reason: string
        }
        Returns: {
          refund_id: string
          replayed: boolean
        }[]
      }
      run_no_show_scan_all: {
        Args: never
        Returns: {
          gym: string
          opened: number
          tenant_id: string
        }[]
      }
      schedule_pt_session: {
        Args: {
          p_ends_at: string
          p_notes: string
          p_order_id: string
          p_session_id: string
          p_starts_at: string
        }
        Returns: {
          order_id: string
          replayed: boolean
          session_id: string
        }[]
      }
      transition_lead: {
        Args: {
          p_expected_revision: string
          p_lead_id: string
          p_lost_reason: string
          p_target: Database["public"]["Enums"]["lead_stage"]
          p_trial_at: string
        }
        Returns: Json
      }
      update_lead: {
        Args: {
          p_assigned_to_staff_id: string
          p_branch_id: string
          p_email: string
          p_expected_revision: string
          p_full_name: string
          p_lead_id: string
          p_notes: string
          p_phone: string
          p_source: Database["public"]["Enums"]["lead_source"]
        }
        Returns: Json
      }
    }
    Enums: {
      addon_kind: "pt_package" | "diet_plan" | "product"
      addon_order_status:
        | "pending"
        | "paid"
        | "active"
        | "completed"
        | "cancelled"
        | "refunded"
      app_role:
        | "super_admin"
        | "platform_support"
        | "gym_owner"
        | "gym_manager"
        | "front_desk"
        | "trainer"
        | "member"
      attendance_source: "qr" | "front_desk"
      consent_purpose: "marketing" | "service"
      contact_channel: "call" | "whatsapp" | "in_person" | "sms"
      follow_up_outcome:
        | "will_return"
        | "injured"
        | "travelling"
        | "timing_issue"
        | "unhappy"
        | "no_response"
        | "cancelled"
      gym_preset: "neighbourhood_gym" | "premium_studio" | "functional_box"
      import_status: "pending" | "processing" | "completed" | "failed"
      lead_source:
        | "walk_in"
        | "referral"
        | "instagram"
        | "google"
        | "website"
        | "phone"
        | "other"
      lead_stage:
        | "new"
        | "contacted"
        | "trial_scheduled"
        | "trial_done"
        | "converted"
        | "lost"
      mandate_status:
        | "created"
        | "authenticated"
        | "active"
        | "paused"
        | "halted"
        | "cancelled"
        | "completed"
        | "expired"
      member_status: "active" | "paused" | "expired" | "cancelled" | "blocked"
      membership_status:
        | "pending"
        | "active"
        | "frozen"
        | "expired"
        | "cancelled"
      no_show_case_status:
        | "open"
        | "contacted"
        | "follow_up_due"
        | "returned"
        | "closed"
      notification_channel:
        | "push"
        | "whatsapp_link"
        | "in_app"
        | "sms"
        | "email"
      notification_status:
        | "scheduled"
        | "sent"
        | "delivered"
        | "failed"
        | "clicked"
        | "converted"
        | "opted_out"
      organization_status:
        | "pending_approval"
        | "trial"
        | "active"
        | "suspended"
        | "closed"
      payment_method: "razorpay" | "cash" | "upi" | "card" | "bank_transfer"
      payment_status:
        | "created"
        | "pending"
        | "paid"
        | "failed"
        | "refunded"
        | "reversed"
      pt_session_status: "scheduled" | "completed" | "cancelled" | "no_show"
      refund_kind: "refund" | "reversal"
      refund_status: "requested" | "processing" | "completed" | "failed"
      streak_rule_type: "visit_streak" | "weekly_goal" | "calendar_streak"
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      addon_kind: ["pt_package", "diet_plan", "product"],
      addon_order_status: [
        "pending",
        "paid",
        "active",
        "completed",
        "cancelled",
        "refunded",
      ],
      app_role: [
        "super_admin",
        "platform_support",
        "gym_owner",
        "gym_manager",
        "front_desk",
        "trainer",
        "member",
      ],
      attendance_source: ["qr", "front_desk"],
      consent_purpose: ["marketing", "service"],
      contact_channel: ["call", "whatsapp", "in_person", "sms"],
      follow_up_outcome: [
        "will_return",
        "injured",
        "travelling",
        "timing_issue",
        "unhappy",
        "no_response",
        "cancelled",
      ],
      gym_preset: ["neighbourhood_gym", "premium_studio", "functional_box"],
      import_status: ["pending", "processing", "completed", "failed"],
      lead_source: [
        "walk_in",
        "referral",
        "instagram",
        "google",
        "website",
        "phone",
        "other",
      ],
      lead_stage: [
        "new",
        "contacted",
        "trial_scheduled",
        "trial_done",
        "converted",
        "lost",
      ],
      mandate_status: [
        "created",
        "authenticated",
        "active",
        "paused",
        "halted",
        "cancelled",
        "completed",
        "expired",
      ],
      member_status: ["active", "paused", "expired", "cancelled", "blocked"],
      membership_status: [
        "pending",
        "active",
        "frozen",
        "expired",
        "cancelled",
      ],
      no_show_case_status: [
        "open",
        "contacted",
        "follow_up_due",
        "returned",
        "closed",
      ],
      notification_channel: ["push", "whatsapp_link", "in_app", "sms", "email"],
      notification_status: [
        "scheduled",
        "sent",
        "delivered",
        "failed",
        "clicked",
        "converted",
        "opted_out",
      ],
      organization_status: [
        "pending_approval",
        "trial",
        "active",
        "suspended",
        "closed",
      ],
      payment_method: ["razorpay", "cash", "upi", "card", "bank_transfer"],
      payment_status: [
        "created",
        "pending",
        "paid",
        "failed",
        "refunded",
        "reversed",
      ],
      pt_session_status: ["scheduled", "completed", "cancelled", "no_show"],
      refund_kind: ["refund", "reversal"],
      refund_status: ["requested", "processing", "completed", "failed"],
      streak_rule_type: ["visit_streak", "weekly_goal", "calendar_streak"],
    },
  },
} as const
