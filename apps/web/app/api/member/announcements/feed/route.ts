import { announcementCommand } from '../../../../../lib/announcement-http';
export async function POST(request: Request) { return announcementCommand(request, 'feed'); }
