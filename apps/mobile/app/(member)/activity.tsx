import { UI_TOKENS } from '@gymloop/shared';
import { StyleSheet, Text, View } from 'react-native';
import { ActionButton, Body, Display, Eyebrow, FONT, LoadingState, Row, Rule, Screen, StateMessage, Status, Title, WeekRhythm, dayLabel } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { rhythmFor } from '../../lib/mobile-data';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

export default function ActivityScreen() {
  const { palette } = useMobile();
  const { data, error, loading, reload } = useMemberSnapshot();
  if (loading) return <Screen><LoadingState /></Screen>;
  if (error || !data) return <Screen><Title>Activity</Title><StateMessage tone="error">{error ?? 'Your activity is unavailable.'}</StateMessage><ActionButton secondary onPress={() => void reload()}>Try again</ActionButton></Screen>;
  const rhythmDays = rhythmFor(data);
  const unit = data.streak.unit === 'week' ? 'week' : 'day';
  const streak = data.streak.current;
  // Zero-streak copy follows the gym's real rule: a weekly-goal streak starts by reaching the goal, a visit streak by visiting.
  const streakLine = streak > 0
    ? data.streak.missed[0] ? `One missed ${unit} does not erase your work.` : 'Keep your rhythm going.'
    : unit === 'week' ? `Reach ${data.member.goal} visits this week to start a streak.` : data.visits.length > 0 ? 'Visit again to start a streak.' : 'Check in to start a streak.';
  const dayFormat = { format: (date: Date) => `${date.toLocaleDateString('en-GB', { weekday: 'short', timeZone: data.gym.timezone })}, ${dayLabel(date.toLocaleDateString('en-CA', { timeZone: data.gym.timezone }), data.gym.timezone)}` };
  const timeFormat = new Intl.DateTimeFormat('en-IN', { hour: 'numeric', minute: '2-digit', timeZone: data.gym.timezone });
  return <Screen>
    <View style={styles.top}>
      <View><Eyebrow>Your progress</Eyebrow><Title>Activity</Title></View>
      <View style={styles.figure} accessible accessibilityLabel={`${data.weekVisits} ${data.weekVisits === 1 ? 'visit' : 'visits'} this week`}>
        <Display size="hero">{data.weekVisits}</Display>
        <Text style={[styles.figureCaption, { color: palette.primaryText }]}>{data.weekVisits === 1 ? 'visit' : 'visits'} this week</Text>
      </View>
    </View>
    <WeekRhythm days={rhythmDays} />
    <View style={styles.streak}>
      <Rule />
      <View style={styles.streakCopy} accessible accessibilityLabel={`Streak: ${streak} ${streak === 1 ? unit : `${unit}s`}. ${streakLine}`}>
        <Display size="section">Streak: {streak} {streak === 1 ? unit : `${unit}s`}</Display>
        <Body muted>{streakLine}</Body>
      </View>
      <Rule />
    </View>
    <View style={styles.visits}>
      <Eyebrow>Recent visits</Eyebrow>
      {data.visits.length === 0
        ? <View style={styles.empty}><Body strong>No confirmed visits yet</Body><Body muted>Your visits appear here once the gym confirms a check-in.</Body></View>
        : <View>{data.visits.map((visit) => <Row key={visit.id} title={<Text style={[styles.visitTitle, { color: palette.primaryText }]}>{dayFormat.format(new Date(visit.checkedInAt))} · {timeFormat.format(new Date(visit.checkedInAt))}</Text>} meta={visit.source === 'qr' ? 'Gym QR' : 'Desk assisted'} trailing={<View style={styles.visitStatus}><Status tone="ok">Confirmed</Status></View>} />)}</View>}
    </View>
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  top: { gap: space[1] },
  figure: { flexDirection: 'row', alignItems: 'flex-end', flexWrap: 'wrap', gap: space[3] },
  figureCaption: { fontFamily: FONT.display, fontSize: UI_TOKENS.typography.sectionTitle.size + space[1], lineHeight: UI_TOKENS.typography.sectionTitle.lineHeight + space[1], paddingBottom: space[2] },
  streak: { gap: space[3] },
  streakCopy: { gap: space[0] },
  visits: { gap: space[2] },
  // Top-aligned with the date line rather than centred on the two-line row.
  visitStatus: { alignSelf: 'flex-start', paddingTop: space[0] },
  visitTitle: { fontFamily: FONT.displayBold, fontSize: UI_TOKENS.typography.mobileSection.size, lineHeight: UI_TOKENS.typography.mobileSection.lineHeight },
  empty: { gap: space[1], paddingVertical: space[5] },
});
