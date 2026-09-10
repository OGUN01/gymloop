import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import {
  addonCatalogueCreateSchema,
  addonCatalogueUpdateSchema,
  DEFAULT_CURRENCY,
} from '@gymloop/shared';
import { apiFail, apiOk, staffSession } from '../../../lib/api';

const CATALOGUE_ROLES = ['gym_owner', 'gym_manager'] as const;
type AddonProductInsert = Database['public']['Tables']['addon_products']['Insert'];
type AddonProductUpdate = Database['public']['Tables']['addon_products']['Update'];
type ExactInsert = Omit<AddonProductInsert, 'price_paise' | 'quote_version'> & {
  price_paise: string;
};
type ExactUpdate = Omit<AddonProductUpdate, 'price_paise'> & { price_paise: string };

async function jsonBody(request: Request): Promise<{ payload: unknown } | { failure: Response }> {
  try {
    return { payload: await request.json() };
  } catch {
    return { failure: apiFail('bad_request', 'malformed_body', 'The request body was not JSON.') };
  }
}

function invalidCatalogue(): Response {
  return apiFail('bad_request', 'invalid_request', 'That add-on offer was not readable.');
}

function knownKind(kind: string): kind is Database['public']['Enums']['addon_kind'] {
  const kinds: readonly string[] = Constants.public.Enums.addon_kind;
  return kinds.includes(kind);
}

/** POST /api/add-ons — publish an owner or manager's caller-scoped catalogue offer. */
export async function POST(request: Request): Promise<Response> {
  const caller = await staffSession(CATALOGUE_ROLES);
  if ('failure' in caller) return caller.failure;

  const body = await jsonBody(request);
  if ('failure' in body) return body.failure;
  const parsed = addonCatalogueCreateSchema.safeParse(body.payload);
  if (!parsed.success || !knownKind(parsed.data.kind)) return invalidCatalogue();

  const offer = {
    tenant_id: caller.session.tenantId,
    kind: parsed.data.kind,
    name: parsed.data.name,
    description: parsed.data.description,
    price_paise: parsed.data.pricePaise,
    currency: DEFAULT_CURRENCY,
    validity_days: parsed.data.validityDays,
    cancellation_terms: parsed.data.cancellationTerms,
    is_active: parsed.data.isActive,
    trainer_staff_id: parsed.data.trainerStaffId,
    trainer_qualification: parsed.data.trainerQualification,
    session_count: parsed.data.sessionCount,
    stock_quantity: parsed.data.stockQuantity,
  } satisfies ExactInsert;
  // PostgREST accepts bigint as decimal JSON text. The generated database type
  // says `number`, which cannot carry every legal paise amount exactly.
  const { data, error } = await caller.session.supabase.from('addon_products')
    .insert(offer as unknown as AddonProductInsert).select().maybeSingle();

  if (error) {
    return apiFail(
      error.code === '42501' ? 'forbidden' : 'server_error',
      error.code === '42501' ? 'not_permitted' : 'operation_failed',
      error.code === '42501' ? 'Your role may not change this catalogue.' : 'That offer could not be saved.',
    );
  }
  if (!data) return apiFail('server_error', 'operation_failed', 'That offer could not be saved.');
  return apiOk(data);
}

/** PATCH /api/add-ons — edit a caller-visible offer; the database protects referenced kind changes. */
export async function PATCH(request: Request): Promise<Response> {
  const caller = await staffSession(CATALOGUE_ROLES);
  if ('failure' in caller) return caller.failure;

  const body = await jsonBody(request);
  if ('failure' in body) return body.failure;
  const parsed = addonCatalogueUpdateSchema.safeParse(body.payload);
  if (!parsed.success || !knownKind(parsed.data.kind)) return invalidCatalogue();

  const offer = {
    kind: parsed.data.kind,
    name: parsed.data.name,
    description: parsed.data.description,
    price_paise: parsed.data.pricePaise,
    validity_days: parsed.data.validityDays,
    cancellation_terms: parsed.data.cancellationTerms,
    is_active: parsed.data.isActive,
    trainer_staff_id: parsed.data.trainerStaffId,
    trainer_qualification: parsed.data.trainerQualification,
    session_count: parsed.data.sessionCount,
    stock_quantity: parsed.data.stockQuantity,
  } satisfies ExactUpdate;
  const { data, error } = await caller.session.supabase.from('addon_products')
    .update(offer as unknown as AddonProductUpdate)
    .eq('id', parsed.data.productId).select().maybeSingle();

  if (error) {
    return apiFail(
      error.code === '42501' ? 'forbidden' : 'server_error',
      error.code === '42501' ? 'not_permitted' : 'operation_failed',
      error.code === '42501' ? 'Your role may not change this catalogue.' : 'That offer could not be saved.',
    );
  }
  if (!data) return apiFail('not_found', 'not_found', 'That add-on offer is unavailable.');
  return apiOk(data);
}
