import Link from 'next/link';

/** Route-controlled navigation; the containing feature owns its reads and state. */
export function ClassesSegments({ current }: { current: 'classes' | 'training' }) {
  return <nav className="cl-actions" aria-label="Classes and training">
    {(['classes', 'training'] as const).map((value) => <Link
      key={value}
      href={value === 'classes' ? '/member/classes' : '/member/classes/training'}
      aria-current={current === value ? 'page' : undefined}
      className={`cl-btn${current === value ? ' cl-btn--primary' : ''}`}
      style={{ whiteSpace: 'normal', overflowWrap: 'anywhere', textAlign: 'center', paddingBlock: 'var(--gymloop-space-8)', transition: 'none', transform: 'none' }}
    >{value === 'classes' ? 'Classes' : 'Training'}</Link>)}
  </nav>;
}
