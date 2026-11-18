# Have Bolna call your phone with Buildify status

This guide sets up an ordinary incoming telephone call to your Android phone.
Buildify reads its status, and a separate Bolna notification agent tells you
that timestamped snapshot. Answer in your phone's normal dialer. Keep the
computer running the helper and the selected Buildify host online.

The notification agent has no Buildify action tools. Use the interactive voice
operator to request changes; this callback reports an observation.

## Current setup

The live configuration check found a valid Bolna API key, zero telephone numbers
listed in the account, and no configured callback recipient or caller ID. A
read-only preview reached the Windows Buildify host. No telephone call was placed
and no notification agent was created during these checks.

The existing phone-browser helper currently targets the laptop. The callback
helper follows a selected session's `target_session`, too. Placing a call from a
phone does not automatically mean its tools run on Android.

## 1. Connect a caller number

In the [Bolna dashboard](https://platform.bolna.ai/agent-studio), connect a
telephone provider and a voice-enabled caller number. The current Buildify
operator uses Plivo. Follow [Plivo's Bolna connection guide](https://www.plivo.com/docs/audio-streaming/integration-guides/bolna)
to connect your account under **Settings → Integrations → Plivo**. Complete the
provider's activation requirements and ensure the accounts have call credit.

The helper checks that the caller ID appears in Bolna's
[phone-number list](https://www.bolna.ai/docs/api-reference/phone-numbers/get_all)
and matches the operator's telephony provider. It does not buy or connect numbers.

## 2. Set your recipient in the local .env

Keep the existing `BOLNA` key. Add these entries to the ignored root `.env`:

```dotenv
BOLNA_STATUS_CALL_TO=+<your country code and mobile number>
BOLNA_STATUS_CALL_FROM=+<your connected Plivo caller number>
```

Replace both placeholders with real numbers, without spaces or angle brackets.
An Indian recipient uses `+91` followed by their mobile number. These numbers are
fixed locally and cannot be redirected by conversation. Keep API keys out of
the APK.

## 3. Check and preview

Run in the repository root:

```powershell
node scripts/bolna-status-call.mjs check
node scripts/bolna-status-call.mjs preview
```

Before dialing, `to_valid`, `from_valid`, `from_owned`, and `provider_matches`
should all be `true`. The check prints booleans and counts, never phone numbers
or credentials. The preview inspects the default Windows session. A running
process alone does not establish successful inference.

For Android phone execution, select the phone-mode session from
[the two-device setup](bolna-two-device-modes.md):

```powershell
node scripts/bolna-status-call.mjs preview --session=build/android-voice/session.json
```

For the separate mobile-to-laptop mode, use
`--session=build/mobile-laptop-voice/session.json`. The callback inspects the
selected session's target, regardless of which phone receives the call.

Use the same `--session` option on the commands below when choosing that session.
Keep its authenticated tool tunnel running and reconnect stale device pairing.

## 4. Prepare the notification agent and call once

```powershell
node scripts/bolna-status-call.mjs prepare
node scripts/bolna-status-call.mjs call
node scripts/bolna-status-call.mjs call --dial
```

`prepare` creates a separate status agent using the operator's speech providers,
reuses it on later runs, and leaves the interactive agent unchanged. Its local
record lives under ignored `build/bolna-status-call/agents/<source-agent-id>.json`.

`call` without `--dial` only previews. `call --dial` submits one real telephone
call to the configured recipient and consumes call balance. It sends the
dedicated agent ID, fixed recipient/caller ID, and status snapshot using Bolna's
[outbound call API](https://www.bolna.ai/docs/api-reference/calls/make).

Answer your phone. The response's `execution_id` identifies the attempt.
`queued` means submitted, not answered. Check it with:

```powershell
node scripts/bolna-status-call.mjs status --execution=<execution UUID>
```

Replace the placeholder with the returned UUID. Review Bolna's call history if
the phone does not ring. `completed` indicates final processing finished; a
disconnected call can still be processing its result.

## 5. Call once after an action finishes

For an existing voice action, such as a model-stop request:

```powershell
node scripts/bolna-status-call.mjs watch --action-id=<action UUID> --dial
```

Get the action ID from the interactive agent's action-list/status tools. The
watcher waits for success, failure, rejection, expiry, or cancellation, then
submits one callback. It does not approve the action; complete that action's
existing approval flow separately.

Keep this command running. It stops waiting after 30 minutes without calling if
no terminal result is observed. **Ctrl+C** stops waiting. No recurring schedule
or background service is installed. Saying “call me when it finishes” in an
interactive conversation does not start this command automatically.

A durable reservation under `build/bolna-status-call/watch/` prevents another
submission when the same watcher restarts. If submission times out, its outcome
may be unknown: inspect Bolna's history before any manual retry. There is no
automatic telephone retry. A new `call --dial` is a separate deliberate call.

## Browser-call recovery

Refresh the existing call page to load these fixes: microphone permission before
session minting, **Cancel call** while connecting, a 45-second startup deadline,
fresh retries, and distinct cooldown, session-budget, and provider-capacity errors.

After ending any call, reload just the relevant helper while retaining its
private invitation and configured host:

```powershell
./scripts/restart-voice-webcall.ps1 -Target windows
./scripts/restart-voice-webcall.ps1 -Target android
```

Here `android` selects the phone-mode helper. For the separate mobile-to-laptop
helper, use `-Target mobile-laptop`. Older untagged sessions may still target the
laptop; run the explicit mode setup to create separate links.
Models, projects, and tool tunnels keep running. If the current shell blocks local
scripts, use a process-scoped invocation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/restart-voice-webcall.ps1 -Target android
```

The launcher now checks an existing public tool tunnel and replaces a stale
connection while preserving the running app pairing. Run
`./scripts/start-voice-demo.ps1` to reconnect the agent after a tool-tunnel change.

## Verification

Thirty-five focused Node tests and two launcher checks passed. Both live browser
helpers were restarted with the fixes and retained their existing private links.
The read-only status preview reached the configured Windows host.

A real outbound telephone call remains unverified until a caller number and
recipient are configured. Account, carrier and speech-provider behavior still
need an answered-call test.
