## Built with

Dart, Flutter Web, TypeScript, Node.js, Firebase Cloud Functions, Firebase Hosting, Cloud Firestore, Auth0 SPA SDK, Auth0 Token Vault, Auth0 Actions, Auth0 Management API, Auth0 Step-Up Authentication, Genkit v1.30, Gemini 2.5 Flash, Gmail API, Google Calendar API, Google Drive API, Express.js, Server-Sent Events (SSE)

## Inspiration

The idea for Beriwo came from a simple frustration: every day, professionals spend hours context-switching between Gmail, Google Calendar, and Google Drive — reading emails, scheduling meetings, finding documents, and repeating the same manual rituals. We imagined saying: *"Check my email, find the flight itinerary, add it to my calendar, and text my wife to remind her about pickup"* — and having it actually happen, securely, without handing our passwords to an AI.

But the moment we started building, we realized the real problem isn't making AI *smart enough* — it's making AI *trustworthy enough*. Every existing approach requires giving an LLM raw API credentials. That's a security nightmare. A prompt injection attack could turn your helpful assistant into a data exfiltration tool. We needed an architecture where **the AI can act on your behalf without ever seeing your credentials**, and where every action is gated, auditable, and reversible. When we saw Auth0's "Authorized to Act" hackathon and the Token Vault SDK, we knew this was the missing piece.

## What it does

Beriwo is an autonomous AI executive assistant that manages your Gmail, Google Calendar, and Google Drive through a secure, consent-gated pipeline. It doesn't just answer questions — it **acts**.

- **Daily Briefing**: Cross-references emails, calendar events, and Drive files, then prioritizes everything into URGENT / TODAY / FYI categories — like having a chief of staff in your browser.
- **10 Google Tools**: List, read, send, and reply to emails. Create, update, and delete calendar events with Google Meet links. Browse and read Drive files. Trash emails and mark spam.
- **Consent-Gated Writes**: Every write operation (send email, create event, delete meeting, trash email) requires explicit user approval through a consent card in the UI. The AI plans the action; *you* decide if it executes.
- **Smart Memory**: Remembers your preferences, contacts, routines, and patterns across conversations — persisted to Firestore so it gets smarter over time.
- **Self-Correcting Agent**: A reflection loop (up to 3 passes) detects when the executor missed tools and re-runs automatically, ensuring reliable results.
- **Real-Time Streaming**: SSE-powered live pipeline shows exactly what the agent is doing — Planning → Executing → Synthesizing — with tool-by-tool progress.
- **Email Management**: Mark emails as spam, move to trash, categorize inbox into Social Media / Business / Bills / Work / Promotion / Potential Spam.
- **Cleanup & Categorize Agents**: One-click agents to empty spam/trash or auto-categorize your entire inbox.

## How we built it

Beriwo is built on a **3-phase sandboxed AI pipeline** — the core architectural innovation that ensures security by design:

**Phase 1 — Sandbox Planner** (no tools, no tokens): A Gemini 2.5 Flash instance analyzes the user's request and produces a structured JSON action plan. It references available tools but physically cannot call them. This prevents prompt injection from reaching tool execution.

**Phase 2 — Policy Gate + Secure Executor** (Token Vault + RBAC + Consent + Step-Up Auth): The plan passes through 5 security layers before execution. Auth0 RBAC claims (set via a Post-Login Action) physically remove unauthorized tools. Write tools are stripped unless the user explicitly approves. High-risk operations require re-authentication (step-up auth with a 5-minute window). Only then does the executor run — with credentials resolved by Auth0 Token Vault, never visible to the AI model.

**Phase 3 — Synthesis Module** (no tools, no tokens): Takes raw tool results and formats them into clear, markdown-formatted responses with cross-service insights and memory extraction.

