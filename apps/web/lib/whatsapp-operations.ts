import { requireAudience } from './identity-session';
import { ptBookRequestSchema, WSP_OPERATIONS_PAGE_MAX } from '@gymloop/shared';
import { isUuid } from './keyset';
import { whatsappOperationsView, type WhatsappOperationsPage } from './whatsapp';

/**
 * The desk/owner WhatsApp operations reader: one `read_whatsapp_operations`
 * call behind the frozen keyset envelope, with the role split applied in
 * `whatsappOperationsView` — desk never sees wallet amounts, owner/manager
 * (and a preview of one) do. The loader never renders; it only refuses shapes
 * the contract does not describe.
 */

export type WhatsappOperationsParams = { cursor?: string };

export type WhatsappOperationsLoad = {
  view: WhatsappOperationsPage | null;
  errorMessage: string | null;
  isPreview: boolean;
};

export async function loadWhatsappOperations(params: WhatsappOperationsParams): Promise<WhatsappOperationsLoad> {
  const { supabase, identity } = await requireAudience('console');
  const isPreview = identity.kind === 'impersonation';
  const refused = { view: null, errorMessage: 'The WhatsApp operations list could not be loaded.', isPreview };
  if (!isPreview && !(identity.kind === 'staff' &&
      ['gym_owner', 'gym_manager', 'front_desk'].includes(identity.role))) return refused;

  // `read_whatsapp_operations` does not exist before the WSP migration lands;
  // the narrow local cast matches the pattern `messages.ts` uses for
  // not-yet-generated RPCs. The keyset cursor is a `created_at,id` pair the
  // previous page returned verbatim; both halves travel or neither does.
  let afterCreatedAt: string | null = null;
  let afterId: string | null = null;
  if (params.cursor !== undefined) {
    const parts = params.cursor.split('|');
    const [createdAt, id] = parts;
    if (parts.length !== ['createdAt', 'id'].length || !createdAt ||
        !ptBookRequestSchema.shape.startsAt.safeParse(createdAt).success || !isUuid(id)) return refused;
    afterCreatedAt = createdAt;
    afterId = id;
  }

  const reader = supabase as unknown as {
    rpc(name: 'read_whatsapp_operations', args: {
      p_after_created_at: string | null; p_after_id: string | null; p_limit: number;
    }): Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await reader.rpc('read_whatsapp_operations', {
    p_after_created_at: afterCreatedAt,
    p_after_id: afterId,
    p_limit: WSP_OPERATIONS_PAGE_MAX,
  });
  if (error) return refused;
  const view = whatsappOperationsView(identity, data);
  if (view !== null) {
    return { view, errorMessage: null, isPreview: identity.kind === 'impersonation' };
  }
  return {
    view: null,
    errorMessage: 'The WhatsApp operations list could not be loaded.',
    isPreview: identity.kind === 'impersonation',
  };
}

export function whatsappOperationsCursor(page: WhatsappOperationsPage): string | null {
  if (page.nextAfter === null || page.nextAfterId === null) return null;
  return `${page.nextAfter}|${page.nextAfterId}`;
}
