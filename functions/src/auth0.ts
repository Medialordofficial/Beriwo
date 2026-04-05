import type { GenkitBeta } from "genkit/beta";
import type { ZodTypeAny } from "zod";
import { AsyncLocalStorage } from "node:async_hooks";

const requestContext = new AsyncLocalStorage<{ refreshToken?: string; accessToken?: string; userId?: string }>();

/** Run a callback with the user's Auth0 tokens available to Token Vault */
export function withTokens<T>(
  tokens: { refreshToken?: string; accessToken?: string; userId?: string },
  fn: () => T,
): T {
  return requestContext.run(tokens, fn);
}

// ── Hybrid Token Architecture ──────────────────────────────────────────────
// Auth0 Token Vault wraps every tool to enforce scope gating, consent
// interrupts, and credential isolation — the AI never sees raw tokens.
//
// However, Token Vault's built-in token *exchange* (e.g. refresh-token →
// downstream access-token) is designed for Regular Web App clients that
// own long-lived refresh tokens.  SPA clients use rotating refresh tokens
// and opaque access tokens, which Token Vault cannot exchange on its own.
//
// Our solution: Token Vault still governs tool access and security policy,
// while we retrieve the downstream Google token via the Management API's
// `read:user_idp_tokens` scope.  This keeps credentials server-side only,
// preserves the zero-trust AI sandbox, and works with any Auth0 app type.
// ───────────────────────────────────────────────────────────────────────────
let _mgmtToken: string | null = null;
let _mgmtTokenExpires = 0;

async function getManagementToken(): Promise<string> {
  if (_mgmtToken && Date.now() < _mgmtTokenExpires) return _mgmtToken;

  const domain = process.env.AUTH0_DOMAIN!;
  const clientId = process.env.AUTH0_CLIENT_ID!;
  const clientSecret = process.env.AUTH0_CLIENT_SECRET!;

  const res = await fetch(`https://${domain}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "client_credentials",
      client_id: clientId,
      client_secret: clientSecret,
      audience: `https://${domain}/api/v2/`,
      scope: "read:users read:user_idp_tokens",
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Management API token failed: ${res.status} ${err}`);
  }

  const data = await res.json() as { access_token: string; expires_in: number; scope?: string };
  _mgmtToken = data.access_token;
  // Refresh 60s before expiry
  _mgmtTokenExpires = Date.now() + (data.expires_in - 60) * 1000;

  return _mgmtToken;
}

/**
 * Retrieve the user's Google access token via Auth0 Management API.
 *
 * When a user signs in with Google through Auth0's social connection,
 * Auth0 stores the downstream Google tokens on the user profile.
 * We read them using the `read:user_idp_tokens` scope — the tokens
 * never leave the server and are never exposed to the AI model.
 */
export async function getGoogleTokenForUser(userAccessToken: string): Promise<string | null> {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { logger } = require("firebase-functions/v2");

  try {
    // Decode user ID from the Auth0 access token
    const parts = userAccessToken.split('.');
    if (parts.length !== 3) return null;
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    const userId = payload.sub;
    if (!userId) return null;

    return await getGoogleTokenForUserId(userId);
  } catch (err: any) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { logger: log } = require("firebase-functions/v2");
    log.warn(`getGoogleTokenForUser error: ${err.message}`);
    return null;
  }
}

export async function getGoogleTokenForUserId(userId: string, _retry = false): Promise<string | null> {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { logger } = require("firebase-functions/v2");

  try {
    const mgmtToken = await getManagementToken();
    const domain = process.env.AUTH0_DOMAIN!;

    const res = await fetch(
      `https://${domain}/api/v2/users/${encodeURIComponent(userId)}?fields=identities&include_fields=true`,
      { headers: { Authorization: `Bearer ${mgmtToken}` } },
    );

    if (!res.ok) {
      const errBody = await res.text().catch(() => "");
      logger.warn(`Management API user fetch failed: ${res.status} ${errBody.substring(0, 300)}`);
      // Clear cached token in case it's expired/invalid
      _mgmtToken = null;
      _mgmtTokenExpires = 0;
      // Retry once with a fresh management token
      if (!_retry && (res.status === 401 || res.status === 403)) {
        logger.info("Retrying with fresh management token...");
        return getGoogleTokenForUserId(userId, true);
      }
      return null;
    }

    const user = await res.json() as {
      identities?: Array<{
        connection: string;
        provider: string;
        access_token?: string;
        refresh_token?: string;
      }>;
    };

    const googleId = user.identities?.find(
      (i) => i.connection === "google-oauth2" || i.provider === "google-oauth2",
    );

    if (!googleId) {
      logger.warn(`No Google identity for ${userId}. Identities: ${user.identities?.map(i => i.connection).join(', ') || 'none'}`);
      return null;
    }

    // First try the stored access token — verify it's still valid
    if (googleId.access_token) {
      const testRes = await fetch(
        "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=" + googleId.access_token,
      );
      if (testRes.ok) {
        logger.info(`Google access token still valid for ${userId}`);
        return googleId.access_token;
      }
      logger.info(`Google access token expired for ${userId}, attempting refresh...`);
    }

    // Access token expired or missing — try to refresh using the refresh_token
    if (googleId.refresh_token) {
      const freshToken = await refreshGoogleToken(googleId.refresh_token);
      if (freshToken) {
        logger.info(`Successfully refreshed Google token for ${userId}`);
        return freshToken;
      }
      logger.warn(`Failed to refresh Google token for ${userId}`);
    } else {
      logger.warn(`No Google refresh_token stored for ${userId}. The Auth0 Google connection needs 'offline_access' / access_type=offline.`);
    }

    // Last resort: return the stored token even if expired (let the caller handle errors)
    if (googleId.access_token) {
      logger.warn(`Returning possibly-expired Google token for ${userId} as last resort`);
      return googleId.access_token;
    }

    logger.warn(`No Google tokens available for ${userId}`);
    return null;
  } catch (err: any) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { logger: log } = require("firebase-functions/v2");
    log.warn(`getGoogleTokenForUserId error: ${err.message}`);
    return null;
  }
}

