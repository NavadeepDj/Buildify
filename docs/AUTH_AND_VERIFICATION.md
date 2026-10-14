# Buildify — Email & Phone Verification System

**Document Version:** 1.0.0  
**Status:** Implemented & Verified  

---

## 1. Overview & Architecture

Buildify features a full-stack, secure user registration and multi-channel verification system. During user registration, users select their primary verification method:
1. **Email Verification Link**: Secure, cryptographically random, single-use 32-byte URL-safe token valid for 30 minutes.
2. **Phone Number SMS OTP**: Cryptographically secure 6-digit numeric OTP sent via SMS, valid for 5 minutes with attempt rate limiting.

### Flow Diagram

```text
               ┌──────────────────────────────┐
               │    User Signup / Register    │
               └──────────────┬───────────────┘
                              │
               ┌──────────────▼───────────────┐
               │ Choose Verification Channel  │
               └───────┬──────────────┬───────┘
                       │              │
           ✉️ EMAIL    │              │ 📱 PHONE
                       │              │
       ┌───────────────▼──┐        ┌──▼────────────────┐
       │ Normalize Email  │        │ Normalize E.164   │
       │ (RFC 5322)       │        │ (+1, +44, +91...) │
       └───────┬──────────┘        └──┬────────────────┘
               │                      │
       ┌───────▼──────────┐        ┌──▼────────────────┐
       │ Generate 32-byte │        │ Generate 6-digit  │
       │ Random Token     │        │ Random OTP Code   │
       └───────┬──────────┘        └──┬────────────────┘
               │                      │
       ┌───────▼──────────┐        ┌──▼────────────────┐
       │ Hash Token (HMAC)│        │ Hash OTP (HMAC)   │
       │ Store in SQLite  │        │ Store in SQLite   │
       └───────┬──────────┘        └──┬────────────────┘
               │                      │
       ┌───────▼──────────┐        ┌──▼────────────────┐
       │ Send Link via    │        │ Send SMS via      │
       │ Email Provider   │        │ Twilio / Webhook  │
       └───────┬──────────┘        └──┬────────────────┘
               │                      │
               ▼                      ▼
       ┌───────────────────────────────────────────────┐
       │      Server-Side Atomic Verification          │
       │  • Constant-time hash equality comparison     │
       │  • Single-use consumption flag (consumed_at)  │
       │  • Expiration validation                      │
       │  • Max 5 attempts & 60s cooldown enforcement  │
       └──────────────────────┬────────────────────────┘
                              │
               ┌──────────────▼───────────────┐
               │  Account Verified & Active   │
               └──────────────────────────────┘
```

---

## 2. Security Guarantees & Safeguards

- **No Plaintext Secrets**: Verification tokens and OTPs are hashed using salted SHA-256 HMAC (`AuthSecurityUtils.hashSecret`) before persistence in the `verification_challenges` database table. Plaintext secrets are never stored.
- **Timing Attack Resistance**: All token and OTP comparisons use constant-time equality checks (`AuthSecurityUtils.constantTimeEquals`).
- **Single-Use Enforcement**: Tokens and OTPs are marked with `consumed_at` timestamp immediately upon successful verification. Replay attempts are rejected.
- **Attempt Rate Limiting**: Phone OTP challenges lock out after 5 consecutive failed attempts (`isLocked`).
- **Resend Cooldown**: A strict 60-second cooldown is enforced between resend requests, with an hourly maximum of 5 resends.
- **Independent Contact Verification States**: `email_verified` and `phone_verified` are tracked as distinct flags in SQLite.
- **Safe Information Masking**: Emails and phone numbers are masked on client screens (e.g. `u***r@domain.com`, `+14***2671`).
- **Zero Accidental Verification**: If an email or SMS delivery fails, the operation returns `deliveryFailed` and the contact is **never** marked verified.

---

## 3. Database Schema & Migration

Database migrations are managed automatically through `DatabaseHelper.instance` in `lib/services/database_helper.dart`.

The database was upgraded to **Version 3** with the following tables:

### Table: `users`
| Column | Type | Constraints / Description |
|---|---|---|
| `id` | `TEXT PRIMARY KEY` | UUIDv4 |
| `name` | `TEXT NOT NULL` | User display handle |
| `email` | `TEXT UNIQUE` | Normalized lowercase email |
| `phone` | `TEXT UNIQUE` | E.164 formatted phone number |
| `password_hash` | `TEXT NOT NULL` | Salted SHA-256 hash |
| `password_salt` | `TEXT NOT NULL` | Cryptographic salt |
| `auth_method` | `TEXT NOT NULL` | `email` or `phone` |
| `email_verified` | `INTEGER NOT NULL DEFAULT 0` | 1 if verified, 0 if pending |
| `phone_verified` | `INTEGER NOT NULL DEFAULT 0` | 1 if verified, 0 if pending |
| `created_at` | `INTEGER NOT NULL` | Epoch milliseconds |
| `updated_at` | `INTEGER NOT NULL` | Epoch milliseconds |

