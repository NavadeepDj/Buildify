# 📱 Buildify AI TypeScript SDK (`buildify-ai`)

The official TypeScript/JavaScript client library for connecting to **Buildify Edge AI Servers** running locally on Android smartphones.

Connect to on-device LLMs (Google Gemma-2B, SmolLM, Qwen) from Node.js, Next.js, Bun, or the browser with **zero cloud bill**, **real-time token streaming**, and **automatic fallback to Google Gemini 2.0 Flash**.

---

## ⚡ Quickstart

### Installation
```bash
npm install buildify-ai
```

---

## 🚀 Basic Usage

```typescript
import { Buildify } from 'buildify-ai';

// Initialize pointing to phone IP or Cloudflare tunnel URL
const client = new Buildify({ baseUrl: 'http://192.168.1.55:8080' });

// Non-streaming completion
const response = await client.chat.completions.create({
  messages: [{ role: 'user', content: 'Explain edge computing in 2 lines' }],
});

console.log(response.choices[0].message.content);
```

---

## 🌊 Real-Time Token Streaming

```typescript
import { Buildify } from 'buildify-ai';

const client = new Buildify({ baseUrl: 'http://192.168.1.55:8080' });

const stream = await client.chat.completions.create({
  messages: [{ role: 'user', content: 'Write a haiku about servers' }],
  stream: true,
});

for await (const chunk of stream) {
  const token = chunk.choices[0]?.delta?.content || '';
  process.stdout.write(token);
}
```

---

## 🔋 Hardware Telemetry & Battery Stats

```typescript
const stats = await client.device.stats();
console.log(`Server Status: ${stats.status}`);
console.log(`Phone Battery: ${stats.battery_pct}% (Charging: ${stats.is_charging})`);
```

---

## ☁️ Hybrid Cloud Fallback (Google Gemini 2.0 Flash)

Ensure high availability when your phone goes offline:

```typescript
const client = new Buildify({
  baseUrl: 'http://192.168.1.55:8080',
  geminiApiKey: process.env.GEMINI_API_KEY,
  fallbackModel: 'gemini-2.0-flash',
  fallbackOnOffline: true, // Transparently switches to Gemini 2.0 Flash if phone is offline!
});
```

---

## 🌐 Next.js App Router (Route Handler) Example

```typescript
// app/api/chat/route.ts
import { Buildify } from 'buildify-ai';

const client = new Buildify({ baseUrl: process.env.BUILDIFY_PHONE_URL });

export async function POST(req: Request) {
  const { messages } = await req.json();

  const stream = await client.chat.completions.create({
    messages,
    stream: true,
  });

  const encoder = new TextEncoder();
  const readable = new ReadableStream({
    async start(controller) {
      for await (const chunk of stream) {
        controller.enqueue(encoder.encode(chunk.choices[0]?.delta?.content || ''));
      }
      controller.close();
    },
  });

  return new Response(readable, {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
}
```
