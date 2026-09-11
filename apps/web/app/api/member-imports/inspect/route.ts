import { authorizedUpload, importOk, inspectionFrom } from '../support';

/**
 * `POST /api/member-imports/inspect` — inspect one uploaded file.
 *
 * Accepts multipart `file` only. It authenticates and checks the real
 * owner/manager role before reading the body (CSV-D01), parses within the
 * fixed v1 limits, and returns the contract's `ImportInspection` — headers by
 * zero-based index, the whole-file row count, and the first 10 sample rows.
 * It writes nothing: no `member_imports` row, no stored bytes, no handle
 * (CSV-D02). The browser keeps the `File`.
 */
export async function POST(request: Request): Promise<Response> {
  const upload = await authorizedUpload(request);
  if ('failure' in upload) return upload.failure;

  return importOk(inspectionFrom(upload.fileName, upload.fileSha256, upload.parsed));
}
