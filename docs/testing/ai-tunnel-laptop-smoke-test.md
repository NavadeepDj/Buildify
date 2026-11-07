# Cloudflare AI Tunnel — Laptop Smoke-Test Runbook

> **Issue:** #104 · **Branch:** `test/ai-tunnel-laptop-smoke-test`

This runbook validates that a phone-hosted llama.cpp model (served via the Buildify app) is reachable from a laptop over a Cloudflare Tunnel, before you commit the tunnel URL to the project or open a PR.

---

## Environment

| Item | Value |
|---|---|
| Phone model | Any Android running Buildify |
| App server port | `8080` (default, configurable in UI) |
| Tunnel tool | `cloudflared` (Cloudflare Tunnel CLI) |
| Laptop OS | Windows / macOS / Linux |
| Network | Phone and laptop may be on **different** networks |

---

## Prerequisites

- [ ] Buildify app installed and a model downloaded on the phone
- [ ] `cloudflared` installed on the phone (or laptop acting as relay)
- [ ] Laptop has `curl` or Postman available

---

## Phase A — Start the model server on the phone

1. Open the Buildify app.
2. Select a downloaded model and tap **Start Server**.
3. Confirm the status bar shows **Server Running** and note the local IP + port (e.g. `192.168.1.5:8080`).

**Expected:** Health endpoint responds locally:
```
curl http://192.168.1.5:8080/health
→ {"status":"ok"}
```

---

## Phase B — Start the Cloudflare Tunnel

Run on the device that has `cloudflared` and can reach the phone's server:

```bash
cloudflared tunnel --url http://localhost:8080
```

Wait for a line like:
```
https://example-random-name.trycloudflare.com
```

Copy that URL — this is your `TUNNEL_URL`.

**Expected:** `cloudflared` prints the public HTTPS URL within ~10 seconds.

---

## Phase C — Smoke test from laptop

Replace `TUNNEL_URL` with the URL from Phase B.

### C1 — Health check
```bash
curl https://TUNNEL_URL/health
```
**Expected:** `{"status":"ok"}`

### C2 — Chat completions (OpenAI-compatible)
```bash
curl -X POST https://TUNNEL_URL/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Say hello in one sentence."}],
    "max_tokens": 64,
    "temperature": 0.7
  }'
```
**Expected:** JSON with `choices[0].message.content` containing a greeting.

### C3 — Latency check
Note the `timings` block in the response:

| Field | Acceptable threshold |
|---|---|
| `predicted_per_second` | ≥ 5 tok/s on mid-range phone |
| Total round-trip | < 30 s for 64 tokens |

---

## Phase D — Teardown

1. Stop the Cloudflare tunnel (`Ctrl+C` on `cloudflared`).
2. Tap **Stop Server** in the Buildify app.
3. Confirm the tunnel URL returns 502/404 (tunnel is down).

---

## Result Matrix

| Test | Pass | Fail |
|---|---|---|
| A — Local health check | `{"status":"ok"}` | Timeout / connection refused |
| B — Tunnel URL obtained | URL printed in ~10 s | `cloudflared` error / hangs |
| C1 — Remote health | `{"status":"ok"}` | 502 / 504 / connection error |
| C2 — Chat completions | Valid JSON with `choices` | 4xx / 5xx / empty body |
| C3 — Latency | ≥ 5 tok/s | Below threshold → note phone load |
| D — Teardown | 502 on tunnel URL | Tunnel still responding |

---

## Failure Paths

| Symptom | Likely cause | Fix |
|---|---|---|
| Phase A fails | App server not started | Tap **Start Server** in app |
| Phase B hangs | `cloudflared` not installed / firewall | Install `cloudflared`; check firewall rules |
| C1 returns 502 | Tunnel started before server | Restart tunnel after server is running |
| C2 returns 400 | Wrong JSON body | Check `Content-Type: application/json` header |
| High latency | Phone under load / large model | Use smaller quantization (Q4 vs Q8) |

---

## References

- [Cloudflare Tunnel quick start](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/trycloudflare/)
- [api-and-testing.md](../api-and-testing.md) — local API reference
- [hosted-development.md](../hosted-development.md) — full dev setup guide
