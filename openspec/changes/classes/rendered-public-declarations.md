# Classes rendered acceptance — declarations only

Existing application-interface-clarification.md and proposal/bar remain
authoritative. The prebooking-cutoff amendment is owner-pending: missing member
deadlines must fail closed, without client policy defaults or a new read grant.
These declarations expose callable seams, not implementation bodies.

```ts
// apps/web/app/member/classes/member-classes-view.tsx
declare function MemberClassesView(props: {
  sessions: MemberClassSession[] | null; today: string;
  nouns: BusinessNouns; cancelWindowHours?: number | null;
}): React.JSX.Element;
// apps/mobile/components/classes-pane.tsx
declare function ClassesPane(props: { desk?: boolean }): React.JSX.Element;

type MemberClassSession = {
  sessionId: string; serviceId: string; serviceName: string;
  serviceDescription: string | null; branchId: string; branchName: string;
  timezone: string; sessionDate: string; startsAt: string; endsAt: string;
  trainerName: string | null; capacity: number; bookedCount: number;
  spotsLeft: number; sessionStatus: Database['public']['Enums']['class_session_status'];
  myBookingId: string | null;
  myBookingStatus: Database['public']['Enums']['booking_status'] | null;
  availability: Database['public']['Enums']['class_availability'];
  canCancel: boolean; cancelBy: string | null;
};
type ClassTimetableSession = {
  sessionId: string; serviceId: string; serviceName: string;
  serviceIsActive: boolean; branchId: string; sessionDate: string;
  startsAt: string; endsAt: string; timezone: string;
  trainerStaffId: string | null; trainerName: string | null;
  trainerIsActive: boolean | null; capacity: number; bookedCount: number;
  attendedCount: number; noShowCount: number; spotsLeft: number;
  sessionStatus: Database['public']['Enums']['class_session_status'];
  cancelReason: string | null; ruleId: string | null;
  isCustomised: boolean; onHoliday: boolean; trainerOverlaps: boolean;
};
type ClassRosterBooking = {
  bookingId: string; memberId: string; memberName: string | null;
  memberCode: string; memberPhone: string | null; hasApp: boolean;
  status: Database['public']['Enums']['booking_status']; bookedAt: string;
  cancelledAt: string | null; cancelReason: string | null;
  markedAt: string | null; membershipLive: boolean; checkedInAt: string | null;
};
type ClassReadWindow = { from: string; to: string };
// apps/mobile/lib/classes.ts
declare function loadMemberClasses(client: SupabaseClient<Database>, window: ClassReadWindow): Promise<MemberClassSession[] | null>;
declare function loadDeskTimetable(client: SupabaseClient<Database>, window: ClassReadWindow & { branchId: string | null }): Promise<ClassTimetableSession[] | null>;
declare function loadDeskRoster(client: SupabaseClient<Database>, sessionId: string): Promise<ClassRosterBooking[] | null>;
declare function bookClass(api: ApiClient, sessionId: string): Promise<ApiEnvelope<{ bookingId: string; status: Database['public']['Enums']['booking_status']; spotsLeft: number }>>;
declare function cancelClassBooking(api: ApiClient, bookingId: string): Promise<ApiEnvelope<{ bookingId: string; status: Database['public']['Enums']['booking_status'] }>>;
declare function deskBookClass(api: ApiClient, sessionId: string, memberId: string): Promise<ApiEnvelope<{ bookingId: string; status: Database['public']['Enums']['booking_status']; spotsLeft: number }>>;
declare function deskCancelClassBooking(api: ApiClient, bookingId: string, reason: string): Promise<ApiEnvelope<{ bookingId: string; status: Database['public']['Enums']['booking_status'] }>>;
declare function markClassAttendance(api: ApiClient, bookingId: string, status: Database['public']['Enums']['booking_status']): Promise<ApiEnvelope<{ bookingId: string; status: Database['public']['Enums']['booking_status'] }>>;
```

These wire types are exported from @gymloop/shared. Native modules export the
functions shown, not reexports of all shared types. useMobile comes from
mobile/lib/mobile-context; useBusinessNouns from mobile/lib/use-business-nouns
returns BusinessNouns. Their public values/API signatures and kit props are in
v2-batch2-shared/native-identity-public-declarations.md and
pt-front/native-read-cancel-declarations.md. Additional kit functions:
SearchField({value,onChangeText,placeholder,accessibilityLabel}), and RowAction
accepts native PressableProps plus children, optional accent/icon. Expo Network
getNetworkStateAsync/addNetworkStateListener and Expo Router public navigation
are the existing platform seams. No new dependencies are required for tests.

loadDeskMembers(client, query) and its DeskMember projection are the existing
public roster search seam; search must match server-side before the cap as
already clarified. Ordinary IDs cannot choose a caller. Read every role,
status/date, reason, cancellation and attendance boundary from the proposal.
Do not obtain declarations by opening helper/type source bodies: request missing
public metadata from root. Doubled kit hosts do not prove actual geometry/dots
or device accessibility.
