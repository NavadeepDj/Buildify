# 🛠️ Buildify Client SDKs

Connect to **Buildify Edge AI Servers** running locally on your Android phone using your favorite programming language.

## Available SDKs

| Language | Package | Directory | Quick Install |
|---|---|---|---|
| **Python** | `buildify-ai` | [`sdk/python/`](./python) | `pip install buildify-ai` |
| **TypeScript / Node.js** | `buildify-ai` | [`sdk/typescript/`](./typescript) | `npm install buildify-ai` |

---

## 🌟 Key Features

1. **Zero-Config LAN Auto-Discovery (`Buildify.discover()`):**
   - Automatically detects active Buildify servers running on Android phones connected to the same Wi-Fi network without typing manual IP addresses.
2. **OpenAI Spec Compatibility:**
   - Standard `client.chat.completions.create(model="...", messages=[...], stream=True)` interface. Drop-in compatible with LangChain, LlamaIndex, and Vercel AI SDK.
3. **Real-Time Token Streaming:**
   - Sub-10ms token streaming via Server-Sent Events (SSE).
4. **Hardware Telemetry & Battery Monitoring (`client.device.stats()`):**
   - Read phone battery level, charging status, and thermal states directly from client code.
5. **Hybrid Cloud Fallback to Google Gemini 2.0 Flash (`gemini-2.0-flash`):**
   - Seamlessly and transparently reroutes requests to Google Gemini 2.0 Flash if the phone enters sleep mode, battery drops below 15%, or goes offline.

---

## 🚀 Comparison

| Feature | Raw `curl` / `requests` | Standard OpenAI SDK | **Buildify SDK** |
|---|---|---|---|
| **Phone Auto-Discovery** | ❌ Manual IP lookup | ❌ Not supported | ✅ `Buildify.discover()` |
| **Battery / Thermal Stats** | ❌ Manual parsing | ❌ Not supported | ✅ `client.device.stats()` |
| **Google Gemini 2.0 Fallback** | ❌ None | ❌ None | ✅ Transparent 1-line fallback |
| **Cloudflare Tunnel Support** | ⚠️ Manual headers | ⚠️ Manual headers | ✅ Native auto-negotiation |
