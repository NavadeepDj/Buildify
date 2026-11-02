# GitHub repository authorization

Buildify uses GitHub OAuth device flow for the native Flutter app. The user opens GitHub in their browser, enters the displayed code, authorizes access, then returns to select a repository. Tokens are kept in flutter_secure_storage and never saved with project metadata.

## Configure

1. At https://github.com/settings/developers create an **OAuth App** (not a GitHub App). Use your product homepage. GitHub requires a callback URL in registration; use your homepage URL, since device flow does not use a redirect callback.
2. Enable **Device Flow** in the OAuth app settings.
3. Copy the public **Client ID** into `GITHUB_CLIENT_ID` in your local `.env` file. The Client ID is public app identification; never put the OAuth app's client secret in the Flutter app.
4. For Android debug runs, pass the define explicitly: `flutter run --dart-define=GITHUB_CLIENT_ID=YOUR_CLIENT_ID`. For a private release APK, run `scripts/build-android-local.ps1`; it reads the Client ID from `.env` and passes it to Flutter. The project's `.env` is in `KEY=value` format, so do not pass it to Flutter's JSON `--dart-define-from-file` option.

The app requests the OAuth `repo` scope to list and download private repositories as well as public repositories. GitHub grants broad read and write capabilities to this OAuth scope, although Buildify currently makes read-only API calls. Organizations may require approval or SSO authorization. This implementation imports a branch snapshot; it does not install webhooks or automatically redeploy changes.

## Verify with a real account

- Tap GitHub in the hosting wizard; copy the code and open GitHub.
- Approve, return to Buildify, search for a repository, then import it.
- Confirm a private repository downloads and its default branch appears in settings.
- Try a different branch and confirm the downloaded contents match.
- Decline authorization, let a code expire, and leave the screen while waiting; retry should remain available without navigating after leaving.
- Revoke the OAuth authorization in GitHub settings; the next import should ask you to reconnect after clearing the invalid session.

To revoke access, visit https://github.com/settings/applications. Buildify reuses the securely stored token until GitHub rejects it. Account switching currently requires revoking authorization and reconnecting.

Reference: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
