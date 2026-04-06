import { z } from "zod";
import { defineProtectedTool } from "../auth0.js";

let _cached: ReturnType<typeof register> | null = null;
export function getGmailTools() {
  if (!_cached) _cached = register();
  return _cached;
}

function register() {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { getAccessTokenFromTokenVault } = require("@auth0/ai-genkit");

  const listEmails = defineProtectedTool(
  {
    name: "list_emails",
    description: "List recent emails from the user's Gmail inbox",
    inputSchema: z.object({
      maxResults: z
        .number()
        .int()
        .min(1)
        .max(50)
        .default(10)
        .describe("Number of emails to retrieve (max 50)"),
      query: z
        .string()
        .optional()
        .describe("Search query to filter emails"),
    }),
    outputSchema: z.object({
      emails: z.array(
        z.object({
          id: z.string(),
          subject: z.string(),
          from: z.string(),
          snippet: z.string(),
          date: z.string(),
        })
      ),
    }),
  },
  async ({ maxResults, query }) => {
      const accessToken = getAccessTokenFromTokenVault();

      const safeMax = Math.min(Math.max(maxResults || 10, 1), 50);
      const params = new URLSearchParams({
        maxResults: String(safeMax),
      });
      if (query) params.set("q", query);

      const listRes = await fetch(
        `https://gmail.googleapis.com/gmail/v1/users/me/messages?${params}`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );

      if (!listRes.ok) {
        const errBody = await listRes.text().catch(() => "");
        require("firebase-functions/v2").logger.warn(`Gmail API error: ${listRes.status} ${errBody.substring(0, 300)}`);
        throw new Error(`Gmail API error: ${listRes.status}`);
      }

      const listData = (await listRes.json()) as {
        messages?: { id: string }[];
      };
      const msgList = listData.messages || [];

      const emails = await Promise.all(
        msgList.slice(0, maxResults).map(async (msg) => {
          const res = await fetch(
            `https://gmail.googleapis.com/gmail/v1/users/me/messages/${msg.id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date`,
            { headers: { Authorization: `Bearer ${accessToken}` } }
          );
          const data = (await res.json()) as {
            id: string;
            snippet?: string;
            payload?: {
              headers?: { name: string; value: string }[];
            };
          };
          const headers = data.payload?.headers || [];
          const get = (name: string) =>
            headers.find((h) => h.name === name)?.value || "";

          return {
            id: data.id,
            subject: get("Subject"),
            from: get("From"),
            snippet: data.snippet || "",
            date: get("Date"),
          };
        })
      );

      return { emails };
  }
);

const readEmail = defineProtectedTool(
  {
    name: "read_email",
    description: "Read the full content of a specific email by its ID",
    inputSchema: z.object({
      emailId: z.string().describe("The Gmail message ID"),
    }),
    outputSchema: z.object({
      subject: z.string(),
      from: z.string(),
      to: z.string(),
      date: z.string(),
      body: z.string(),
    }),
  },
  async ({ emailId }) => {
      const accessToken = getAccessTokenFromTokenVault();

      const res = await fetch(
        `https://gmail.googleapis.com/gmail/v1/users/me/messages/${emailId}?format=full`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );

      if (!res.ok) {
        throw new Error(`Gmail API error: ${res.status}`);
      }

      const data = (await res.json()) as {
        payload?: {
          headers?: { name: string; value: string }[];
          body?: { data?: string };
          parts?: { mimeType: string; body?: { data?: string } }[];
        };
      };
      const headers = data.payload?.headers || [];
      const get = (name: string) =>
        headers.find((h) => h.name === name)?.value || "";

      let body = "";
      if (data.payload?.body?.data) {
        body = Buffer.from(data.payload.body.data, "base64url").toString(
          "utf-8"
        );
      } else if (data.payload?.parts) {
        const textPart = data.payload.parts.find(
          (p) => p.mimeType === "text/plain"
        );
        if (textPart?.body?.data) {
          body = Buffer.from(textPart.body.data, "base64url").toString("utf-8");
        }
      }

      return {
        subject: get("Subject"),
        from: get("From"),
        to: get("To"),
        date: get("Date"),
        body: body.slice(0, 3000),
      };
  }
);

const sendEmail = defineProtectedTool(
  {
    name: "send_email",
    description: "Compose and send a new email on behalf of the user",
    inputSchema: z.object({
      to: z.string().describe("Recipient email address"),
      subject: z.string().describe("Email subject line"),
      body: z.string().describe("Email body (plain text)"),
      cc: z.string().optional().describe("CC recipients (comma-separated)"),
      bcc: z.string().optional().describe("BCC recipients (comma-separated)"),
    }),
    outputSchema: z.object({
      id: z.string(),
      threadId: z.string(),
      status: z.string(),
    }),
  },
  async ({ to, subject, body, cc, bcc }) => {
    const accessToken = getAccessTokenFromTokenVault();

    const headers = [
      `To: ${to}`,
      `Subject: ${subject}`,
      `Content-Type: text/plain; charset="UTF-8"`,
    ];
    if (cc) headers.push(`Cc: ${cc}`);
    if (bcc) headers.push(`Bcc: ${bcc}`);

    const rawMessage = headers.join("\r\n") + "\r\n\r\n" + body;
    const encodedMessage = Buffer.from(rawMessage)
      .toString("base64")
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");

    const res = await fetch(
      "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ raw: encodedMessage }),
      }
    );

    if (!res.ok) {
      const errBody = await res.text().catch(() => "");
      throw new Error(`Gmail send error: ${res.status} ${errBody.substring(0, 200)}`);
    }

    const data = (await res.json()) as { id: string; threadId: string };
    return { id: data.id, threadId: data.threadId, status: "sent" };
  }
);

