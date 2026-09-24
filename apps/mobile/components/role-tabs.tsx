import { Tabs } from 'expo-router';
import { ChartNoAxesColumn, Dumbbell, House, ListTodo, LogIn, MoreHorizontal, UserRound, UsersRound } from 'lucide-react-native';
import { UI_TOKENS } from '@gymloop/shared';
import { StyleSheet, View, type ColorValue } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useMobile } from '../lib/mobile-context';
import { FONT } from './ui';
const ICON_SIZE = UI_TOKENS.icons.navigationSize;
const space = UI_TOKENS.geometry.spacing;
/**
 * Stock Lucide line icons at the navigation stroke. The current tab is marked the same way on every tab — a 3×24 clay
 * bar hung from the tab bar's rule, above the icon — so the cue never depends on whether a glyph has an area to fill.
 * The glyph also turns clay, fills at a low tint where it has an area, and the Activity bars, which have none, thicken.
 */
const icon = (Icon: typeof House) => ({ color, focused }: { color: ColorValue; focused: boolean }) => <View style={styles.slot}>
  <View style={[styles.indicator, { backgroundColor: focused ? color : 'transparent' }]} />
  {Icon === ChartNoAxesColumn
    ? <Icon color={color} size={ICON_SIZE} strokeWidth={focused ? UI_TOKENS.icons.currentStrokeWidth : UI_TOKENS.icons.strokeWidth} />
    : <Icon color={color} size={ICON_SIZE} strokeWidth={UI_TOKENS.icons.strokeWidth} fill={focused ? color : 'none'} fillOpacity={UI_TOKENS.opacity.currentIconFill} />}
</View>;
export function RoleTabs({ desk = false }: { desk?: boolean }) {
  const { palette } = useMobile();
  const insets = useSafeAreaInsets();
  const names = desk ? [{ name: 'index', title: 'Check-in', Icon: LogIn }, { name: 'members', title: 'Members', Icon: UsersRound }, { name: 'follow-ups', title: 'Follow-ups', Icon: ListTodo }, { name: 'more', title: 'More', Icon: MoreHorizontal }] : [{ name: 'index', title: 'Home', Icon: House }, { name: 'activity', title: 'Activity', Icon: ChartNoAxesColumn }, { name: 'gym', title: 'My gym', Icon: Dumbbell }, { name: 'you', title: 'You', Icon: UserRound }];
  return <Tabs screenOptions={{ headerShown: false, tabBarActiveTintColor: palette.primaryAction, tabBarInactiveTintColor: palette.secondaryText, tabBarStyle: { backgroundColor: palette.canvas, borderTopColor: palette.decorativeSeparator, borderTopWidth: 1, elevation: 0, height: UI_TOKENS.geometry.targets.touch + space[3] + insets.bottom, paddingBottom: insets.bottom + space[0] }, tabBarItemStyle: { minHeight: UI_TOKENS.geometry.targets.touch, paddingTop: 0 }, tabBarIconStyle: styles.slot, tabBarLabelStyle: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.secondary.size } }}>{names.map(({ name, title, Icon }) => <Tabs.Screen key={name} name={name} options={{ title, tabBarIcon: icon(Icon) }} />)}</Tabs>;
}
const styles = StyleSheet.create({
  // The icon slot starts on the tab bar's rule: the bar, 4, the 22 glyph (where it sat before), then 4 to the label.
  slot: { height: UI_TOKENS.icons.currentStrokeWidth + space[0] + ICON_SIZE + space[0], alignItems: 'center', gap: space[0] },
  indicator: { width: space[4], height: UI_TOKENS.icons.currentStrokeWidth, borderBottomLeftRadius: UI_TOKENS.icons.currentStrokeWidth, borderBottomRightRadius: UI_TOKENS.icons.currentStrokeWidth },
});
