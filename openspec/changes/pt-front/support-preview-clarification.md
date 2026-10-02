# PTF-022: canonical read-only support preview

Status: precise clarification of the already frozen PTF-022/PTF-028 read-only
preview requirement; fresh public contract review required before author fanout.
No new platform mutation or ordinary staff authority is proposed.

The current access-token hook issues a live impersonation preview as gym_owner,
tenant_id and impersonation_session_id, keeps the active super-admin actor's sub,
and includes neither staff_id nor member_id. A preview cannot satisfy the real
staff binding check. PTF's actor-helper prose must distinguish these two paths
to deliver its expressly required read-only preview.

For app.pt_staff_actor(p_roles, p_allow_preview), the ordinary path retains every
complete active same-tenant staff/id/user/role requirement and refuses any member
claim. Every mutation passes p_allow_preview=false and rejects impersonation.

Only read_pt_bookings and read_pt_packs pass p_allow_preview=true. With a preview
claim, the helper admits a row only when all of the following are true:

- auth.uid, tenant and impersonation id are present; the claimed role is
  gym_owner and belongs to p_roles; staff_id and member_id are absent.
- The exact impersonation_sessions row has that id, actor_user_id=auth.uid and
  tenant_id equal to the claim. The canonical app.impersonation_is_live helper
  confirms it is unended and unexpired.
- The same current platform_users actor is active and role super_admin, matching
  the unchanged hook's actual impersonation eligibility.
- The target gym exists. Its status is not an additional preview restriction:
  NAV-006 and the unchanged hook permit preview of any existing gym, including
  pending, suspended, closed and expired-trial gyms. No invented staff identity
  is substituted. Member booking eligibility remains separately unchanged.

The helper returns tenant_id, staff_id=NULL, user_id=auth.uid, role=gym_owner for
this read-only path. Missing, expired, ended, foreign, wrong-actor, inactive actor,
platform_support, contaminated staff/member or non-owner preview claims refuse
42501. An ordinary platform token without a valid preview remains refused.
No session EXECUTE grant is added to the private helper, and no claim hook,
existing table policy or write guard changes.

Both independent SQL authors derive a genuine canonical preview claim through
the existing hook, establish positive scoped booking/pack reads, and test the
invalid/contaminated/live-session boundaries plus every mutation's refusal and
no-write evidence. Tests are committed red before the separate source fix; a
fresh source critic reviews the final read-only path. App authors retain their
already required preview read-only UI/API coverage.
