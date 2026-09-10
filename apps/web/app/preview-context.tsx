'use client';

import { createContext, useContext, type ComponentProps, type ReactNode } from 'react';

const PreviewContext = createContext(false);

/** The UI mirrors the database preview boundary while leaving reads usable. */
export function PreviewProvider({ readOnly, children }: { readOnly: boolean; children: ReactNode }) {
  return <PreviewContext value={readOnly}>{children}</PreviewContext>;
}

export function usePreviewReadOnly() {
  return useContext(PreviewContext);
}

/** Product POST forms are absent during preview, including before hydration. */
export function MutationForm(props: ComponentProps<'form'>) {
  const readOnly = usePreviewReadOnly();
  return readOnly ? null : <form {...props} />;
}
