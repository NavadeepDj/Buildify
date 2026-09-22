# 📱 Buildify AI Python SDK (`buildify-ai`)

The official Python client library for connecting to **Buildify Edge AI Servers** running locally on Android smartphones.

Run quantized models (Google Gemma-2B, SmolLM, Qwen) on your phone, and interact with them in 3 lines of Python code—with **zero cloud subscription costs**, **zero-latency local Wi-Fi streaming**, and **transparent hybrid fallback to Google Gemini 2.0 Flash**.

---

## ⚡ Quickstart

### Installation
```bash
pip install buildify-ai
```

Optional dependencies for Gemini fallback:
```bash
pip install "buildify-ai[gemini]"
```

---

## 🚀 Basic Usage

```python
from buildify import Buildify

# Connect to phone (auto-discovers on local Wi-Fi or pass base_url)
client = Buildify(base_url="http://192.168.1.55:8080")

# Stream chat completion
stream = client.chat.completions.create(
    model="default",
    messages=[{"role": "user", "content": "Explain quantum computing in 2 lines"}],
    stream=True,
)

for chunk in stream:
    print(chunk.delta_text, end="", flush=True)
```

---

## 🔋 Hardware Telemetry & Battery Awareness

Since your server is running on a battery-powered device, Buildify gives you real-time hardware telemetry:

```python
stats = client.device.stats()
print(f"Status: {stats.status}")
print(f"Battery: {stats.battery_pct}% (Charging: {stats.is_charging})")
print(f"Active Model: {stats.active_model}")
```

---

## 🌐 Auto-Discovery (Zero-Config Wi-Fi Pairing)

Don't want to type your phone's IP address every time? Buildify broadcasts its presence on the local network:

```python
# Automatically finds your phone on the Wi-Fi!
client = Buildify.discover()
print(f"Found phone at: {client.base_url}")
```

---

## ☁️ Hybrid Edge-to-Cloud Fallback (Google Gemini 2.0 Flash)

Guarantee 99.9% uptime. If your phone battery runs out or the server goes offline, Buildify can transparently route requests to **Google Gemini 2.0 Flash**:

```python
client = Buildify(
    base_url="http://192.168.1.55:8080",
    gemini_api_key="YOUR_GEMINI_API_KEY",
    fallback_model="gemini-2.0-flash",
    fallback_on_offline=True, # Seamlessly switches to Gemini 2.0 if phone is unreachable!
)
```

---

## 🦜 LangChain Integration

Buildify complies 100% with the OpenAI API specification, making it a drop-in provider for LangChain:

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    base_url="http://<phone-ip>:8080/v1",
    api_key="not-needed",
    model="gemma-2b",
)
```
