# WSP loader refusal interface — mechanical freeze, 2026-10-04

This completes the public loader interface declared in
`../v2-batch2-shared/wave-c-app-verification-declarations.md`. It changes no
role, tenant, consent, money, recipient or paging requirement.

`loadWhatsappOperations({cursor?})` reports a refused read through its
declared result envelope:
`{view: null, errorMessage: 'The WhatsApp operations list could not be loaded.', isPreview}`.
The preview flag describes the verified caller. A malformed or unpaired
cursor returns this envelope **before any RPC call**. It never restarts the
initial page, repairs a cursor, exposes cursor contents in the message or
returns partial operations. Query validation uses this result, rather than
throwing an exception into the page renderer.

The cursor timestamp is a complete ISO 8601 calendar date and time with an
explicit `Z` or numeric timezone offset, as returned by the timestamp RPC
projection. A bare date/number, impossible calendar date or missing timezone
is malformed, even if JavaScript `Date.parse` accepts it. It uses the same
refusal envelope before RPC. Both halves are preserved verbatim when valid.

The existing concealed-phone projection requirement applies to **all**
visible digits together: adding a mask marker or separators to a fully
visible phone does not conceal it. Independent privacy checks must cover
grouped and decorated full phones as well as the legitimate masked output.

Independent tests must retain refusal and zero-RPC assertions while using
this exact public result convention. Unexpected infrastructure exceptions
are outside this mechanical declaration. This is not feature acceptance.
