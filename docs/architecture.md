# Architecture

## Shared account and SaaS direction

[ADR 0001: Shared accounts and SaaS management](decisions/0001-shared-accounts-and-management.md)
defines the target cloud identity, database, API, device-agent, subscription, and
hostname boundaries tracked in [epic #75](https://github.com/NavadeepDj/Buildify/issues/75).
It distinguishes planned behavior from the local runtime described below. Local
project files and AI inference stay on hosting devices; shared identity does not
move compute to Supabase.

Buildify turns an Android phone into a **small HTTP server** that runs a **GGUF** model locally. Other devices on the same Wi‑Fi call it like a mini "Ollama on a phone." An optional **Cloudflare Tunnel** exposes the server to the internet via a public HTTPS URL. **Tailscale** provides a private mesh VPN so tailnet devices can reach the server.

## High-level flow

```text
┌─────────────────────────────────────────────────────────────┐
│  Flutter (Dart) — UI only                                    │
│  • Model picker, download progress, Start/Stop, logs, IP     │
│  • Tunnel start/stop, public URL display                     │
└───────────────────────────┬─────────────────────────────────┘
                            │ MethodChannel: buildify.ai/server
                            │  startServer / stopServer / getServerStatus
                            │  getLocalIp / getTailscaleIp / getModelBasePath
                            │  startTunnel / stopTunnel / getTunnelStatus
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Kotlin — MainActivity + AiServerService (foreground)        │
│  • Notification while running                                 │
│  • Spawns native process, sets LD_LIBRARY_PATH               │
└───────────────────────────┬─────────────────────────────────┘
                            │ ProcessBuilder
                ┌───────────┴───────────┐
                ▼                       ▼
┌─────────────────────────────┐ ┌─────────────────────────────┐
│  llama.cpp — llama-server   │ │  cloudflared — tunnel client │
│  • Loads GGUF, inference    │ │  • --url http://localhost:8080│
│  • Binds 0.0.0.0:8080      │ │  • Public URL via trycloudflare│
└──────────────┬──────────────┘ └──────────────┬──────────────┘
               │ reads                          │ connects to
               ▼                                ▼
┌─────────────────────────────┐ ┌─────────────────────────────┐
│  App-private storage:        │ │  Cloudflare edge network     │
│  files/models/<name>.gguf   │ │  → HTTPS public URL → phone  │
└─────────────────────────────┘ └─────────────────────────────┘
               ▲
      HTTP from laptops / other phones
      http://<phone-lan-ip>:8080/...
      https://<tunnel-id>.trycloudflare.com/...
```

## Design rules (project)

- **Flutter** owns UI and state; it does not embed the inference runtime.
- **No Termux** and **no Python/FastAPI** inside the shipped Android app (desktop prototypes like `llamaserver.py` are optional dev tools only).
- **Foreground service** is required so Android is less likely to kill the server.
- **Bind to `0.0.0.0`** (not only `127.0.0.1`) so LAN clients can connect.
- **Cloudflare quick tunnel** (`cloudflared tunnel --url`) provides a public HTTPS URL with no account required.

## Key source files

| Area | Location |
|------|----------|
| UI + download + channel bridge + Tailscale detection | `lib/main.dart` |
| Model catalog (JSON) | `assets/models/catalog.json` |
| MethodChannel handlers | `android/.../MainActivity.kt` |
| LLM foreground service | `android/.../AiServerService.kt` |
| Resolve llama-server binary | `android/.../LlamaServerBinary.kt` |
| Tunnel foreground service | `android/.../CloudflareTunnelService.kt` |
| Resolve cloudflared binary | `android/.../CloudflaredBinary.kt` |
| Native libs layout | `android/app/src/main/jniLibs/arm64-v8a/` |
| Cloudflared (arm32) | `android/app/src/main/jniLibs/armeabi-v7a/` |

See [android-llama-engine.md](android-llama-engine.md) for why the binary lives under jniLibs.
