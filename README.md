# Buildify

Local AI server and full-stack project hosting workspace.

Buildify turns devices into an edge-cloud orchestration platform, enabling developers to host local AI models (via `llama.cpp` GGUF) and web backend services (Node.js, Python, Flask, Static) exposed securely via Cloudflare Tunnels and Tailscale private mesh networks.

## Authentication & Verification

Buildify includes a multi-channel user authentication and verification system:
- **Email Verification Link**: Secure single-use, 32-byte cryptographic token valid for 30 minutes.
- **Phone Number SMS OTP**: 6-digit numeric OTP sent via SMS, valid for 5 minutes with attempt rate limiting.
- **Security Features**: Hashed challenge secrets (HMAC-SHA256), constant-time equality comparisons, single-use consumption tracking, 60-second resend cooldowns, and independent contact verification states.

For complete documentation on the authentication and verification architecture, provider setup, and database migrations, see:
- [Authentication & Verification Architecture](docs/AUTH_AND_VERIFICATION.md)
- [Backend Hosting Specification](docs/BACKEND_HOSTING_ARCHITECTURE.md)
- [Security & Safety](docs/security-and-safety.md)

## Environment Configuration

Copy `.env.example` to `.env` to configure your environment variables:
```bash
cp .env.example .env
```
Supported providers include **Resend**, **SendGrid**, **Twilio**, custom HTTP webhooks, and local sandbox development outbox.

## Testing

Run the automated test suite:
```bash
flutter test
```
All unit, security, persistence, and widget flow tests are located in `test/`.
