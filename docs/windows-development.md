# Windows desktop build and test handoff

The public Flutter app has a Windows x64 development build. Device registration
(#84), remote commands and paid routing are separate features; this work does not
implement or deploy them. The device contract remains in draft PR #117.

## Build and run

Use Flutter 3.41.2 / Dart 3.11 and Visual Studio 2022 Build Tools with Desktop C++,
the Windows SDK, CMake, and **C++ ATL for the current x64/x86 toolset**. ATL is
required by the existing secure-storage plugin; a missing atlstr.h is a toolchain
dependency, not permission to disable credential protection.

```powershell
flutter pub get
./scripts/build-windows.ps1 -PublicConfig config/supabase.development.json
```

The public config is ignored locally and may contain only BUILDIFY_ENV,
SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and MANAGEMENT_API_URL. The packaging script
rejects other keys. Do not pass any backend `.env`, database password, SMTP key or
platform-wide Cloudflare credential. Without a config file the build supports
local-only use; a public CI artifact is not automatically an Auth-enabled release.

Run `build/windows/x64/runner/Release/buildify_flutter.exe`, or extract all of
`build/HostAny-windows-x64.zip` into a writable directory and run its executable.
Keep all adjacent files. The package includes Flutter data/plugins, sqlite3.dll
from the locked sqflite_common_ffi package, and checksum-verified CPU llama.cpp /
cloudflared with licenses. Model weights are downloaded/imported separately.
Microsoft's x64 C++ Redistributable may be needed on a clean machine; the bundle
does not assume that copying the exe alone installs the C++ runtime. Signing and
clean-machine installer testing remain distribution work, not completed claims.

The native versions/checksums are pinned in scripts/prepare-windows-runtime.ps1.
Runtime downloads occur explicitly during preparation, not at app startup. The
Windows release workflow now uses the same complete packager. A separate Windows
CI job builds/tests on windows-2022 and uploads a seven-day artifact; this is a
build/automated smoke check, not human visual or production-readiness approval.

## Desktop behavior

- Native tools launch directly with argument arrays and a restricted child
  environment, without an intermediate cmd shell. A model remains starting until
  its /health endpoint succeeds. An occupied port is rejected before launch.
- Quick-tunnel URLs assemble correctly across pipe chunks. A URL alone is not
  readiness: wait for a registered tunnel connection. Secrets are redacted from
  bounded errors; named connector tokens go through the child environment.
- Stop waits for the native process to exit. Windows project commands preserve
  quoted paths, withhold unrelated inherited host secrets, and stop their owned
  command process tree. A Windows Job Object makes the app's child processes exit
  if the desktop app closes/crashes. Keep the window open while hosting.
- Windows reports real memory/disk/CPU/power data through its own method channel.
  It doesn't display phone placeholder hardware. Model endpoints bind loopback;
  use the local loopback URL or a deliberate tunnel, not a fictitious LAN listener.
- Phone-only thermal/battery/idle auto-stop controls are not advertised as active
  Windows controls. Windows continues to manage system power/thermal behavior.
- New databases use application support/databases. An existing legacy desktop
  working-directory database is preserved in place, without schema/owner changes.
  No project migration, files deletion or #82 claim rule is introduced here.
- A missing Windows named-tunnel connector does not start an endless automatic
  reconnect loop; local model hosting and deliberate quick tunnels still work.

## Verification

```powershell
flutter analyze
flutter test
flutter test integration_test/windows_smoke_test.dart -d windows --dart-define-from-file=config/supabase.development.json
```

The integration test runs the actual Windows plugins, round-trips a dedicated
synthetic secure-store key then deletes it, opens SQLite schema, checks real
hardware metrics, mounts the app and navigates into local hosting. It does not
read or change account passwords/project records. Live dashboard timers require
bounded pumping rather than waiting for the UI to become permanently idle.

Opt-in native smoke (never automatically enabled in CI): set HOSTANY_WINDOWS_LIVE=1,
HOSTANY_SMOKE_MODEL to an absolute GGUF path, BUILDIFY_LLAMA_SERVER and
BUILDIFY_CLOUDFLARED to the prepared executables, then run:

```powershell
flutter test test/services/windows_runtime_live_test.dart
```

Set HOSTANY_CHAT_SMOKE=1 for a chat-template model (for example TinyLlama), otherwise
the small ggml-org stories model uses /completion. The smoke requires real local
and public inference, rejects missing API keys, and closes both processes in
finally. It exposes only the disposable model endpoint behind a synthetic key,
never user project files. Normal flutter test skips this network/native check.

## Evidence from 2026-11-07

- C++ toolchain installed; Windows release compiled. The existing secure-storage
  plugin needed additional ATL headers. Quiet installer modification required
  elevation; the local build used matching Microsoft ATL VSIX headers/libraries
  verified against official catalog hashes, extracted under ignored build tools.
  No installed SDK was patched and no security setting changed. Future developers
  should install the normal ATL component. Local overrides are not app dependencies.
- All 88 Flutter tests passed; three expected skips, including the opt-in live test.
- Real Windows integration passed secure storage, startup, SQLite, hardware metrics
  and local dashboard navigation. Static analysis was clean before final docs.
- Both small-model completion and catalog TinyLlama chat passed locally and through
  temporary Cloudflare tunnels; unauthenticated requests were 401, processes were
  stopped and ports released. No permanent DNS/tunnel/backend changes were made.
- Reports/models are under ignored build/windows-testing. Native packages and
  versions are under build/windows-runtime. No binaries/models belong in Git.
- Native screenshot automation failed to initialize (missing kernel assets), so
  no human-style visual review or manual sign-in using the owner's account is
  claimed. The owner should test sign-in, resizing, model import/chat and restart.

Source edits are on feat/windows-desktop-ready, independent of the #84 contract
branch. Keep this evidence with its PR; update outcome/build hash when packaging
changes. Android compiler intermediates were cleared to make room for C++ tooling;
source, APK outputs, archived worktrees and private service files were preserved.
