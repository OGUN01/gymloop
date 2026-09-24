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
  // The gym's configured rule decides the unit and the copy: goal-reaching weeks or visited days in a row.
  // Rest days, holidays and approved pauses never break a consecutive-day streak (STK-002).
  const streakNote = unit === 'week'
    ? current === 0
      ? `Reach ${data.member.goal} ${data.member.goal === 1 ? 'visit' : 'visits'} in a week to start a streak.`
      : remaining === 0 ? 'This week counts. Keep the run going next week.' : `${remaining} more ${remaining === 1 ? 'visit' : 'visits'} this week keeps it going.`
    : `${current === 0 ? 'Visit on consecutive days.' : 'Each consecutive day you visit adds a day.'} Rest days, holidays and approved pauses don’t break it.`;
  const streakLine = current > 0 ? `Streak: ${current} ${current === 1 ? unit : `${unit}s`}` : 'No streak yet';
  const time = new Intl.DateTimeFormat('en-IN', { hour: 'numeric', minute: '2-digit', timeZone });
  const months = groupByMonth(data.visits, (visit) => visit.checkedInAt, timeZone);
  const [latest, ...older] = months;
  // The eyebrow sits directly on its first row (that row's own 12 is the gap), so the month label belongs to its list.
  const renderMonth = (month: (typeof months)[number]) => <View key={month.key}>
    <Eyebrow>{month.label}</Eyebrow>
    <View>{month.items.map((visit) => {
      const at = new Date(visit.checkedInAt);
      // Intl joins the clock and its meridiem with a narrow space the condensed cut all but closes, and spaces the "·"
      // just as tightly, so both gaps are set in the normal-width cut; the meridiem is upper case ("10:10 PM"), as on web.
      const [clock, meridiem] = time.format(at).split(/\s+/u);
      return <Row key={visit.id} reserveChevron title={<Text style={[styles.visitTitle, { color: palette.primaryText }]}>{at.toLocaleDateString('en-GB', { weekday: 'short', timeZone })}, {dayLabel(toLocalDate(at, timeZone), timeZone)}<Text style={styles.visitGap}> · </Text>{clock}{meridiem ? <><Text style={styles.visitGap}> </Text>{meridiem.toUpperCase()}</> : null}</Text>} meta={visit.source === 'qr' ? 'Gym QR' : 'Desk assisted'} trailing={<View style={styles.visitStatus}><Status tone="ok">Confirmed</Status></View>} />;
    })}</View>
  </View>;
  return <Screen>
    <View><Eyebrow>Your progress</Eyebrow><Title>Activity</Title></View>
    <Rule />
    {/* One paragraph, so the caption shares the numeral's baseline exactly. */}
    <View style={styles.hero} accessible accessibilityLabel={`${data.weekVisits} ${data.weekVisits === 1 ? 'visit' : 'visits'} this week`}>
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
  // The hero's 88 line box sits about 14 above the numeral's cap; pulling it up 8 makes the visible gap from the rule
  // match the other section gaps on the screen (about 30).
  hero: { marginTop: -space[1] },
  // Hairline, 24, the streak, 24, hairline: the same ruled band as web.
  streak: { gap: space[4] },
  streakCopy: { gap: space[0] },
  // The visit list opens 32 below the streak band's closing hairline (the screen's 24 plus 8) — more than the 12 between
  // its eyebrow and first row, so the month label reads with the list, not the band above.
  visits: { marginTop: space[1], gap: space[4] },
  // Top-aligned with the date line rather than centred on the two-line row.
  visitStatus: { alignSelf: 'flex-start', paddingTop: space[0] },
  visitTitle: { fontFamily: FONT.displayBold, fontSize: UI_TOKENS.typography.mobileSection.size, lineHeight: UI_TOKENS.typography.mobileSection.lineHeight },
  visitGap: { fontFamily: FONT.bold },
  empty: { gap: space[1], paddingVertical: space[5] },
});
