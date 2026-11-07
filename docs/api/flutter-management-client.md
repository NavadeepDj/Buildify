# Flutter management account connection

This client implements the health/current-account contract's account read; it adds
no device, tunnel, billing or entitlement behavior. Work tracks public issue #83.
The private service is deployed to development and checked separately there.

## Configuration and behavior

Use the existing ignored public configuration file and command:

```sh
flutter run --dart-define-from-file=config/supabase.development.json
```

Add the public `MANAGEMENT_API_URL` to that JSON, for example
`https://YOUR_PROJECT.supabase.co/functions/v1/management`. The example config
documents it. No database password or backend secret belongs in this file.
The client currently accepts only the same HTTPS Supabase origin as authentication
and this exact function prefix (optional trailing slash). Different/custom API
hosts require an intentional future trust/configuration change.

With no management URL, existing signup/sign-in/local hosting remains available.
An invalid management URL disables only cloud-profile access, with safe UI feedback.
The app never silently selects the development service in an unconfigured build.

After sign-in or restoration, the account gate starts a cloud-profile read without
blocking local projects. Open the existing Account screen to see the display name
returned by the backend. It is not treated as billing/ownership authority for other
resources. Refresh is manual; there is no polling or retry loop.

The client sends the current user JWT in Authorization and public project key in
apikey. An expired local session refreshes through the SDK; an API 401 allows one
refresh/retry, then offers sign-in again. Network/provider failures are retryable;
429 uses a bounded integer Retry-After or a conservative fallback cooldown. No
automatic retry happens after the cooldown. Account changes invalidate the provider,
and an in-flight response cannot return a different/signed-out user's profile.

Requests use the fixed `/v1/account` route without owner selectors or a body, forbid
redirects, cap response bytes at 64 KiB and close the per-request client after a
12-second HTTP deadline. Returned ID/name/request-ID are validated; raw gateway
HTML/provider errors are never displayed or logged. User credentials are never
added to URLs, disk caches or configuration. SDK refresh state continues using the
existing secure auth storage configured by the app.

## Reproducible validation

```sh
flutter test test/management_account_service_test.dart test/management_account_ui_test.dart test/hosted_account_ui_test.dart
flutter analyze
flutter test
```

`contracts/management/examples/account.json` is consumed by both Dart and the
OpenAPI schema tests, so the success wire example cannot silently diverge.
The OpenAPI spec/types/version are unchanged by this connection.

`test/management_live_smoke_test.dart` is skipped by default. An explicit private
backend harness creates two synthetic confirmed users, supplies only their refresh
tokens to a child Flutter test process through runtime environment variables, and
deletes the users/profiles afterward. It never puts credentials in dart-defines,
build artifacts, public config or source. Its test output is captured privately;
only sanitized pass/fail and cleanup summaries are emitted.

From the private repo, with its ignored backend `.env` and the public checkout's
public development JSON configured:

```sh
node --env-file=.env scripts/verify-flutter-client.mjs --project-ref DEVELOPMENT_PROJECT_REF --flutter-root PATH_TO_FLUTTER_SDK --public-root PATH_TO_PUBLIC_CHECKOUT
```

The backend admin secret stays in the parent process. The child environment uses
an OS/SDK-variable allowlist plus temporary-user refresh tokens; there are no admin
credentials in the Flutter test process. Failed runs preserve a private cleanup
journal; inspect its flags before retrying. Never use actual user accounts for this.

Remaining #83 hosting/log-review and full live expired/unconfirmed-token evidence
are recorded in the private handoff. This connection does not establish production
readiness or enable browser origins on the native-only development deployment.
