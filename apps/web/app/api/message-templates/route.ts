import { Constants } from '@gymloop/db';
import { messageTemplateRequestSchema, RESERVED_RENEWAL_TEMPLATE_KEY } from '@gymloop/shared';
import { apiFail, staffJson, type StaffSession } from '../../../lib/api';
import { commsOk, commsRpcFailure } from '../../../lib/comms';

/**
 * `POST /api/message-templates` — create or edit a gym's message template
 * (contract §2, §8). Gym admin only: front desk and trainers work messages,
 * not their content, so this is a narrower audience than `/api/consents`.
 *
 * An ordinary RLS-backed insert/update, not an RPC — the contract is explicit
 * that this is "ordinary RLS-backed insert/update" (§8), so the write goes
 * through `.from('message_templates')` the same way `apps/web/app/api/members/route.ts`
 * writes a member row. `key`, `channel` and `locale` are frozen at creation:
 * an update carries them in the body (so the form can always resubmit its
 * current values) but the write only ever sets `category`, `body` and
 * `is_active` — never those three.
 */
const TEMPLATE_ADMIN_ROLES = ['gym_owner', 'gym_manager'] as const;

type TemplateRow = {
  id: string; key: string; channel: string; locale: string;
  category: string; body: string; isActive: boolean;
};

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** Reads a written or read-back row leniently: the real column is `is_active`, a mocked/test row may already say `isActive`. */
function templateRow(data: unknown): TemplateRow | null {
  if (!isObject(data)) return null;
  const isActive = Object.hasOwn(data, 'isActive') ? data.isActive : data.is_active;
  if (typeof data.id !== 'string' || typeof data.key !== 'string' || typeof data.channel !== 'string' ||
    typeof data.locale !== 'string' || typeof data.category !== 'string' || typeof data.body !== 'string' ||
    typeof isActive !== 'boolean') {
    return null;
  }
  return { id: data.id, key: data.key, channel: data.channel, locale: data.locale, category: data.category, body: data.body, isActive };
}

async function createTemplate(
  supabase: StaffSession['supabase'],
  fields: { tenantId: string; key: string; channel: string; locale: string; category: string; body: string; isActive: boolean },
): Promise<Response> {
  const writer = supabase as unknown as {
    from(table: 'message_templates'): {
      insert(values: Record<string, unknown>): {
        select(): { single(): Promise<{ data: unknown; error: { code: string; message: string } | null }> };
      };
    };
  };
  const { data, error } = await writer.from('message_templates').insert({
    tenant_id: fields.tenantId, key: fields.key, channel: fields.channel, locale: fields.locale,
    category: fields.category, body: fields.body, is_active: fields.isActive,
  }).select().single();
  if (error) return commsRpcFailure(error);
  const row = templateRow(data);
  if (row === null) return apiFail('server_error', 'operation_failed', 'The template could not be saved. Nothing was written.');
  return commsOk('created', row);
}

async function updateTemplate(
  supabase: StaffSession['supabase'],
  templateId: string,
  fields: { category: string; body: string; isActive: boolean },
): Promise<Response> {
  const writer = supabase as unknown as {
    from(table: 'message_templates'): {
      update(values: Record<string, unknown>): {
        eq(column: 'id', value: string): {
          select(): { maybeSingle(): Promise<{ data: unknown; error: { code: string; message: string } | null }> };
        };
      };
    };
  };
  const { data, error } = await writer.from('message_templates')
    .update({ category: fields.category, body: fields.body, is_active: fields.isActive })
    .eq('id', templateId)
    .select()
    .maybeSingle();
  if (error) return commsRpcFailure(error);
  if (data === null) return apiFail('not_found', 'not_found', 'That template is not available.');
  const row = templateRow(data);
  if (row === null) return apiFail('server_error', 'operation_failed', 'The template could not be saved. Nothing was written.');
  return commsOk('ok', row);
}

export async function POST(request: Request): Promise<Response> {
  const caller = await staffJson(request, TEMPLATE_ADMIN_ROLES, { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return caller.failure;

  const parsed = messageTemplateRequestSchema.safeParse(caller.payload);
  if (!parsed.success) {
    return apiFail('bad_request', 'invalid_request', 'Check the template key, channel, locale, category and body, then try again.');
  }
  const { templateId, key, channel, locale, category, body, isActive } = parsed.data;

  if (!(Constants.public.Enums.notification_channel as readonly string[]).includes(channel)) {
    return apiFail('bad_request', 'invalid_request', 'That channel is not recognized.');
  }
  if (key === RESERVED_RENEWAL_TEMPLATE_KEY) {
    return apiFail('bad_request', 'invalid_request', '"renewal_reminder" is a reserved system key and cannot be authored here.');
  }

  if (templateId === undefined) {
    return createTemplate(caller.supabase, { tenantId: caller.tenantId, key, channel, locale, category, body, isActive });
  }
  return updateTemplate(caller.supabase, templateId, { category, body, isActive });
}
