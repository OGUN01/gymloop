import { useState } from 'react';
import { useRouter } from 'expo-router';
import { DEFAULT_TIMEZONE, SLF_LIMITS, freezeRequestCopy, freezeRequestRefusalMessage } from '@gymloop/shared';
import { KeyboardAvoidingView, Platform } from 'react-native';
import { ActionButton, Body, Field, Screen, StateMessage, Title } from '../../components/ui';
import { MemberFreezeBody } from '../../components/freeze-requests';
import { useMemberFreezeRequests } from '../../lib/member-freeze-requests';
import { useBusinessNouns } from '../../lib/use-business-nouns';

/**
 * The member's freeze-request surface. Reads and commands run through
 * `useMemberFreezeRequests`; the request form states the frozen truth — this
 * is a request, the desk adopts it and a second configured-role person
 * approves it. No offline queue, no promised approval (SLF-004/017), and a
 * refused command always names itself (SLF-018).
 */
export default function FreezeRequestsScreen() {
  const nouns = useBusinessNouns();
  const router = useRouter();
  const { state, reload, create, cancel } = useMemberFreezeRequests();
  const copy = freezeRequestCopy(nouns);
  const [startsOn, setStartsOn] = useState('');
  const [endsOn, setEndsOn] = useState('');
  const [reason, setReason] = useState('');
  const [notice, setNotice] = useState<string | null>(null);
  const pendingMembership = state.membership?.status === 'pending';
  const canRequest = state.membership !== null
    && state.membershipId !== null
    && !pendingMembership
    && !state.offline
    && (state.membership.status === 'active' || state.membership.status === 'frozen');
  const submit = async () => {
    const answer = await create({ membershipId: state.membershipId ?? '', startsOn, endsOn, reason });
    if (answer.ok) {
      setNotice(null);
      setStartsOn('');
      setEndsOn('');
      setReason('');
    } else {
      setNotice(answer.offline ? copy.offlineNotice : freezeRequestRefusalMessage(answer.code ?? 'operation_failed'));
    }
  };
  const withdraw = async (requestId: string) => {
    const answer = await cancel(requestId);
    if (!answer.ok) setNotice(answer.offline ? copy.offlineNotice : freezeRequestRefusalMessage(answer.code ?? 'operation_failed'));
    else setNotice(null);
  };
  return <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}><Screen>
    <Title>Freeze requests</Title>
    {notice ? <StateMessage tone="warning">{notice}</StateMessage> : null}
    <MemberFreezeBody
      state={state}
      copy={copy}
      nouns={nouns}
      timeZone={DEFAULT_TIMEZONE}
      onRetry={() => void reload()}
      onRenew={() => router.push('/(member)/buy')}
      onCancel={(requestId) => void withdraw(requestId)}
    />
    {canRequest ? <>
      <Body strong>{copy.startsOnLabel}</Body>
      <Field placeholder="YYYY-MM-DD" value={startsOn} onChangeText={setStartsOn} autoCapitalize="none" accessibilityLabel={copy.startsOnLabel} />
      <Body strong>{copy.endsOnLabel}</Body>
      <Field placeholder="YYYY-MM-DD" value={endsOn} onChangeText={setEndsOn} autoCapitalize="none" accessibilityLabel={copy.endsOnLabel} />
      <Body strong>{copy.reasonLabel}</Body>
      <Field placeholder={copy.reasonLabel} value={reason} onChangeText={setReason} maxLength={SLF_LIMITS.reasonMaxChars} accessibilityLabel={copy.reasonLabel} />
      <ActionButton onPress={() => void submit()}>{copy.sendCta}</ActionButton>
      <Body muted>{copy.datesNote}</Body>
    </> : null}
  </Screen></KeyboardAvoidingView>;
}
