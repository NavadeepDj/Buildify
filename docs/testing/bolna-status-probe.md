# Buildify voice operator prototype

For ordinary incoming status calls, see [Have Bolna call your phone](bolna-phone-status-calls.md).

For Android voice calls, choose [run on the phone or control the laptop](bolna-two-device-modes.md).

The Windows app exposes authenticated owner tools over an opt-in loopback
bridge. Bolna custom HTTP functions and the official-SDK MCP stdio adapter use
the same typed manifest. This is a single paired owner/host prototype.

## Start and reuse

After source changes: `flutter build windows --debug --no-pub`.
Run `./scripts/start-status-probe.ps1 -Tunnel`, then
`node scripts/connect-bolna-status.mjs` from the repository root. The launcher
sets native-runtime paths and a temporary token in the app process. The connector
reads `BOLNA` from ignored `.env` and updates the existing agent.

The connector enables English (`en`), Telugu (`te`) and Hindi (`hi`), starting in English,
with requested or automatically detected language switching. English uses
Deepgram Nova-3 and ElevenLabs Turbo v2.5; Telugu and Hindi use Sarvam Saaras v4 and
Bulbul v3 (Priya). All three use GPT-4.1-mini and the complete Buildify tool policy.
Other languages are not enabled. Start a new call after updating.

For an owner-initiated browser call, run `node scripts/bolna-webcall.mjs`, open
the private `url` from `build/status-probe/webcall-server.json`, and click
**Call Buildify**. Grant microphone access. The link includes an invitation;
the bare localhost URL cannot start a call.
No outbound callback or phone number is needed. Dial-in telephone routing
requires a separately configured supported number.

## Android APK

Build with `./scripts/build-android-local.ps1`, or `flutter build apk --release
--target-platform android-arm64`. The packaged voice tunnel currently supports
arm64 Android devices. Install `build/app/outputs/flutter-apk/app-release.apk`.
No Bolna account key is compiled into the app.

1. In the APK, tap **Call Buildify**, then **Enable voice connection**. Wait
   until it says ready to pair. This starts a separate authenticated voice
   tunnel; model and project routing keep their own tunnel.
2. Tap **Copy pairing details**. Transfer that JSON privately to your trusted
   computer. Save it under ignored `build/android-voice/pairing.json`, then run:
   `./scripts/start-android-voice.ps1 -PairingFile build/android-voice/pairing.json`.
   If the pairing JSON is already in that computer's clipboard, use
   `./scripts/start-android-voice.ps1 -FromClipboard` instead.
3. Copy `phone_url` from `build/android-voice/webcall-server.json` back to the
   **Phone call link** field in the APK. Tap **Call to control this phone**,
   allow Buildify's microphone permission, then tap **Call Buildify** on the
   in-app call page.
4. Speak your request. Use **Review voice requests** to review model setup or other action
   approvals. The call targets this Android app; it uses a separate Bolna agent
   and session file from the Windows prototype.

Keep the helper computer online and the Android app running during calls.
Internet access is required on both. Android embeds the web call inside Buildify;
ordinary telephone dial-in still needs a supported number configured in Bolna.
Wispr is not the live-call transcriber. Calls use the existing Bolna speech
providers and account balance.

Pairing tokens are generated on the device and stay in memory. **Disconnect
voice** revokes the device connection; reconnecting or restarting the app needs
pairing again. Keep pairing JSON and private call links confidential. The helper
limits session creation to eight calls per run with a 20-second cooldown.
Run `./scripts/stop-android-voice.ps1` to stop its computer-side helper and call
tunnel, then disconnect in the APK. Android may terminate background apps;
reopen Buildify and reconnect if the phone loses its voice connection.

Automated checks cover authenticated tool access, pairing rotation/revocation,
the Android voice UI, and protected browser session creation. A physical Android
microphone call must still be verified on a connected phone.

Keep the app, tool tunnel and local web-call server open. Calls and prompt updates
do not require rebuilding. After restarting the tunnel, rerun the connector;
the URL/token rotate and the agent ID is retained. Reconnect MCP after rotation.

## Implemented groups

- Model setup: recommended or specific compatible model, visible plan, local
  approval, download/start progress, artifact checking and real inference.
- Models: catalog, installed/download state, select/download/cancel/stop/delete,
  generation settings, redacted diagnostics and fixed inference probe.
- Networking: request protected public model sharing or device/LAN scope.
- Projects: list/details, redacted logs, start/restart/stop/delete, local HTTP
  verification, public GitHub prebuilt-static import and subdomain changes.
- Local input: open the wizard, project details or environment editor for
  advanced configuration, files, account authorization and secrets.
