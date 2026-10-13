# Buildify AI Server

<p align="center">
  <img src="demo-video/buildify-brief-small.gif" alt="Buildify demo — host anything from your phone: run a local AI model or your project, on your own device" width="640">
</p>


Flutter Android app that turns a phone into a **local LLM HTTP server** on your Wi‑Fi: pick a GGUF model, start the server, and other devices call OpenAI-compatible endpoints (e.g. `/v1/chat/completions`) on the phone’s LAN IP.

**Stack:** Flutter UI → MethodChannel → Kotlin foreground service → [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server` → GGUF on your device.

## Requirements

- Flutter SDK (see `pubspec.yaml` for Dart SDK constraint)
- Android device or emulator (arm64 recommended)
- **Native binaries:** ship `llama-server` and companion `.so` files under `android/app/src/main/jniLibs/arm64-v8a/` (see `android/app/src/main/jniLibs/arm64-v8a/README.txt`). Android does not allow executing binaries copied from app assets into private storage; jniLibs + `libllama-server.so` naming is required.
- Models download into app storage (`files/models/`); curated URLs are in `lib/main.dart`.

## Quick start (developers)

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Place GGUF models via in-app download or adb into the app’s `files/models/` directory (see project docs / logs).

## Documentation

### Persistent project Live URLs

Project Detail uses a project-name slug plus a random suffix, such as
`https://my-project.buildiify.tech`. The project-name label is preferred; a random
suffix is added on collision or for a reserved name. SQLite schema v3 stores `subdomain`,
`live_url`, and `live_url_status`, with a unique subdomain index. Existing v2
placeholder subdomains are cleared during migration and assigned once on first
load. Source repository URLs remain separate. Ephemeral project identities are
released on deletion; stale ephemeral records are cleared on startup.

The backend starts a streaming HTTP/WebSocket router on loopback port 8787 and
a separate authenticated management API on loopback port 8788. Project ports
remain allocated by the existing backend (3000–3099). The app must run on the
same host as cloudflared and the project processes. It keeps the existing
single-active-project lifecycle. Starting/stopping a project no longer starts
or stops a temporary tunnel: Project Detail starts **buildiify-gateway**, reusing
tunnel `b3ff649c-04c3-48d4-9d7a-aa9cda8f8efd`.

For a private Android build, put `CF_TUNNEL_TOKEN` in the ignored local `.env`.
Android Gradle loads only that connector credential into native BuildConfig,
including ordinary `flutter run` and debug builds without special flags.
The app imports the connector
token into device secure storage and automatically connects the named subdomain
when the AI server starts. No token prompt is needed. This private APK contains
the connector credential and must not be distributed publicly. The `.env` is
not a Flutter asset and is not committed to Git.

For builds without a configured token, tap **Configure gateway** in the Live URL field and enter only the
connector token from the existing tunnel's install command in Cloudflare. This
is a tunnel connector credential, not the Cloudflare API token. It is stored in
Flutter secure storage on the hosting device and passed to the native
cloudflared process through `TUNNEL_TOKEN`, never a command-line argument or
project environment variable. Then tap **Start Tunnel** (or Start Server for
future launches). The same Android foreground service used by the model tunnel
runs the named gateway against its remotely configured wildcard ingress.
The existing model button continues to use a temporary tunnel; Android supports
one active tunnel service, so stop the model tunnel before starting the gateway.
The gateway remains running when a project stops, serving the stopped-project
page. Desktop hosting can use `CF_TUNNEL_TOKEN` in the server process environment.
DNS and ingress still require the one-time setup below; entering the connector
token alone does not configure wildcard DNS. A shared tunnel on several phones
with independent project databases cannot route projects reliably: use one
hosting device or a shared reachable project router.

Copy `.env.example` and load the values into the process environment before
starting the app or setup script; these processes do not automatically load
dotenv files. `BASE_DOMAIN` defaults to `buildiify.tech`, `ROUTER_PORT` to 8787,
and `LIVE_URL_API_PORT` to 8788. Set `LIVE_URL_API_TOKEN` to a strong random
management token. `RESERVED_SUBDOMAINS` adds comma-separated reserved labels.
Keep account API credentials, `CF_ACCOUNT_ID`, and `CF_ZONE_ID` server-side;
never put those in Flutter assets, project environment variables, or frontend
build defines. Only the connector credential is supported in private device builds.
Cloudflare credentials are used only by the setup script, never per project.

Run the one-time setup with Node 22+:

```sh
node scripts/setup-tunnel.js
```

For a remotely managed tunnel, set `CF_TUNNEL_MANAGEMENT=remote`,
`CF_ACCOUNT_ID`, `CF_ZONE_ID`, `CF_TUNNEL_ID`, and `CF_API_TOKEN`. Scope the token
to Zone:DNS:Edit and Account:Cloudflare Tunnel:Edit for the chosen account/zone.
The script preserves existing specific ingress rules, places the wildcard
before the final `http_status:404`, and creates a proxied wildcard CNAME to
`<tunnel-id>.cfargotunnel.com`. It never creates or deletes a tunnel. Conflicting
DNS/ingress or a global `httpHostHeader` causes an error instead of an overwrite.
Rerunning after a partial failure is safe. Do not run concurrent setup processes.

For local management, use `CF_TUNNEL_MANAGEMENT=local` and point
`CF_TUNNEL_CONFIG` to the existing `config.yml`. Install the local YAML parser
with `npm install --prefix scripts --ignore-scripts`. The script preserves all
settings, including `tunnel` and `credentials-file`, backs up the original file,
and writes the updated config atomically. Local
mode needs Zone:DNS:Edit only. Validate with `cloudflared tunnel ingress validate`
and restart cloudflared after changes. Do not set `httpHostHeader` on the
wildcard rule. Keep any specific hostname rules before it.

Every cloudflared replica must forward to the same router/project host (or an
identical reachable router and shared project registry/runtime). Remote tunnel
configuration propagates automatically; local replicas need the same config.
Running this desktop app independently on several hosts creates independent
SQLite databases and is **not** a shared multi-host deployment. `localhost`
targets require cloudflared and the router on the same machine. No inbound port
needs to be opened; allow cloudflared outbound TCP/UDP 7844, and allow the app
HTTPS 443 for public activation checks and setup API calls.

Management endpoints require `Authorization: Bearer <LIVE_URL_API_TOKEN>`:

| Method | Path | Behavior |
| --- | --- | --- |
| POST | `/api/projects/:id/live-url` | Assign once or retry activation |
| GET | `/api/projects/:id` | Return identity and URL status |
| PATCH | `/api/projects/:id/live-url` | Set JSON `{"subdomain":"my-project"}` |
| DELETE | `/api/projects/:id/live-url` | Release identity |
| GET | `/api/projects/check-subdomain?name=my-project` | Validate and check availability |

The management API is limited to 60 authenticated requests/minute and is never
routed through wildcard project hosts. The Flutter page calls the same service
directly and receives status updates through the existing backend stream.
Provisioning polls the public URL until a no-cache health response identifies
the correct project; after bounded retries it shows Failed and offers Retry.
Stopped projects retain their URL. Editing validates syntax/reserved labels
inline and uses the database index to reject collisions. On native Flutter,
clicking a URL launches the external browser (there is no HTML anchor element).

Local smoke test, substituting the assigned slug:

```sh
curl -H "Host: my-project-a3b91f.buildiify.tech" http://127.0.0.1:8787/
curl -H "Host: unknown.buildiify.tech" http://127.0.0.1:8787/
curl -H "Authorization: Bearer YOUR_MANAGEMENT_TOKEN" http://127.0.0.1:8788/api/projects/PROJECT_ID
```

Request flow: **browser → Cloudflare wildcard DNS/TLS → existing gateway tunnel
→ router (original Host) → SQLite subdomain lookup → running project port**.
Unknown or nested labels return a friendly 404; stopped projects return 503.
Project creation, edits, and deletion never call Cloudflare.

If activation fails, verify wildcard DNS is proxied, cloudflared is connected,
ingress points to the router port, and no Host override or earlier broad rule
intercepts the wildcard. Check local Host-header routing before testing HTTPS.
Cloudflare Access challenges or cached health responses can prevent activation;
exclude `/__buildify_health` from caching and configure Access deliberately.
Port binding failures and health/API/proxy errors are logged on server stderr.
The Live URL service does not keep devices awake; existing runtime/device
constraints still apply.

Detailed guides live under **[docs/](docs/)** — start at [docs/README.md](docs/README.md):

- Architecture, Android engine (jniLibs), models & ADB, API & Postman, troubleshooting, product scope, roadmap.

## Marketing site

The promo site for **buildify.me** lives in **[website/](website/)** (Next.js 16 + Tailwind 4 + shadcn + Magic UI). It auto-renders the docs in `docs/` at build time.

```bash
cd website
pnpm install
pnpm dev      # http://localhost:3000
pnpm build    # production build
```

Deployment notes are in [website/README.md](website/README.md).

## Contributing

### Git workflow

Use **small, focused commits**. Each commit should explain one logical change.

Recommended branch names:

```text
feat/model-download-progress
fix/server-start-on-android-10
ui/logs-copy-button
docs/readme-contributing
chore/flutter-deps
```

### Commit message convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

```text
type(scope): short description
```

Examples:

```text
feat(download): stream GGUF from Hugging Face with progress
fix(android): resolve llama-server via nativeLibraryDir
ui(home): add copy-logs button
docs(readme): document jniLibs layout
chore(deps): bump http package
test(widget): smoke test home screen
refactor(native): simplify AiServerService process launch
perf(ui): reduce rebuilds on download progress
build(android): enable jniLibs legacy packaging
```

Common types:

| Type | Use for |
|------|---------|
| `feat` | New feature |
| `fix` | Bug fix |
| `ui` | Visual or interaction change |
| `docs` | Documentation only |
| `chore` | Maintenance, tooling, dependencies |
| `test` | Tests only |
| `refactor` | Restructure without behavior change |
| `perf` | Performance |
| `build` | Build system or platform config |

### Pull request checklist

Before opening or merging a PR:

- [ ] Run `flutter analyze`
- [ ] Run `flutter test`
- [ ] Confirm **no secrets** are committed (API keys, keystores, `.env`)
- [ ] Keep **generated build outputs** out of Git (`build/`, `.dart_tool/`, etc.)
- [ ] Update **README** or setup docs when install/run behavior changes
- [ ] Use a **clear PR title** following the commit convention

### Files that should not be committed

Do **not** commit:

- `.env` or environment files with real credentials
- **Signing keys:** `*.jks`, `*.keystore`, `key.properties` with real passwords
- **Google / Firebase** config files if they contain project secrets you do not intend to share publicly
- **Build outputs:** `build/`, Android `**/build/`, `.dart_tool/`
- **Machine-local paths:** `android/local.properties`
- **Huge optional tarballs** extracted beside the repo (e.g. `llama-b*/`); prefer documenting download + copy steps (root `.gitignore` ignores `llama-b*/` by default)

**Large native binaries (`jniLibs/*.so`):**  
You may commit them for a turnkey clone, or document “copy from official llama.cpp Android release” and use **Git LFS** if files exceed GitHub’s size limits. Do not commit unrelated platform builds (Windows `.exe`, etc.).

The `.gitignore` is set up for typical Flutter + Android + secret patterns; review before every push.

## License

Add a `LICENSE` file when you choose a license for the project.
# AI project subdomains

AI hosting details show the named URL below the live URL, using the AI project
name from the project list (for example `llama-3-8b-server.buildiify.tech`).
Starting the AI server automatically starts its configured connector and named
URL. Stopping the server removes the route and cancels connection attempts.
There are no connect/disconnect subdomain buttons or token prompts in AI details.
The URL becomes Live after its public health check reaches the AI server, and
temporary failures are retried automatically while the server remains running.
The Android named connector uses HTTP/2 over IPv4 for mobile network reliability.

Configure the Cloudflare tunnel with a wildcard hostname `*.buildiify.tech`
pointing to `http://localhost:8787`, preserve the original Host header, and add
a proxied wildcard CNAME to `<tunnel-id>.cfargotunnel.com`. The connector token
alone cannot configure these account settings. The existing
`scripts/setup-tunnel.js` supports configuring DNS and ingress with account API
credentials supplied through environment variables. Never commit credentials.

