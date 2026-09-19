import { Redirect } from 'expo-router';
import { RoleTabs } from '../../components/role-tabs';
import { useMobile } from '../../lib/mobile-context';
export default function DeskLayout() { const { identity, ready } = useMobile(); if (ready && identity.kind !== 'staff') return <Redirect href="/sign-in" />; return <RoleTabs desk />; }
