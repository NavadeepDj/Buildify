# Roadmap (reference)

## Shared accounts and SaaS management (planned)

Track the next delivery sequence in
[epic #75](https://github.com/NavadeepDj/Buildify/issues/75): shared authentication
and local-data migration, remote device/project management, subscriptions and
branded URLs, then operational readiness and staged beta validation.
[ADR 0001](decisions/0001-shared-accounts-and-management.md) records the architecture
baseline and links unresolved provider, pricing, domain, and release decisions.
This work is planned; it does not change the status of the runtime phases below.

Rough phases discussed during development. Status is indicative — check the codebase for truth.

| Phase | Topic | Status |
|-------|--------|--------|
| 1 | Flutter ↔ Kotlin MethodChannel (`buildify.ai/server`) | Done |
| 2 | Foreground service, notification, status | Done |
| 3 | Run llama.cpp server on device | Done (jniLibs + `libllama-server.so`) |
| 4 | Real GGUF download + progress + verify | Done (HTTP stream in `lib/main.dart`) |
| 5 | Cloudflare Tunnel via `cloudflared` binary | Done (jniLibs + `libcloudflared.so`) |
| 6 | Model catalog loaded from JSON + remote update | Done (`assets/models/catalog.json`) |
| — | JNI / `libllama.so` in-process (performance) | Not started |
| — | Chat tab calls real HTTP instead of simulated text | Done (Self test tab) |
| — | API key for LAN (`Authorization: Bearer …`) | Done (`docs/security-and-safety.md`) |
| — | Idle / thermal / battery auto-stop | Done (`docs/security-and-safety.md`) |
| — | Cloudflare named tunnels (account-based) | Optional |
| — | Wi‑Fi-only download toggle | Optional |
| — | Rate limiting / per-client keys | Optional |
| — | QR code for base URL | Optional |

## Native binary source of truth

- Prefer **official** [llama.cpp Android arm64 release tarball](https://github.com/ggml-org/llama.cpp/releases).
- **cloudflared** is built from source: `CGO_ENABLED=0 GOOS=android GOARCH=arm64 go build -trimpath -ldflags="-s -w" ./cmd/cloudflared/` for arm64, and `CGO_ENABLED=1 GOOS=android GOARCH=arm GOARM=7` with NDK toolchain for arm32.
- Document exact copy list in `android/app/src/main/jniLibs/arm64-v8a/README.txt`.