### Table: `verification_challenges`
| Column | Type | Constraints / Description |
|---|---|---|
| `id` | `TEXT PRIMARY KEY` | UUIDv4 |
| `user_id` | `TEXT NOT NULL` | Foreign key referencing `users(id)` |
| `channel` | `TEXT NOT NULL` | `email` or `phone` |
| `target` | `TEXT NOT NULL` | Normalized recipient target |
| `secret_hash` | `TEXT NOT NULL` | HMAC-SHA256 digest of secret |
| `salt` | `TEXT NOT NULL` | Per-challenge salt |
| `expires_at` | `INTEGER NOT NULL` | Expiration timestamp |
| `consumed_at` | `INTEGER` | Null until successfully verified |
| `attempts` | `INTEGER NOT NULL DEFAULT 0` | Failed attempts counter |
| `max_attempts` | `INTEGER NOT NULL DEFAULT 5` | Maximum allowed attempts |
| `resend_count` | `INTEGER NOT NULL DEFAULT 0` | Number of times resent |
| `last_sent_at` | `INTEGER NOT NULL` | Timestamp of last dispatch |
| `created_at` | `INTEGER NOT NULL` | Creation timestamp |

---

## 4. Provider Configuration & Environment Variables

Copy `.env.example` to `.env` or set environment variables in your deployment environment.

### Email Configuration
| Variable | Allowed Values | Description |
|---|---|---|
| `BUILDIFY_EMAIL_PROVIDER` | `resend`, `sendgrid`, `webhook`, `memory` | Email transport driver |
| `BUILDIFY_EMAIL_FROM` | e.g. `Buildify Auth <no-reply@buildify.me>` | Verified sender address |
| `BUILDIFY_RESEND_API_KEY` | `re_...` | API key from [resend.com](https://resend.com) |
| `BUILDIFY_SENDGRID_API_KEY` | `SG....` | API key from [sendgrid.com](https://sendgrid.com) |
| `BUILDIFY_EMAIL_WEBHOOK_URL` | HTTPS endpoint | Custom HTTP endpoint for email dispatch |

#### Setting up Resend:
1. Create an account at [resend.com](https://resend.com).
2. Add and verify your domain in the Resend dashboard (DNS TXT/MX records).
3. Generate an API Key with `Sending access`.
4. Set `BUILDIFY_EMAIL_PROVIDER=resend` and `BUILDIFY_RESEND_API_KEY=re_...`.

### SMS Configuration
| Variable | Allowed Values | Description |
|---|---|---|
| `BUILDIFY_SMS_PROVIDER` | `twilio`, `webhook`, `memory` | SMS transport driver |
| `BUILDIFY_TWILIO_ACCOUNT_SID` | `AC...` | Twilio Account SID |
| `BUILDIFY_TWILIO_AUTH_TOKEN` | Token string | Twilio Auth Token |
| `BUILDIFY_TWILIO_FROM_NUMBER` | e.g. `+18005550199` | Twilio purchased phone number |
| `BUILDIFY_SMS_WEBHOOK_URL` | HTTPS endpoint | Custom HTTP endpoint for SMS dispatch |

#### Setting up Twilio:
1. Create an account at [twilio.com](https://twilio.com).
2. Acquire an SMS-capable phone number.
3. Locate `Account SID` and `Auth Token` in the Twilio Console.
4. Set `BUILDIFY_SMS_PROVIDER=twilio`, `BUILDIFY_TWILIO_ACCOUNT_SID`, and `BUILDIFY_TWILIO_AUTH_TOKEN`.

---

## 5. Development & Sandbox Mode

When `BUILDIFY_ENV` is set to `development` (the default) and no third-party email or SMS API credentials are provided:
- Buildify operates in **Development Sandbox Mode**.
- Outgoing verification emails and SMS messages are securely captured in the in-memory outbox (`ConfiguredEmailProvider.sandboxOutbox` and `ConfiguredSmsProvider.sandboxOutbox`).
- Tokens can be copied directly from the sandbox or pasted into the manual token verification field on `VerificationPage`.
- In `production` mode (`BUILDIFY_ENV=production`), unconfigured providers immediately fail with a descriptive error and never pretend delivery succeeded.

---

## 6. Running Tests

Run the full automated test suite using Flutter's test runner:

```bash
# Run all tests
flutter test

# Run only authentication and verification tests
flutter test test/auth_service_test.dart
flutter test test/auth_security_utils_test.dart
flutter test test/auth_ui_flow_test.dart
```
