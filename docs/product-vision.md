# Product vision and constraints

## Shared services direction

The local compute goal remains: project servers and model inference run on the
user's device. Planned shared accounts, remote management, and paid branded URLs
are defined in [ADR 0001](decisions/0001-shared-accounts-and-management.md).
The target local/LAN core remains usable without a paid plan or cloud login;
cloud enrollment and entitlements govern platform-managed remote services.
These are target boundaries, not claims that the SaaS features are shipped.

## Goal

Let **non-developers** install an app, **download an open model**, tap **Start**, and have a **local AI HTTP server** on their Wi‑Fi — **no paid cloud inference** for the core experience.

## In scope

- **Local GGUF** models only (via llama.cpp).
- **Curated** small models suitable for phones (1–4B class Q4 first).
- **LAN access** (`0.0.0.0`) for household / lab devices.
- **OpenAI-compatible** endpoints where possible (`/v1/chat/completions`) for tool compatibility.

## Explicitly out of scope (for this product direction)

- **Cloud API keys** inside the app as a first-class “paste your Gemini/OpenAI key” feature — that undermines the “phone is the server” story (can be a separate product mode later if desired).
- **Closed models** without downloadable weights (Gemini Flash, GPT‑4, etc.) as *local* runtimes.

## Practical limits

- **RAM, thermals, battery** — sustained inference is heavy; future work: idle shutdown, thermal hooks, low-power presets.
- **Throughput** — expect single-digit to low teens tokens/sec on CPU for small models; set user expectations in UI.

## Legal / distribution

- Ship **LICENSE** files for bundled native binaries where required.
- Model licenses differ; surface **short license hints** in the model store when you expand the catalog.
