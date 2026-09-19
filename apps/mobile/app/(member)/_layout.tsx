import { Redirect } from 'expo-router';
import { RoleTabs } from '../../components/role-tabs';
import { useMobile } from '../../lib/mobile-context';
export default function MemberLayout() { const { identity, ready } = useMobile(); if (ready && identity.kind !== 'member') return <Redirect href="/sign-in" />; return <RoleTabs />; }
