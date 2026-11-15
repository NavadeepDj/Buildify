# Buildify voice operator prototype

The Windows app exposes authenticated owner tools over an opt-in loopback
bridge. Bolna custom HTTP functions and the official-SDK MCP stdio adapter use
the same typed manifest. This is a single paired owner/host prototype.

## Start and reuse

After source changes: `flutter build windows --debug --no-pub`.
Run `./scripts/start-status-probe.ps1 -Tunnel`, then
`node scripts/connect-bolna-status.mjs` from the repository root. The launcher
sets native-runtime paths and a temporary token in the app process. The connector
reads `BOLNA` from ignored `.env` and updates the existing agent.

For an owner-initiated browser call, run `node scripts/bolna-webcall.mjs`, open
`http://127.0.0.1:19001`, and click **Call Buildify**. Grant microphone access.
No outbound callback or phone number is needed. Dial-in telephone routing
requires a separately configured supported number.

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
