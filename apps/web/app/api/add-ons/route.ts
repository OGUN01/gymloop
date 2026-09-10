import { Constants } from '@gymloop/db';
import type { Database } from '@gymloop/db';
import {
  addonCatalogueCreateSchema,
  addonCatalogueUpdateSchema,
  DEFAULT_CURRENCY,
} from '@gymloop/shared';
import { apiFail, apiOk, jsonBody, staffSession } from '../../../lib/api';
import type { StaffSession } from '../../../lib/api';

const CATALOGUE_ROLES = ['gym_owner', 'gym_manager'] as const;
type AddonProductInsert = Database['public']['Tables']['addon_products']['Insert'];
type AddonProductUpdate = Database['public']['Tables']['addon_products']['Update'];
type ExactInsert = Omit<AddonProductInsert, 'price_paise' | 'quote_version'> & {
  price_paise: string;
};
type CatalogueValues = {
  kind: Database['public']['Enums']['addon_kind'];
  name: string;
  description: string | null;
  price_paise: string;
  validity_days: number | null;
  cancellation_terms: string | null;
  is_active: boolean;
  trainer_staff_id: string | null;
  trainer_qualification: string | null;
  session_count: number | null;
  stock_quantity: number | null;
};
type CatalogueCommand = {
  kind: string;
  name: string;
  description: string | null;
  pricePaise: string;
  validityDays: number | null;
  cancellationTerms: string | null;
  isActive: boolean;
  trainerStaffId: string | null;
  trainerQualification: string | null;
  sessionCount: number | null;
  stockQuantity: number | null;
};
type CatalogueSchema<T extends CatalogueCommand> = {
  safeParse(value: unknown): { success: true; data: T } | { success: false };
};

function invalidCatalogue(): Response {
  return apiFail('bad_request', 'invalid_request', 'That add-on offer was not readable.');
}

function knownKind(kind: string): kind is Database['public']['Enums']['addon_kind'] {
  const kinds: readonly string[] = Constants.public.Enums.addon_kind;
  return kinds.includes(kind);
}

async function catalogueRequest<T extends CatalogueCommand>(
  request: Request,
  schema: CatalogueSchema<T>,
): Promise<{ caller: StaffSession; data: T } | { failure: Response }> {
  const caller = await staffSession(CATALOGUE_ROLES, { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return caller;
  const body = await jsonBody(request);
  if ('failure' in body) return body;
  const parsed = schema.safeParse(body.payload);
  if (!parsed.success || !knownKind(parsed.data.kind)) return { failure: invalidCatalogue() };
  return { caller: caller.session, data: parsed.data };
}

function catalogueValues(data: CatalogueCommand): CatalogueValues {
  return {
    kind: data.kind as Database['public']['Enums']['addon_kind'],
    name: data.name,
    description: data.description,
    price_paise: data.pricePaise,
    validity_days: data.validityDays,
    cancellation_terms: data.cancellationTerms,
    is_active: data.isActive,
    trainer_staff_id: data.trainerStaffId,
    trainer_qualification: data.trainerQualification,
    session_count: data.sessionCount,
    stock_quantity: data.stockQuantity,
  };
}

function catalogueWriteFailure(code: string, details: string | null): Response {
  if (code === '42501') {
    return apiFail('forbidden', 'not_permitted', 'Your role may not change this catalogue.');
  }
  if (
    code === 'GL055' && details !== null && [
      'catalogue_incomplete', 'offer_unavailable', 'quote_changed',
      'unsupported_currency', 'invalid_quantity', 'invalid_validity',
    ].includes(details)
  ) {
    return apiFail('conflict', details, 'That offer conflicts with the current catalogue facts.');
  }
  if (code === '40001' || code === '40P01') {
    return apiFail('conflict', 'retryable', 'That offer changed while it was being saved. Please retry.');
  }
  return apiFail(
    'server_error',
    'operation_failed',
    'That offer could not be saved.',
  );
}

/** POST /api/add-ons — publish an owner or manager's caller-scoped catalogue offer. */
export async function POST(request: Request): Promise<Response> {
  const requested = await catalogueRequest(request, addonCatalogueCreateSchema);
  if ('failure' in requested) return requested.failure;

  const offer = {
    ...catalogueValues(requested.data),
    tenant_id: requested.caller.tenantId,
    currency: DEFAULT_CURRENCY,
  } satisfies ExactInsert;
  // PostgREST accepts bigint as decimal JSON text. The generated database type
  // says `number`, which cannot carry every legal paise amount exactly.
  const { data, error } = await requested.caller.supabase.from('addon_products')
    .insert(offer as unknown as AddonProductInsert)
    .select('id,name,kind,description,price_paise::text,currency,validity_days,cancellation_terms,session_count,stock_quantity,is_active,trainer_staff_id,trainer_qualification,quote_version')
    .maybeSingle();

  if (error) return catalogueWriteFailure(error.code, error.details);
  if (!data) return apiFail('server_error', 'operation_failed', 'That offer could not be saved.');
  const { price_paise: pricePaise, ...catalogue } = data;
  return apiOk({ ...catalogue, pricePaise });
}

/** PATCH /api/add-ons — edit a caller-visible offer; the database protects referenced kind changes. */
export async function PATCH(request: Request): Promise<Response> {
  const requested = await catalogueRequest(request, addonCatalogueUpdateSchema);
  if ('failure' in requested) return requested.failure;

  const offer = catalogueValues(requested.data);
  const { data, error } = await requested.caller.supabase.from('addon_products')
    .update(offer as unknown as AddonProductUpdate)
    .eq('id', requested.data.productId)
    .select('id,name,kind,description,price_paise::text,currency,validity_days,cancellation_terms,session_count,stock_quantity,is_active,trainer_staff_id,trainer_qualification,quote_version')
    .maybeSingle();

  if (error) return catalogueWriteFailure(error.code, error.details);
  if (!data) return apiFail('not_found', 'not_found', 'That add-on offer is unavailable.');
  const { price_paise: pricePaise, ...catalogue } = data;
  return apiOk({ ...catalogue, pricePaise });
}