const replyToEmail = defineProtectedTool(
  {
    name: "reply_to_email",
    description: "Reply to an existing email thread",
    inputSchema: z.object({
      emailId: z.string().describe("The Gmail message ID to reply to"),
      body: z.string().describe("Reply body (plain text)"),
    }),
    outputSchema: z.object({
      id: z.string(),
      threadId: z.string(),
      status: z.string(),
    }),
  },
  async ({ emailId, body }) => {
    const accessToken = getAccessTokenFromTokenVault();
    const headers = { Authorization: `Bearer ${accessToken}` };

    // Fetch original message to get headers
    const origRes = await fetch(
      `https://gmail.googleapis.com/gmail/v1/users/me/messages/${emailId}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Message-ID`,
      { headers }
    );
    if (!origRes.ok) throw new Error(`Gmail API error: ${origRes.status}`);

    const orig = (await origRes.json()) as {
      threadId: string;
      payload?: { headers?: { name: string; value: string }[] };
    };
    const origHeaders = orig.payload?.headers || [];
    const getH = (name: string) => origHeaders.find((h) => h.name === name)?.value || "";

    const replyTo = getH("From");
    const origSubject = getH("Subject");
    const messageId = getH("Message-ID");
    const subject = origSubject.startsWith("Re:") ? origSubject : `Re: ${origSubject}`;

    const rawHeaders = [
      `To: ${replyTo}`,
      `Subject: ${subject}`,
      `In-Reply-To: ${messageId}`,
      `References: ${messageId}`,
      `Content-Type: text/plain; charset="UTF-8"`,
    ];
    const rawMessage = rawHeaders.join("\r\n") + "\r\n\r\n" + body;
    const encodedMessage = Buffer.from(rawMessage)
      .toString("base64")
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");

    const res = await fetch(
      "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ raw: encodedMessage, threadId: orig.threadId }),
      }
    );

    if (!res.ok) {
      const errBody = await res.text().catch(() => "");
      throw new Error(`Gmail reply error: ${res.status} ${errBody.substring(0, 200)}`);
    }

    const data = (await res.json()) as { id: string; threadId: string };
    return { id: data.id, threadId: data.threadId, status: "sent" };
  }
);

const trashEmail = defineProtectedTool(
  {
    name: "trash_email",
    description: "Move an email to the Trash folder",
    inputSchema: z.object({
      emailId: z.string().describe("The Gmail message ID to trash"),
    }),
    outputSchema: z.object({
      status: z.string(),
    }),
  },
  async ({ emailId }) => {
    const accessToken = getAccessTokenFromTokenVault();

    const res = await fetch(
      `https://gmail.googleapis.com/gmail/v1/users/me/messages/${emailId}/trash`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}` },
      }
    );

    if (!res.ok) {
      const errBody = await res.text().catch(() => "");
      throw new Error(`Gmail trash error: ${res.status} ${errBody.substring(0, 200)}`);
    }

    return { status: "trashed" };
  }
);

const markAsSpam = defineProtectedTool(
  {
    name: "mark_as_spam",
    description: "Mark an email as spam by adding the SPAM label and removing INBOX",
    inputSchema: z.object({
      emailId: z.string().describe("The Gmail message ID to mark as spam"),
    }),
    outputSchema: z.object({
      status: z.string(),
    }),
  },
  async ({ emailId }) => {
    const accessToken = getAccessTokenFromTokenVault();

    const res = await fetch(
      `https://gmail.googleapis.com/gmail/v1/users/me/messages/${emailId}/modify`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          addLabelIds: ["SPAM"],
          removeLabelIds: ["INBOX"],
        }),
      }
    );

    if (!res.ok) {
      const errBody = await res.text().catch(() => "");
      throw new Error(`Gmail spam error: ${res.status} ${errBody.substring(0, 200)}`);
    }

    return { status: "marked_as_spam" };
  }
);

return { listEmails, readEmail, sendEmail, replyToEmail, trashEmail, markAsSpam };
}
