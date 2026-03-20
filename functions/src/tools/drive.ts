import { z } from "zod";
import { defineProtectedTool } from "../auth0.js";

let _cached: ReturnType<typeof register> | null = null;
export function getDriveTools() {
  if (!_cached) _cached = register();
  return _cached;
}

function register() {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { getAccessTokenFromTokenVault } = require("@auth0/ai-genkit");

  const listDriveFiles = defineProtectedTool(
  {
    name: "list_drive_files",
    description:
      "List files from the user's Google Drive. Can search by name.",
    inputSchema: z.object({
      query: z
        .string()
        .optional()
        .describe("Search term to filter files by name"),
      maxResults: z
        .number()
        .int()
        .min(1)
        .max(20)
        .default(10)
        .describe("Number of files to retrieve"),
    }),
    outputSchema: z.object({
      files: z.array(
        z.object({
          id: z.string(),
          name: z.string(),
          mimeType: z.string(),
          modifiedTime: z.string(),
          webViewLink: z.string().optional(),
        })
      ),
    }),
  },
  async ({ query, maxResults }) => {
      const accessToken = getAccessTokenFromTokenVault();

      const params = new URLSearchParams({
        pageSize: String(maxResults),
        fields: "files(id,name,mimeType,modifiedTime,webViewLink)",
        orderBy: "modifiedTime desc",
      });

      if (query) {
        params.set("q", `name contains '${query.replace(/'/g, "\\'")}'`);
      }

      const res = await fetch(
        `https://www.googleapis.com/drive/v3/files?${params}`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );

      if (!res.ok) {
        throw new Error(`Drive API error: ${res.status}`);
      }

      const data = (await res.json()) as {
        files?: {
          id: string;
          name: string;
          mimeType: string;
          modifiedTime: string;
          webViewLink?: string;
        }[];
      };
      return { files: data.files || [] };
  }
);

const readDriveFile = defineProtectedTool(
  {
    name: "read_drive_file",
    description:
      "Read the text content of a Google Drive document (Docs, Sheets text, or plain text files)",
    inputSchema: z.object({
      fileId: z.string().describe("The Google Drive file ID"),
    }),
    outputSchema: z.object({
      name: z.string(),
      content: z.string(),
    }),
  },
  async ({ fileId }) => {
      const accessToken = getAccessTokenFromTokenVault();
      const headers = { Authorization: `Bearer ${accessToken}` };

      // Get file metadata
      const metaRes = await fetch(
        `https://www.googleapis.com/drive/v3/files/${fileId}?fields=name,mimeType`,
        { headers }
      );

      if (!metaRes.ok) {
        throw new Error(`Drive API error: ${metaRes.status}`);
      }

      const meta = (await metaRes.json()) as {
        name: string;
        mimeType: string;
      };

      // Export Google Docs/Sheets/Slides as plain text
      let contentUrl: string;
      if (meta.mimeType.startsWith("application/vnd.google-apps.")) {
        contentUrl = `https://www.googleapis.com/drive/v3/files/${fileId}/export?mimeType=text/plain`;
      } else {
        contentUrl = `https://www.googleapis.com/drive/v3/files/${fileId}?alt=media`;
      }

      const contentRes = await fetch(contentUrl, { headers });
      if (!contentRes.ok) {
        throw new Error(`Failed to read file: ${contentRes.status}`);
      }

      const content = await contentRes.text();

      return {
        name: meta.name,
        content: content.slice(0, 5000),
      };
  }
);

return { listDriveFiles, readDriveFile };
}
