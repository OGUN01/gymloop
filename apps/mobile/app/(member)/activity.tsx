import { DAYS_PER_WEEK, UI_TOKENS } from '@gymloop/shared';
import { StyleSheet, View } from 'react-native';
import { Body, Eyebrow, LoadingState, Screen, StateMessage, Surface, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

export default function ActivityScreen() {
  const { palette } = useMobile();
  const { data, error, loading } = useMemberSnapshot();
  if (loading) return <Screen><LoadingState /></Screen>;
  if (error || !data) return <Screen><Title>Activity</Title><StateMessage tone="error">{error ?? 'Activity is unavailable.'}</StateMessage></Screen>;
  const localToday = new Date().toLocaleDateString('en-CA', { timeZone: data.gym.timezone });
  const rhythmDays = Array.from({ length: DAYS_PER_WEEK }, (_, index) => { const day = new Date(`${localToday}T12:00:00Z`); day.setUTCDate(day.getUTCDate() - (DAYS_PER_WEEK - 1 - index)); const dayKey = day.toLocaleDateString('en-CA', { timeZone: 'UTC' }); return { fullLabel: day.toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'short', timeZone: 'UTC' }), label: day.toLocaleDateString('en-IN', { weekday: 'narrow', timeZone: 'UTC' }), visited: data.visits.some((visit) => new Date(visit.checkedInAt).toLocaleDateString('en-CA', { timeZone: data.gym.timezone }) === dayKey) }; });
  return <Screen><Eyebrow>YOUR PROGRESS</Eyebrow><Title>Activity</Title><Surface><Eyebrow>LAST 7 DAYS</Eyebrow><View style={styles.rhythm}>{rhythmDays.map((day) => <View accessible accessibilityLabel={`${day.fullLabel}: ${day.visited ? 'visited' : 'rest day'}`} key={day.fullLabel} style={styles.rhythmDay}><View style={[styles.rhythmDot, { backgroundColor: day.visited ? palette.primaryAction : palette.elevatedSurface, borderColor: day.visited ? palette.primaryAction : palette.requiredControlOutline }]} /><Eyebrow>{day.label}</Eyebrow></View>)}</View><View style={[styles.streak, { borderColor: palette.decorativeSeparator }]}><Title>{data.streak.current}</Title><View style={styles.streakCopy}><Body>{data.streak.unit === 'week' ? 'week' : 'day'} streak</Body>{data.streak.missed[0] ? <Body muted>One missed {data.streak.unit} does not erase your work.</Body> : <Body muted>Keep your rhythm going.</Body>}</View></View></Surface><Eyebrow>RECENT VISITS</Eyebrow>{data.visits.length === 0 ? <StateMessage>No confirmed visits yet.</StateMessage> : <Surface>{data.visits.map((visit, index) => <View key={visit.id} style={[styles.visitRow, index > 0 ? styles.dividedRow : null, { borderColor: palette.decorativeSeparator }]}><View style={styles.visitCopy}><Body>{new Date(visit.checkedInAt).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}</Body><Body muted>{new Date(visit.checkedInAt).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })} · {visit.source === 'qr' ? 'Gym QR' : 'Desk assisted'}</Body></View><Eyebrow>CONFIRMED</Eyebrow></View>)}</Surface>}</Screen>;
}

const styles = StyleSheet.create({
  rhythm: { flexDirection: 'row', justifyContent: 'space-between' },
  rhythmDay: { alignItems: 'center', gap: UI_TOKENS.geometry.spacing[0] },
  rhythmDot: { borderRadius: UI_TOKENS.geometry.radii.control, borderWidth: StyleSheet.hairlineWidth, height: UI_TOKENS.geometry.spacing[2], width: UI_TOKENS.geometry.spacing[2] },
  streak: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', alignItems: 'center', gap: UI_TOKENS.geometry.spacing[3], marginTop: UI_TOKENS.geometry.spacing[3], paddingTop: UI_TOKENS.geometry.spacing[3], borderTopWidth: StyleSheet.hairlineWidth },
  streakCopy: { flex: 1, minWidth: 0 },
  visitRow: { minHeight: UI_TOKENS.geometry.targets.touch, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: UI_TOKENS.geometry.spacing[3], paddingVertical: UI_TOKENS.geometry.spacing[2] },
  dividedRow: { borderTopWidth: StyleSheet.hairlineWidth },
  visitCopy: { flex: 1, gap: UI_TOKENS.geometry.spacing[1] },
});
