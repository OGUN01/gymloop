// GENERATED FILE — DO NOT HAND-EDIT.
// Source of truth is the Postgres schema, not this file (docs/architecture.md,
// "one truth chain for data"). Regenerate with:
//   supabase gen types typescript --linked > packages/db/types/database.ts
// CI diffs this file against a fresh generation on every push
// (.github/workflows/db.yml) — drift fails the build.

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
            columns: ["payment_id"]
            isOneToOne: true
            referencedRelation: "payments"
            referencedColumns: ["id"]
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
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
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
            columns: ["approved_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "membership_pauses_membership_id_fkey"
            columns: ["membership_id"]
            isOneToOne: false
            referencedRelation: "memberships"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "membership_pauses_requested_by_staff_id_fkey"
            columns: ["requested_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
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
          ends_on: string | null
          id: string
          member_id: string
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
          ends_on?: string | null
          id?: string
          member_id: string
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
          ends_on?: string | null
          id?: string
          member_id?: string
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
            columns: ["coupon_id"]
            isOneToOne: false
            referencedRelation: "coupons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memberships_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memberships_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memberships_renewal_of_membership_id_fkey"
            columns: ["renewal_of_membership_id"]
            isOneToOne: false
            referencedRelation: "memberships"
            referencedColumns: ["id"]
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
            columns: ["coupon_id"]
            isOneToOne: false
            referencedRelation: "coupons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_mandate_id_fkey"
            columns: ["mandate_id"]
            isOneToOne: false
            referencedRelation: "razorpay_mandates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_membership_id_fkey"
            columns: ["membership_id"]
            isOneToOne: false
            referencedRelation: "memberships"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_recorded_by_staff_id_fkey"
            columns: ["recorded_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
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
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
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
            columns: ["initiated_by_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "refunds_payment_id_fkey"
            columns: ["payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["id"]
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
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
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
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      app_role:
        | "super_admin"
        | "platform_support"
        | "gym_owner"
        | "gym_manager"
        | "front_desk"
        | "trainer"
        | "member"
      gym_preset: "neighbourhood_gym" | "premium_studio" | "functional_box"
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
      app_role: [
        "super_admin",
        "platform_support",
        "gym_owner",
        "gym_manager",
        "front_desk",
        "trainer",
        "member",
      ],
      gym_preset: ["neighbourhood_gym", "premium_studio", "functional_box"],
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
      refund_kind: ["refund", "reversal"],
      refund_status: ["requested", "processing", "completed", "failed"],
      streak_rule_type: ["visit_streak", "weekly_goal", "calendar_streak"],
    },
  },
} as const
