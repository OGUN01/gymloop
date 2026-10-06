import { humanize } from '@gymloop/shared';
import { useEffect, useState } from 'react';
import { useLocalSearchParams } from 'expo-router';
import { Screen, Title, Eyebrow, SegmentedControl } from '../../components/ui';
import { ClassesPane } from '../../components/classes-pane';
import { TrainingSection } from '../../components/training-section';
import { useBusinessNouns } from '../../lib/use-business-nouns';
export default function ClassesScreen() {
  const nouns = useBusinessNouns();
  const { section } = useLocalSearchParams<{ section?: string | string[] }>();
  const destination = typeof section === 'string' ? section : undefined;
  const [segment, setSegment] = useState<'classes' | 'training'>(destination === 'training' ? 'training' : 'classes');
  useEffect(() => { setSegment(destination === 'training' ? 'training' : 'classes'); }, [destination]);
  return <Screen><Eyebrow>{destination === 'bookings' ? 'Your commitments' : 'Your timetable'}</Eyebrow><Title>{segment === 'classes' ? destination === 'bookings' ? 'My classes' : humanize(nouns.classes) : 'Training'}</Title>
    <SegmentedControl value={segment} onChange={setSegment} />
    {segment === 'classes' ? <ClassesPane bookingsOnly={destination === 'bookings'} /> : <TrainingSection />}
  </Screen>;
}