- Jobs: list pending/recent actions and read individual action status.

Remote tools cannot approve execution. Model setup uses **Approve and run**;
other mutations use **Voice action review**. The floating voice-request menu
reopens either screen. Pending requests deduplicate; approval expires after five
minutes. Changed model artifacts or project execution settings invalidate
queued approval. Conflicting actions execute one at a time. Local review details
and environment values are not serialized into remote tool results.

Starting a project can run its saved scripts, interrupt its single active project
and start its configured public route. Advanced arbitrary repository builds,
secret/key entry and account authorization require local app input. The app's
existing runtime/platform limitations still apply.

Import is not deployment. Process state is not inference. Local HTTP verification
is not public reachability. Only actual verified model output may be described
as successful inference; historical verification becomes inactive after stop.

## Verification performed

The Windows low-memory follow-up passed 75 assistant/navigation tests. Setup can
select a smaller 1024/512/256-token context when the catalog context does not fit;
the exact context is included in the approved plan and rechecked before launch.
The 512 MiB host reserve remains. TinyLlama's optional Windows overhead budget
uses a single inference slot and 128-token processing batches; other platforms
retain their existing overhead budget. A real 512-context native run answered
`2 + 2 = 4.` with HTTP 200. Its sampled peak working set was 1029 MiB on this
Windows machine, which supports this planning adjustment but is not a guarantee
for every workload or platform. Startup still verifies actual inference.

On 15 November 2026, the assistant/navigation suite passed 65 tests. A separate
native Windows live test started cached TinyLlama, verified actual local and
authenticated public inference, rejected unauthenticated access, and cleaned up.
The full Windows integration test exercised HTTP setup request, visible local
UI approval, artifact verification, real inference and stop. It also started,
HTTP-verified and cleaned up a disposable static project. The actual setup
result is in ignored `build/status-probe/setup-live-test.json`.

Run `npm test` in `tool/buildify-mcp` with the normal app open for the MCP live
smoke check. It uses the official MCP client to discover real tools, read state
and catalog, and check rejection of remote approval arguments. Final live voice
behavior after the expanded agent update still needs owner testing.

User-project/model deletion, public GitHub imports and every advanced runtime
combination are not certified by these checks. Destructive test execution used
only a disposable fixture; approval/rejection checks used synthetic resources.

Stop the app and tool tunnel with `./scripts/stop-status-probe.ps1`. Generated
credentials/configurations stay in ignored `build/status-probe/`; do not share
its session or generated tool files. Stop the web-call Node process separately.

## Voice Go prototype

Say "Run a model". Bolna prepares a compatible plan, polls until ready, reads
its model/settings and public-sharing scope, and asks you to say "Go".
`confirm_model_setup` accepts only that ready plan's `plan_id`; duplicate Go
requests reuse the operation. No second model selection or app approval is needed.
Execution disables model API-key authorization before startup, verifies actual inference,
then starts a public Cloudflare tunnel. Poll `get_setup_status` for
`public_endpoint`, `tunnel_state`, and any `publication_error`. Public reachability
is reported separately from verified local inference. Copy the public URL from
model setup connection details; no API key or Authorization header is needed. The quick tunnel lasts while the app and tunnel remain running.
Other project/action approvals continue to use the existing review flow.

## Calling the laptop from a mobile browser

The calling device and the managed host are separate. Pair the mobile Bolna
agent with the current laptop tools using:

    node scripts/connect-bolna-status.mjs --session=build/android-voice/session.json --target-session=build/status-probe/session.json

The selected target session is saved in the ignored caller session and survives
later connector updates. `start-android-voice.ps1` also accepts `-TargetSession`.
Phone calls then use the laptop's current confirmation and email tools, with no
email credential placed on Android. Start a new call after updating an agent.

Spoken approval confirms the exact model plan or an eligible reversible model
action ID. Project actions and deletions still require local review. Both owner
UI approval buttons use the same model coordinator, including public routing and
email. A new model request clears earlier email receipts. To resend an existing
endpoint email, call `email_model_endpoint` with `resend: true`; this is limited
to once a minute and never requires stopping or restarting the model.

For an owner-requested stop confirmation email, call `email_model_stop_status`
with the exact `stop_model` action ID. This queues a notification without
approving the action; spoken approval still uses `confirm_model_action`.
`get_action_status.action_email` reports waiting, sending, accepted (`sent`),
or failure independently of the action state. The host sends only after the
stop returns verified completion, model identity and a timestamp. Repeated
requests for one action deduplicate. No recipient or message body is accepted.
Notifications continue after hangup while the host app remains running; pending
notifications and action history are in memory and do not survive app restarts.
