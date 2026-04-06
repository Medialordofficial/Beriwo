import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";

// All heavy dependencies are lazy-loaded inside ensureApp() so that
// Firebase Functions discovery (which imports this module) completes
// quickly without loading firebase-admin, express, genkit, auth0, etc.

let _app: any;

// ── Policy: which tools are READ-only vs WRITE (need consent) ──
const WRITE_TOOLS = new Set([
  "create_calendar_event",
  "update_calendar_event",
  "delete_calendar_event",
  "send_email",
  "reply_to_email",
]);

// High-risk writes require step-up authentication (recent login).
// If the user's auth_time is older than STEP_UP_MAX_AGE_S, the backend
// returns a step_up interrupt so the frontend can trigger re-authentication.
const STEP_UP_TOOLS = new Set([
  "send_email",
  "reply_to_email",
  "delete_calendar_event",
]);
const STEP_UP_MAX_AGE_S = 300; // 5 minutes
const TOOL_LABELS: Record<string, string> = {
  list_emails: "Reading emails",
  read_email: "Reading email content",
  send_email: "Sending email",
  reply_to_email: "Replying to email",
  list_upcoming_events: "Checking calendar",
  create_calendar_event: "Creating calendar event",
  update_calendar_event: "Updating calendar event",
  delete_calendar_event: "Deleting calendar event",
  list_drive_files: "Browsing Drive",
  read_drive_file: "Reading Drive file",
};

interface ExecutionStep {
  tool: string;
  label: string;
  status: "pending" | "running" | "done" | "blocked" | "skipped";
  requiresConsent: boolean;
  result?: string;
  error?: string;
  durationMs?: number;
}