**Tech Stack:**
- **Frontend**: Flutter Web (Dart) with Provider state management, `flutter_markdown` for rich responses, Auth0 SPA SDK with PKCE
- **Backend**: Firebase Cloud Functions (TypeScript, Node.js 22, Express), Genkit v1.30 (beta) with Gemini 2.5 Flash
- **Auth**: Auth0 Token Vault (`@auth0/ai-genkit`), Auth0 Actions for RBAC, Management API for token retrieval, step-up authentication via `auth_time` claims
- **Database**: Cloud Firestore for conversations, cross-session memory, and FGA audit logs
- **APIs**: Gmail API, Google Calendar API, Google Drive API
- **Hosting**: Firebase Hosting at [beriwo-inc.web.app](https://beriwo-inc.web.app)

We used 7 Auth0 features: Token Vault, Post-Login Actions (RBAC), consent-gated execution, step-up authentication, FGA-style audit trail, social connection with token refresh, and interrupt & resume flow.

## Challenges we ran into

1. **Token Vault + SPA Compatibility**: Auth0 Token Vault's built-in token exchange is designed for Regular Web App clients with long-lived refresh tokens. SPAs use rotating refresh tokens and opaque access tokens, which Token Vault cannot exchange directly. We solved this with a hybrid architecture — Token Vault still governs all tool access and security policy, while the Management API's `read:user_idp_tokens` scope retrieves the downstream Google token server-side. This kept credentials out of the AI while working within SPA constraints.

2. **Interrupt Survival Across OAuth Redirects**: When Token Vault detects missing Google authorization mid-conversation, it interrupts the pipeline. But the OAuth redirect wipes the SPA state. We built a `localStorage`-based persistence layer that saves the interrupted message *before* the redirect and auto-retries after the user returns — making the flow seamless.

3. **Prompt Injection in a 3-Phase Pipeline**: Ensuring that a malicious email body (read by the executor) couldn't trick the synthesis module into performing actions was non-trivial. The sandboxed architecture — where the synthesis module has zero tool access — was specifically designed to mitigate this class of attack.

4. **Firebase Functions Cold Start + Genkit Loading**: The Genkit SDK, Auth0AI, and Firebase Admin SDK together caused function discovery timeouts. We solved this with lazy-loading all heavy dependencies inside `ensureApp()` and a `FUNCTIONS_DISCOVERY_TIMEOUT=60000` environment variable.

5. **Response Speed**: The 3-phase pipeline means 3 sequential LLM calls. We built a fast-plan detector that bypasses the planner for common operations (check email, delete, mark spam), skips synthesis for simple results, disables the reflection loop for ≤2-tool plans, and runs Firestore I/O in parallel — cutting response times from ~12s to ~3-5s for common actions.

## Accomplishments that we're proud of

- **Zero-credential AI**: The Gemini model never sees a single Google token, API key, or user credential — ever. Auth0 Token Vault resolves credentials server-side, and the 3-phase pipeline ensures the AI's tool access and user communication are physically separated.

- **5-Layer Security Stack**: RBAC, consent gate, step-up auth, sandboxed pipeline, and FGA audit trail — all enforced at the code level (tool removal), not the prompt level. This isn't "please don't do bad things" — it's architecturally impossible for the AI to bypass security.

- **Production-Ready Consent Flow**: The floating consent banner, per-message consent cards, and the fast-exit path for all-blocked operations create a genuine "human-in-the-loop" experience for AI write operations.

- **Cross-Service Intelligence**: Beriwo doesn't just fetch data from three services — it connects the dots. An email about "Project X" gets linked to a meeting about "Project X" and a Drive document with the same name, organized by urgency.

- **Self-Correcting Execution**: The reflection loop detects missing tool calls and autonomously re-runs, achieving reliable multi-step task completion without user intervention.

- **Auth0 Feature Depth**: We didn't just use Auth0 for login. We used 7 features across the full stack — Token Vault for credential isolation, Actions for RBAC, Management API for token retrieval, step-up auth for high-risk operations, FGA patterns for audit, social connections for Google integration, and interrupt/resume for seamless OAuth flows.

## What we learned

- **Security must be architectural, not instructional.** Telling an LLM "don't misuse credentials" in a system prompt is not security — it's a suggestion. Real security comes from physically removing tools, tokens, and permissions from the AI's execution context. The 3-phase pipeline taught us that the best security boundary is one the AI doesn't even know exists.

- **Auth0 Token Vault changes the game for AI agents.** Before Token Vault, there was no clean way to give an AI agent delegated authority over user accounts without exposing credentials. The combination of Token Vault + Genkit's tool system creates a genuinely new paradigm for secure AI-human collaboration.

- **SPA + AI agent = unique challenges.** The SPA's rotating refresh tokens, opaque access tokens, and stateless nature create real friction with server-side AI pipelines. The hybrid token architecture we built is a pattern we think other teams will need as AI agents become more common in web apps.

- **Speed and security are not enemies.** Our fast-plan detector proves you can have a rigorous 5-layer security pipeline AND sub-5-second response times — you just need to be smart about which layers to invoke for which operations.

- **Users need to see the AI working.** The SSE-powered phase indicators (Planning → Executing → Synthesizing) with tool-by-tool progress dramatically increased trust. Users who can see what the AI is doing are far more willing to grant consent for write operations.

## What's next for Beriwo

- **More Integrations**: Slack, Microsoft Teams, Notion, Jira, and GitHub — expanding from Google Workspace to a truly universal executive assistant.
- **Proactive Agent Mode**: AutoPilot that runs on a schedule — triaging your inbox every morning, flagging urgent items, pre-drafting responses, and cleaning up spam automatically (with consent patterns learned over time).
- **Voice Interface**: "Hey Beriwo, what's on my plate today?" — voice-first interaction for hands-free productivity.
- **Team Collaboration**: Shared workspaces where Beriwo coordinates across team members' calendars and email threads, respecting individual RBAC permissions.
- **Fine-Grained Authorization with Auth0 FGA**: Moving from our Firestore audit log to a full Auth0 FGA implementation with relationship-based access control — enabling scenarios like "Beriwo can read my calendar but only my assistant can approve meeting changes."
- **Mobile App**: Bringing Beriwo to iOS and Android with Flutter's cross-platform capabilities, using the same backend and Auth0 security stack.
- **Enterprise Tier**: Admin dashboard, usage analytics, custom RBAC policies, SOC 2 compliance reporting generated from the FGA audit trail.
