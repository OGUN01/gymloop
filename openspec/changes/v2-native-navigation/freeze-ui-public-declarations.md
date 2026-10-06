# Existing native Freeze interface — type-only fixture declaration

This is an existing interface declaration for the independent UI test author, not a new backend contract. The author does not read the hook implementation. Root must not change that hook in this change.

`useMemberFreezeRequests()` returns:

```ts
{
  state: {
    phase: 'ready' | 'loading' | 'error';
    offline: boolean;
    loadedAt: string | null;
    membershipId: string | null;
    membership: null | {
      planName: string | null;
      status: string;
      startsOn: string | null;
      endsOn: string | null;
      recordedAgreedPricePaise: string | null;
      currency: string;
    };
    requests: MemberFreezeRequestRow[];
  };
  reload(): Promise<void>;
  create(input: { membershipId: string; startsOn: string; endsOn: string; reason: string }): Promise<{ ok: boolean; code: string | null; offline: boolean }>;
  cancel(requestId: string): Promise<{ ok: boolean; code: string | null; offline: boolean }>;
}
```

MemberFreezeRequestRow is the registered shared projection. An empty requests array is a valid fixture for cheap copy/keyboard tests. Existing native screen calls create with ISO date strings, clears fields on success and shows the safe refusal on failure. Existing hook behavior and command payload stay unchanged. Root will remove the duplicate approval footer, render safe native renewal help without a raw route, format membership/request dates for display, and wrap the form in standard native keyboard avoidance while retaining scroll access. This does not promise a date-picker or change the required date-entry payload.
