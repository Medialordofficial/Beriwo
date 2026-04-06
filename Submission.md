# BERIWO — Demo Video Script

**Target: 3–4 minutes**

---

## [0:00–0:15] HOOK — The Problem

*Screen: Dark background, text appears*

> "AI agents are powerful. But giving them your credentials? That's terrifying."

*Cut to: Quick montage of headlines about AI data leaks*

> "What if an AI could act on your behalf — read your email, manage your calendar, search your files — without ever seeing a single token?"

---

## [0:15–0:30] INTRO

*Screen: Beriwo logo reveal, then the live app at beriwo-inc.web.app*

> "This is Beriwo — an autonomous AI executive assistant secured by Auth0 Token Vault. It has 10 tools across Gmail, Calendar, and Google Drive. And the AI never touches your credentials."

---

## [0:30–1:00] AUTH0 LOGIN + RBAC

*Screen: Click "Sign in with Auth0" → Auth0 Universal Login appears*

> "Authentication starts with Auth0 SPA SDK using PKCE. When you log in, our custom Auth0 Post-Login Action fires — it enriches your JWT with AI-specific claims."

*Screen: Show the Auth0 Actions dashboard briefly, highlight the code*

> "Your access tier, which tools you're allowed to use, whether you can do write operations, and your rate limit — all baked into the token at login time. The backend doesn't guess your permissions. Auth0 tells it."

---

## [1:00–1:45] LIVE DEMO — Read Operations

*Screen: Back in the app, type "What's on my schedule today and summarize my latest emails"*

> "Let's ask Beriwo about our day."

*Screen: Show the SSE streaming — "Planning…" → "Executing…" → "Synthesizing…"*

> "Watch the 3-phase pipeline. Phase 1 is a sandboxed planner — it has NO tools, NO tokens. It can only produce a plan. Phase 2 is the secure executor — Auth0 Token Vault resolves Google credentials server-side. The AI calls the tools but never sees the tokens. Phase 3 synthesizes the results — again, no tools, no tokens. The AI is never trusted with credentials and communication at the same time."

*Screen: Show the response with email summaries and calendar events*

---

## [1:45–2:30] LIVE DEMO — Consent Gate + Write Operations

*Screen: Type "Send an email to [contact] saying I'll be 10 minutes late to our meeting"*

> "Now watch what happens when the AI wants to WRITE."

*Screen: Consent card appears — "Actions need your approval: Send email"*

> "The Policy Gate physically removed send_email from the executor's tool registry. It doesn't exist. The AI literally cannot call it until I approve. This isn't a prompt instruction — it's code-level enforcement."

*Screen: Click "Approve"*

> "Now I approve, the request re-sends with my explicit consent, and the Policy Gate lets it through."

*Screen: Show the email being sent successfully*

> "Every single one of these decisions — allow, deny — is logged to our FGA audit trail in Firestore. Who, what tool, what decision, why, and when."

---

## [2:30–3:00] ARCHITECTURE RECAP

*Screen: Show the architecture diagram from the README (or a clean slide version)*

> "Five layers of security. One: Sandboxed AI — three phases, never tools plus user communication together. Two: RBAC — Auth0 Actions set your tier, the Policy Gate enforces it. Three: Consent gate — writes blocked by default, physically removed from the tool registry. Four: Step-up auth — sensitive operations check your JWT auth_time. If your login is stale, you re-authenticate. Five: FGA audit trail — every authorization decision recorded."

---

## [3:00–3:20] THE INSIGHT

*Screen: Text on screen*

> "Our insight for Auth0: Token Vault works brilliantly for securing AI tool access. But SPA developers need a first-class path — reading downstream tokens via the Management API is a workaround. And Auth0 Actions are the perfect place to define AI-specific RBAC. Imagine if the auth0/ai library read custom claims automatically to filter tool availability."

---

## [3:20–3:30] CLOSE

*Screen: Beriwo logo + GitHub link + live URL*

> "Beriwo. Your AI assistant that's authorized to act — but never trusted to hold the keys."

---

## SHOT LIST

| # | Shot | How |
|---|------|-----|
| 1 | Problem text on black screen | Keynote/Canva slide |
| 2 | Beriwo logo reveal | Slide or screen recording of app loading |
| 3 | Auth0 login flow | Screen record clicking Sign In → Auth0 popup |
| 4 | Auth0 Actions dashboard | Screen record showing the deployed "Beriwo AI RBAC" action code |
| 5 | Read query demo | Screen record typing query, show streaming phases |
| 6 | Response with real data | Let the response fully render |
| 7 | Write query demo | Screen record typing "send email..." |
| 8 | Consent card appearing | Capture the moment the card pops up |
| 9 | Clicking Approve → success | Full flow through to "email sent" |
| 10 | Architecture diagram | Slide with the ASCII diagram or a cleaned-up version |
| 11 | 5-layer security table | Slide |
| 12 | Insight text | Slide |
| 13 | Closing logo + links | Slide |

---

## PRODUCTION TIPS

- Record your screen at 1920×1080, use a clean browser window (no bookmarks bar)
- Voiceover can be recorded separately and layered in
- Keep it under 4 minutes — judges watch many submissions
- Make sure you have real emails/events in the account so the demo shows actual data
