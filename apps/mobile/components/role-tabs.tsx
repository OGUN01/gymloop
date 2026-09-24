import { Tabs } from 'expo-router';
import { ChartNoAxesColumn, Dumbbell, House, ListTodo, LogIn, MoreHorizontal, UserRound, UsersRound } from 'lucide-react-native';
import { UI_TOKENS } from '@gymloop/shared';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useMobile } from '../lib/mobile-context';
import { FONT } from './ui';
import type { ColorValue } from 'react-native';
const ICON_SIZE = UI_TOKENS.icons.navigationSize;
const icon = (Icon: typeof House) => ({ color }: { color: ColorValue }) => <Icon color={color} size={ICON_SIZE} strokeWidth={UI_TOKENS.icons.strokeWidth} />;
export function RoleTabs({ desk = false }: { desk?: boolean }) {
  const { palette } = useMobile();
  const insets = useSafeAreaInsets();
  const names = desk ? [{ name: 'index', title: 'Check-in', Icon: LogIn }, { name: 'members', title: 'Members', Icon: UsersRound }, { name: 'follow-ups', title: 'Follow-ups', Icon: ListTodo }, { name: 'more', title: 'More', Icon: MoreHorizontal }] : [{ name: 'index', title: 'Home', Icon: House }, { name: 'activity', title: 'Activity', Icon: ChartNoAxesColumn }, { name: 'gym', title: 'My gym', Icon: Dumbbell }, { name: 'you', title: 'You', Icon: UserRound }];
  return <Tabs screenOptions={{ headerShown: false, tabBarActiveTintColor: palette.primaryAction, tabBarInactiveTintColor: palette.secondaryText, tabBarStyle: { backgroundColor: palette.canvas, borderTopColor: palette.decorativeSeparator, borderTopWidth: 1, elevation: 0, height: UI_TOKENS.geometry.targets.touch + UI_TOKENS.geometry.spacing[3] + insets.bottom, paddingBottom: insets.bottom + UI_TOKENS.geometry.spacing[0] }, tabBarItemStyle: { minHeight: UI_TOKENS.geometry.targets.touch, paddingTop: UI_TOKENS.geometry.spacing[0] }, tabBarLabelStyle: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.secondary.size } }}>{names.map(({ name, title, Icon }) => <Tabs.Screen key={name} name={name} options={{ title, tabBarIcon: icon(Icon) }} />)}</Tabs>;
}
