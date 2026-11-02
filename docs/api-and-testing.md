# HTTP API and testing

Assume the app shows **local IP** (e.g. `192.168.1.5`) and port **8080** (configurable in UI).

<img width="1066" height="808" alt="image" src="https://github.com/user-attachments/assets/7fc3bf3b-97bb-4232-9b33-c3b80a937ea8" />


**Base URL:** `http://<phone-ip>:8080`

## Health

**GET** `/health`

Expect JSON with status OK when the server is up.

## Chat (OpenAI-compatible)

**POST** `/v1/chat/completions`  
**Headers:** `Content-Type: application/json`

Example body:

```json
{
  "messages": [
    { "role": "user", "content": "Hello in one short sentence." }
  ],
  "max_tokens": 64,
  "temperature": 0.7
}
```

Response shape matches OpenAI-style chat completions (`choices`, `usage`, etc.).  
llama.cpp may also include extra fields such as **`timings`** (prefill vs decode speed).

## Legacy / simple completion (`/completion`)

**POST** `/completion`  
(Exact JSON schema depends on llama-server version; often `prompt`, `n_predict`, `temperature`.)

> [!WARNING]
> **Autocomplete vs. Chat**: The `/completion` endpoint performs **raw text completion**. If you are using an instruction-tuned model (like `qwen2-1_5b-instruct`), using raw text (e.g., `"prompt": "Hi, I am Navadeep."`) will cause the model to act like an autocomplete and simply continue the sentence. 
> 
> To get a conversational response, you **must** either:
> 1. Use the `/v1/chat/completions` endpoint (Recommended - automatically formats the prompt).
> 2. Format the prompt manually using the model's specific chat template (e.g. ChatML for Qwen) in the `/completion` request body:
>    ```json
>    {
>      "prompt": "<|im_start|>system\nYou are a helpful assistant.<|im_end|>\n<|im_start|>user\nHi, I am Navadeep.<|im_end|>\n<|im_start|>assistant\n",
>      "n_predict": 50
>    }
>    ```

## Postman

1. Create a request: method **GET** or **POST**, URL as above.
2. For POST, Body → **raw** → **JSON**.
3. Ensure phone and PC are on the **same Wi‑Fi**; disable VPN if it blocks LAN.
4. If the request hangs, confirm the app shows **Server Running** and check `adb logcat`.

## Reading `timings` in responses

Example fields:

| Field | Meaning |
|-------|---------|
| `prompt_n` / `prompt_ms` | Input tokens and time to process them |
| `predicted_n` / `predicted_ms` | Generated tokens and generation time |
| `predicted_per_second` | Decode throughput (tokens/sec, approximate) |

Useful for tuning model size and expectations on phones.

## Remote / Cloudflare Tunnel Testing

To test the phone-hosted model from a laptop over the internet (without being on the same Wi-Fi), use a Cloudflare Tunnel:

```bash
cloudflared tunnel --url http://localhost:8080
```

This exposes your local server at a public `https://*.trycloudflare.com` URL. All the endpoints above (`/health`, `/v1/chat/completions`, `/completion`) work the same way over the tunnel URL.

For a full step-by-step smoke-test runbook including environment setup, phases, result matrix, and failure paths, see:

📄 [docs/testing/ai-tunnel-laptop-smoke-test.md](testing/ai-tunnel-laptop-smoke-test.md)
