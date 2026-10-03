import { announcementCommand } from '../../../../../lib/announcement-http';
export async function POST(request: Request, context: { params: Promise<{ announcementId: string }> }) { return announcementCommand(request, 'edit', context); }