function ensureApp() {
  if (_app) return _app;

  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const admin = require("firebase-admin");
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const express = require("express");
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const cors = require("cors");
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { getAI, withTokens } = require("./auth0.js");
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { getGmailTools } = require("./tools/gmail.js");
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { getCalendarTools } = require("./tools/calendar.js");
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { getDriveTools } = require("./tools/drive.js");

  admin.initializeApp();
  const db = admin.firestore();

  const app = express();
  app.use(cors({ origin: true }));
  app.use(express.json());

  // ── Auth Middleware: verify Authorization header via Auth0 /userinfo ──
  const AUTH0_DOMAIN = process.env.AUTH0_DOMAIN || "dev-erixgo5lgfsbtbzc.eu.auth0.com";

  // Cache validated tokens for 5 minutes to avoid hitting /userinfo on every request
  const _tokenCache = new Map<string, { auth: any; expires: number }>();

  async function authMiddleware(req: any, res: any, next: any) {
    const authHeader = req.headers?.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Authorization required" });
      return;
    }

    const token = authHeader.substring(7);
    if (!token) {
      res.status(401).json({ error: "Empty token" });
      return;
    }

    // Check cache first
    const cached = _tokenCache.get(token);
    if (cached && cached.expires > Date.now()) {
      (req as any).auth = cached.auth;
      next();
      return;
    }

    // Attempt 1: decode JWT payload locally (no external dependency needed)
    try {
      const parts = token.split('.');
      if (parts.length === 3) {
        const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
        if (payload.iss === `https://${AUTH0_DOMAIN}/` && payload.exp && payload.exp > Date.now() / 1000) {
          (req as any).auth = payload;
          _tokenCache.set(token, { auth: payload, expires: Date.now() + 300_000 });
          next();
          return;
        }
      }
    } catch {
      // Not a valid JWT — try /userinfo for opaque tokens
    }

    // Attempt 2: validate opaque token via Auth0 /userinfo endpoint
    try {
      const resp = await fetch(`https://${AUTH0_DOMAIN}/userinfo`, {
        headers: { authorization: `Bearer ${token}` },
      });
      if (resp.ok) {
        const auth = await resp.json();
        (req as any).auth = auth;
        _tokenCache.set(token, { auth, expires: Date.now() + 300_000 });
        next();
        return;
      }
    } catch {
      logger.warn("Auth0 /userinfo fallback failed");
    }

    res.status(401).json({ error: "Invalid or expired token" });
  }

  app.use(authMiddleware);

  // ── Auto Pilot API ──
  app.post("/api/settings/autopilot", async (req: any, res: any) => {
    const auth = (req as any).auth;
    const { enabled } = req.body;
    if (typeof enabled !== "boolean") return res.status(400).send("Invalid status");
    
    // Store in Firestore auto_pilot collection
    await db.collection("user_settings").doc(auth.sub).set({ autoPilot: enabled }, { merge: true });
    
    res.json({ success: true, autoPilot: enabled });
  });

  // ── Direct Data API: returns raw Google data for the frontend dashboard ──
  const { getGoogleTokenForUser, getGoogleTokenForUserId } = require("./auth0.js");

  app.get("/api/dashboard", async (req: any, res: any) => {
    const auth = (req as any).auth;
    const userId = auth?.sub;
    try {
      logger.info(`Dashboard: fetching Google token for user ${userId || 'unknown'}`);
      // Use userId directly from auth middleware (works with both JWT and opaque tokens)
      const googleToken = userId
        ? await getGoogleTokenForUserId(userId)
        : await getGoogleTokenForUser(req.headers.authorization?.substring(7));
      if (!googleToken) {
        logger.warn(`Dashboard: No Google token available for user ${userId || 'unknown'}`);
        return res.json({ connected: false, emails: [], events: [], files: [] });
      }
      logger.info(`Dashboard: Got Google token, fetching data...`);
      const headers = { Authorization: `Bearer ${googleToken}` };

      // Parallel fetch: emails, calendar events, drive files
      const now = new Date().toISOString();
      const endOfDay = new Date();
      endOfDay.setHours(23, 59, 59, 999);
      const [emailsRes, eventsRes, filesRes] = await Promise.all([
        fetch(`https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=10`, { headers }).then(r => r.ok ? r.json() : { messages: [] }),
        fetch(`https://www.googleapis.com/calendar/v3/calendars/primary/events?maxResults=10&singleEvents=true&orderBy=startTime&timeMin=${now}&timeMax=${endOfDay.toISOString()}`, { headers }).then(r => r.ok ? r.json() : { items: [] }),
        fetch(`https://www.googleapis.com/drive/v3/files?pageSize=10&fields=files(id,name,mimeType,modifiedTime,webViewLink)&orderBy=modifiedTime%20desc`, { headers }).then(r => r.ok ? r.json() : { files: [] }),
      ]);

      // Expand email metadata
      const msgList = (emailsRes as any).messages || [];
      const emails = await Promise.all(
        msgList.slice(0, 10).map(async (msg: any) => {
          const r = await fetch(
            `https://gmail.googleapis.com/gmail/v1/users/me/messages/${msg.id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date`,
            { headers }
          );
          if (!r.ok) return null;
          const data = await r.json() as any;
          const hdrs = data.payload?.headers || [];
          const get = (name: string) => hdrs.find((h: any) => h.name === name)?.value || "";
          const labels: string[] = data.labelIds || [];
          return {
            id: data.id,
            subject: get("Subject"),
            from: get("From"),
            snippet: data.snippet || "",
            date: get("Date"),
            unread: labels.includes("UNREAD"),
          };
        })
      );

      const events = ((eventsRes as any).items || []).map((e: any) => ({
        id: e.id,
        summary: e.summary || "(No title)",
        start: e.start?.dateTime || e.start?.date || "",
        end: e.end?.dateTime || e.end?.date || "",
        location: e.location || "",
        attendees: (e.attendees || []).map((a: any) => a.email).slice(0, 5),
      }));

      const files = ((filesRes as any).files || []).map((f: any) => ({
        id: f.id,
        name: f.name,
        mimeType: f.mimeType,
        modifiedTime: f.modifiedTime,
        webViewLink: f.webViewLink || "",
      }));

      // Load activity log from Firestore
      const activitySnap = await db.collection("activity_log").doc(auth.sub).collection("actions")
        .orderBy("timestamp", "desc").limit(10).get();
      const activities = activitySnap.docs.map((d: any) => ({ ...d.data(), id: d.id }));

      res.json({ connected: true, emails: emails.filter(Boolean), events, files, activities });
    } catch (err: any) {
      logger.error(`Dashboard API error: ${err.message}`);
      res.status(500).json({ error: "Failed to load dashboard data" });
    }
  });

  app.get("/api/emails", async (req: any, res: any) => {
    const auth = (req as any).auth;
    const userId = auth?.sub;
    try {
      const googleToken = userId
        ? await getGoogleTokenForUserId(userId)
        : await getGoogleTokenForUser(req.headers.authorization?.substring(7));
      if (!googleToken) return res.json({ connected: false, emails: [] });
      const headers = { Authorization: `Bearer ${googleToken}` };
      const q = req.query.q || "";
      const label = req.query.label || "INBOX"; // INBOX or SENT
      const params = new URLSearchParams({ maxResults: "30", labelIds: label });
      if (q) params.set("q", q);
      const listRes = await fetch(`https://gmail.googleapis.com/gmail/v1/users/me/messages?${params}`, { headers });
      if (!listRes.ok) return res.json({ connected: true, emails: [] });
      const listData = await listRes.json() as any;
      const msgList = listData.messages || [];
      const emails = await Promise.all(
        msgList.slice(0, 30).map(async (msg: any) => {
          const r = await fetch(
            `https://gmail.googleapis.com/gmail/v1/users/me/messages/${msg.id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Date`,
            { headers }
          );
          if (!r.ok) return null;
          const data = await r.json() as any;
          const hdrs = data.payload?.headers || [];
          const get = (name: string) => hdrs.find((h: any) => h.name === name)?.value || "";
          const labels: string[] = data.labelIds || [];
          const fromAddr = get("From").toLowerCase();
          // Heuristic: business emails come from domains that aren't common consumer providers
          const consumerDomains = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com", "aol.com", "icloud.com", "mail.com", "protonmail.com", "live.com", "msn.com"];
          const domainMatch = fromAddr.match(/@([a-z0-9.-]+)/);
          const domain = domainMatch ? domainMatch[1] : "";
          const isBusiness = domain.length > 0 && !consumerDomains.includes(domain);
          return {
            id: data.id, subject: get("Subject"), from: get("From"), to: get("To"),
            snippet: data.snippet || "", date: get("Date"),
            unread: labels.includes("UNREAD"), isBusiness,
            labels: labels,
          };
        })
      );
      res.json({ connected: true, emails: emails.filter(Boolean) });
    } catch (err: any) {
      logger.error(`Emails API error: ${err.message}`);
      res.status(500).json({ error: "Failed to load emails" });
    }
  });

  app.get("/api/events", async (req: any, res: any) => {
    const auth = (req as any).auth;
    const userId = auth?.sub;
    try {
      const googleToken = userId
        ? await getGoogleTokenForUserId(userId)
        : await getGoogleTokenForUser(req.headers.authorization?.substring(7));
      if (!googleToken) return res.json({ connected: false, events: [] });
      const headers = { Authorization: `Bearer ${googleToken}` };
      const now = new Date();
      const endOfDay = new Date();
      endOfDay.setHours(23, 59, 59, 999);
      const params = new URLSearchParams({
        maxResults: "10", singleEvents: "true", orderBy: "startTime",
        timeMin: now.toISOString(), timeMax: endOfDay.toISOString(),
      });
      const r = await fetch(`https://www.googleapis.com/calendar/v3/calendars/primary/events?${params}`, { headers });
      if (!r.ok) return res.json({ connected: true, events: [] });
      const data = await r.json() as any;
      const events = (data.items || []).map((e: any) => ({
        id: e.id, summary: e.summary || "(No title)",
        start: e.start?.dateTime || e.start?.date || "",
        end: e.end?.dateTime || e.end?.date || "",
        location: e.location || "",
        attendees: (e.attendees || []).map((a: any) => a.email).slice(0, 5),
      }));
      res.json({ connected: true, events });
    } catch (err: any) {
      logger.error(`Events API error: ${err.message}`);
      res.status(500).json({ error: "Failed to load events" });
    }
  });

  app.get("/api/files", async (req: any, res: any) => {
    const auth = (req as any).auth;
    const userId = auth?.sub;
    try {
      const googleToken = userId
        ? await getGoogleTokenForUserId(userId)
        : await getGoogleTokenForUser(req.headers.authorization?.substring(7));
      if (!googleToken) return res.json({ connected: false, files: [] });
      const headers = { Authorization: `Bearer ${googleToken}` };
      const q = req.query.q || "";
      const params = new URLSearchParams({
        pageSize: "20", fields: "files(id,name,mimeType,modifiedTime,webViewLink)", orderBy: "modifiedTime desc",
      });
      if (q) params.set("q", `name contains '${q.replace(/'/g, "\\'")}'`);
      const r = await fetch(`https://www.googleapis.com/drive/v3/files?${params}`, { headers });
      if (!r.ok) return res.json({ connected: true, files: [] });
      const data = await r.json() as any;
      const files = (data.files || []).map((f: any) => ({ id: f.id, name: f.name, mimeType: f.mimeType, modifiedTime: f.modifiedTime, webViewLink: f.webViewLink || "" }));
      res.json({ connected: true, files });
    } catch (err: any) {
      logger.error(`Files API error: ${err.message}`);
      res.status(500).json({ error: "Failed to load files" });
    }
  });

  // ── Tool Registry: named map enables policy-based filtering ──
  function getToolMap(): Record<string, any> {
    const { listEmails, readEmail, sendEmail, replyToEmail } = getGmailTools();
    const { listUpcomingEvents, createEvent, updateEvent, deleteEvent } = getCalendarTools();
    const { listDriveFiles, readDriveFile } = getDriveTools();
    return {
      list_emails: listEmails,
      read_email: readEmail,
      send_email: sendEmail,
      reply_to_email: replyToEmail,
      list_upcoming_events: listUpcomingEvents,
      create_calendar_event: createEvent,
      update_calendar_event: updateEvent,
      delete_calendar_event: deleteEvent,
      list_drive_files: listDriveFiles,
      read_drive_file: readDriveFile,
    };
  }

  /** Return ONLY the tools allowed by the policy gate. */
  function filterTools(
    toolMap: Record<string, any>,
    allowedNames: string[],
  ): any[] {
    return allowedNames
      .filter(n => toolMap[n])
      .map(n => toolMap[n]);
  }

  function getDateContext() {
    const now = new Date();
    const dateStr = now.toLocaleDateString('en-US', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
      timeZone: 'UTC',
    });
    const timeStr = now.toLocaleTimeString('en-US', {
      hour: '2-digit', minute: '2-digit', timeZone: 'UTC', timeZoneName: 'short',
    });
    return { dateStr, timeStr };
  }

  // ── Memory helpers: per-user persistent memory ──
  async function loadMemory(userId: string): Promise<string[]> {
    const snap = await db
      .collection("user_memory")
      .doc(userId)
      .collection("facts")
      .orderBy("timestamp", "desc")
      .limit(20)
      .get();
    return snap.docs.map((d: any) => d.data().text as string);
  }

  async function saveMemory(userId: string, facts: string[]) {
    const batch = db.batch();
    for (const text of facts) {
      const ref = db.collection("user_memory").doc(userId).collection("facts").doc();
      batch.set(ref, { text, timestamp: admin.firestore.FieldValue.serverTimestamp() });
    }
    await batch.commit();
  }

  // Derive a stable user ID from the JWT access token's 'sub' claim.
  // This survives token rotation — the same Auth0 user always maps to the same ID.
  function deriveUserId(refreshToken?: string, accessToken?: string): string {
    if (accessToken) {
      try {
        // JWT is base64url(header).base64url(payload).signature — decode payload
        const payload = accessToken.split('.')[1];
        if (payload) {
          const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString());
          if (decoded.sub) return `u_${decoded.sub}`;
        }
      } catch {
        // Not a valid JWT — fall through to hash
      }
    }
    // Fallback: hash token (less stable, but works if no JWT)
    const raw = refreshToken || accessToken || "anonymous";
    let hash = 0;
    for (let i = 0; i < raw.length; i++) {
      hash = ((hash << 5) - hash + raw.charCodeAt(i)) | 0;
    }
    return `u_${Math.abs(hash).toString(36)}`;
  }

  // ── PHASE 1: Sandbox Planner (no tools, no tokens) ──
  // The untrusted AI brain that THINKS but cannot ACT.
  function getSandboxSystemPrompt(memoryFacts: string[]) {
    const { dateStr, timeStr } = getDateContext();
    const memoryBlock = memoryFacts.length > 0
      ? `\nYou know these facts about this user from previous conversations:\n${memoryFacts.map(f => `- ${f}`).join('\n')}\nUse this knowledge to give more personalized plans.\n`
      : '';
    return `You are the PLANNING module of Beriwo, an autonomous AI agent.
Your job is to ANALYZE the user's request and produce a structured action plan.

Current date and time: ${dateStr}, ${timeStr}
${memoryBlock}
CRITICAL RULES:
- You have NO access to any tools or APIs. You can only PLAN.
- You NEVER see or handle user credentials. You are sandboxed.
- Your plans will be validated by a Policy Gate before execution.
- You CAN and MUST plan write operations (send emails, create events, etc.) — the Policy Gate and Consent system will handle approval. NEVER refuse to plan a write operation. NEVER say "I cannot create events" or "I cannot send emails". You absolutely CAN — plan it and the system handles the rest.

Available tools you can reference in your plan:
- list_emails(maxResults, query) — Read recent emails
- read_email(emailId) — Read full email content
- send_email(to, subject, body, cc?, bcc?) — Compose and send a new email [REQUIRES USER CONSENT]
- reply_to_email(emailId, body) — Reply to an existing email thread [REQUIRES USER CONSENT]
- list_upcoming_events(maxResults, timeMin, timeMax) — Check calendar
- create_calendar_event(summary, startDateTime, endDateTime, description, location, attendees?) — Create event [REQUIRES USER CONSENT]. For Google Meet, add "Google Meet link will be added" in the description — Google Calendar auto-generates Meet links for events with attendees.
- update_calendar_event(eventId, summary?, startDateTime?, endDateTime?, description?, location?) — Reschedule or edit event [REQUIRES USER CONSENT]
- delete_calendar_event(eventId) — Delete/cancel event [REQUIRES USER CONSENT]
- list_drive_files(query, maxResults) — Browse Drive files
- read_drive_file(fileId) — Read file content

IMPORTANT: Only use { "type": "direct" } for greetings, general knowledge questions, or requests that genuinely need NO tools. If the user asks to send, create, schedule, update, delete, or manage ANYTHING — you MUST return a plan with { "type": "plan" }.

For requests that need NO tools (general chat, greetings, questions about yourself):
Return a JSON object: { "type": "direct", "response": "your response here" }

For requests that need tools:
Return a JSON object:
{
  "type": "plan",
  "reasoning": "Brief explanation of your approach",
  "steps": [
    { "tool": "tool_name", "args": { ... }, "purpose": "why this step" },
    ...
  ],
  "synthesisHint": "How to present results to the user",
  "memoryUpdates": ["optional: new facts to remember about this user for future sessions"]
}

PLANNING GUIDELINES:
1. When asked to triage/summarize the day, plan MULTIPLE parallel reads: emails + calendar + drive.
2. When asked to create events, plan a calendar check FIRST, then the create step.
3. For relative dates ("today", "tomorrow"), compute the correct ISO 8601 date.
4. Be thorough — if the user asks about their day, don't just check one service.
5. Always respond with valid JSON only. No markdown, no explanation outside JSON.
6. If you learn user preferences (timezone, meeting length, etc.), include them in memoryUpdates.
7. When asked to send/reply to emails, draft the content yourself based on context. If the user gives instructions like "reply saying I'll be late", compose a professional email.
8. For multi-step tasks (e.g. "read my latest email and reply"), chain the steps: read first, then reply.
9. Be proactive — if asked to "handle" or "deal with" something, plan all necessary steps (read, respond, schedule, etc.).
10. For email sends/replies, always include the full composed body in the plan args. Don't leave placeholders.
11. CROSS-SERVICE INTELLIGENCE: When briefing the user on their day, connect the dots across services. For example, if there's a meeting about "Project X" and emails about "Project X", mention the connection. Flag conflicts (double-bookings, emails that need responses before scheduled meetings). Prioritize by urgency and time-sensitivity.
12. For daily briefings and triaging, organize output into actionable categories: URGENT (needs response before next meeting), TODAY (time-sensitive), and FYI (informational). This makes Beriwo more than a data fetcher — it becomes an executive assistant.
13. For Google Meet / video call requests: create a calendar event with create_calendar_event. Google Calendar automatically generates Meet links for events. Include relevant details in the description.
14. NEVER refuse to plan an action that uses an available tool. If the user asks to "schedule", "set up", "create", "send", "reply", "update", or "delete" something — ALWAYS create a plan. The consent system will ask the user for approval before execution.`;
  }

  // ── PHASE 3: Synthesis (no tools, no tokens) ──
  // Formats raw tool results into a human-friendly response.
  function getSynthesisSystemPrompt() {
    const { dateStr, timeStr } = getDateContext();
    return `You are the SYNTHESIS module of Beriwo, an autonomous AI agent.
Your job is to take raw tool execution results and format them into a clear, helpful response for the user.

Current date and time: ${dateStr}, ${timeStr}

RULES:
- You have NO access to any tools. You only format results.
- Use markdown for readability (headers, bullets, bold for important items).
- Be concise but thorough.
- If a step was blocked (required consent the user hasn't granted), explain what happened and that the action requires their approval.
- If a step failed, explain gracefully without exposing technical details.
- Never fabricate data. Only use the results provided.
- Highlight urgent or time-sensitive items.
- CROSS-SERVICE INSIGHTS: When results span multiple services (Gmail + Calendar + Drive), connect related items. Flag emails that reference upcoming meetings, documents relevant to scheduled events, and time conflicts. Organize by urgency: URGENT, TODAY, FYI.
- At the end of your response, if you learned any NEW facts about the user (preferences, patterns, names), return a JSON block:
\`\`\`memory
["fact1", "fact2"]
\`\`\`
Only include genuinely new, reusable facts. Omit this block if nothing new was learned.`;
  }

  // ── PHASE 2: Secure Executor (Token Vault + tools) ──
  // Executes ONLY pre-approved tool calls through Auth0 Token Vault.
  function getExecutorSystemPrompt(planInstructions?: string) {
    const { dateStr, timeStr } = getDateContext();
    const planBlock = planInstructions
      ? `\n\nYou MUST follow this execution plan from the planning module:\n${planInstructions}\nExecute exactly these steps in order. Do NOT call tools outside this plan.`
      : '';
    return `You are the SECURE EXECUTOR module of Beriwo. You execute tool calls through Auth0 Token Vault.

Current date and time: ${dateStr}, ${timeStr}
${planBlock}

IMPORTANT BEHAVIORS:
1. Execute the plan's steps faithfully. If the plan says to check calendar then read emails, do exactly that.
2. If a tool call fails with an authorization error, explain that you need Google account access via Auth0 Token Vault — credentials are never exposed to the AI.
3. Return raw results. Do NOT format them prettily — the Synthesis module will do that.
4. When the user asks about "today", "tomorrow", or any relative date, use the current date above.
5. Never fabricate data. Only report what tools actually return.`;
  }

  // Extract tool names from Genkit response messages
  function extractToolsUsed(response: any): string[] {
    const toolsUsed: string[] = [];
    if (response.messages) {
      for (const msg of response.messages) {
        if (msg.content) {
          for (const part of msg.content) {
            if (part.toolRequest?.name) {
              toolsUsed.push(part.toolRequest.name);
            }
          }
        }
      }
    }
    return [...new Set(toolsUsed)];
  }

  // Extract memory facts from synthesis response
  function extractMemoryFacts(text: string): { cleanText: string; facts: string[] } {
    const match = text.match(/```memory\s*\n([\s\S]*?)```/);
    if (!match) return { cleanText: text, facts: [] };
    try {
      const facts = JSON.parse(match[1].trim());
      const cleanText = text.replace(/```memory\s*\n[\s\S]*?```/, '').trim();
      return { cleanText, facts: Array.isArray(facts) ? facts : [] };
    } catch {
      return { cleanText: text, facts: [] };
    }
  }

  // ── Core 3-phase pipeline (reused by /chat, /resume, /approve) ──
  // ── FGA-style audit trail: log every authorization decision ──
  async function logAuthzDecision(db: any, admin: any, entry: {
    userId: string;
    action: string;
    resource: string;
    decision: "allow" | "deny";
    reason: string;
    tier?: string;
    timestamp?: any;
  }) {
    try {
      await db.collection("authz_audit_log").add({
        ...entry,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch { /* best-effort audit */ }
  }

  async function runPipeline(opts: {
    message: string;
    convoId: string;
    history: any[];
    refreshToken?: string;
    accessToken?: string;
    approvedWrites?: string[];
    userId: string;
    authTime?: number; // Unix epoch from JWT auth_time claim (for step-up auth)
    aiTier?: string;          // RBAC tier from Auth0 Action custom claim
    aiAllowedTools?: string[]; // allowed tools from Auth0 Action custom claim
    onEvent?: (event: string, data: any) => void;
  }): Promise<{
    reply: string;
    toolsUsed: string[];
    steps: ExecutionStep[];
    phases: { planned: boolean; executed: boolean; synthesized: boolean };
    plan: any;
    blockedWrites?: any[];
    interrupt?: any;
    stepUpRequired?: { tools: string[]; maxAge: number };
  }> {
    const { message, convoId, history, refreshToken, accessToken, approvedWrites, userId, authTime } = opts;
    const aiTier = opts.aiTier || "pro";
    const aiAllowedTools = opts.aiAllowedTools; // undefined = allow all (backwards compat)
    const onEvent = opts.onEvent;
    const ai = getAI();
    const steps: ExecutionStep[] = [];
    let plan: any = null;

    // Load cross-conversation memory
    const memoryFacts = await loadMemory(userId);
    logger.info(`Pipeline: userId=${userId}, memoryFacts=${memoryFacts.length}`);

    // ═══════════════════════════════════════════════════
    // PHASE 1: SANDBOX PLANNER (no tools, no tokens)
    // ═══════════════════════════════════════════════════
    logger.info("Phase 1: Sandbox planning...");
    onEvent?.("phase", { name: "planning", status: "started" });
    const plannerSession = ai.createSession();
    if (history.length > 0) {
      await plannerSession.updateMessages('main', history);
    }
    const plannerChat = plannerSession.chat({
      system: getSandboxSystemPrompt(memoryFacts),
    });
    const planResponse = await plannerChat.send(message);
    const planText = planResponse.text?.trim() || "";

    logger.info(`Phase 1 raw output: ${planText.substring(0, 500)}`);

    // Parse the plan — handle markdown code fences
    let cleanPlanText = planText;
    const fenceMatch = planText.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (fenceMatch) {
      cleanPlanText = fenceMatch[1].trim();
    }

    try {
      plan = JSON.parse(cleanPlanText);
    } catch {
      logger.warn("Planner returned non-JSON, falling back to direct execution");
      plan = null;
    }

    // Save any memory updates from the planner
    if (plan?.memoryUpdates?.length > 0) {
      await saveMemory(userId, plan.memoryUpdates);
      logger.info(`Saved ${plan.memoryUpdates.length} planner memory facts`);
    }

    // ── Direct response (no tools needed) ──
    if (plan?.type === "direct") {
      onEvent?.("phase", { name: "planning", status: "done", type: "direct" });
      await db.collection("conversations").doc(convoId).collection("messages").add({
        role: "model",
        text: plan.response || planText,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {
        reply: plan.response || planText,
        toolsUsed: [],
        steps: [],
        phases: { planned: true, executed: false, synthesized: false },
        plan,
      };
    }

    // ═══════════════════════════════════════════════════
    // PHASE 2: POLICY GATE + SECURE EXECUTION
    // The gate REMOVES tools, not just tells the LLM to skip them
    // ═══════════════════════════════════════════════════
    logger.info("Phase 2: Policy gate + secure execution...");
    onEvent?.("phase", { name: "planning", status: "done", type: "plan", stepCount: plan?.steps?.length });

    const approvedSet = new Set(approvedWrites || []);
    let hasBlockedWrites = false;
    const blockedWriteSteps: any[] = [];
    const allowedToolNames: string[] = [];

    const toolMap = getToolMap();
    const allToolNames = Object.keys(toolMap);

    // ── RBAC: filter tools by Auth0 Action tier claims ──
    const rbacAllowed = aiAllowedTools ? new Set(aiAllowedTools) : null;
    const rbacBlockedTools: string[] = [];
    if (rbacAllowed) {
      for (const name of allToolNames) {
        if (!rbacAllowed.has(name)) rbacBlockedTools.push(name);
      }
      logger.info(`RBAC tier=${aiTier}: allowed=${[...rbacAllowed].join(',')}, blocked=${rbacBlockedTools.join(',')}`);
    }

    if (plan?.type === "plan" && plan.steps?.length > 0) {
      for (const step of plan.steps) {
        const toolName = step.tool;
        const requiresConsent = WRITE_TOOLS.has(toolName);
        const isApproved = !requiresConsent || approvedSet.has(toolName);

        const execStep: ExecutionStep = {
          tool: toolName,
          label: TOOL_LABELS[toolName] || toolName,
          status: isApproved ? "pending" : "blocked",
          requiresConsent,
        };

        if (rbacAllowed && !rbacAllowed.has(toolName)) {
          // RBAC blocks this tool entirely — user's tier doesn't allow it
          execStep.status = "blocked";
          execStep.error = `Not available on ${aiTier} tier`;
          logAuthzDecision(db, admin, { userId, action: toolName, resource: "tool", decision: "deny", reason: `RBAC tier ${aiTier}`, tier: aiTier });
        } else if (!isApproved) {
          hasBlockedWrites = true;
          blockedWriteSteps.push({ ...step, execStep });
          execStep.status = "blocked";
          execStep.error = "Requires user consent";
          logAuthzDecision(db, admin, { userId, action: toolName, resource: "tool", decision: "deny", reason: "consent_required", tier: aiTier });
        } else if (allToolNames.includes(toolName)) {
          allowedToolNames.push(toolName);
          logAuthzDecision(db, admin, { userId, action: toolName, resource: "tool", decision: "allow", reason: "policy_gate_pass", tier: aiTier });
        }

        steps.push(execStep);
      }
    } else {
      // No plan — allow all read tools, block all write tools (also respect RBAC)
      for (const name of allToolNames) {
        if (rbacAllowed && !rbacAllowed.has(name)) continue; // RBAC blocks it
        if (!WRITE_TOOLS.has(name)) {
          allowedToolNames.push(name);
        } else if (approvedSet.has(name)) {
          allowedToolNames.push(name);
        }
      }
    }

    // REAL ENFORCEMENT: only pass allowed tools to the executor
    const executorTools = filterTools(toolMap, [...new Set(allowedToolNames)]);

    // ── STEP-UP AUTHENTICATION ──────────────────────────────────
    // High-risk tools (send_email, reply_to_email, delete_calendar_event)
    // require a recent login.  If the user's auth_time is too old,
    // we interrupt and ask the frontend to re-authenticate.
    const stepUpNeeded = allowedToolNames.filter(t => STEP_UP_TOOLS.has(t));
    if (stepUpNeeded.length > 0 && authTime) {
      const age = Math.floor(Date.now() / 1000) - authTime;
      if (age > STEP_UP_MAX_AGE_S) {
        logger.info(`Step-up required: auth_time age=${age}s, max=${STEP_UP_MAX_AGE_S}s, tools=${stepUpNeeded.join(',')}`);
        onEvent?.("phase", { name: "executing", status: "step_up_required" });
        return {
          reply: "",
          toolsUsed: [],
          steps,
          phases: { planned: true, executed: false, synthesized: false },
          plan: plan ? { reasoning: plan.reasoning, steps: plan.steps } : null,
          stepUpRequired: { tools: stepUpNeeded, maxAge: STEP_UP_MAX_AGE_S },
        };
      }
    }

    logger.info(`Policy gate: allowed=${allowedToolNames.join(',')}, blocked=${blockedWriteSteps.map((s: any) => s.tool).join(',')}`);
    onEvent?.("phase", { name: "executing", status: "started", allowedTools: allowedToolNames, blockedTools: blockedWriteSteps.map((s: any) => s.tool) });
    // Build a structured prompt that feeds the plan to the executor
    let executorPrompt = message;
    if (plan?.type === "plan" && plan.steps?.length > 0) {
      const planStepsDesc = plan.steps
        .filter((s: any) => !WRITE_TOOLS.has(s.tool) || approvedSet.has(s.tool))
        .map((s: any, i: number) => `${i + 1}. Call ${s.tool}(${JSON.stringify(s.args)}) — ${s.purpose}`)
        .join('\n');
      executorPrompt = `User request: "${message}"\n\nExecute these steps:\n${planStepsDesc}`;
    }

    const run = async () => {
      const session = ai.createSession();
      if (history.length > 0) {
        await session.updateMessages('main', history);
      }
      const chat = session.chat({
        system: getExecutorSystemPrompt(
          plan?.type === "plan"
            ? plan.steps
                .filter((s: any) => !WRITE_TOOLS.has(s.tool) || approvedSet.has(s.tool))
                .map((s: any) => `- ${s.tool}: ${s.purpose}`)
                .join('\n')
            : undefined,
        ),
        tools: executorTools,
      });
      return chat.send(executorPrompt);
    };

    const execStart = Date.now();

    const response = await withTokens(
      { refreshToken: refreshToken || undefined, accessToken: accessToken || undefined, userId: userId?.replace(/^u_/, '') },
      run,
    );

    // Check for interrupts (Token Vault auth needed)
    if (response.interrupts && response.interrupts.length > 0) {
      const interrupt = response.interrupts[0];
      logger.warn(`Token Vault interrupt: ${JSON.stringify(interrupt).substring(0, 500)}`);
      logger.warn(`Interrupt metadata: ${JSON.stringify(interrupt.metadata).substring(0, 500)}`);
      logger.warn(`All interrupts count: ${response.interrupts.length}`);
      return {
        reply: "",
        toolsUsed: [],
        steps,
        phases: { planned: true, executed: false, synthesized: false },
        plan: plan ? { reasoning: plan.reasoning, steps: plan.steps } : null,
        interrupt: { type: "authorization_required", data: interrupt.metadata },
      };
    }

    const executedTools = extractToolsUsed(response);
    const execDuration = Date.now() - execStart;

    // Update step statuses
    for (const step of steps) {
      if (step.status === "blocked") continue;
      if (executedTools.includes(step.tool)) {
        step.status = "done";
        step.durationMs = Math.round(execDuration / Math.max(executedTools.length, 1));
      } else {
        step.status = "skipped";
      }
    }

    for (const toolName of executedTools) {
      if (!steps.find(s => s.tool === toolName)) {
        steps.push({
          tool: toolName,
          label: TOOL_LABELS[toolName] || toolName,
          status: "done",
          requiresConsent: WRITE_TOOLS.has(toolName),
          durationMs: Math.round(execDuration / Math.max(executedTools.length, 1)),
        });
      }
    }

    // ═══════════════════════════════════════════════════
    // PHASE 2.5: MULTI-PASS REFLECTION LOOP — up to 3 passes
    // Each pass checks if the executor missed tools, re-runs if needed
    // ═══════════════════════════════════════════════════
    const MAX_REFLECTION_PASSES = 3;
    const rawResult = response.text || "";
    let finalResult = rawResult;

    if (plan?.type === "plan" && executedTools.length > 0) {
      for (let pass = 0; pass < MAX_REFLECTION_PASSES; pass++) {
        const missingTools = allowedToolNames.filter(t => !executedTools.includes(t));
        if (missingTools.length === 0) break;

        onEvent?.("phase", { name: "reflecting", status: "started", pass: pass + 1, missingTools });

        const reflectionSession = ai.createSession();
        const reflectionChat = reflectionSession.chat({
          system: `You are a reflection module. Given execution results, decide if the agent should try another pass to gather missing data. Respond with JSON only:
{ "needsMore": true/false, "reason": "..." }`,
        });

        try {
          const reflectionResp = await reflectionChat.send(
            `Plan had ${plan.steps.length} steps. Executed tools: ${executedTools.join(', ')}. Missing tools: ${missingTools.join(', ')}. Result so far: ${finalResult.substring(0, 500)}`
          );
          const reflText = reflectionResp.text?.trim() || "";
          let cleanRefl = reflText;
          const reflFence = reflText.match(/```(?:json)?\s*([\s\S]*?)```/);
          if (reflFence) cleanRefl = reflFence[1].trim();
          const reflection = JSON.parse(cleanRefl);

          if (!reflection.needsMore) {
            logger.info(`Reflection pass ${pass + 1}: no more data needed`);
            break;
          }

          logger.info(`Reflection pass ${pass + 1}: re-executing (${reflection.reason})`);

          const passRun = async () => {
            const s = ai.createSession();
            if (history.length > 0) await s.updateMessages('main', history);
            const c = s.chat({
              system: getExecutorSystemPrompt(),
              tools: executorTools,
            });
            return c.send(`${message}\n\nYou already gathered this data:\n${finalResult}\n\nNow complete these remaining steps: ${missingTools.join(', ')}`);
          };

          const passResult = await withTokens(
            { refreshToken: refreshToken || undefined, accessToken: accessToken || undefined, userId: userId?.replace(/^u_/, '') },
            passRun,
          );

          if (passResult.interrupts?.length) break; // Auth needed

          const passTools = extractToolsUsed(passResult);
          for (const t of passTools) {
            if (!executedTools.includes(t)) executedTools.push(t);
            const existing = steps.find(s => s.tool === t);
            if (existing) existing.status = "done";
            else steps.push({ tool: t, label: TOOL_LABELS[t] || t, status: "done", requiresConsent: WRITE_TOOLS.has(t) });
          }
          finalResult += "\n\n" + (passResult.text || "");

          onEvent?.("phase", { name: "reflecting", status: "done", pass: pass + 1, newTools: passTools });

          if (passTools.length === 0) break; // No new tools used, stop looping
        } catch {
          logger.warn(`Reflection pass ${pass + 1} failed, continuing`);
          break;
        }
      }
    }

    // ═══════════════════════════════════════════════════
    // PHASE 3: SYNTHESIS (no tools, no tokens)
    // ═══════════════════════════════════════════════════
    logger.info("Phase 3: Synthesis...");
    onEvent?.("phase", { name: "executing", status: "done", tools: executedTools });
    onEvent?.("phase", { name: "synthesizing", status: "started" });

    const synthesisPrompt = `The user asked: "${message}"

The secure executor produced this raw result:
---
${finalResult}
---

Execution summary:
${steps.map(s => `- ${s.label}: ${s.status}${s.requiresConsent ? ' [WRITE - consent required]' : ''}`).join('\n')}

${hasBlockedWrites ? `\nBLOCKED ACTIONS: The following write operations were blocked by the policy gate and require explicit user consent before execution: ${blockedWriteSteps.map((s: any) => TOOL_LABELS[s.tool] || s.tool).join(', ')}` : ''}

${plan?.synthesisHint ? `Presentation hint: ${plan.synthesisHint}` : ''}

Format a clear, helpful response for the user. Use markdown.`;

    const synthesisSession = ai.createSession();
    const synthesisChat = synthesisSession.chat({
      system: getSynthesisSystemPrompt(),
    });
    const synthesisResponse = await synthesisChat.send(synthesisPrompt);
    const synthesisText = synthesisResponse.text || finalResult;

    // Extract and save any memory facts from synthesis
    const { cleanText: reply, facts: synthFacts } = extractMemoryFacts(synthesisText);
    if (synthFacts.length > 0) {
      await saveMemory(userId, synthFacts);
      logger.info(`Saved ${synthFacts.length} synthesis memory facts`);
    }

    const finalReply = (reply && reply.trim().length > 0)
      ? reply
      : finalResult || "I wasn't able to complete that request. Please try again.";

    // Store the synthesized response
    await db.collection("conversations").doc(convoId).collection("messages").add({
      role: "model",
      text: finalReply,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(`Pipeline complete: ${steps.length} steps, ${executedTools.length} tools, blocked=${hasBlockedWrites}`);
    onEvent?.("phase", { name: "synthesizing", status: "done" });

    return {
      reply: finalReply,
      toolsUsed: executedTools,
      steps,
      phases: { planned: true, executed: true, synthesized: true },
      plan: plan ? { reasoning: plan.reasoning, stepCount: plan.steps?.length } : null,
      blockedWrites: hasBlockedWrites
        ? blockedWriteSteps.map((s: any) => ({
            tool: s.tool,
            label: TOOL_LABELS[s.tool] || s.tool,
            args: s.args,
            purpose: s.purpose,
          }))
        : undefined,
    };
  }

  // ── Main chat endpoint ──
  app.post("/chat", async (req: any, res: any) => {
    const { message, conversationId, refreshToken, accessToken, approvedWrites } = req.body;

    if (!message) {
      res.status(400).json({ error: "message is required" });
      return;
    }

    logger.info(`Chat: convo=${conversationId || 'new'}, hasAuth=${!!accessToken}`);

    const convoId = conversationId || admin.firestore().collection("tmp").doc().id;
    const userId = (req as any).auth?.sub
      ? `u_${(req as any).auth.sub}`
      : deriveUserId(refreshToken, accessToken);

    // Load conversation history
    const historySnap = await db
      .collection("conversations")
      .doc(convoId)
      .collection("messages")
      .orderBy("timestamp", "asc")
      .limit(50)
      .get();

    const history = historySnap.docs.map((doc: any) => {
      const d = doc.data();
      return { role: d.role as "user" | "model", content: [{ text: d.text }] };
    });

    logger.info(`Chat: convoId=${convoId}, historyMessages=${history.length}`);

    // Store user message
    await db
      .collection("conversations")
      .doc(convoId)
      .collection("messages")
      .add({
        role: "user",
        text: message,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

    try {
      // Extract RBAC claims from Auth0 Action (post-login enrichment)
      const auth = (req as any).auth || {};
      const aiTier = auth["https://beriwo.com/ai_tier"];
      const aiAllowedTools = auth["https://beriwo.com/ai_tools"];
      if (aiTier) logger.info(`RBAC: user tier=${aiTier}, tools=${aiAllowedTools?.length || 'all'}`);

      const result = await runPipeline({
        message,
        convoId,
        history,
        refreshToken,
        accessToken,
        approvedWrites,
        userId,
        authTime: (req as any).auth?.auth_time,
        aiTier,
        aiAllowedTools,
      });

      if (result.stepUpRequired) {
        res.json({
          conversationId: convoId,
          reply: null,
          stepUpRequired: result.stepUpRequired,
          executionSteps: result.steps,
          phases: result.phases,
          plan: result.plan,
        });
        return;
      }

      if (result.interrupt) {
        res.json({
          conversationId: convoId,
          reply: null,
          interrupt: result.interrupt,
          executionSteps: result.steps,
          phases: result.phases,
          plan: result.plan,
        });
        return;
      }

      res.json({
        conversationId: convoId,
        reply: result.reply,
        toolsUsed: result.toolsUsed,
        executionSteps: result.steps,
        phases: result.phases,
        plan: result.plan,
        blockedWrites: result.blockedWrites,
      });
    } catch (err: unknown) {
      const error = err as Error;
      console.error("Chat error:", error.message, error.stack);
      res.status(500).json({
        error: "Failed to process message",
        phases: { planned: false, executed: false, synthesized: false },
      });
    }
  });

  // ── Approve blocked writes — full pipeline with approved set ──
  app.post("/conversations/:id/approve", async (req: any, res: any) => {
    const { id } = req.params;
    const { refreshToken, accessToken, approvedTools } = req.body;

    logger.info(`Approve: convoId=${id}, tools=${approvedTools?.join(',')}`);

    try {
      const lastMsgSnap = await db
        .collection("conversations")
        .doc(id)
        .collection("messages")
        .where("role", "==", "user")
        .orderBy("timestamp", "desc")
        .limit(1)
        .get();

      if (lastMsgSnap.empty) {
        res.status(400).json({ error: "No user message found" });
        return;
      }

      const lastMessage = lastMsgSnap.docs[0].data().text;
      const userId = (req as any).auth?.sub
        ? `u_${(req as any).auth.sub}`
        : deriveUserId(refreshToken, accessToken);

      const historySnap = await db
        .collection("conversations")
        .doc(id)
        .collection("messages")
        .orderBy("timestamp", "asc")
        .limit(50)
        .get();

      const history = historySnap.docs.map((doc: any) => {
        const d = doc.data();
        return { role: d.role as "user" | "model", content: [{ text: d.text }] };
      });

      const result = await runPipeline({
        message: lastMessage,
        convoId: id,
        history,
        refreshToken,
        accessToken,
        approvedWrites: approvedTools || [],
        userId,
        authTime: (req as any).auth?.auth_time,
      });

      if (result.interrupt) {
        res.json({
          conversationId: id,
          reply: null,
          interrupt: result.interrupt,
        });
        return;
      }

      res.json({
        conversationId: id,
        reply: result.reply,
        toolsUsed: result.toolsUsed,
        executionSteps: result.steps,
        phases: result.phases,
      });
    } catch (err: unknown) {
      const error = err as Error;
      logger.error("Approve error:", error.message, error.stack);
      res.status(500).json({ error: "Failed to execute approved actions" });
    }
  });

  // ── Resume after Token Vault authorization — full pipeline ──
  app.post("/conversations/:id/resume", async (req: any, res: any) => {
    const { id } = req.params;
    const { refreshToken, accessToken } = req.body;

    logger.info(`Resume: convoId=${id}`);

    try {
      const lastMsgSnap = await db
        .collection("conversations")
        .doc(id)
        .collection("messages")
        .where("role", "==", "user")
        .orderBy("timestamp", "desc")
        .limit(1)
        .get();

      if (lastMsgSnap.empty) {
        res.status(400).json({ error: "No user message found to resume" });
        return;
      }

      const lastMessage = lastMsgSnap.docs[0].data().text;
      const userId = (req as any).auth?.sub
        ? `u_${(req as any).auth.sub}`
        : deriveUserId(refreshToken, accessToken);

      logger.info(`Resume: replaying message "${lastMessage.substring(0, 80)}"`);

      const historySnap = await db
        .collection("conversations")
        .doc(id)
        .collection("messages")
        .orderBy("timestamp", "asc")
        .limit(50)
        .get();

      const history = historySnap.docs.map((doc: any) => {
        const d = doc.data();
        return { role: d.role as "user" | "model", content: [{ text: d.text }] };
      });

      // Exclude the last message from history since the pipeline will replay it
      const resumeHistory = history.slice(0, -1);

      const result = await runPipeline({
        message: lastMessage,
        convoId: id,
        history: resumeHistory,
        refreshToken,
        accessToken,
        userId,
        authTime: (req as any).auth?.auth_time,
      });

      if (result.interrupt) {
        logger.warn(`Resume STILL interrupted. refreshToken=${refreshToken ? 'present' : 'MISSING'}`);
        res.json({
          conversationId: id,
          reply: null,
          interrupt: result.interrupt,
        });
        return;
      }

      logger.info(`Resume success: replyLen=${result.reply?.length}, tools=${result.toolsUsed.join(',')}`);
      res.json({
        conversationId: id,
        reply: result.reply,
        toolsUsed: result.toolsUsed,
        executionSteps: result.steps,
        phases: result.phases,
      });
    } catch (err: unknown) {
      const error = err as Error;
      logger.error("Resume error:", error.message, error.stack);
      res.status(500).json({ error: "Failed to resume conversation" });
    }
  });

  // ── SSE streaming endpoint: live pipeline updates ──
  app.post("/chat/stream", async (req: any, res: any) => {
    const { message, conversationId, refreshToken, accessToken, approvedWrites } = req.body;

    if (!message) {
      res.status(400).json({ error: "message is required" });
      return;
    }

    // Set up SSE
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");
    res.flushHeaders();

    const sendSSE = (event: string, data: any) => {
      res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };

    const convoId = conversationId || admin.firestore().collection("tmp").doc().id;
    const userId = (req as any).auth?.sub
      ? `u_${(req as any).auth.sub}`
      : deriveUserId(refreshToken, accessToken);

    sendSSE("started", { conversationId: convoId });

    const historySnap = await db
      .collection("conversations")
      .doc(convoId)
      .collection("messages")
      .orderBy("timestamp", "asc")
      .limit(50)
      .get();

    const history = historySnap.docs.map((doc: any) => {
      const d = doc.data();
      return { role: d.role as "user" | "model", content: [{ text: d.text }] };
    });

    await db.collection("conversations").doc(convoId).collection("messages").add({
      role: "user",
      text: message,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      // Extract RBAC claims from Auth0 Action (post-login enrichment)
      const auth = (req as any).auth || {};
      const aiTier = auth["https://beriwo.com/ai_tier"];
      const aiAllowedTools = auth["https://beriwo.com/ai_tools"];

      const result = await runPipeline({
        message,
        convoId,
        history,
        refreshToken,
        accessToken,
        approvedWrites,
        userId,
        authTime: (req as any).auth?.auth_time,
        aiTier,
        aiAllowedTools,
        onEvent: sendSSE,
      });

      if (result.stepUpRequired) {
        sendSSE("step_up", {
          conversationId: convoId,
          stepUpRequired: result.stepUpRequired,
          executionSteps: result.steps,
          phases: result.phases,
        });
      } else if (result.interrupt) {
        sendSSE("interrupt", {
          conversationId: convoId,
          type: result.interrupt.type,
          data: result.interrupt.data,
          executionSteps: result.steps,
          phases: result.phases,
        });
      } else {
        sendSSE("done", {
          conversationId: convoId,
          reply: result.reply,
          toolsUsed: result.toolsUsed,
          executionSteps: result.steps,
          phases: result.phases,
          plan: result.plan,
          blockedWrites: result.blockedWrites,
        });
      }
    } catch (err: unknown) {
      const error = err as Error;
      logger.error("Stream error:", error.message);
      sendSSE("error", { message: "Pipeline failed" });
    }

    res.end();
  });

  _app = app;
  return _app;
}

export const api = onRequest((req, res) => {
  const app = ensureApp();
  return app(req, res);
});

export const agentTick = onSchedule("every 10 minutes", async (event) => {
  const app = ensureApp(); // Loads admin, express, AI etc.
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const admin = require("firebase-admin");
  const db = admin.firestore();
  
  // 1. Fetch users with auto_pilot enabled
  const snap = await db.collection("user_settings").where("autoPilot", "==", true).get();
  if (snap.empty) {
    logger.info("No users have Auto Pilot enabled.");
    return;
  }

  logger.info(`Running AutoPilot tick for ${snap.size} users...`);

  // 2. Execute agent cycle for each active user
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { runAutoPilot } = require("./agent.js");
  
  const promises = snap.docs.map((doc: any) => {
    const userId = doc.id;
    return runAutoPilot(userId, db).catch((e: Error) => {
      logger.error(`AutoPilot failed for user ${userId}:`, e);
    });
  });

  await Promise.all(promises);
  logger.info("AutoPilot tick complete.");
});
