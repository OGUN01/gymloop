# R2 browser-upload policy — owner decision

Status: owner approved in the campaign chat on 2026-10-02. The standing owner rule in
`docs/planning/v2-handoff.md` item 7 reserves R2 bucket CORS changes for the owner.
The approved MEDIA verifier amendment explicitly preserves this separate gate.

Read-only verification on 2026-10-02, using the existing registered R2 configuration
and S3 GetBucketCors, returned NoSuchCORSConfiguration for `gymloop-media`.
No configuration or object was changed by that initial read. After the explicit
approval, the exact policy below was installed once, read back and verified with
production PUT, foreign-origin PUT and production DELETE preflights. No object
was written. Evidence is `docs/evidence/v2/media/r2-cors.json`; browser upload and
trusted publication verification remain pending the SHP implementation.

## Exact proposed S3 policy

```json
{
  "CORSRules": [
    {
      "AllowedOrigins": ["https://fitcruxx.vercel.app"],
      "AllowedMethods": ["PUT"],
      "AllowedHeaders": ["Content-Type"],
      "MaxAgeSeconds": 3600
    }
  ]
}
```

Only the verified production website origin is admitted, without wildcards,
development/preview origins or extra methods/headers. The bucket stays private.
This policy grants no object access: an upload still needs the server-issued
short-lived staging-only signed PUT. Published objects cannot receive a signed
PUT under the approved MEDIA contract. Browser code sends only Content-Type;
if implementation requires another header, seek a precise amendment first.
No public bucket/domain, credentials, retention or object ACL changes are approved.

[Cloudflare's official CORS documentation](https://developers.cloudflare.com/r2/buckets/cors/)
confirms browser presigned requests need a matching policy and documents these
fields. Its example uses a 3600-second preflight cache; this operational setting
does not change the shorter upload URL expiry or authorize an expired signature.
No browser ETag exposure is needed because the trusted verifier reads it directly.

## Apply and verify after approval

Re-read the existing policy immediately before changing it. If it is no longer
absent, stop and reconcile the changed configuration rather than replacing another
operator's rules. Apply only the policy above to the exact `gymloop-media` bucket
through authenticated S3 PutBucketCors using existing credentials, without logging
credentials or signed URLs. Read back and compare exact fields; verify production
PUT preflight succeeds, a foreign origin is not admitted, and unapproved methods
are not admitted. Record the policy and evidence in the campaign ledger.

The later actual browser upload/verified publish/overwrite rejection pass remains
required after SHP and the approved Edge deployment are built. CORS success alone
does not prove file validation or tenant authorization. If rollback is needed,
restore the captured absent policy with DeleteBucketCors only while it still
equals this exact installed policy; never erase another operator's subsequent edit.
