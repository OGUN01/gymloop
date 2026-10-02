# SHP upload-stage observation

Status: orchestrator-frozen delegated interface clarification, 2026-10-03.
SHP-Q4 already requires honest Uploading, Verifying and Saving stages. This
additive observation seam changes no request, return, authority or media rule.

- Web `MediaUploadStage` is the UI-only union `'uploading' | 'verifying'`.
- `uploadMediaFile(file, kind, onStage?)` retains its first two arguments and
  `{ assetId }` result. Optional `onStage(stage)` reports `uploading` after
  successful preflight and before registration/upload requests, then `verifying`
  only after PUT success and before the trusted confirmation request.
- Invalid input emits no stage or network request. Failed registration/PUT
  never emits verifying. A failed confirmation preserves the existing error
  and never returns a confirmed result. An observer cannot change the request
  protocol or make a failed operation successful.
- `uploadProductImage(file, onStage?)` delegates the file, product kind and
  observer to that one helper; it does not duplicate the upload protocol.
- The owning display form shows Saving only after verified helper success and
  before its existing product-display mutation. A failed upload cannot enter
  Saving. The UI preserves pending/double-submit and connection behavior.

Independent visible observer/delegation regressions are committed first, then
the separate MEDIA implementer adds the optional argument. Existing visible
and held protocol suites stay unchanged. Fresh client-stage review and actual
browser upload verify the complete progression; this is no deployment waiver.
