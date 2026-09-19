import { Tabs } from 'expo-router';
import { Activity, CircleUserRound, Dumbbell, Home, ListTodo, MoreHorizontal, QrCode, UsersRound } from 'lucide-react-native';
import { UI_TOKENS } from '@gymloop/shared';
import { useMobile } from '../lib/mobile-context';
import type { ColorValue } from 'react-native';
const ICON_SIZE = UI_TOKENS.icons.controlSize;
const icon = (Icon: typeof Home) => ({ color }: { color: ColorValue }) => <Icon color={color} size={ICON_SIZE} strokeWidth={UI_TOKENS.icons.strokeWidth} />;
export function RoleTabs({ desk = false }: { desk?: boolean }) {
  const { palette } = useMobile();
  const names = desk ? [{ name: 'index', title: 'Check-in', Icon: QrCode }, { name: 'members', title: 'Members', Icon: UsersRound }, { name: 'follow-ups', title: 'Follow-ups', Icon: ListTodo }, { name: 'more', title: 'More', Icon: MoreHorizontal }] : [{ name: 'index', title: 'Home', Icon: Home }, { name: 'activity', title: 'Activity', Icon: Activity }, { name: 'gym', title: 'My gym', Icon: Dumbbell }, { name: 'you', title: 'You', Icon: CircleUserRound }];
  return <Tabs screenOptions={{ headerShown: false, tabBarActiveTintColor: palette.primaryAction, tabBarInactiveTintColor: palette.secondaryText, tabBarStyle: { position: 'absolute', backgroundColor: palette.surface, borderColor: palette.decorativeSeparator, borderTopWidth: 1, borderRadius: UI_TOKENS.geometry.radii.floatingNavigation, height: UI_TOKENS.geometry.targets.touch + UI_TOKENS.geometry.spacing[4], left: UI_TOKENS.geometry.spacing[3], right: UI_TOKENS.geometry.spacing[3], bottom: UI_TOKENS.geometry.spacing[2] }, tabBarItemStyle: { minHeight: UI_TOKENS.geometry.targets.touch }, tabBarLabelStyle: { fontFamily: 'Inter_500Medium', fontSize: UI_TOKENS.typography.secondary.size } }}>{names.map(({ name, title, Icon }) => <Tabs.Screen key={name} name={name} options={{ title, tabBarIcon: icon(Icon) }} />)}</Tabs>;
}
