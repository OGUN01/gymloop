import { useState } from 'react';
import { Redirect } from 'expo-router';
import { ActionButton, Body, Eyebrow, Field, Screen, StateMessage, Title } from '../components/ui';
import { useMobile } from '../lib/mobile-context';
export default function SignIn() {
  const { identity, ready, supabase } = useMobile();
  const [email, setEmail] = useState(''); const [password, setPassword] = useState('');
  const [pending, setPending] = useState(false); const [message, setMessage] = useState<string | null>(null);
  if (ready && identity.kind !== 'unlinked') return <Redirect href="/" />;
  const submit = async () => { setPending(true); setMessage(null); const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password }); setPending(false); if (error) setMessage('Those sign-in details did not work.'); };
  return <Screen><Eyebrow>GYMLOOP</Eyebrow><Title>Welcome back.</Title><Body muted>Sign in with the account your gym linked to you.</Body><Field accessibilityLabel="Email" autoCapitalize="none" keyboardType="email-address" placeholder="Email" value={email} onChangeText={setEmail} /><Field accessibilityLabel="Password" secureTextEntry placeholder="Password" value={password} onChangeText={setPassword} />{message && <StateMessage tone="error">{message}</StateMessage>}<ActionButton disabled={pending || email.trim() === '' || password === ''} onPress={() => void submit()}>{pending ? 'Signing in…' : 'Sign in'}</ActionButton></Screen>;
}
