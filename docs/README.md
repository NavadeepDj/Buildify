# Buildify documentation

[Assistant host inspection](assistant-host-inspection.md) documents the first
Buildify AI foundation: fresh local measurements and read-only runtime tools.
Track the model-first assistant roadmap in
[epic #124](https://github.com/NavadeepDj/Buildify/issues/124).

[Hosted development setup](hosted-development.md) covers creating the development
project, applying the account migration, configuring verification mail, and
running Flutter with validated public configuration.

[HostAny delivery tracks](hostany-delivery-tracks.md) maps epic #75 to Navadeep,
Sujith, and Harita, including issue ownership, dependencies, and file handoffs.

For the planned shared-account backend, start with
[ADR 0001: Shared accounts and SaaS management](decisions/0001-shared-accounts-and-management.md).
It covers Supabase Auth/PostgreSQL, SQL migrations without a new ORM, device
ownership, remote commands, subscriptions, domain routing, and release blockers.

Index of guides for **Buildify AI Server** (Flutter Android → local LLM HTTP server).

| Doc | What it covers |
|-----|----------------|
| [architecture.md](architecture.md) | End-to-end flow: UI, MethodChannel, service, engine, model |
| [android-llama-engine.md](android-llama-engine.md) | Why jniLibs, `libllama-server.so`, tarball layout, Gradle packaging |
| [models-and-downloads.md](models-and-downloads.md) | GGUF only, curated URLs, `files/models/`, ADB copy tricks |
| [api-and-testing.md](api-and-testing.md) | LAN URLs, Postman, `/health`, `/v1/chat/completions`, response fields |
| [security-and-safety.md](security-and-safety.md) | API key, auto‑stop (idle / battery / thermal), Authorization header |
| [troubleshooting.md](troubleshooting.md) | Common errors (`Permission denied`, missing `.so`, Wi‑Fi) |
| [product-vision.md](product-vision.md) | Goals, constraints (local-only), what we do *not* ship |
| [roadmap.md](roadmap.md) | Implemented vs planned phases |
| [marketing-site-deployment.md](marketing-site-deployment.md) | **buildify.me** — pnpm vs npm, Vercel vs GitHub Pages, Cloudflare DNS |

Project root [README.md](../README.md) has **quick start** and **contributing** (Git workflow, PR checklist). The Next.js site lives in [website/](../website/).
