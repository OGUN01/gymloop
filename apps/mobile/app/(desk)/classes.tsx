import { humanize } from '@gymloop/shared';
import { Screen, Title, Eyebrow } from '../../components/ui';
import { ClassesPane } from '../../components/classes-pane';
import { useBusinessNouns } from '../../lib/use-business-nouns';
export default function ClassesScreen() { const nouns = useBusinessNouns(); return <Screen><Eyebrow>Front desk</Eyebrow><Title>{humanize(nouns.classes)}</Title><ClassesPane desk /></Screen>; }
