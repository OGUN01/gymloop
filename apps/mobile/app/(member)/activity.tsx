import { UI_TOKENS, formatDay } from '@gymloop/shared';
import { StyleSheet, Text, View } from 'react-native';
import { ActionButton, Body, Display, Eyebrow, FONT, LoadingState, Row, Rule, Screen, StateMessage, Status, Title } from '../../components/ui';
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
  const dayFormat = { format: (date: Date) => `${date.toLocaleDateString('en-GB', { weekday: 'short', timeZone: data.gym.timezone })}, ${formatDay(date.toLocaleDateString('en-CA', { timeZone: data.gym.timezone })).replace(/ \d{4}$/, '')}` };
  const timeFormat = new Intl.DateTimeFormat('en-IN', { hour: 'numeric', minute: '2-digit', timeZone: data.gym.timezone });
  return <Screen>
    <View><Eyebrow>Your progress</Eyebrow><Title>Activity</Title></View>
    <View style={styles.figure} accessible accessibilityLabel={`${data.weekVisits} ${data.weekVisits === 1 ? 'visit' : 'visits'} this week`}>
      <Display size="hero">{data.weekVisits}</Display>
      <Text style={[styles.figureCaption, { color: palette.primaryText }]}>{data.weekVisits === 1 ? 'visit' : 'visits'} this week</Text>
    </View>
    <Rule />
    <View style={styles.rhythm}>{rhythmDays.map((day) => <View accessible accessibilityLabel={`${day.name}: ${day.visited ? 'visited' : day.future ? 'still ahead' : 'no visit'}`} key={day.key} style={styles.rhythmDay}><Text style={[styles.rhythmLabel, { color: palette.secondaryText }]}>{day.label}</Text><View style={[styles.rhythmDot, { backgroundColor: day.visited ? palette.primaryText : 'transparent', borderColor: day.visited ? palette.primaryText : palette.requiredControlOutline }, day.future ? { borderStyle: 'dashed', opacity: UI_TOKENS.opacity.disabled } : null]} /></View>)}</View>
    <Rule />
    {data.streak.current > 0 ? <View accessible accessibilityLabel={`${data.streak.current} ${unit} streak`}>
      <Display size="section">Streak: {data.streak.current} {data.streak.current === 1 ? unit : `${unit}s`}</Display>
      <Body muted>{data.streak.missed[0] ? `One missed ${unit} does not erase your work.` : 'Keep your rhythm going.'}</Body>
    </View> : <Body muted>Your next visit starts a new streak.</Body>}
    <Rule />
    <Eyebrow>Recent visits</Eyebrow>
    {data.visits.length === 0
      ? <View style={styles.empty}><Body strong>No confirmed visits yet</Body><Body muted>Your visits appear here once the gym confirms a check-in.</Body></View>
      : <View>{data.visits.map((visit) => <Row key={visit.id} title={<Text style={[styles.visitTitle, { color: palette.primaryText }]}>{dayFormat.format(new Date(visit.checkedInAt))} · {timeFormat.format(new Date(visit.checkedInAt))}</Text>} meta={visit.source === 'qr' ? 'Gym QR' : 'Desk assisted'} trailing={<Status tone="ok">Confirmed</Status>} />)}</View>}
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  figure: { flexDirection: 'row', alignItems: 'flex-end', flexWrap: 'wrap', gap: space[3] },
  figureCaption: { fontFamily: FONT.display, fontSize: UI_TOKENS.typography.sectionTitle.size + space[2], lineHeight: UI_TOKENS.typography.sectionTitle.lineHeight + space[2], paddingBottom: space[2] },
  rhythm: { flexDirection: 'row', justifyContent: 'space-between' },
  rhythmDay: { alignItems: 'center', gap: space[2], minWidth: UI_TOKENS.geometry.targets.interactive },
  rhythmLabel: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.compact.size },
  rhythmDot: { width: space[4], height: space[4], borderRadius: space[4], borderWidth: UI_TOKENS.icons.strokeWidth },
  visitTitle: { fontFamily: FONT.displayBold, fontSize: UI_TOKENS.typography.mobileSection.size, lineHeight: UI_TOKENS.typography.mobileSection.lineHeight },
  empty: { gap: space[1], paddingVertical: space[5] },
});
