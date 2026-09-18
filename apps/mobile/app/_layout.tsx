import { Stack } from 'expo-router';
import { MobileProvider } from '../lib/mobile-context';
export default function Layout() { return <MobileProvider><Stack screenOptions={{ headerShown: false }} /></MobileProvider>; }
