# Buildify voice: run on the phone or control the laptop

In the Android APK, open **Call Buildify** and choose **This phone** or **My laptop**.
Each mode uses a separate paired Bolna agent and private call link. The APK checks
the link's target before opening the in-app call screen; the call page and agent identify that
target too. Changing the selection does not move or stop a running model.

## This phone

Compatible AI models run on the Android phone's bundled ARM64 llama runtime.
Buildify checks the phone's available memory, storage and model compatibility;
a powerful phone still cannot run every model. Downloads need storage and time.
Prebuilt static websites can be imported and hosted on the phone. This does not
install Node.js, Python or npm, build arbitrary desktop apps, or generate a new
app from a spoken description. Project changes still require review in Buildify
on the phone. Model plans use the existing explicit spoken Go approval.

1. Install the updated ARM64 APK and open **Call Buildify → This phone**.
2. Tap **Enable voice connection** and wait for pairing to become available.
3. Copy pairing details and transfer them privately to your trusted helper computer.
4. On that computer, with the pairing JSON on its clipboard, run from this repo:

   ```powershell
   ./scripts/start-android-voice.ps1 -RunOn phone -FromClipboard
   ```

5. Privately copy `phone_url` from `build/android-voice/webcall-server.json` into
   the APK's **Phone call link**, then tap **Call to control this phone**.
6. Allow Buildify's microphone permission, then tap **Call Buildify** inside the
   embedded call page. Try “What device are you controlling?”,
   “Prepare a compatible model for short answers”, then approve the ready plan
   with “Go”. Ask for progress; only a successful inference check proves readiness.
7. For existing static projects, say “List my projects”, then request a project by
   name. Use **Review voice requests** inside the call screen to review the
   pending project action; the call stays mounted while reviewing.

The Android app and its voice tunnel must remain alive. Android background and
battery restrictions can end long sessions. Publishing a model or project also
requires the existing gateway and DNS configuration; a successful local start
does not prove the public endpoint works.

## My laptop

Your Android phone supplies the microphone and speaker. Models and projects run
on the laptop using its resources. Phone model hosting need not be enabled.

1. On the laptop, refresh its running Buildify connection:

   ```powershell
   ./scripts/start-voice-demo.ps1
   ```

2. Create a separate HTTPS invitation for mobile access:

   ```powershell
   ./scripts/start-android-voice.ps1 -RunOn laptop
   ```

3. Paste `phone_url` from `build/mobile-laptop-voice/webcall-server.json` into
   **Call Buildify → My laptop → Laptop call link**. Tap
   **Call to control my laptop**. Confirm the page says **Runs on your laptop**.
4. Ask for models, setup or existing project actions. Review project changes on
   the laptop. Keep the laptop app and helper online.

The two setup commands use separate state directories, agents and default ports
(19002 phone, 19003 laptop). Neither mode inherits a stale target from the other.
Old Android sessions that pointed at the laptop are not reused as phone agents.
To preview routing without changing anything, add `-ShowPlan`.

## Current voice dependency and recovery

Phone inference and static hosting run on the phone. Bolna speech and reasoning
use online services, and this prototype still needs a trusted computer running
the call helper in **both** modes. It is not yet a completely computer-free
Android voice service. Bolna account credentials stay on that computer and are
never packaged into the APK.

If PowerShell blocks a script, invoke it using a process-only policy override:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-android-voice.ps1 -RunOn laptop
```

End a call before restarting its helper. To update an existing helper while
preserving its invitation:

```powershell
./scripts/restart-voice-webcall.ps1 -Target android
./scripts/restart-voice-webcall.ps1 -Target mobile-laptop
```

Invitations are bound to the paired target and agent. Restart refuses to reuse a
link if either changes, or if old metadata lacks the binding. After ending calls,
create a fresh invitation for the selected mode with:

```powershell
./scripts/restart-voice-webcall.ps1 -Target android -NewInvitation
# Or: -Target mobile-laptop -NewInvitation
```

Copy the new `phone_url` into the APK. Previous invitation links stop working.
Failed preflight checks leave the existing helper running.

If an old link cannot verify its target, restart the corresponding helper or run
setup again. Setup refuses a busy port; stop the matching helper first:

```powershell
./scripts/stop-android-voice.ps1 -RunOn phone
./scripts/stop-android-voice.ps1 -RunOn laptop
```

Stopping the helper does not stop models or projects. Disconnect phone voice in
the APK to revoke its pairing. Keep private links and pairing details private.
For telephone callbacks after an action finishes, see
[the callback guide](bolna-phone-status-calls.md); callback numbers are configured
separately and switching device modes does not schedule a callback.

## In-app audio lifecycle

The Android call route embeds the existing HTTPS page in Android System WebView
using a Flutter platform view. No new Flutter WebView package or native Bolna
audio protocol is needed. The helper keeps the Bolna API key; the native view
receives only the validated private invitation. Runtime microphone permission
is requested before loading the page. WebView microphone grants additionally
check the exact paired origin and reject camera or unexpected resources.

**End call**, leaving the call route, audio-focus interruption, or putting
Buildify in the background ends media and restores the audio mode. It does not
stop models or projects. In-app review routes keep the call view mounted.
After a background interruption, return and use **Retry**, which rechecks the
target before loading a new call page. Background and lock-screen calling are
not implemented. Browser calling remains available by opening the private link
manually. Update Android System WebView if microphone support is unavailable.

The embedded call still requires the trusted helper and a reachable target.
It does not resolve tunnel outages or guarantee immunity from OEM process
freezing. Physical-device microphone, playback, headset/Bluetooth, interruption,
and English/Telugu/Hindi switching must be checked on an installed APK; mocked
widget tests do not prove audio quality or a successful conversation.

### Validation recorded on 16 November 2026

The ARM64 debug APK and web release build compiled successfully. Full-project
analysis reported no issues; the full Flutter suite passed 193 tests with three
skipped. After the final initialization-recovery changes, all seven call-screen
tests and focused analysis passed. The helper's 18 Node tests and all three
native origin/navigation/microphone-policy tests passed. The native tests are
also included in the Android CI build job.

No Android device was connected to ADB during this run. The APK has not been
installed or certified for live two-way audio, language switching, or audio
device routing. Complete those checks using the flow above before closing #150.

Automated tests cover independent routing, target checks, UI mode selection and
Android readiness handling. Real audio calls and model inference on a physical
Android phone still require device validation.
