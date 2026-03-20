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
        .max(20)
        .default(5)
        .describe("Number of emails to retrieve"),
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

      const params = new URLSearchParams({
        maxResults: String(maxResults),
      });
      if (query) params.set("q", query);

      const listRes = await fetch(
        `https://gmail.googleapis.com/gmail/v1/users/me/messages?${params}`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );

      if (!listRes.ok) {
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

return { listEmails, readEmail };
}
