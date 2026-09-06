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
      member_status: "active" | "paused" | "expired" | "cancelled" | "blocked"
      organization_status:
        | "pending_approval"
        | "trial"
        | "active"
        | "suspended"
        | "closed"
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
      member_status: ["active", "paused", "expired", "cancelled", "blocked"],
      organization_status: [
        "pending_approval",
        "trial",
        "active",
        "suspended",
        "closed",
      ],
      streak_rule_type: ["visit_streak", "weekly_goal", "calendar_streak"],
    },
  },
} as const
