'use client';
import { AnnouncementCommandStatus, useAnnouncementCommand } from '../../../lib/use-announcement-command';
export function AnnouncementOffline() { const command = useAnnouncementCommand(); return <><AnnouncementCommandStatus command={command} />{!command.online ? <button type="button" className="cl-btn" onClick={() => { if (command.isCurrent()) window.location.reload(); }}>Try again</button> : null}</>; }
