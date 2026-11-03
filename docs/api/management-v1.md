# HostAny management API v1: foundation contract

Status: draft for #83. This document describes the first backend slice; it does
not mean the endpoints are deployed. Backend implementation belongs in the
separate private SaaS repository.
The implementation repository is [hostany-management](https://github.com/NavadeepDj/hostany-management)
(private; access required). Prerequisite #78's database authorization evidence remains
a release gate.

The machine-readable source is [openapi.json](../../contracts/management/openapi.json).
The [contract package](../../contracts/management/README.md) documents generation
and checks shared with the private repository.

## Purpose and first slice

The Flutter app authenticates through Supabase Auth. It calls this API for cloud
management operations. Projects and models continue running on the hosting device;
their public HTTP traffic does not pass through this management API.

The first implementation exposes only these logical routes:

- `GET /v1/health`: minimal service/version liveness; no account or provider data.
- `GET /v1/account`: the confirmed caller's account ID and display name.
- `OPTIONS` for supported routes: browser preflight for approved origins.

Device enrollment (#84), command acquisition (#87), billing (#93/#94), and
publication (#95-#97) are later contracts. Do not return invented device data or
implement those endpoints inside the foundation task.

The deployed base URL, including Supabase's function prefix, is environment
configuration. Clients append the logical route once. Never hardcode the
development project into a shared client or redirect requests based on user input.

## User identity boundary

Protected requests carry `Authorization: Bearer <Supabase user access token>`.
Where the Supabase gateway requires an `apikey` header, it contains the project's
public publishable key. That key identifies an application/project; it is not
user identity or authorization.

The private implementation must:

1. Verify the access token using supported Supabase verification/JWKS mechanisms,
   configured for the expected project. Never merely decode a JWT and trust it.
2. Enforce expected issuer, audience, signature/algorithm, expiry and applicable
   not-before claims. Require a valid user subject and the authenticated user
   role; reject public anon/service-role credentials and anonymous Auth users.
3. Obtain trusted current account confirmation/status through the provider or an
   equivalently maintained server authority. User-editable metadata cannot prove
   confirmation, permissions, ownership, billing or administrative status.
4. Build the request's account identity from the verified subject. The account
   route accepts no caller-supplied account ID, owner ID or email selector.
5. Query only the caller's profile using that identity. RLS remains enabled as
   defense in depth. A missing expected profile is a controlled dependency/state
   failure, not permission to create arbitrary ownership records.

Provider authentication unavailability returns a safe retryable error; it must
not fall back to trusting the token payload or a local SQLite account. Immediate
global session revocation is not claimed by local JWT signature verification;
the supported revocation model and propagation limits belong to #81.

Use separate device credentials when #84 is implemented. Device connectors must
not reuse interactive user credentials or platform-wide provider credentials.

## Request and response behavior

Responses use UTF-8 JSON, except empty preflight responses. Account responses and
errors include `Cache-Control: no-store`. The server creates a fresh UUID request
ID; return it in `X-Request-ID` and the JSON envelope. Client-provided request IDs
must not become unsanitized log identifiers.

Success example (synthetic data):

```json
{
  "data": {
    "id": "11111111-1111-4111-8111-111111111111",
    "display_name": "Example user"
  },
  "request_id": "22222222-2222-4222-8222-222222222222"
}
```

Error example:

```json
{
  "error": {
    "code": "authentication_required",
    "message": "Sign in to continue."
  },
  "request_id": "22222222-2222-4222-8222-222222222222"
}
```

Stable error code families:

- `400 invalid_request`: unsupported query fields or invalid request shape.
- `401 authentication_required` / `invalid_token`: missing, malformed, expired,
  wrong-project or otherwise invalid user credentials. Do not expose the token.
- `403 email_confirmation_required` / `forbidden`: verified identity lacks the
  required confirmation or permission. Browser origin rejection is also denied.
- `404 not_found`: unknown route or an inaccessible resource; future resource
  endpoints must not reveal another account's resource existence.
- `405 method_not_allowed`: unsupported method; provide the actual `Allow` header.
- `413 payload_too_large`: enforced request-size bound, including streamed bodies.
- `415 unsupported_media_type`: unsupported body format on future body routes.
- `429 rate_limited`: include a bounded positive integer `Retry-After` in seconds.
- `503 dependency_unavailable`: provider, profile store or required shared limiter
  unavailable. Do not convert authorization uncertainty into success.
- `500 internal_error`: generic message plus request ID; no stack traces or secrets.

Health is liveness only; a successful health response does not prove identity,
database readiness, a connected device or a running model. Framework/gateway
failures can occur before the handler; clients must handle non-JSON transport
errors without assuming they are application envelopes.

## Browser origins and input limits

- Configure an exact origin allowlist per environment. Never trust a wildcard
  customer-content subdomain, reflect arbitrary Origin values, or use suffix-only
  matching. No browser origin is pre-approved by this draft.
- Native clients may omit Origin; they still require authentication. CORS is a
  browser policy, not an authorization mechanism.
- Allowed preflight requests declare supported methods/headers only. Expose the
  response request ID and retry header to approved browsers, and use `Vary: Origin`.
- Initial reads accept no body and no query selectors. Reject unexpected input;
  do not silently trust future-looking `owner_id`, URL or admin fields.
- Private service configuration must explicitly define body/header/input limits,
  request deadlines and rate budgets before deployment. Tests must verify boundary
  behavior; an unbounded body read is not a size limit.
- Use a shared, atomic limiter for authenticated account quotas rather than a
  process-local counter that resets or diverges across Edge Function instances.
  Anonymous ingress limits must use trustworthy gateway information, not an
  arbitrary client-supplied forwarding header. Quotas are infrastructure controls,
  not approved subscription prices or commercial entitlements.

## Ownership extension point

Later resource handlers must resolve ownership from server records before
privileged side effects. A client-supplied project/device ID selects a resource;
it does not authorize it. The authorization interface must be independently
testable with account A, account B, missing records and revoked credentials.

Do not add service-role bypasses merely to make a test fixture visible. Unknown
and other-account resources should produce indistinguishable public not-found
responses while retaining an appropriate internal outcome category.

## Audit and redaction contract

Emit bounded structured events containing only server request ID, operation,
timestamp, coarse outcome, duration, and the minimum approved actor/resource IDs.
Define retention and access before deployment. No passwords, Authorization or
apikey headers, access/refresh tokens, cookies, SMTP/provider credentials, raw
query/body content, email addresses, local paths, source code, prompts or model
responses belong in logs. Avoid dumping exception objects or whole requests.

Reject paths and inputs safely without echoing attacker-provided values into
messages. Test success, validation, dependency failure and thrown-exception logs,
not just the happy path.

## Private implementation handoff and completion evidence

#83 remains open until the private backend supplies:

- Runnable Supabase Edge Function entry point and pinned dependencies/runtime.
- Environment validation, identity/ownership middleware, bounded input handling,
  CORS, shared rate enforcement, error mapping and redacted audit implementation.
- A local harness using generated synthetic identities/tokens; no production keys
  in fixtures. Include missing/malformed/expired/wrong issuer/wrong audience/wrong
  signature/service-role/anon/unconfirmed identity cases.
- Owner and second-account isolation tests; forged owner metadata/body fields
  must not change authority. Cover unsupported methods, origin lookalikes,
  body-size boundaries, shared-limiter concurrency, provider failures and log
  redaction. No success path may depend on disabled authorization checks.
- Real development/staging profile authorization checks completing #78, plus
  explicit deployment configuration and a harmless confirmed-account smoke test.
- Evidence of the current revocation behavior; document limitations rather than
  suggesting local signature verification immediately revokes every session.

No frontend/runtime files need modification to review this first contract. Sujith
and Harita may prepare adapters/sample states against it, but must treat it as
proposed until Navadeep accepts the contract and backend tests pass.

## Sources

- [ADR 0001](../decisions/0001-shared-accounts-and-management.md).
- [Supabase Edge Function authentication](https://supabase.com/docs/guides/functions/auth).
- [Supabase getClaims verification](https://supabase.com/docs/reference/javascript/auth-getclaims).
- [Supabase getUser](https://supabase.com/docs/reference/javascript/auth-getuser).
