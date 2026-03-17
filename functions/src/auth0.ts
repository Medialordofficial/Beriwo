import { Auth0AI } from "@auth0/ai-genkit";
import { genkit, z } from "genkit/beta";
import { googleAI, gemini20Flash } from "@genkit-ai/googleai";

export const ai = genkit({
  plugins: [googleAI({ apiKey: process.env.GOOGLE_AI_API_KEY })],
  model: gemini20Flash,
});

export const auth0AI = new Auth0AI({
  auth0: {
    domain: process.env.AUTH0_DOMAIN!,
    clientId: process.env.AUTH0_CLIENT_ID!,
    clientSecret: process.env.AUTH0_CLIENT_SECRET!,
  },
  genkit: ai as any,
});

const withGoogle = auth0AI.withTokenVault({
  connection: "google-oauth2",
  scopes: [
    "openid",
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/drive.readonly",
  ],
});

export function defineProtectedTool<
  I extends z.ZodTypeAny,
  O extends z.ZodTypeAny,
>(config: { name: string; description: string; inputSchema: I; outputSchema: O }, fn: (input: z.infer<I>) => Promise<z.infer<O>>) {
  return ai.defineTool(...withGoogle(config, fn as any));
}
