# Hosted Supabase development

Tracking: #77 (environment), #78 (profiles), #79 (cloud login), #80 (email).
Architecture: [ADR 0001](decisions/0001-shared-accounts-and-management.md).

## Status and scope

The repository now contains the initial hosted account integration, a versioned
profile migration, and public build configuration validation. A hosted project,
applied migration, configured sender, and real two-device verification are still
required. Adding these files does not provision Supabase or prove Gmail delivery.

This first slice uses email/password plus email codes. Native confirmation
deep links, password recovery, legacy-project ownership migration, cloud device
registration, subscriptions, and remote management remain separate tasks. The
legacy local authentication UI/service is retained for migration/reference tests;
the application entry point uses hosted authentication and never falls back to
checking a local password. Local hosting is available without a cloud login.
Local projects are still device-local and are not yet account-isolated (#82).
Use a test installation without another person's local projects for this beta.

## 1. Create a hosted development project

In the Supabase dashboard, create a separate Free development project, for example
`buildify-development`. Select a suitable region and keep its database password
in your password manager. Record the project reference and responsible maintainer
privately. Do not reuse a production database for these steps.

Copy the Project URL and public publishable key from the project's Connect/API
settings. Modern keys begin with `sb_publishable_`. A legacy `anon` key also works.
Never use a secret or service-role key in Flutter, even in a development APK.

## 2. Apply the profile migration

An optional development-only PostgreSQL helper can apply and verify this migration
without starting local Supabase. Its password is read from the ignored root
`.env` as `SUPABASE_DB_PASSWORD`; it never enters command arguments or Flutter.
If the direct endpoint is unavailable on an IPv4-only network, copy Host/User
from **Connect > Session pooler** into `SUPABASE_DB_HOST` and `SUPABASE_DB_USER`.
Use port 5432 and the exact project-specific username shown in that panel.
Do not guess the region/host or use the transaction pooler for this helper.

```powershell
python -m venv .backend-tools
.backend-tools/Scripts/python.exe -m pip install -r tool/requirements-hosted-database.txt
.backend-tools/Scripts/python.exe tool/hosted_database.py check
.backend-tools/Scripts/python.exe tool/hosted_database.py apply
.backend-tools/Scripts/python.exe tool/hosted_database.py verify
dart tool/check_hosted_backend.dart
```

The helper only accepts the development config, checks the administrative target,
keeps certificate/hostname verification enabled, and records the migration in the
Supabase CLI-compatible ledger atomically with the DDL. If the project needs a
specific CA certificate, download it from the dashboard and set its local path in
`SUPABASE_DB_SSLROOTCERT`; do not disable verification. The `verify` command creates
synthetic identities inside a transaction, checks owner/second-account/anonymous
access and restricted field writes, then rolls back every fixture. It does not
send mail, reset the database, or delete existing accounts. Python is tooling,
not part of the Flutter runtime or a new ORM.

### SQL editor alternative

For a newly created, empty development project, open the dashboard SQL editor and
run the checked-in file
`supabase/migrations/20261028000000_cloud_profiles.sql` once. Review the target
project before running it. This creates owner-isolated profiles and a signup
trigger, including a backfill for any existing development identities. It does
not alter the device's SQLite database or migrate local credentials.

The migration deliberately is not rerunnable DDL: accidental reapplication fails
instead of silently changing existing objects. Capture application time and
result in the development environment record. Do not use `db reset` on a hosted
database. Before a future CLI deployment, reconcile this manually applied file
into the migration ledger with `supabase migration repair --status applied
20261028000000` after checking the matching schema and linked project. This is a
temporary hosted-first bootstrap; local/CI migration replay is still part of #77.

The migration includes a transaction so partial failures roll back. If application
fails, inspect the error and schema state before retrying. Follow-up changes use
new versioned migrations, not edits to an applied
file. Production promotion requires reviewed migrations, backup/restore evidence,
and an explicit release decision; do not automatically deploy this to production.

## 3. Configure email confirmation

Keep **Confirm email** enabled under Authentication's email provider settings.
Set a suitable minimum password length (at least 8), email-code length (6–10),
expiry, and rate limits. Set the Site URL to an origin you control. This first
code-based flow does not request custom redirects or require opening a native
app link; leave additional redirect URLs narrowly allowlisted for future work.

Configure Custom SMTP with a real transactional sender and verified sender
domain, including the DNS records required by that provider. Enter credentials
only in Supabase's SMTP configuration. Default Supabase email delivery is limited
to pre-authorized team addresses and is not a general-user delivery service. Resend
delivers these Supabase-generated messages (`notifications@hostany.app`). Editing a
Resend marketing template will not update this auth email; no Cloudflare/DNS or
SMTP-credential changes are needed for this design task.

### Template and Personalization Behavior
The source of truth for the signup confirmation email template is tracked in:
`supabase/templates/confirmation.html`

- **Approved Subject:** `Welcome to HostAny — confirm your email`
- **Dynamic Token Source:** Uses `{{ .Token }}` exactly. Do not hardcode codes or assume a fixed digit count.
- **In-App Flow:** Preserves the code-entry in app flow without requiring deep links or external callbacks.
- **Metadata Personalization:** Supabase templates expose user metadata through `{{ .Data }}`.
  Signup sends `data: {'display_name': name.trim()}` via `lib/services/hosted_account_service.dart`.
  The template uses safe fallback greeting logic:
  ```gotemplate
  {{ if .Data.display_name }}Hi {{ .Data.display_name }},{{ else }}Welcome to HostAny!{{ end }}
  ```
- **Safety & Untrusted Text:** Go's template engine HTML-escapes metadata automatically, preventing XSS. Long and non-Latin names are wrapped with `word-break: break-word` to ensure layouts do not break.

### Deployment Instructions (Manual Dashboard Step)
Editing the local HTML file alone does not update hosted Supabase. Deployment is a separate manual step:
1. Open the [Supabase Dashboard](https://supabase.com/dashboard) and select the **DEVELOPMENT** project.
2. Navigate to **Authentication** > **Email Templates** (or Email settings).
3. Select the **Confirm signup** template tab.
4. Set Subject to: `Welcome to HostAny — confirm your email`
5. Paste the entire body from `supabase/templates/confirmation.html` into the Body editor.
6. Save changes. Coordinate dashboard access and deployment with Navadeep rather than sharing administrator credentials.

### Rollback Instructions
If rollback is required, re-open the **Confirm signup** template in Supabase Dashboard and restore the previous minimal working body:
```html
<h2>Confirm your HostAny account</h2>
<p>Return to HostAny and enter this verification code:</p>
<p><strong>{{ .Token }}</strong></p>
<p>This code expires according to the project's email verification settings. If you did not request this account, ignore this email.</p>
```
And reset the Subject to: `Confirm your HostAny account`.

Do not disable confirmation to work around a missing email. If CAPTCHA is enabled,
client CAPTCHA integration is required before this slice can be used; it is not
implemented by these initial screens. Document this as a beta limitation rather
than weakening an existing production protection.

## 4. Configure and run Flutter

Copy `config/supabase.development.example.json` to the ignored file
`config/supabase.development.json`. Replace both placeholders. This file contains
public configuration only, and its values are embedded in the Flutter build.
`BUILDIFY_ENV` must be `development`; the helper rejects extra fields and server
keys. Optionally include the public `GITHUB_CLIENT_ID` for repository access.
The root `.env` is not an asset and is not loaded automatically by Flutter.

From the repository root:

```powershell
dart tool/validate_hosted_config.dart config/supabase.development.json
./scripts/run-hosted-development.ps1 -Device windows
# Or select your attached Android device ID:
./scripts/run-hosted-development.ps1 -Device YOUR_DEVICE_ID
# Build a private test APK with this account configuration:
./scripts/run-hosted-development.ps1 -BuildApk
```

On another shell/platform, validate first, then use:

```sh
flutter run --dart-define-from-file=config/supabase.development.json
```

Changing a define requires restarting/rebuilding the app, not hot reload. Android
and desktop sessions use Flutter secure storage, namespaced by project host.
The existing Android Gradle setup can also embed a device connector token from
the root `.env`; the public account JSON does not override that private-build
behavior. Keep such test APKs private. Public distribution needs the scoped
device-enrollment/connector work in #84/#96 rather than a bundled shared token.
Web builds are not a verified hosting target, and browser persistence has different
security properties. Existing account/password records in SQLite do not log in to
the cloud; create a new cloud account. Existing source/model files are retained.

## 5. Staging and production separation

Create independent hosted projects and ignored public configuration files for
staging/production before their respective launches. Set `BUILDIFY_ENV` accordingly
and validate with the second argument `staging` or `production`. Use separate
project URLs/keys, SMTP configuration, origin allowlists, and provider secrets.
Never point development test fixtures at production. The development helper
intentionally cannot build a production target.

The future management backend (#83) must validate environment, Supabase URL,
approved client origins/redirects, and feature-specific server secrets at startup.
Privileged Supabase credentials come from the hosted runtime's secrets; Cloudflare
and billing credentials remain there too. They are not part of this public JSON
contract or the initial Flutter auth integration. Rotation is maintainer-owned:
rotate in the owning provider, update only the matching environment's secret,
verify dependent behavior, then revoke the old credential. Compromised user
sessions and device credentials require their own revocation workflows.

## Verification checklist

- Validate a filled public config; reject missing/placeholder keys, server keys,
  wrong environments, non-HTTPS URLs, and extra secret fields.
- Run the hosted config/service/widget tests. Mock HTTP is not email evidence.
- In staging, sign up a fresh test email, receive a real Gmail code, confirm it,
  and check that one matching profile exists. Record redacted delivery results.
- Sign out; wrong credentials fail; unconfirmed accounts cannot enter an account
  session; valid email/password works on a second device using the same project.
- Restart the app and verify session restoration, then sign out and restart again.
- Verify account A cannot read/update account B's profile through the Data API,
  anonymous access is denied, and clients cannot insert/delete profiles or update
  identity/timestamp fields. Include an allowed owner display-name update.
- Simulate delivery failure/rate limiting, wrong/expired code, network loss, and
  secure-storage failure. Do not post codes, credentials, or account data in issues.
- Verify local hosting remains available when cloud setup is missing or offline.

No live authentication, SMTP, database migration, or two-account RLS check is
considered complete until it has been exercised on the configured development
project. Keep #77–#80 open for outstanding deployment/verification criteria.

References: [Flutter signup](https://supabase.com/docs/reference/dart/auth-signup),
[email templates](https://supabase.com/docs/guides/auth/auth-email-templates),
[SMTP](https://supabase.com/docs/guides/auth/auth-smtp),
[environment workflow](https://supabase.com/docs/guides/deployment/managing-environments).

