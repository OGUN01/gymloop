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
  'cancelled_by_member' | 'cancelled_by_gym' | 'session_cancelled'; consumed: boolean;
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

## Existing kit declarations (presentation only)

```ts
declare function Status(props: { children: ReactNode; tone?: 'ok' | 'warn' | 'risk' | 'accent' | 'neutral' }): React.JSX.Element;
declare function ActionButton(props: PressableProps & {
  children: ReactNode; secondary?: boolean; quiet?: boolean;
  disabledNeutral?: boolean; icon?: ReactNode;
}): React.JSX.Element;
declare function Row(props: {
  title: ReactNode; meta?: ReactNode; status?: ReactNode; value?: string;
  trailing?: ReactNode; onPress?: () => void; expanded?: boolean;
  reserveChevron?: boolean; accessibilityLabel?: string;
  accessibilityHint?: string; accessibilityState?: PressableProps['accessibilityState'];
  icon?: ReactNode;
}): React.JSX.Element;
declare function Sheet(props: { visible: boolean; onClose: () => void; children: ReactNode }): React.JSX.Element;
declare function SheetHeader(props: {
  eyebrow?: string; title: string; detail?: string; control: 'Done' | 'Cancel';
  onControl: () => void; controlDisabled?: boolean; controlAccessibilityLabel?: string;
}): React.JSX.Element;
declare function EmptyState(props: { title: string; children: ReactNode }): React.JSX.Element;
declare function ErrorRetry(props: { message: string; onRetry: () => void }): React.JSX.Element;
declare function LoadingState(): React.JSX.Element;
declare function StateMessage(props: { children: ReactNode; tone?: 'neutral' | 'error' | 'warning' | 'success' }): React.JSX.Element;
```

Kit hosts may be doubled for deterministic component interactions while
preserving their public children/props/callbacks. A doubled Status does not prove
the real kit's dot, target dimensions, layout or device accessibility. Those
remain source and real rendered/native acceptance checks.
