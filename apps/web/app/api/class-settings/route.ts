import { classSettingsRequestSchema, parseClassSettingsResult } from '@gymloop/shared';
import { classCommand } from '../../../lib/class-http';

export async function PUT(request: Request): Promise<Response> {
  return classCommand(request, { schema: classSettingsRequestSchema, roles: ['gym_owner', 'gym_manager'], errors: { '42501': ['forbidden', 'not_permitted'], settings_missing: ['not_found', 'settings_not_found'] },
    execute: async (client, input, tenantId) => {
      const result = await client.from('organization_settings').update({ class_cancel_window_hours: input.cancelWindowHours, class_allow_cross_branch: input.allowCrossBranch }).eq('tenant_id', tenantId).select('class_cancel_window_hours,class_allow_cross_branch');
      return !result.error && Array.isArray(result.data) && result.data.length === 0 ? { data: null, error: { code: 'settings_missing' } } : result;
    },
    answer: (data) => parseClassSettingsResult(data),
  });
}
