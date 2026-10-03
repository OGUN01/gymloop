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
  const [segment, setSegment] = useState<'classes' | 'training'>(section === 'training' ? 'training' : 'classes');
  useEffect(() => { setSegment(section === 'training' ? 'training' : 'classes'); }, [section]);
  return <Screen><Eyebrow>Your timetable</Eyebrow><Title>{segment === 'classes' ? humanize(nouns.classes) : 'Training'}</Title>
    <SegmentedControl value={segment} onChange={setSegment} />
    {segment === 'classes' ? <ClassesPane /> : <TrainingSection />}
  </Screen>;
}
