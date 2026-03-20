import type { GenkitBeta } from "genkit/beta";
import type { ZodTypeAny } from "zod";
import { AsyncLocalStorage } from "node:async_hooks";

const requestContext = new AsyncLocalStorage<{ refreshToken: string }>();

/** Run a callback with the user's Auth0 refresh token available to Token Vault */
export function withRefreshToken<T>(
  refreshToken: string,
  fn: () => T,
): T {
  return requestContext.run({ refreshToken }, fn);
}

let _ai: GenkitBeta;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let _withGoogle: any;

function ensureInit() {
  if (_ai) return;

  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { genkit } = require("genkit/beta");
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { googleAI, gemini } = require("@genkit-ai/googleai");
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { Auth0AI } = require("@auth0/ai-genkit");

  _ai = genkit({
    plugins: [googleAI({ apiKey: process.env.GOOGLE_AI_API_KEY })],
    model: gemini("gemini-2.5-flash"),
  });

  const auth0AI = new Auth0AI({
    auth0: {
      domain: process.env.AUTH0_DOMAIN!,
      clientId: process.env.AUTH0_CLIENT_ID!,
      clientSecret: process.env.AUTH0_CLIENT_SECRET!,
    },
    genkit: _ai as any,
  });

  _withGoogle = auth0AI.withTokenVault({
    refreshToken: () => {
      const ctx = requestContext.getStore();
      return ctx?.refreshToken;
    },
    connection: "google-oauth2",
    scopes: [
      "openid",
      "https://www.googleapis.com/auth/gmail.readonly",
      "https://www.googleapis.com/auth/calendar.readonly",
      "https://www.googleapis.com/auth/calendar.events",
      "https://www.googleapis.com/auth/drive.readonly",
    ],
  });
}

export function getAI(): GenkitBeta {
  ensureInit();
  return _ai;
}

export function defineProtectedTool<
  I extends ZodTypeAny,
  O extends ZodTypeAny,
>(
  config: { name: string; description: string; inputSchema: I; outputSchema: O },
  fn: (input: any) => Promise<any>,
) {
  ensureInit();
  const [toolConfig, toolFn] = _withGoogle(config, fn as any);
  return _ai.defineTool(toolConfig, toolFn);
}
