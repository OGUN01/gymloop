import { ClassesSegments } from '../segments';

export default function Loading() {
  return <main className="cl-page" aria-busy="true">
    <ClassesSegments current="training" /><h1 className="cl-title">Training</h1>
    <p role="status">Loading training…</p>
    <div className="cl-skeleton" aria-hidden="true" />
  </main>;
}
