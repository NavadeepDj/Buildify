# ADR 0001: Shared accounts and SaaS management

- Date: 2026-10-28
- Status: implementation baseline; deployment and commercial launch gates remain open
- Tracking: [architecture task #76](https://github.com/NavadeepDj/Buildify/issues/76), [epic #75](https://github.com/NavadeepDj/Buildify/issues/75)

## Context

Buildify runs project servers and GGUF inference on user-owned devices. The
current authentication service uses local SQLite accounts; this does not provide
shared identity across installations. Projects and deployment history also live
locally. Existing named-tunnel and deployment UI work is groundwork, not a
multi-tenant subscription service.

The next product stage needs verified accounts, multiple registered devices,
remote project operations, subscriptions, and stable branded public URLs. Shared
identity must not require uploading source code, model weights, or environment
secrets. This ADR specifies the target architecture; it does not claim those
features are implemented or that verification emails currently reach users.

## Decision

### 1. Managed identity and shared PostgreSQL

Use Supabase Auth for email/password identity, confirmation, recovery, and user
sessions. Use Supabase PostgreSQL for profiles and shared management records.
The first release has individual ownership: one account owns a device, project,
publication, and subscription. Use stable owner IDs so workspace membership can
be added later; do not implement teams or use display names as authorization.

The Supabase user UUID is the account identifier. Device and cloud project IDs
are UUIDs; a project remains bound to one hosting device in the first release.
Preserve local project IDs where migration can safely map them, otherwise record
an explicit local-to-cloud mapping. Names, repository URLs, and email addresses
are not resource identities. Account/device reassignment requires a separate
verified workflow, never an update to a client-supplied owner field.

### 2. SQL migrations and repositories, without a new ORM

Keep checked-in, versioned SQL migrations for shared tables, constraints, grants,
and row-level security (RLS). Use the Supabase Dart client behind typed models
and repository interfaces in Flutter. The Supabase client is not an ORM.

Retain direct SQLite access through DatabaseHelper for local state. Do not
introduce a second schema migration system or replace local persistence merely
to add cloud identity. A future ORM must justify its migration, policy, runtime,
and tooling impact in a separate decision.

Grant clients only the required operations. Owner-scoped reads and safe profile
updates may use the Supabase Data API with RLS. Device claims, command creation,
quota allocation, entitlement writes, and provider operations go through trusted
handlers or constrained database functions. RLS and database constraints remain
defense in depth; privileged handlers must authorize before elevated writes.

### 3. Short-lived management API and durable jobs

Use TypeScript Supabase Edge Functions as the initial Buildify management API.
They are hosted backend request handlers, separate from the Flutter app and
from the user-hosted project servers. Start with short request/response work:
authorization, enrollment, command submission/claim/result, checkout creation,
payment event receipt, and hostname provisioning coordination.

Use PostgreSQL records for commands, leases, event receipts, provisioning jobs,
and audit outcomes. Process external side effects in bounded, retryable batches
triggered by a scheduler. Persist intent before making provider changes and
reconcile actual state after partial failures. No important job may depend on
an in-memory timer or a function remaining alive after its response.

Do not run a project build, model inference, a perpetual device listener, or a
public traffic proxy inside the management function. Hosting agents execute
local work and report progress later. If bounded jobs cannot meet measured beta
latency/throughput requirements, introduce a separate durable worker with its
own deployment decision; do not hide an endless worker inside a function.

Function quotas include background agent traffic. Heartbeat and command polling
cadence must be budgeted per active device before the beta. Use incremental
sync, backoff, batching, and optional realtime wake-up hints; a durable command
record is authoritative even when notifications are lost. Realtime has separate
costs and limits and is not assumed to be free.

### 4. Data authority and local storage

The cloud is authoritative for identity, ownership, registered-device status,
desired management configuration, command state, billing entitlements, hostname
reservations, and publication policy. Billing events are verified against the
payment provider; Cloudflare is reconciled for actual routing state.

SQLite and the host filesystem remain authoritative for project files, local
build configuration and environment values, runtime processes, installed models,
and local deployment output. Runtime observations in the cloud are dated reports,
not proof that a process is currently reachable. Device input cannot overwrite
server-owned billing, permissions, or domain ownership.

Sync only approved metadata: IDs, display names, runtime capabilities, selected
non-secret configuration, status revisions, and timestamps. Do not sync whole
SQLite files, source trees, model weights, private filesystem paths, prompts,
responses, environment-secret values, or repository tokens by default.

Migration requires a new verified cloud identity and an explicit local claim of
legacy projects. Existing local password hashes and verification flags are not
cloud credentials. Email matching alone cannot claim an installation. Preserve
projects/history and a local recovery path through interruption and retry.

### 5. Separate user sessions, agent identity, and public access

Interactive clients use Supabase user sessions. Verify issuer, audience,
signature, expiry, applicable verification state, and resource ownership at
protected boundaries using supported verification libraries.

Registered hosting agents use individually scoped, revocable device credentials
issued after authenticated enrollment. Store device secrets in platform secure
storage. Device credentials cannot act as the owner, change entitlements, or
administer another device. A public project visitor has neither user-management
nor agent authority.

Keep Supabase privileged keys, Cloudflare account/DNS tokens, payment secrets,
and SMTP credentials server-side. Public app configuration may contain the
Supabase project URL and publishable client key, but those never substitute for
authorization. Do not distribute a shared platform connector identity.

GitHub OAuth is a separate repository-access connection. A Buildify login does
not authorize GitHub, and connecting GitHub does not grant a Buildify plan.
Repository tokens stay with the hosting device unless a future design explicitly
requires and protects a server-side connection.

### 6. Typed outbound remote operations

Agents establish outbound authenticated communication; public tunnels do not
expose the local management API. Commands use typed operations, stable request
IDs, ownership checks, atomic claims, leases, deadlines, and bounded retries.
Initial operations are start, stop, restart, and redeploy of an existing project.
No arbitrary shell commands or remote filesystem browser are included.

Assume at-least-once delivery, not exactly-once execution. Persist receipts and
inspect runtime state when recovering. Report uncertain outcomes honestly after
a crash. Keep desired, accepted, running, and completed states distinct. Expired
queued commands cannot execute after a device reconnects. Revocation blocks new
claims; operation-specific cancellation and in-flight behavior are explicit.

Use a versioned logical /v1 API and versioned command/payload schemas. The hosted
function prefix is deployment configuration. Publish validation/error contracts
with correlation IDs and idempotency behavior. Agents advertise capabilities and
protocol versions; reject unsupported operations rather than guessing. Additive
changes retain old-client compatibility; breaking changes require a new version
and a documented upgrade path.

### 7. Subscriptions and public hostname routing

Use a payment-provider adapter selected after merchant and distribution-channel
eligibility checks. The backend creates checkout sessions and reconciles signed
payment events. A client callback, success page, or editable profile flag never
grants paid access. Store entitlements separately from user-editable metadata.

Reserve hostnames transactionally in PostgreSQL with a unique normalized label
per managed zone. Check account eligibility and quotas during reservation. The
Cloudflare adapter provisions the owned name to the intended registered device;
the local public router selects the allowed project/service.

Prefer one isolated named tunnel per hosting device for the beta, subject to
provider capacity and measured operating costs. Multiple projects on that device
may share its local router. Unrelated devices must not be replicas of one tunnel.
Unknown hostnames are denied and tenant routing is verified using two hosts.

Use separate registrable domains for the account/dashboard and customer-hosted
content. Cookies for the dashboard are host-scoped. Customer content is not a
trusted origin for authentication redirects or management CORS. The candidate
buildify.app is illustrative, not a verified purchase or a configured zone.

Subscription grace, suspension, recovery, and release operate at the controlled
publication boundary, independent of whether an agent cooperates. Cancellation
does not delete a user's source files or stop permitted local/LAN hosting.
Reservation retention and delayed reallocation must avoid stale routes exposing
content from a previous owner. Public AI defaults to service-scoped API keys and
bounded request/concurrency limits; sharing a URL does not authorize inference.

### 8. Local-first availability and platforms

Preserve local/LAN use without a paid plan and make it available without a cloud
login as the new auth flow is introduced. This is a target behavior, not a claim
about today's startup route. Platform-provided remote management and branded
publication require cloud enrollment and the relevant entitlement.

A management-backend outage does not intentionally terminate a running local
process. Disable new cloud mutations, show cached status as stale, and retry
with backoff. Existing public routing may continue until provider state changes;
do not promise instantaneous suspension across disconnected providers.

Interactive logout clears that client's sessions and private cloud caches. It
does not silently remove files or stop enrolled background hosting. Explain this
and offer a separate disconnect/revoke action. On shared hosting installations,
account switching must not expose the previous owner's local records; stopping
or detaching its agent is an explicit transition. Account deletion revokes
dependent cloud access through the deletion workflow.

Sleep, app termination, connectivity loss, or a stopped runtime can make hosted
projects unavailable even when DNS and payment remain valid. Heartbeat freshness
uses server time. A persistent address is not an always-on cloud-compute SLA and
remote commands cannot wake an otherwise unreachable device.

Initial hosting targets are Android with its foreground-service constraints and
desktop bridges on Windows/macOS/Linux, validated per capability. Flutter build
support is not proof of hosting support. iOS/web are potential remote clients;
their readiness needs explicit tests. No browser or iOS background hosting
guarantee is introduced by this ADR.

### 9. Environment, retention, and operational principles

Separate local development, staging, and production databases, auth redirects,
provider credentials, and billing modes. Keep migrations/configuration in version
control with placeholders, and keep real credentials out of builds and fixtures.
Use local mail capture for automated development only; stage real SMTP delivery
and sender authentication before claiming Gmail verification works.

Collect minimum operational metadata, with bounded sizes and explicit retention
per category before beta. Logs must redact credentials and omit AI bodies by
default. Commands, payment receipts, and hostname tombstones need retention
compatible with retry/replay/reallocation windows, not an arbitrary short TTL.
Legal billing retention and deletion policy must be decided before live charging.
No indefinite diagnostic retention is the default.

Backups must be restored in staging and reconciled with external billing/DNS
state without replaying old commands. Document incidents, private vulnerability
reporting, resource quotas, and spending alerts. Keep the current MIT license;
hosting-service terms and any future licensing proposal are separate decisions.

### 10. Open-core and paid-service repository boundary

User-confirmed direction (2026-11-01): retain the public local-hosting core and
implement the proprietary hosted SaaS backend in a separate private repository.
Apply this boundary when starting subscriptions and billing (#92-#94), before
adding payment processing to this public repository.

- Public core: device agent, local project and AI hosting, runtime controls,
  local logs, and documented management-service interfaces. Upgrade/pricing UI,
  subscription-status display, and the SaaS API client may remain public.
- Private SaaS backend: payment checkout creation, payment webhooks, subscription
  records, server-owned entitlement enforcement, and proprietary hosted
  management functionality. Backend-specific billing migrations belong there.
- The server authorizes every paid hosted operation. Client subscription state
  is presentation data, never proof of payment or authority to grant access.
- Payment credentials and webhook signing secrets belong in server secret
  storage, outside either repository and outside distributed app builds.

Review the existing license and ownership of any reused code before implementing
the private backend. This decision does not relicense the public MIT core, make
already-published code proprietary, or require moving the current public Auth
and profiles setup. Exact proprietary feature boundaries remain implementation
decisions; a paid hosted service alone does not make otherwise fully open-source
software open core.

## Launch gates and follow-up owners

Each gate below belongs to the linked implementation task; a placeholder is not
evidence that a provider is configured or that an operational decision is done.

- Backend project region, deployment configuration, secrets, local tooling, and
  migration CI: [#77](https://github.com/NavadeepDj/Buildify/issues/77) and
  [#83](https://github.com/NavadeepDj/Buildify/issues/83).
- Account isolation, cloud login, verified Gmail delivery, recovery, and local
  migration: [#78](https://github.com/NavadeepDj/Buildify/issues/78) through
  [#82](https://github.com/NavadeepDj/Buildify/issues/82). SMTP provider, sender
  domain control, and approved confirmation URLs remain deployment gates in #80.
  Coordinate remaining phone scope with [#61](https://github.com/NavadeepDj/Buildify/issues/61).
- Enrollment, heartbeat/polling budget, command contracts, and platform behavior:
  [#84](https://github.com/NavadeepDj/Buildify/issues/84) through
  [#91](https://github.com/NavadeepDj/Buildify/issues/91).
- Approved prices/limits, payment-provider eligibility, currencies, purchase
  surfaces, grace periods, refund/cancellation policy, and webhook reconciliation:
  [#92](https://github.com/NavadeepDj/Buildify/issues/92) through
  [#94](https://github.com/NavadeepDj/Buildify/issues/94).
- Actual domain selection/ownership, zone and HTTPS setup, connector capacity,
  tenant isolation, suspension enforcement and name retention/reallocation:
  [#95](https://github.com/NavadeepDj/Buildify/issues/95) through
  [#97](https://github.com/NavadeepDj/Buildify/issues/97). Confirm provider traffic
  constraints for the intended AI/content workloads before paid launch.
- AI access controls and billing/domain UX:
  [#98](https://github.com/NavadeepDj/Buildify/issues/98) and
  [#99](https://github.com/NavadeepDj/Buildify/issues/99).
- Numeric retention settings, backup/restore, alert thresholds, cost envelope,
  deletion, and end-to-end beta evidence:
  [#100](https://github.com/NavadeepDj/Buildify/issues/100) through
  [#102](https://github.com/NavadeepDj/Buildify/issues/102).

Maintainers make commercial/provider/production decisions in those tasks. This
ADR does not buy domains, activate billing, provision production, or set prices.

## Journey review

1. Signup: Flutter calls Auth; a real SMTP email confirms identity; a profile is
   owner-bound. Unconfirmed accounts cannot publish remotely. #78-#81 validate it.
2. Second-device management: the owner enrolls a host, metadata sync identifies
   its projects, and another client submits an authorized expiring command. The
   host executes locally and reports an outcome. #82-#91 validate it.
3. Paid URL: server-verified billing grants entitlement; the API atomically
   reserves a name and reconciles its isolated route. #92-#96 validate it.
4. Offline device: status becomes stale/offline; the name can stay reserved but
   the service is unavailable; stale commands expire. #85/#87/#91 validate it.
5. Cancellation/deletion: approved billing timing changes publication access;
   revocation/reconciliation clean up routes and credentials without deleting
   remote source files implicitly. #94/#97/#101/#102 validate it.

These are design walkthroughs, not executed integration tests. The epic's release
gates require recorded staging evidence before claiming delivered behavior.

## Alternatives and consequences

Local-only identity cannot provide cross-device account ownership. A fully
custom auth server increases password/session and operational work without
changing the need for Buildify-specific routing/billing orchestration. A separate
always-on management server may become appropriate for sustained jobs but adds
deployment work now. An ORM does not replace RLS or migration discipline.

The chosen baseline speeds up shared identity and keeps the local hosting core,
at the cost of provider integration, quotas, explicit authorization policies,
and reconciliation across independent systems. Keep adapters for Auth, commands,
Cloudflare, and payments testable; migration to another provider is possible work,
not a claim of zero lock-in.

## Provider references

Checked 2026-10-28. Quotas/prices change; verify them when implementing cost gates.

- [Supabase Auth](https://supabase.com/docs/guides/auth)
- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Function limits](https://supabase.com/docs/guides/functions/limits)
- [Function pricing](https://supabase.com/docs/guides/functions/pricing)
- [Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
- [Cloudflare routing](https://developers.cloudflare.com/tunnel/concepts/routing/)
