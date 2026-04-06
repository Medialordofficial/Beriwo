# Beriwo — Autonomous AI Agent with Auth0 Token Vault

**An AI executive assistant that reads your Gmail, manages your Calendar, and searches your Drive — all secured through Auth0's zero-trust architecture.**

Built for the [Authorized to Act Hackathon](https://authorizedtoact.devpost.com/) | [Live Demo](https://beriwo-inc.web.app)

---

## The Problem

AI agents need access to your private data to be useful, but giving an LLM your credentials is a security nightmare. How do you let AI act on your behalf without ever exposing your tokens?

## Our Solution

Beriwo uses **Auth0 Token Vault** to create a zero-trust boundary between the AI and user credentials. The AI can *request* tool execution, but credentials are resolved server-side through Token Vault — the model never sees a single token.

We go further with a **3-phase sandboxed pipeline** enforcing security at every layer, **RBAC via Auth0 Actions**, **consent-gated writes**, **step-up authentication**, and a **fine-grained authorization audit trail**.

## Architecture

```
                        ┌──────────────────────────┐
                        │      Flutter Web SPA      │
                        │   Auth0 SPA SDK + PKCE    │
                        └────────────┬─────────────┘
                                     │ Bearer Token (JWT w/ RBAC claims)
                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Firebase Cloud Functions (Express)                │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    AUTH MIDDLEWARE                            │    │
│  │  JWT decode → extract ai_tier, ai_tools, ai_can_write       │    │
│  │  Fallback: Auth0 /userinfo for opaque tokens                 │    │
│  └──────────────────────────┬──────────────────────────────────┘    │
│                              │                                      │
│  ┌──────────────┐   ┌───────▼──────┐   ┌────────────┐             │
│  │   PHASE 1    │   │   PHASE 2    │   │  PHASE 3   │             │
│  │   Sandbox    │──▶│   Secure     │──▶│  Synthesis  │             │
│  │   Planner    │   │   Executor   │   │  Module     │             │
│  │              │   │              │   │             │             │
│  │ • No tools   │   │ • Token Vault│   │ • No tools  │             │
│  │ • No tokens  │   │ • RBAC gate  │   │ • No tokens │             │
│  │ • Plans only │   │ • Consent    │   │ • Format    │             │
│  │              │   │ • Step-up    │   │   results   │             │
│  │              │   │ • FGA audit  │   │ • Memory    │             │
│  └──────────────┘   └──────┬───────┘   └────────────┘             │
│                              │                                      │
│  ┌───────────────────────────▼─────────────────────────────────┐    │
│  │                   Auth0 Token Vault                          │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐     │    │
│  │  │ Gmail Tools  │  │Calendar Tools│  │  Drive Tools    │     │    │
│  │  │ list,read,   │  │list,create,  │  │ list, read      │     │    │
│  │  │ send,reply   │  │update,delete │  │                 │     │    │
│  │  └──────────────┘  └─────────────┘  └─────────────────┘     │    │
│  │  Credentials isolated from AI • Scope-gated • Per-tool      │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                      │
│  ┌───────────────────────────▼─────────────────────────────────┐    │
│  │              FGA Authorization Audit Trail                   │    │
│  │  Every tool access decision logged: ALLOW/DENY + reason      │    │
│  │  (Firestore: authz_audit_log collection)                     │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        ┌──────────┐  ┌────────────┐  ┌────────────┐
        │ Gmail API│  │Calendar API│  │ Drive API  │
        └──────────┘  └────────────┘  └────────────┘
```

## Auth0 Features Used

### 1. Token Vault (`@auth0/ai-genkit` v6)
Every tool is wrapped with `defineProtectedTool()` through Token Vault. The AI model requests tool calls, but **credentials are resolved server-side** — the model never sees a token. We use a hybrid approach: Token Vault governs tool protection while the Management API retrieves downstream Google tokens from the user's linked social identity.

### 2. Auth0 Post-Login Action — RBAC for AI Agents
A custom Auth0 Action enriches JWT tokens with AI-specific claims at login time:

```javascript
// Custom claims added to every access token:
"https://beriwo.com/ai_tier": "pro",        // User's AI access tier
"https://beriwo.com/ai_tools": [...],        // Allowed tool names
"https://beriwo.com/ai_can_write": true,     // Can perform write ops
"https://beriwo.com/ai_max_calls": 50        // Rate limit per session
```

**Tier permissions:**
| Tier | Read Tools | Write Tools | Max Calls |
|------|-----------|-------------|-----------|
| `basic` | list_emails, read_email, list_events, list_files, read_file | None | 10 |
| `pro` | All read tools | send_email, reply_to_email, create/update/delete events | 50 |

The backend's Policy Gate **physically removes** tools not in the user's `ai_tools` claim — they don't exist in the executor's tool registry.

### 3. Consent-Gated Execution (Policy Gate)
All write operations (`send_email`, `reply_to_email`, `create_calendar_event`, etc.) are **blocked by default**. The Policy Gate removes these tools from the executor unless the user explicitly approves via a consent card in the UI. This is code-level enforcement, not a prompt instruction.

### 4. Step-Up Authentication
High-risk tools (`send_email`, `reply_to_email`, `delete_calendar_event`) check the JWT's `auth_time` claim. If the user's login is older than 5 minutes, execution halts and the frontend triggers re-authentication via Auth0 popup with `max_age: 0`.

### 5. Fine-Grained Authorization (FGA) Audit Trail
Every tool access decision is logged to Firestore with a structured authorization record:

```json
{
  "userId": "u_google-oauth2|123...",
  "action": "send_email",
  "resource": "tool",
  "decision": "deny",
  "reason": "consent_required",
  "tier": "pro",
  "timestamp": "2026-04-04T..."
}
```

This follows the FGA tuple pattern (`user` → `relation` → `object`) and enables:
- Complete audit trail of what the AI was allowed/denied
- Compliance reporting for sensitive operations
- Anomaly detection (unexpected tool access patterns)

### 6. Social Connection with Token Refresh
Google OAuth2 social connection with custom credentials, `offline_access` scope, and automatic token refresh. When the stored Google access token expires (~1 hour), the backend refreshes it using the Google refresh token stored in Auth0's identity.

### 7. Interrupt & Resume Flow
If Token Vault detects missing authorization, the flow interrupts gracefully. The interrupted message is persisted to `localStorage`, survives the OAuth redirect, and retries automatically after the user grants access.

## Security Architecture — 5 Layers Deep

| Layer | Mechanism | What It Prevents |
|-------|-----------|------------------|
| **1. Sandboxed AI** | 3-phase pipeline — AI never has tools + user communication simultaneously | Prompt injection exploiting tool access |
| **2. RBAC** | Auth0 Action enriches JWT with tier claims → Policy Gate enforces | Unauthorized tool access by user tier |
| **3. Consent Gate** | Write tools physically removed unless user approves | AI performing unintended write operations |
| **4. Step-Up Auth** | JWT `auth_time` check, 5-min window, re-auth popup | Stale session exploitation, unattended browser |
| **5. FGA Audit** | Every decision logged with user/action/resource/decision | Untraceable AI operations, compliance gaps |

## Features

| Feature | Description |
|---------|-------------|
| **Daily Briefing** | Cross-service intelligence — emails, calendar & Drive cross-referenced, prioritized into URGENT / TODAY / FYI |
| **10 Google Tools** | Gmail (list, read, send, reply) · Calendar (list, create, update, delete) · Drive (list, read) |
| **RBAC Tiers** | Auth0 Action sets user tier → Policy Gate enforces tool-level access control |
| **Consent Gate** | Write operations require explicit user approval via consent card |
| **Step-Up Auth** | High-risk writes require re-authentication (JWT `auth_time` check) |
| **FGA Audit Trail** | Every authorization decision logged for compliance and debugging |
| **Live Pipeline** | SSE streaming shows real-time phase progress (Planning → Executing → Synthesizing) |
| **Smart Memory** | Remembers user preferences and facts across conversations |
| **Reflection Loop** | Self-correcting agent with up to 3 passes for reliable tool execution |
| **Token Resilience** | Automatic Google token refresh, Management API retry with fresh tokens |

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter Web (Dart) |
| Auth | Auth0 SPA SDK + Token Vault (`@auth0/ai-genkit` v6) + Auth0 Actions |
| Backend | Firebase Cloud Functions (TypeScript, Node.js 22) |
| AI | Gemini 2.5 Flash via Genkit v1.30 |
| Database | Cloud Firestore (conversations, memory, FGA audit log) |
| APIs | Gmail API, Google Calendar API, Google Drive API |

## Project Structure

```
beriwo/
├── app/                          # Flutter frontend
│   └── lib/
│       ├── main.dart             # App entry, auth gate
│       ├── config.dart           # Auth0 & API configuration
│       ├── models/               # Data models (ChatMessage, BlockedWrite)
│       ├── screens/              # Login & Chat screens
│       ├── services/             # AuthService, ChatService, DashboardService
│       └── widgets/              # ChatInput, MessageBubble
├── functions/                    # Firebase Cloud Functions
│   └── src/
│       ├── auth0.ts              # Token Vault + Management API + token refresh
│       ├── index.ts              # Express server, 3-phase pipeline, RBAC, FGA
│       └── tools/
│           ├── gmail.ts          # Gmail tools (list, read, send, reply)
│           ├── calendar.ts       # Calendar tools (list, create, update, delete)
│           └── drive.ts          # Drive tools (list, read)
├── firebase.json                 # Firebase hosting + functions config
├── firestore.rules               # Firestore security rules
└── firestore.indexes.json        # Firestore indexes
```

## Setup

### Prerequisites

- Node.js 20+
- Flutter 3.x
- Firebase CLI (`npm install -g firebase-tools`)
- Auth0 account with:
  - SPA Application (frontend)
  - Machine-to-Machine Application (backend)
  - Custom API with RS256 signing
  - Google social connection with required scopes
  - Post-Login Action deployed (see below)
- Google Cloud project with Gmail, Calendar, and Drive APIs enabled

### Backend

```bash
cd functions
npm install

# Create .env with your credentials:
# AUTH0_DOMAIN=your-tenant.auth0.com
# AUTH0_CLIENT_ID=your-m2m-client-id
# AUTH0_CLIENT_SECRET=your-m2m-client-secret
# GOOGLE_AI_API_KEY=your-gemini-api-key
# GOOGLE_OAUTH_CLIENT_ID=your-google-oauth-client-id
# GOOGLE_OAUTH_CLIENT_SECRET=your-google-oauth-client-secret

npm run build
```

### Frontend

```bash
cd app
flutter pub get
flutter run -d chrome
```

### Deploy

```bash
# Build Flutter web
cd app && flutter build web --release && cd ..

# Deploy everything
FUNCTIONS_DISCOVERY_TIMEOUT=60000 firebase deploy
```

### Auth0 Configuration

1. **SPA Application**: Enable Refresh Token Rotation, allow `offline_access`, set Allowed Callback URLs
2. **M2M Application**: Authorize against Management API with `read:users`, `read:user_idp_tokens`, `read:connections`, `update:connections` scopes
3. **Custom API**: Identifier `https://api.beriwo.com`, RS256 signing, "Allow Offline Access" enabled
4. **Google Social Connection**: Enable Gmail, Calendar, Drive scopes + `offline_access`; configure with custom Google OAuth credentials
5. **Post-Login Action**: Deploy "Beriwo AI RBAC" action (sets `ai_tier`, `ai_tools`, `ai_can_write`, `ai_max_calls` custom claims)

## How the Consent Flow Works

```
User: "Send an email to my wife tina Javynyuy and tell her to pick up my son ethan from the daycare at 15:00, since i wont be able to close earlier than planned.."
  │
  ▼
Phase 1 — Planner (NO tools, NO tokens)
  Plans: [read_email, send_email]
  │
  ▼
Phase 2 — Policy Gate
  ├─ RBAC check: Is send_email in user's ai_tools? ✓ (pro tier)
  ├─ Consent check: Is send_email in approvedWrites? ✗
  ├─ FGA audit: LOG {action: send_email, decision: DENY, reason: consent_required}
  └─ Result: send_email BLOCKED, read_email ALLOWED
  │
  ▼
Frontend shows consent card: "Actions need your approval: Send email"
  │
  User clicks "Approve"
  │
  ▼
Re-sends with approvedWrites: ["send_email"]
  │
  ▼
Phase 2 — Policy Gate (retry)
  ├─ RBAC check: send_email in ai_tools? ✓
  ├─ Consent check: send_email in approvedWrites? ✓
  ├─ Step-up check: auth_time age < 300s? ✓
  ├─ FGA audit: LOG {action: send_email, decision: ALLOW, reason: policy_gate_pass}
  └─ Result: send_email ALLOWED
  │
  ▼
Phase 2 — Executor (Token Vault resolves Google token)
  Sends email via Gmail API — AI never sees credentials
  │
  ▼
Phase 3 — Synthesis
  "I've sent the email to John letting him know you'll be late."
```

## Judging Criteria Alignment

| Criterion | How Beriwo Addresses It |
|-----------|------------------------|
| **Security Model** | 5-layer defense: sandboxed AI, RBAC via Auth0 Actions, consent gate (physical tool removal), step-up auth, FGA audit trail |
| **Auth0 Integration Depth** | Token Vault, SPA SDK, Management API, Post-Login Action, Social Connection w/ token refresh, step-up auth, interrupt/resume |
| **User Control** | Consent gate for writes, step-up re-authentication, clear pipeline visualization, approve/deny UI |
| **Technical Execution** | 10 tools across 3 Google services, SSE streaming, reflection loop, cross-conversation memory, production deployment |
| **Potential Impact** | Cross-service intelligence (not just data fetching — connecting dots between email, calendar & drive), RBAC tiers for enterprise use |
| **Insight Value** | Token Vault SPA hybrid architecture, Auth0 Actions for AI RBAC, FGA audit pattern for AI agents |

## Insight for Auth0

> The `@auth0/ai` library could benefit from:
> 1. **First-class SPA flow** — leveraging `read:user_idp_tokens` internally so SPA developers get seamless Token Vault without the hybrid workaround
> 2. **Built-in RBAC for tools** — reading custom claims to automatically filter tool availability based on user tier
> 3. **FGA integration** — native audit logging and per-resource permission checks for AI tool execution

## License

MIT
