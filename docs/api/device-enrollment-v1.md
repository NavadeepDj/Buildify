# Device enrollment contract proposal (#84)

Status: **proposed; no device endpoint is implemented or deployed**. Review this
contract before implementing handlers or changing device storage. The reviewed
foundation `contracts/management/openapi.json` is unchanged; this proposal lives
in `contracts/management/devices/openapi.json`, with separate generated types.
It does not update the private backend's immutable contract pin automatically.

## Purpose and delivery order

A user session identifies an account. A device credential identifies one enrolled
hosting installation and cannot become an owner session. The owner may manage
multiple devices with the same name; names never identify resources. The backend
generates the stable device UUID, binds it to the verified account and treats all
caller IDs as selectors, never proof of ownership.

1. Review this public interface and secure-storage/ownership handoff with Sujith.
2. Implement private migrations, authorization, credential hashing and transactions;
   test two accounts, retries, races, rotation and revocation locally.
3. After #82's ownership rules are integrated, add the Android secure-storage
   adapter and enrollment UI. Test on a real phone before calling #84 complete.
4. Add desktop adapters using the same API, then test the actual OS credential
   store and reinstall/account-switch behavior separately on each platform.

Desktop Flutter builds are not a prerequisite for the shared backend. A compiled
desktop app is not proof of secure storage or hosting support. No runtime files,
SQLite ownership migrations, email templates or IDE settings change in this slice.
No device is enrolled by starting the app or merely signing in.

## Proposed direct enrollment (no pairing codes)

Enrollment happens on the hosting installation while its owner is signed in and
explicitly chooses **Register this device**. A remote dashboard cannot silently
enroll another machine. There is no short code/challenge in this slice; if remote
pairing is introduced later, it requires its own expiring single-use protocol.
This is a client consent requirement, not hardware attestation: the backend cannot
prove a caller's physical platform or stop an authenticated owner spoofing their
own device metadata. Do not use these reports to grant extra privileges.

Before any network mutation, the adapter must:

- Confirm the current verified account is allowed by #82's local ownership state.
- Generate an enrollment UUID and 32 random bytes using the platform CSPRNG.
- Persist the account ID, enrollment UUID and secret in the platform credential
  store, then read them back successfully. Never put the secret in SQLite,
  SharedPreferences, `.env`, logs, analytics or ordinary files.
- If storage is unavailable or verification fails, stop before sending enrollment.
  Local-only hosting remains available; remote registration is not claimed.

`POST /v1/devices` takes that enrollment UUID, a display name, supported platform,
protocol/capabilities and the secret over HTTPS under the owner session. No owner
field is accepted. The private backend stores a SHA-256 digest of the random
secret, never the raw secret; secrets are not human passwords. It must use
constant-time comparison and never log a credential or request body.

The response contains device metadata only. The client constructs the device
bearer `hny_device_<server-device-uuid>.<base64url-secret>` in memory when needed.
It retains the staged secure record until the returned device ID is durably bound
and read back; a failed local move must not erase the staged recovery record.
Credential version starts at 1. The secret has no scheduled expiry in this initial
proposal; it is independently revocable/rotatable and must be replaced on suspected
exposure. This is an architectural tradeoff for intermittent hosts, not a claim
that a long-lived bearer cannot be stolen. #100 owns operational rotation policy.

An identical retry under the same verified owner/enrollment UUID returns the same
device and current state without another credential or duplicate record. Compare
the normalized enrollment request including its secret digest. Changed inputs
return 409. A revoked record is never reactivated by replay. Preserve enrollment
deduplication with the device/tombstone until #101's explicit deletion policy;
never silently expire a receipt and create a duplicate device on an old retry.

Names trim outer whitespace and contain 1–80 Unicode code points and at least one
non-whitespace character. Request digests use the trimmed name and sorted unique
capabilities; their ordering is not meaningful. Capabilities are untrusted reports
of locally implemented features, not entitlements, authorization or evidence that
AI/project/database hosting works. An agent advertises only implemented adapters;
database hosting is a future capability, not a feature delivered by enrollment.

## Owner operations and independent device authentication

Owner routes require the existing verified Supabase user session. Device bearers,
publishable keys and backend keys do not authorize them. List/get/rename/rotate/
revoke queries constrain ownership to the verified subject. Foreign/missing IDs
return the same 404 without disclosing the owning account. No ownership updates
are accepted, even from a device. Pagination includes only the owner's records,
max 50 per page, using server-created cursors and stable `(created_at, id)` order.

