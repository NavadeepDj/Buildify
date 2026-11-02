# HostAny: three-developer delivery plan

Planning baseline: 2026-11-02. Tracker: [epic #75](https://github.com/NavadeepDj/Buildify/issues/75).
HostAny is the agreed product name; the repository still uses Buildify identifiers.
Assignments are ownership of delivery, not permission to bypass dependencies or
proof that an issue is complete. No calendar estimates are implied.

## Verified progress and remaining foundation work

The maintainer reported successful signup, receipt of a verification email,
verification, and account access in the Android app; the user also appeared in
Supabase Auth. `hostany.app` was registered, Cloudflare activated, DNSSEC configured,
the domain verified in Resend, and custom SMTP saved in the development Supabase
project. These are development observations, not staging/production certification.

The local workspace contains the initial auth/profile implementation and unrelated
GitHub OAuth work, being published in separate focused PRs. Navadeep must
merge the focused, reviewed foundation changes before other developers branch from
them. Do not rebuild or overwrite that work from an older main branch.

Keep #76-#80 open until their complete acceptance criteria and required CI are
satisfied. In particular, two-account RLS tests, clean migration replay/CI,
session refresh/restoration and second-device checks, and the callback scope in
#80 remain to be validated or implemented. The current flow uses email codes;
confirmation deep links are not implemented. Revise scope explicitly before
claiming a code-only implementation completes callback criteria. Recovery (#81)
and local ownership migration (#82) are still outstanding.

## Track A: Navadeep / @NavadeepDj

Architecture, shared contracts, security-sensitive backend, infrastructure and
release authority. Primary owner of 15 issues:

- #76 architecture; #77 environments/migration workflow; #78 profiles and RLS.
- #79 initial cloud login/session integration; #80 verification delivery and
  remaining confirmation scope. Retain ownership until the current implementation
  is handed off; Sujith extends it through #81 afterward.
- #83 management API foundation; #84 enrollment/credential trust model;
  #87 command queue authorization, leases and expiry.
- #92 entitlement rules; #93 payment-provider decision/sandbox checkout;
  #94 verified webhook reconciliation.
- #96 isolated tunnel provisioning; #98 public AI access/key enforcement.
- #100 operational recovery/observability; #101 account deletion orchestration.

Navadeep approves architectural, schema/security, provider, domain, pricing,
retention and release decisions. Keep the public local core under its existing
license. Build the proprietary SaaS backend/billing implementation in a separate
private repository; link its work without copying private source or secrets into
public issues. Public API contracts and client/upgrade UI may remain public.

## Track B: Sujith / @Sujith8257

Device/runtime implementation and agreed feature services. Primary owner of
nine issues, with Navadeep reviewing shared contracts and security behavior:

- #81 account recovery and session revocation, after the #79/#80 handoff.
- #82 local ownership migration, preserving existing files and account isolation.
- #85 heartbeat/reconnect; #86 metadata sync.
- #88 command executor; #89 redeploy; #90 bounded redacted log/history transport.
- #95 transactional hostname reservations, after entitlement/schema approval.
- #97 publication suspension/recovery/release, after payment and routing contracts.

Sujith owns runtime changes in `lib/backend/`, the database helper, native/desktop
bridges and agent transport. The backend parts of #85/#86/#90/#95/#97 go in the
private service, using the agreed contracts. After #80 is handed off, Sujith owns
recovery-related edits to the hosted auth service/provider/page. Do not parallel
edit those auth files while Navadeep is finishing #79/#80.

## Track C: Harita / @hariThA1130

Smaller staged UI changes, email presentation and contributor validation
documentation. Primary owner of five issues. Start with #103/#104; remote and
billing UI integration remains dependent on its backend work:

- #103 personalized HostAny welcome-style signup confirmation. Edit
  `supabase/templates/confirmation.html`, preserve the dynamic code, use the
  existing display-name metadata with a fallback, and document deployment in
  `docs/hosted-development.md`. Navadeep coordinates the separate Supabase
  dashboard update; editing the local file alone does not deploy it.
- #104 phone-hosted AI endpoint smoke test from a laptop. Test the current actual
  Cloudflare URL with a small real inference request, then repeat across separate
  internet connections. Record authentication, stop/restart and reconnect results
  in `docs/testing/ai-tunnel-laptop-smoke-test.md`. Hand runtime failures to
  Sujith/Navadeep. This task does not wait for future paid subdomain provisioning.

- #91 remote device/project UI. Split into focused PRs: device/project list and
  offline states; supported command actions; operation/log views. Use sample
  responses behind an adapter first, then wire to the real endpoints as their
  dependencies pass. Never imply a sample result is a real remote operation.
- #99 plan/hostname UI. Split into read-only plan/status, checkout handoff, then
  hostname actions/states. Real payment and publication actions remain blocked
  on #94/#97/#91. No pricing invention or client-owned Pro flag.
- #102 beta checklist and contributor docs coordination. Start with the test
  matrix/setup instructions now; execute end-to-end cases only as dependencies
  land. Every developer supplies evidence for their own features. Navadeep owns
  security/restore sign-off and the final beta decision; Harita does not carry
  the entire integration suite or production release alone.

Harita owns new remote/billing UI files and their widget tests. Shared navigation,
provider contracts and existing project-page entry points need a small agreed
integration PR after the relevant screen lands. Do not modify runtime services,
database policies or payment/tunnel provisioning to make a screen work.

## Start now and handoffs

1. Navadeep: finish/review/publish the existing #76-#80 foundation, reconcile the
   hosted migration history, and pin #83's API contract. Provision the private
   backend repository before proprietary implementation begins.
2. Sujith: prepare #82 migration fixtures and the migration/claim proposal from
   the existing database schema. Implementation waits for the #79 baseline and
   approved claim rules. Prepare #81 recovery cases; auth edits wait for #80.
3. Harita: start #103's welcome email and #104's current public AI endpoint test
   using the reviewed working baseline. Then prepare #102's reproducible checklist
   and #91 screen-state sketches with clearly marked sample data in separate files.
   Request the #83 contract rather than guessing response fields. No future
   remote-management or billing integration is claimed from these smoke tests.

The original issue dependencies remain authoritative. Preparatory work does not
waive them. Useful cross-track checkpoints:

- Auth baseline: Navadeep -> Sujith (#81/#82) and Harita (auth test instructions).
- #83/#84 publish identity, device, ownership and error contracts before device
  integration; #85/#86 status contracts unblock real remote browsing.
- #87 defines command IDs/types/leases/results before #88; #88/#89/#90 feed #91.
- #92 defines approved limits; #93/#94 payment and #95/#96 hostname/tunnel work
  converge at #97. #99 integrates only after actual publication states exist.
- #98/#100/#101 plus all other #102 dependencies must pass before beta sign-off.

## Rules to reduce collisions

- One issue owner and one active implementation branch per task. Use focused
  branches/PRs from the latest reviewed `main`; do not share a working directory.
- Before coding, put the planned files and contract version in the issue/PR.
  If another active task owns a file, agree a handoff or separate an adapter
  instead of editing it concurrently.
- Navadeep coordinates `lib/main.dart`, `pubspec.yaml`/lockfile, shared public
  configuration, root CI, schema migration ordering and global contracts. Others
  propose minimal integration patches rather than independently changing them.
- Proposed new code areas: Sujith's agent/sync services and Harita's remote/billing
  pages stay separate. Existing `project_gateway.dart`, `live_url_service.dart`
  and AI provider changes require coordination with Navadeep's tunnel/AI work.
- Agree request/response shapes, errors, ownership rules and state names first.
  Each feature owner supplies relevant tests and redacted results; follow
  CONTRIBUTING.md and run required CI before merging.
- Database changes use new migrations after the baseline, never edits to an
  already-applied migration. Regenerate shared/plugin files only in the PR that
  introduces the dependency change.
- Final deployment, paid activation, licensing changes and production launch
  remain explicit maintainer decisions. An assigned issue does not authorize them.

## Definition of ready and done

Ready for integration: dependencies accepted, contract agreed, repository and
file ownership identified, and synthetic test data available. Sample-data UI can
be reviewed earlier but remains marked as preparatory.

Done: the entire issue's acceptance criteria pass, required checks pass, the PR
is reviewed/merged, and external-service claims have real redacted evidence.
Do not close #79/#80 from one successful signup or #102 from a single-device demo.
