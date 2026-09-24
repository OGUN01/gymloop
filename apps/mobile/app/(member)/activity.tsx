import { groupByMonth, toLocalDate, UI_TOKENS } from '@gymloop/shared';
import { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { ActionButton, Body, Display, Eyebrow, FONT, LoadingState, Row, Rule, Screen, StateMessage, Status, Title, WeekRhythm, dayLabel } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { rhythmFor } from '../../lib/mobile-data';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

export default function ActivityScreen() {
  const { palette } = useMobile();
  const { data, error, loading, reload } = useMemberSnapshot();
  const [showOlder, setShowOlder] = useState(false);
  if (loading) return <Screen><LoadingState /></Screen>;
  if (error || !data) return <Screen><Title>Activity</Title><StateMessage tone="error">{error ?? 'Your activity is unavailable.'}</StateMessage><ActionButton secondary onPress={() => void reload()}>Try again</ActionButton></Screen>;
  const timeZone = data.gym.timezone;
  const rhythmDays = rhythmFor(data);
  const { current, unit } = data.streak;
  const remaining = Math.max(data.member.goal - data.weekVisits, 0);
  // The gym's configured rule decides the unit and the copy; the same sentences as the web Activity page.
  const streakNote = unit === 'week'
    ? current === 0
      ? `Reach ${data.member.goal} visits this week to start one.`
      : remaining === 0 ? 'This week counts. Keep the run going next week.' : `${remaining} more ${remaining === 1 ? 'visit' : 'visits'} this week keeps it going.`
    : current === 0 ? 'Visit again to start one.' : 'Visit again to extend it.';
  const streakLine = current > 0 ? `Streak: ${current} ${current === 1 ? unit : `${unit}s`}` : 'No streak yet';
  const time = new Intl.DateTimeFormat('en-IN', { hour: 'numeric', minute: '2-digit', timeZone });
  const months = groupByMonth(data.visits, (visit) => visit.checkedInAt, timeZone);
  const [latest, ...older] = months;
  const renderMonth = (month: (typeof months)[number]) => <View key={month.key} style={styles.month}>
    <Eyebrow>{month.label}</Eyebrow>
    <View>{month.items.map((visit) => {
      const at = new Date(visit.checkedInAt);
      return <Row key={visit.id} title={<Text style={[styles.visitTitle, { color: palette.primaryText }]}>{at.toLocaleDateString('en-GB', { weekday: 'short', timeZone })}, {dayLabel(toLocalDate(at, timeZone), timeZone)} · {time.format(at)}</Text>} meta={visit.source === 'qr' ? 'Gym QR' : 'Desk assisted'} trailing={<View style={styles.visitStatus}><Status tone="ok">Confirmed</Status></View>} />;
    })}</View>
  </View>;
  return <Screen>
    <View><Eyebrow>Your progress</Eyebrow><Title>Activity</Title></View>
    <Rule />
    {/* One paragraph, so the caption shares the numeral's baseline exactly. */}
    <View accessible accessibilityLabel={`${data.weekVisits} ${data.weekVisits === 1 ? 'visit' : 'visits'} this week`}>
      <Display size="hero">{data.weekVisits}<Text style={[styles.figureCaption, { color: palette.primaryText }]}> {data.weekVisits === 1 ? 'visit' : 'visits'} this week</Text></Display>
    </View>
    <WeekRhythm days={rhythmDays} />
    <View style={styles.streak}>
      <Rule />
      {/* A running streak is a heading-size figure; no streak is still a stat, one step smaller, never a paragraph. */}
      <View style={styles.streakCopy} accessible accessibilityLabel={`${streakLine}. ${streakNote}`}>
        <Display size={current > 0 ? 'heading' : 'section'}>{streakLine}</Display>
        <Body muted>{streakNote}</Body>
      </View>
      <Rule />
    </View>
    {latest === undefined
      ? <View style={styles.empty}><Body strong>No confirmed visits yet</Body><Body muted>Your visits appear here once the gym confirms a check-in.</Body></View>
      : <View style={styles.visits}>
        {renderMonth(latest)}
        {older.length > 0 ? <Row title="Show older visits" meta={`${older.reduce((total, month) => total + month.items.length, 0)} earlier`} expanded={showOlder} onPress={() => setShowOlder((value) => !value)} accessibilityLabel="Show older visits" /> : null}
        {showOlder ? older.map(renderMonth) : null}
      </View>}
  </Screen>;
}

const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  // The caption is about half the numeral's cap height in the bold condensed cut, so the figure dominates.
  figureCaption: { fontFamily: FONT.displayBold, fontSize: UI_TOKENS.typography.sectionTitle.size + space[1] },
  // Hairline, 24, the streak, 24, hairline: the same ruled band as web.
  streak: { gap: space[4] },
  streakCopy: { gap: space[0] },
  visits: { gap: space[4] },
  month: { gap: space[2] },
  // Top-aligned with the date line rather than centred on the two-line row.
  visitStatus: { alignSelf: 'flex-start', paddingTop: space[0] },
  visitTitle: { fontFamily: FONT.displayBold, fontSize: UI_TOKENS.typography.mobileSection.size, lineHeight: UI_TOKENS.typography.mobileSection.lineHeight },
  empty: { gap: space[1], paddingVertical: space[5] },
});
