# Training read and existing-session cancellation — public declarations

Delegated presentation metadata for the frozen proposal and
application-interface-clarification.md. The proposed member-policy reader and
new-booking confirmation remain owner-pending. This packet authorizes neither.
Independent rendered checks may exercise TrainingSection's already-approved
read, pack, programme and existing-session cancellation behavior.

```ts
declare function TrainingSection(): React.JSX.Element;
type ReadSection<T> = { data: T[] | null; error: string | null };
type MemberTraining = {
  trainers: ReadSection<PtTrainer>;
  programmes: ReadSection<PtProgramme>;
  packs: ReadSection<PtPack>;
  upcoming: ReadSection<PtSession>;
  history: ReadSection<PtSession>;
};
type PtTrainer = {
  trainerKey: string; displayName: string; qualification: string | null;
  bio: string; specialities: string[]; imageUrl: string | null;
  branchName: string | null; isProfileListed: boolean;
};
type PtProgramme = {
  programmeId: string; trainerKey: string; trainerName: string;
  trainerQualification: string; name: string; description: string;
  pricePaise: string; currency: string; gstRateBp: number;
  sessionCount: number; validityDays: number; cancellationTerms: string;
};
type PtPack = {
  orderId: string; programmeName: string; trainerKey: string;
  trainerName: string; sessionsTotal: number; sessionsUsed: number;
  sessionsScheduled: number; sessionsRemaining: number;
  startsOn: string; expiresOn: string; state: 'live' | 'fully_booked' | 'spent' |
    'expired' | 'closed'; canBook: boolean; timezone: string;
};
type PtSession = {
  sessionId: string; orderId: string; programmeName: string;
  trainerKey: string; trainerName: string; startsAt: string;
  endsAt: string; timezone: string; status: 'booked' | 'attended' | 'no_show' |
    'cancelled_by_member' | 'cancelled_by_gym'; consumed: boolean;
  cancelledAt: string | null; cancelCutoff: string | null;
  lateNow: boolean; consumesNow: boolean; canCancel: boolean;
};
declare function loadTraining(client: SupabaseClient<Database>, api?: ApiClient): Promise<MemberTraining>;
declare function loadTrainingHistory(client: SupabaseClient<Database>, cursor?: {
  startsAt: string; sessionId: string;
}): Promise<ReadSection<PtSession>>;
```

The five existing member RPC projections are caller-scoped and map their
underscore fields mechanically to these public camelCase names. Failed sections
are null with sanitized errors; empty successful sections are empty arrays.
One failure cannot erase independent successful sections. Native images remain
display URLs only through the generic current-caller MEDIA API.

Use the registered useMobile provider value and kit (declarations in
v2-batch2-shared/native-identity-public-declarations.md); Expo Network public
getNetworkStateAsync()/addNetworkStateListener() provide live connectivity.
No native command queue or persisted Training cache exists. The existing
session cancellation command uses only api.post('/api/member/pt-bookings/cancel',
{ sessionId }). Refresh authoritative current session facts before preparing
or reopening its confirmation. Status words, pack facts, offline/refusal text,
permissions and lifetime rules remain those of the proposal/bar.

New booking policy, a new SQL routine, new props/test-only factories and any
claim reclassification are outside this packet. Test authors must request any
missing public declarations rather than open helper/implementation files.
