# Cloud model setup assistant (experimental)

The assistant interprets a short conversation into local setup preferences. It
does not run commands, choose arbitrary downloads, authorize a session stop, or
publish an endpoint. The app's existing device inspection and curated catalog
choose the candidate; the existing approval/executor flow performs setup.

## Configuration and rollout

Use the existing signed-in, confirmed Supabase account and `MANAGEMENT_API_URL`
for this build's management Edge Function. No new provider key belongs in Flutter.
The companion implementation is in the private `hostany-management` repository.
Merge/deploy that backend before expecting cloud requests to work.

Server-only variables:

- `ASSISTANT_ENABLED=true` enables interpretation; absent/false disables it.
- `ASSISTANT_GEMINI_API_KEY` is a backend secret.
- `ASSISTANT_GEMINI_MODEL` must explicitly name a supported Gemini model. Verify
  availability and cost with the provider before enabling it.
- Existing `MANAGEMENT_DEADLINE_MS` applies to authentication and interpretation
  together (default 8 seconds, configurable up to 15 seconds).

Keep development rollout controlled. The current shared database account budget
allows assistant requests only below 5 requests per account/window (or the smaller
configured account limit). Account reads consume the same bucket; this is not an
independent assistant quota. Each accepted turn makes at most one provider call.
There is no global provider-spend cap or public abuse protection added by this
feature. Disable the flag to roll back interpretation; manual setup still works.

Only displayed conversation messages go to the backend/provider. No device paths,
model files, API keys or hardware inventory are included. Conversation is held in
screen memory, cleared on account change/new conversation/closing the screen.
The backend's allowlisted audit event excludes prompts, replies and provider keys.
This does not establish the hosting/provider platform's own retention policies.

## Experimental wire contract

Authenticated `POST /v1/assistant/intent` relative to the management base URL.
Headers: existing Bearer session token, public `apikey`, JSON content type.
Redirects are forbidden. Request: `{ "messages": [{ "role": "user", "text":
"Run a fast local model for short answers" }] }`.

Messages alternate user/assistant and end with user: 1–8 entries, at most 1500
characters per message and 8192 UTF-8 bytes for the entire JSON request.

Success envelope contains `data` and `request_id`, matching `X-Request-ID`:

```json
{
  "data": {
    "status": "ready",
    "task": "short_answers",
    "preference": "speed",
    "scope": "device_network",
    "reply": "Prepare a fast local setup plan."
  },
  "request_id": "33333333-3333-4333-8333-333333333333"
}
```

These five fields are exact. `status`: ready/clarify/unsupported; `task`:
short_answers/multilingual/reasoning; `preference`: speed/balanced/quality;
`scope`: device_network/public/unspecified. Reply is nonempty plain text, at most
600 characters. Ready requires device_network. Extra execution/approval/model
fields are rejected. Public setup is unsupported in this conversation flow.
Existing management error envelopes/statuses apply. This experimental extension
does not replace the separately pinned reviewed account API contract.

## Laptop check after both PRs are integrated

1. Sign in with a confirmed account. Ask for “a fast model for short answers on
   this laptop.” Confirm a cloud reply appears and nothing starts automatically.
2. Choose **Prepare suggested plan**. Confirm a local candidate/resource budget
   appears. Only **Approve and run** may begin download/start/inference.
3. Ask a vague question and answer the clarification. Ask for a public endpoint:
   confirm no local approval plan or public tunnel is created from that reply.
4. Disable the backend flag or disconnect: confirm an honest unavailable message
   and usable manual setup controls. Switch accounts: conversation must clear.
5. After real inference, compatibility says the test passed. Stop the model:
   connection details must be labeled historical and Stop model disabled.

Automated tests use synthetic provider replies; they do not establish real Gemini
availability, latency, billing or Windows/Android device behavior.