Device credentials initially access only `GET /v1/agent/device`, returning that
device's ID, credential version and protocol. They cannot list/rename/revoke
devices, enroll devices, edit profiles or gain provider/billing authority. User
JWTs cannot substitute for device bearers on this route. Check the authoritative
digest, version, revocation and owner state on every device request; no cached
positive authorization that could survive revocation. Compare wrong/missing/
revoked credentials using the same generic 401. Auth/database failures fail closed.
Account deletion invalidates dependent credentials even before cleanup finishes.

## Rotation, revocation and recovery

Owner rename and rotation use a quoted `If-Match` revision from a Device response.
Revision changes serialize concurrent mutations; mismatch is 412. Do not confuse
this record revision with credential_version, which changes only on rotation.

Rotate from the host under its owner's interactive session. Persist and read back
a new secret plus rotation UUID before sending. The backend atomically validates
ownership/revision/status, replaces the digest, increments credential version and
revision, and records the rotation UUID plus normalized request digest. The old
secret stops authorizing new requests immediately after commit; no grace period.
An exact retry of the most recent rotation with no intervening mutation returns
the committed result before stale-revision rejection. Reused latest UUID with
different inputs is 409. After an intervening mutation, return 412 (or revoked 409)
and require reconciliation, never replay an older rotation over newer state.

When a response is lost, the host still has both secrets in secure storage. Test
the candidate with `/v1/agent/device`; matching device ID and expected incremented
credential version establish completion. Otherwise reread metadata under the owner
session and retry/reconcile. Never erase the last usable secret on a network error.
If secure storage is lost entirely, sign in as owner, revoke the old device and
explicitly enroll anew; do not recover a raw secret from the backend. Keep errors
honest about ambiguous completion. After a successful read-back/verification,
remove the old local secret. Account switching never sends the prior owner's
credential under a new account; #82 defines the stop/detach transition.

Revocation is a monotonic, owner-authorized operation and does not require a
potentially stale If-Match. It wins races with rename/rotation; all mutation and
credential-verification transactions must check status atomically. Repeated revoke
returns the same revoked state without generating new revisions. Credential checks
that start after commit fail immediately. A request authorized before commit may
finish; no rollback of already completed work is promised. Future command claims
must check revocation in the same transaction as acquisition, not reuse an earlier
HTTP auth result. Command cancellation belongs to #87/#91. Revocation alone does
not delete files or stop permitted local/LAN hosting.

Reinstall creates a new enrollment UUID/secret/device ID, even for the same phone.
If the OS restores an older secure-store entry, the adapter requires an explicit
resume decision and checks ownership/revocation before reusing it; never identify
an installation by hardware IDs, model name or a restored display name. The owner
can revoke the old entry. This proposal does not automatically reassign projects
or reattach old cloud project/device mappings after reinstall.

## Transport, limits and validation gates

All routes use HTTPS, no redirects, `Cache-Control: no-store`, safe JSON errors
and matching server UUID request IDs. Owner and device headers/bodies/secrets are
never logged. The deployed foundation currently allows only GET/OPTIONS and empty
bodies; new handlers must deliberately add JSON POST/PATCH routes, 4 KiB streamed
body limits, strict content type/schema/unknown-field checks and exact-origin
preflight for allowed methods/headers (including If-Match). Native-only origins
remain the initial policy. A publishable gateway key is configuration, not identity.

Reuse bounded deadlines and shared budgets. Add owner enrollment/rotation quotas
and a bounded pre-verification budget for device traffic without trusting forged
IP headers or creating rows from unverified IDs. Choose numeric budgets in the
private implementation review; this contract does not invent paid-plan quotas.
The foundation limiter is not pre-invocation/DDoS protection; retain #100's gates.

The schema tests here establish wire compatibility only. Before shipping #84,
private integration tests must cover independent accounts and credentials,
wrong-route credentials, idempotent retry/mismatch, revoked enrollment replay,
rotation/revoke races, stale revisions, DB outages, malformed/oversized requests,
log redaction and database grants/RLS. Device tests must cover failed writes and
read-back, lost responses, cancellation, account switches, restored/absent secure
state and reinstall. Real Android/desktop storage tests are still required.
