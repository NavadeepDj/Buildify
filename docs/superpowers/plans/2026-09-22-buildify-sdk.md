# Buildify Client SDK (Python & TypeScript) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide lightweight, zero-friction client SDKs in Python (`buildify-ai`) and TypeScript (`@buildify/sdk`) that let developers seamlessly interact with edge AI models hosted on their Android phones with automated LAN discovery, token streaming, device telemetry, and Gemini 2.0 Flash hybrid cloud fallback using the new unified `google-genai` SDK.

**Architecture:** A dual-package ecosystem (Python `sdk/python` and TypeScript `sdk/typescript`) implementing a shared API client architecture: a core HTTP transport layer supporting SSE streaming, an OpenAI-compatible Chat/Completions client, an mDNS/subnet discovery utility for finding phone servers without typing IPs, a device telemetry client (battery/thermals/RAM), and a graceful fallback router to Google Gemini 2.0 Flash (`gemini-2.0-flash`) using the modern unified `google-genai` / `@google/genai` client when the phone is unreachable or throttling.

**Tech Stack:**
- **Python SDK:** Python 3.9+, `httpx` (async & sync HTTP + SSE), `pydantic` v2, `google-genai` (official unified Google GenAI SDK for Gemini 2.0 Flash), `zeroconf` (mDNS discovery), `pytest`.
- **TypeScript SDK:** Node.js 18+ / Browser, `fetch` / `EventSource` / web streams, `zod`, `@google/genai` (official unified Google GenAI SDK for Gemini 2.0 Flash), `vitest`.
- **On-Device Server Enhancements (Dart/Kotlin):** mDNS broadcast service (`_buildify._tcp`), device telemetry endpoint (`/api/device/stats`).

**Spec:** `docs/BACKEND_HOSTING_ARCHITECTURE.md` and `docs/android-llama-engine.md`.

## Global Constraints
- Must be a drop-in replacement for OpenAI client usage: `client.chat.completions.create(...)`.
- Zero external heavy dependencies: lightweight installs for fast developer onboarding (`pip install buildify-ai`, `npm i buildify-ai`).
- Multi-transport: Must support both Direct LAN (`http://<ip>:8080`) and Cloudflare Tunnel (`https://<slug>.trycloudflare.com`).
- Offline-first: Default to local phone inference; only route to Gemini when explicitly configured or when fallback threshold (battery < 15%, device offline) triggers.
- Cross-platform: Python works on Windows/macOS/Linux; TypeScript works in Node, Bun, Deno, and browser.

---

### Task 1: On-Device Discovery & Device Telemetry Endpoints (Flutter/Android)
**Files:**
- Create: `lib/services/mdns_service.dart`
- Modify: `lib/backend/embedded_backend.dart`
- Test: `test/services/mdns_service_test.dart`

**Interfaces:**
- Consumes: Battery & RAM status from `AiServerState` / platform channels.
- Produces: HTTP endpoint `GET /api/device/stats` returning JSON:
  ```json
  {
    "status": "running",
    "active_model": "gemma-2b-it.Q4_K_M.gguf",
    "battery_pct": 78,
    "is_charging": true,
    "thermal_state": "nominal",
    "port": 8080,
    "tunnel_url": "https://xyz.trycloudflare.com"
  }
  ```
  and mDNS broadcast `_buildify._tcp`.

- [ ] **Step 1: Write the unit test for device stats JSON formatting**
- [ ] **Step 2: Implement device stats serialization and HTTP handler in `embedded_backend.dart`**
- [ ] **Step 3: Implement `MdnsService` to advertise `_buildify._tcp` with host and port**
- [ ] **Step 4: Verify test passes**

---

### Task 2: Python SDK Scaffolding & Core HTTP Transport
**Files:**
- Create: `sdk/python/pyproject.toml`
- Create: `sdk/python/buildify/__init__.py`
- Create: `sdk/python/buildify/types.py`
- Create: `sdk/python/buildify/transport.py`
- Test: `sdk/python/tests/test_transport.py`

**Interfaces:**
- Consumes: `httpx` HTTP client.
- Produces: `Transport` and `AsyncTransport` handling base URLs, headers, timeout, retries, and SSE stream parsing.

- [ ] **Step 1: Write test for `Transport` initialization with LAN URL and Cloudflare URL**
- [ ] **Step 2: Implement `pyproject.toml` and basic transport layer using `httpx`**
- [ ] **Step 3: Run `pytest sdk/python/tests/test_transport.py` and verify PASS**

---

