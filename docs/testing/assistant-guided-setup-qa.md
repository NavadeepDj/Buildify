# Guided model setup: Windows and Android manual QA

Owner: tester named in the result sheet. Maintainer: Navadeep.
Related: [pilot #131](https://github.com/NavadeepDj/Buildify/issues/131),
[integration #144](https://github.com/NavadeepDj/Buildify/pull/144),
[navigation #145](https://github.com/NavadeepDj/Buildify/issues/145).
Prepared: 13 November 2026. This is a test procedure, not completed test evidence.

## What we are testing

A user chooses a task and preference, reviews a model setup plan, approves it,
observes download/integrity/startup/inference steps, and receives connection
details after a real response. The guided operation uses device/LAN scope.
Public sharing is a separate deliberate action with authentication checks.

Cloud conversation, voice, project deployment, remote device control and broad
model-performance claims are outside this test. The existing automated test
results do not replace these real-device checks.

## 0. Maintainer handoff and access gate — required before testing

The maintainer must supply:

- An identified Windows bundle and Android APK from the complete integration.
  Record commit SHA, build date/version, download location and app package ID.
- A normal navigation path to **Model setup assistant**, and to the screen with
  **Allow public AI sharing**. Supply the exact clicks for this build.
- Bundled/installed llama-server and cloudflared versions for each platform.
- A dedicated test device/profile, a dedicated model API key for public tests,
  and a permitted tunnel mode (quick or configured named gateway).
- A place to submit sanitized results and bug reports.

**Known access blockers at preparation time:** #144 is open, and the assistant
button is currently attached to AiServerShell while normal app navigation uses
other pages. #145 tracks that missing integration. The NetworkScreen sharing
switch has the same access concern. Do not tell testers to find a button that
their build cannot expose. Recheck these issues when distributing the build.

The expected controls, once the access gate is fixed, are:

1. Open Buildify through its normal launcher/home flow.
2. Follow the maintainer-supplied AI hosting path.
3. Open **Model setup assistant**.
4. Confirm **Task**, **Speed / Balanced / Quality**, **Allow replacing the current
   model session**, and **Prepare a plan** are visible.
5. Confirm the supplied network path exposes **Allow public AI sharing**.

If any step is unavailable, mark **BLOCKED — Q00**, attach a screenshot and the
build SHA, and request the correct build/navigation fix. Do not substitute an
isolated widget-test screen and mark the end-to-end navigation case passed.

## 1. Test equipment and baseline

### Minimum pilot coverage

- One Windows x64 host using the complete packaged app.
- One physical Android device with its Android version and ABI recorded.
- Repeat core cases on both. Each result belongs to that specific host/model/
  runtime combination; one passing phone does not certify all Android devices.
- For public-access cases, use a second client on a different internet
  connection. Same-Wi-Fi LAN access alone does not prove public reachability.

Use a small curated model for the first run. **Short answers + Speed** normally
prefers a small candidate when resource checks permit it. Record the actual
selection; do not require one model on every device. The catalog currently
contains roughly 669 MB, 986 MB and 2.4 GB artifacts. Available memory, context
budget and storage reserve determine whether a candidate can be prepared.

### Windows preparation

- Extract the entire supplied bundle into a writable test folder. Keep its
  DLLs, data and native runtime directories beside the executable.
- Launch `buildify_flutter.exe`. A lone copied executable is not a valid bundle.
- Keep the app open while hosting. Use the host's displayed loopback endpoint
  for local checks; Windows currently does not advertise a LAN listener.
- Developer-built bundles follow [Windows setup](../windows-development.md).
  The documented baseline is Flutter 3.41.2; testers using supplied artifacts
  do not need to install Flutter or upgrade their SDK.

### Android preparation

- Install the maintainer-supplied test APK on a dedicated test device/profile.
- Record model, Android version, ABI, total/available memory, free disk, battery
  and whether charging. Let the device cool before inference tests.
- Confirm the APK has the required native runtime for this ABI. App installation
  alone does not prove llama-server is present.
- Keep the app foreground for the first core run. Background/lock behavior is a
  separate case. Keep battery/thermal safeguards enabled.
- Use an approved test connector if named tunnels are configured. Do not
  redistribute a private APK containing a connector credential.

### Shared baseline

- Use synthetic prompts and owner-controlled test data only.
- Stop active test sessions before the clean-start case. Do not stop somebody
  else's service or delete personal models/projects to prepare a test.
- Turn **Allow public AI sharing** OFF before the local run.
- Record whether the selected model is already installed. The fresh-download
  and cancellation cases require a model not already present.
- Have Postman or an equivalent HTTP client ready. For Android LAN checks, use
  the actual phone LAN IP and port from Buildify. `127.0.0.1` on a laptop means
  that laptop, not the phone.

## 2. Core cases — run on both Windows and Android

### Q01 — Prepare a plan without running it

1. Open the setup assistant. Choose **Short answers**, then **Speed**.
2. Leave **Allow replacing the current model session** unchecked.
3. Tap **Prepare a plan** once.
4. Read the proposed model, download size, estimated memory, context, access
   scope and interruption behavior.
5. Wait briefly without approving; navigate away and return if supported.

**Pass:** the plan or a clear refusal appears. No model download, model start or
new public tunnel occurs merely because the plan was prepared. The plan states
that runtime compatibility is not yet verified. It is an estimate, not a promise
of model speed or quality. Approval remains a separate action.

Record plan screenshot, selected model, resource readings and preparation time.
If resources cannot support any candidate, use Q07 to assess the refusal; mark
the successful-start case blocked on hardware rather than fabricating a pass.

### Q02 — Approve, run and independently verify inference

1. With adequate resources, approve the reviewed plan using **Approve and run**.
2. Observe each visible stage: checking settings, download/reuse, integrity
   check, configuration, startup, and testing a real response. Fast stages may
   pass too quickly to photograph; record the stages actually observed.
3. Check that repeated approval is unavailable while the operation runs.
4. On success, record the model ID, base URL, test duration and auth guidance.
5. Copy the base URL and send the independent request in section 4.
6. Use **Stop model**, then send a new request to the same local endpoint.

**Pass:** **Connection ready** appears only after inference verification; the
independent request returns nonempty generated text. Copying the URL copies the
displayed address. Stop prevents new successful inference requests.

**Fail:** a process/health page alone is reported as completed inference, the
response is empty, the displayed address belongs to the wrong host/model, or a
new request still generates after the model has stopped.

Record total setup time separately from download, warmup and the displayed
single-request time. No universal tokens/second or visitor threshold is required.

### Q03 — Cancel an in-progress download

1. Use a candidate absent from the test profile. Avoid deleting an existing
   personal model. A maintainer can provide a clean profile if needed.
2. Prepare and approve its plan. While **Downloading or reusing the model** is
   active and bytes are transferring, tap **Cancel setup**.
3. Wait for cancellation/cleanup to settle. Record elapsed time and any delay.
4. Check the model has not started and that no public endpoint was created.
5. Confirm previously installed models/projects are still present.
6. Prepare a fresh plan and retry. Verify it does not claim an incomplete file
   is a ready model; complete the run if practical.

**Pass:** the operation reaches a cancelled or explicit needs-attention outcome,
never successful setup; it eventually releases the host for another operation.
Existing assets survive. An assistant partial file may remain for recovery;
zero leftover bytes is not required. Cancellation does not promise resume from
the previous byte offset.

**Fail:** continued startup after cancellation, false success, a permanently busy
host, or deletion/corruption of unrelated assets. If the download finished before
Cancel was tapped, mark this attempt **NOT TESTED** and repeat with a suitable
candidate; cancelling after completion does not exercise this case.

### Q04 — Device/LAN scope does not create public exposure

1. Keep public sharing OFF. Complete Q02 with a fresh plan.
2. Observe tunnel/named-URL indicators, then leave the app idle for at least
   30 seconds to cover reconnect timer activity.
3. If this device had a public model URL earlier, send a NEW small inference
   request to that old URL from an external client.
4. Repeat after navigating away/back and after an app reopen on this test host.

**Pass:** no public model route is created or silently reconnected. The previous
public URL, when available, cannot produce fresh model output under local scope.
Local inference can still work. An unrelated project gateway process may remain
running; its existence alone is not an AI-publication failure.

Device/LAN is not a guarantee of loopback-only access: Android can listen on LAN
interfaces, and local authentication depends on its configured setting. A phone
answering on the same Wi-Fi is not proof of public internet exposure.

### Q05 — Active workload requires explicit interruption consent

1. Start a test model successfully and record its identity/endpoint.
2. Prepare another setup with replacement permission unchecked; approve it.
3. Confirm the existing model has not been silently stopped or replaced.
4. Prepare a NEW plan with replacement permission checked and approve it.

**Pass:** the first attempt refuses conflicting work; the approved replacement
attempt may stop the old model and reports the new operation's actual result.
Record which model runs afterward. A failed replacement must not be described
as a successful new service, nor imply the old one was restored automatically.

### Q06 — Plan expiry and duplicate actions

1. Prepare a plan, wait more than five minutes, then attempt approval.
2. Confirm the expired plan does not start download/model actions; prepare a
   fresh plan to continue.
3. On a new valid plan, double-tap approval and navigate away/back during work.

**Pass:** stale approval is refused, and duplicate taps do not create competing
setup jobs or duplicate model processes. Observed progress remains associated
with the same operation. Record app responsiveness and any duplicate traffic.

## 3. Failure and lifecycle cases

Run Q07–Q09 on each host where practical. Q10–Q11 require maintainer-provided
fixtures; testers should mark them blocked when those fixtures are unavailable.

### Q07 — Insufficient or unavailable resources

Use a dedicated constrained VM/emulator/device or a maintainer fixture. Do not
fill a primary phone's storage or deliberately destabilize the OS.

Prepare a plan when available memory/disk is insufficient, then repeat when a
metric is unavailable if a supported fixture exists.

**Pass:** a clear refusal/needs-attention outcome; missing data is not replaced
with a confident compatibility claim, and no download/start is silently triggered.
Capture the actual readings. If resources recover, a new inspection can produce
a new plan. Do not require a fixed model choice across different hosts.

### Q08 — Network loss during download

On the dedicated test host, disconnect its network during transfer, then restore
it. Observe failure/cancel behavior, app responsiveness and the ability to prepare
a fresh plan. The stream has an idle timeout; a disconnect need not fail instantly.

**Pass:** there is no premature success, incomplete bytes are not accepted as a
model, and retry/owner recovery is possible. Record time to outcome and whether
the next download restarts. Test with a small permitted data budget.

### Q09 — Background, app exit and interruption

- Android: lock/background briefly during a run, then return. Record OS/device
  behavior, safety stops, whether progress resumes and whether inference works.
- Windows: close the app only on a dedicated test run. Reopen and inspect state.
  Windows child processes are expected to stop when the app exits.
- During a separate setup attempt, interrupt/reopen the app if the maintainer
  permits it. Do not clear app data. Check whether it reports/reconciles uncertain
  work rather than silently replaying a start/download.

**Pass:** actual state is reported accurately; no guaranteed background uptime is
implied; uncertain interrupted work is not replayed without review. If the UI has
no way to find the interrupted operation, report that recovery gap. Persistent
journal files alone do not prove usable recovery. Never disable thermal/battery
protection to obtain a passing result.

### Q10 — Artifact integrity fixture (maintainer-assisted)

The maintainer supplies a dedicated profile containing an invalid/truncated
artifact at the exact selected model location and documents how it was prepared.
Do not edit production/user files or substitute an arbitrary download URL.

**Pass:** byte/hash mismatch stops before inference success; the existing file is
not silently treated as valid or deleted. Record the error code, selected model
and fixture identifier. Recovery may require an explicit owner action.

### Q11 — Missing runtime / occupied port fixture (maintainer-assisted)

Use a disposable bundle without the inference binary, or a dedicated local
service occupying the expected test port. The maintainer owns fixture setup and
cleanup; do not terminate unrelated applications or remove their binaries.

**Pass:** no false Connection ready result, no inference request is mistaken for
another service's model response, and the app remains usable. Record which fixture
was used and whether a running process needs explicit cleanup afterward.

## 4. Independent inference request — Postman or equivalent

Use the actual address shown by the build. If the copied base ends in `/v1`, add
`/chat/completions` once. For example, a Windows host may show
`http://127.0.0.1:8080/v1`; its request URL is
`http://127.0.0.1:8080/v1/chat/completions`.

For Android, use the in-app Self test on the phone, or its reachable LAN address
from a same-network client. Loopback on the laptop does not address the phone.

1. Method: **POST**. Disable automatic redirects for the test.
2. Header: `Content-Type: application/json`.
3. If the running model requires a key, add `Authorization: Bearer <test-key>`
   using a local secret variable. Never paste the real key into a shared report.
4. Body:

```json
{
  "messages": [{"role": "user", "content": "Give one short greeting for test Q02."}],
  "max_tokens": 16,
  "temperature": 0,
  "stream": false
}
```

If this runtime requires `model`, use the actual advertised model identifier
from its model listing; a Buildify catalog ID and the runtime's API model alias
need not be identical. Record that distinction rather than inventing an alias.

**Success evidence:** actual HTTP status, elapsed time and nonempty
`choices[0].message.content`. A Cloudflare page, auth challenge HTML, stale UI
card or successful `/health` response alone is not generated model output.

## 5. Public sharing and authorization — separate cases

Run only with a dedicated key and maintainer-approved network configuration.
If no working connector/network route is provided, mark these **BLOCKED** rather
than changing DNS/provider credentials or waiving authentication. The guided
setup action itself does not support public scope; these tests use Network.

### Q12 — Explicit publication with a protected model

1. Complete local inference first.
2. Enable **Allow public AI sharing**. Confirm API-key protection is enabled.
3. Stop and restart the model so the configured key is applied to the process.
4. Use the supported tunnel flow. A configured named route may connect
   automatically; otherwise deliberately start the quick tunnel.
5. Copy the actual displayed HTTPS URL. From the separate-network client, send
   the section 4 request with the correct key.

**Pass:** fresh nonempty inference succeeds via the approved public URL. Record
route mode and network arrangement. A same-Wi-Fi LAN request is not a substitute.

### Q13 — Missing/wrong key cannot generate

At the same URL, send new requests with no Authorization header, an intentionally
wrong dedicated test key, then the correct key. Avoid inherited Postman auth or
cookie settings that could accidentally supply valid credentials.

**Pass:** missing/wrong keys cannot produce inference; the correct key still
works. Record observed rejection statuses; do not assume every health endpoint
requires authentication. Report unauthorized generation privately to the
maintainer under [SECURITY.md](../../SECURITY.md), not with live keys/URLs in a
public issue. Stop public testing if unauthorized generation occurs.

### Q14 — Revoke publication and test reconnect behavior

1. With a public model working, switch **Allow public AI sharing** OFF.
2. Immediately send a new public inference request, then retry after at least
   30 seconds and after navigating away/back.
3. Confirm local inference still behaves as expected. Stop any outstanding
   requests before judging whether new work can begin.
4. With maintainer permission, repeat rapid ON → OFF during connection startup.

**Pass:** no NEW public model inference is accepted after revocation settles;
retry timers and late saves do not re-enable sharing. Existing in-flight work
may have different cancellation behavior: record it separately. Public failure
codes may vary; inability to generate is the relevant result.

### Q15 — Key changes and app reopen

1. Enable sharing and establish protected public inference.
2. Regenerate the model key using the existing security controls. Confirm public
   intent is revoked. Re-enable sharing only after deliberately applying the new
   key to a restarted model; old-key inference must fail afterward.
3. On a separate run, disable Require API key. Confirm public sharing becomes
   OFF; the unprotected model must not be published automatically.
4. Reopen the app while a previously started model may still exist. The app
   cannot assume that saved key settings prove the existing process has them;
   record any required restart instead of treating it as silent publication.

**Pass:** key settings cannot grant access merely by changing UI preferences;
the running process and publication gate agree before protected sharing works.

## 6. Results, severity and completion gate

Use **PASS**, **FAIL**, **BLOCKED**, or **NOT TESTED** for every required case.
Never leave a blank result or mark a case passed solely because an automated
test covers related logic. Copy the [result template](assistant-guided-setup-results-template.md)
for each host/model combination. Keep real credentials out of the shared copy.

- Treat unauthorized generation, unapproved public exposure, unrelated data loss
  or an unapproved workload replacement as a release blocker. Report sensitive
  findings privately and preserve sanitized evidence.
- Treat false success, inability to cancel/retry, unusable navigation and missing
  recovery controls as feature blockers for the affected workflow.
- Record confusing copy, visual clipping and timing problems separately; do not
  mask functional failures as cosmetic issues.

The local pilot is ready for maintainer sign-off only after Q00–Q06 pass on both
Windows and physical Android, Q07–Q09 outcomes are documented, and Q10–Q11 have
evidence or an explicit outstanding gate. Public sharing has a separate gate:
Q12–Q15 must pass with an independent network client before claiming public
readiness. Mark it unvalidated if fixtures/network access are unavailable.

All required failures/blocked cases need a linked issue and retest outcome.
Do not close #131 based on this document alone. Source build, tested runtime,
device and remaining limits must be named in the sign-off.

## 7. Cleanup

Stop test inference and public sharing, confirm old public URLs cannot generate
new responses, revoke/rotate dedicated test credentials through the owner, and
let the maintainer remove only documented disposable fixtures. Preserve user
models/projects and sanitized reports. Leave the host in its recorded baseline
state and note any partial artifacts or running services needing attention.