/**
 * Refresh a Google access token using a stored refresh token.
 * Requires GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET env vars,
 * which must match the Google OAuth client configured in Auth0's Google social connection.
 */
async function refreshGoogleToken(refreshToken: string): Promise<string | null> {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { logger } = require("firebase-functions/v2");

  const clientId = process.env.GOOGLE_OAUTH_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_OAUTH_CLIENT_SECRET;

  if (!clientId || !clientSecret) {
    logger.warn("GOOGLE_OAUTH_CLIENT_ID / GOOGLE_OAUTH_CLIENT_SECRET not set — cannot refresh Google token");
    return null;
  }

  try {
    const res = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "refresh_token",
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
      }).toString(),
    });

    if (!res.ok) {
      const errBody = await res.text().catch(() => "");
      logger.warn(`Google token refresh failed: ${res.status} ${errBody.substring(0, 300)}`);
      return null;
    }

    const data = await res.json() as { access_token: string; expires_in: number };
    return data.access_token;
  } catch (err: any) {
    logger.warn(`Google token refresh error: ${err.message}`);
    return null;
  }
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
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { logger } = require("firebase-functions/v2");

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

  // Use direct access token path: provide the Google token directly via
  // Auth0 Management API (reads from user's linked google-oauth2 identity).
  // This avoids Token Vault's token exchange which doesn't work with SPA
  // refresh tokens (rotating) or access tokens (not a resource server).
  _withGoogle = auth0AI.withTokenVault({
    accessToken: async () => {
      const ctx = requestContext.getStore();
      
      let googleToken: string | null = null;
      if (ctx?.userId) {
        googleToken = await getGoogleTokenForUserId(ctx.userId);
      } else if (ctx?.accessToken) {
        googleToken = await getGoogleTokenForUser(ctx.accessToken);
      }

      if (!googleToken) {
        logger.warn("Token Vault: no Google token found (no userId or accessToken)");
        return undefined;
      }

      // Return a token response object that Token Vault will use directly
      // (no exchange). The scope string must include all required scopes.
      return {
        access_token: googleToken,
        token_type: "Bearer",
        scope: [
          "https://www.googleapis.com/auth/gmail.readonly",
          "https://www.googleapis.com/auth/gmail.send",
          "https://www.googleapis.com/auth/calendar.readonly",
          "https://www.googleapis.com/auth/calendar.events",
          "https://www.googleapis.com/auth/drive.readonly",
        ].join(" "),
      };
    },
    connection: "google-oauth2",
    scopes: [
      "https://www.googleapis.com/auth/gmail.readonly",
      "https://www.googleapis.com/auth/gmail.send",
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