### Task 3: Python SDK OpenAI-Compatible Chat & Streaming
**Files:**
- Create: `sdk/python/buildify/chat.py`
- Create: `sdk/python/buildify/client.py`
- Test: `sdk/python/tests/test_chat.py`

**Interfaces:**
- Consumes: `Transport` from Task 2.
- Produces:
  ```python
  client = Buildify(base_url="http://192.168.1.55:8080")
  response = client.chat.completions.create(
      model="gemma-2b",
      messages=[{"role": "user", "content": "Hello"}],
      stream=True
  )
  ```

- [ ] **Step 1: Write failing test with mock server streaming chunks (`data: {"choices": [...]}`)**
- [ ] **Step 2: Implement `ChatCompletions` with sync generator `stream=True` and single object `stream=False`**
- [ ] **Step 3: Implement `AsyncChatCompletions` for `async for chunk in response:`**
- [ ] **Step 4: Run test to verify it passes**

---

### Task 4: Python SDK LAN Discovery & Device Telemetry
**Files:**
- Create: `sdk/python/buildify/discovery.py`
- Create: `sdk/python/buildify/device.py`
- Modify: `sdk/python/buildify/client.py`
- Test: `sdk/python/tests/test_discovery.py`

**Interfaces:**
- Consumes: `zeroconf` or fast IP range pinging (`/health`).
- Produces:
  ```python
  client = Buildify.discover() # returns Buildify client connected to phone!
  stats = client.device.stats() # returns DeviceStats(battery_pct=85, ...)
  ```

- [ ] **Step 1: Write test for `Buildify.discover()` with mock Zeroconf broadcast**
- [ ] **Step 2: Implement `discovery.py` with mDNS query and subnet scan fallback**
- [ ] **Step 3: Implement `device.py` fetching `/api/device/stats`**
- [ ] **Step 4: Run tests to verify PASS**

---

### Task 5: Hybrid Fallback to Google Gemini 2.0 Flash
**Files:**
- Create: `sdk/python/buildify/fallback.py`
- Modify: `sdk/python/buildify/client.py`
- Test: `sdk/python/tests/test_fallback.py`

**Interfaces:**
- Consumes: Official unified `google-genai` SDK (`from google import genai`) with model `gemini-2.0-flash`.
- Produces: Seamless rerouting when phone is offline, low battery, or explicitly requested:
  ```python
  client = Buildify(
      base_url="http://192.168.1.55:8080",
      gemini_api_key="AIzaSy...",
      fallback_model="gemini-2.0-flash",
      fallback_on_offline=True
  )
  ```

- [ ] **Step 1: Write test simulating phone connection timeout and checking fallback response from Gemini 2.0 Flash mock**
- [ ] **Step 2: Implement `FallbackRouter` using `google.genai.Client` to invoke `gemini-2.0-flash`**
- [ ] **Step 3: Run test to verify PASS**

---

### Task 6: TypeScript SDK Scaffolding & Chat Client
**Files:**
- Create: `sdk/typescript/package.json`
- Create: `sdk/typescript/tsconfig.json`
- Create: `sdk/typescript/src/index.ts`
- Create: `sdk/typescript/src/client.ts`
- Create: `sdk/typescript/src/chat.ts`
- Create: `sdk/typescript/src/types.ts`
- Test: `sdk/typescript/tests/client.test.ts`

**Interfaces:**
- Consumes: Standard web `fetch` and `ReadableStream`.
- Produces:
  ```typescript
  import { Buildify } from 'buildify-ai';
  const client = new Buildify({ baseUrl: 'http://192.168.1.55:8080' });
  const stream = await client.chat.completions.create({
    messages: [{ role: 'user', content: 'Hi' }],
    stream: true
  });
  for await (const chunk of stream) {
    process.stdout.write(chunk.choices[0]?.delta?.content || '');
  }
  ```

- [ ] **Step 1: Write Vitest test for TypeScript client chat creation and streaming**
- [ ] **Step 2: Implement TypeScript client with async iterator streaming**
- [ ] **Step 3: Run `npm test` and verify PASS**

---

### Task 7: Documentation, Examples & Developer Quickstarts
**Files:**
- Create: `sdk/README.md`
- Create: `sdk/python/examples/basic_chat.py`
- Create: `sdk/python/examples/langchain_integration.py`
- Create: `sdk/typescript/examples/nextjs_route.ts`
- Modify: `docs/roadmap.md`

- [ ] **Step 1: Write runnable quickstart scripts showing 3 lines of code to connect to the phone**
- [ ] **Step 2: Write LangChain custom LLM wrapper example**
- [ ] **Step 3: Update documentation and website docs page**
