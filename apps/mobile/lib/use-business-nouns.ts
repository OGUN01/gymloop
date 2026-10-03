import type { BusinessNouns } from '@gymloop/shared';
import { useMobile } from './mobile-context';
export function useBusinessNouns(): BusinessNouns { return useMobile().nouns; }
