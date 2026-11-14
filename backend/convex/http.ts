import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { exchangeAuthorizationCode, verifyAppleIdentityToken } from "./lib/apple";
import { REFRESH_TOKEN_TTL_MS } from "./lib/constants";
import { hashToken, newRefreshToken, publicJwks, signAccessToken } from "./lib/tokens";

/**
 * Auth endpoints for the iOS app. All take and return JSON. Errors are
 * `{ code }` with 400 (`invalid_request`), 401 (`invalid_token`) or 503
 * (`apple_unavailable`, when Apple's keys can't be fetched).
 */
const http = httpRouter();

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
const badRequest = () => json({ code: "invalid_request" }, 400);
const invalidToken = () => json({ code: "invalid_token" }, 401);

async function readBody(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const body = await req.json();
    return body && typeof body === "object" && !Array.isArray(body) ? body : null;
  } catch {
    return null;
  }
}

/** Accepts "Ram Sharma" or Apple's {givenName, familyName}. */
function fullNameString(value: unknown): string | undefined {
  if (typeof value === "string") return value;
  if (value && typeof value === "object") {
    const { givenName, familyName } = value as Record<string, unknown>;
    const parts = [givenName, familyName].filter((p): p is string => typeof p === "string");
    return parts.join(" ") || undefined;
  }
  return undefined;
}

const optionalString = (value: unknown) => (typeof value === "string" && value ? value : undefined);

async function issueTokens(userId: string, refreshToken: string, refreshExpiresAt: number) {
  const access = await signAccessToken(userId, Date.now());
  return {
    accessToken: access.token,
    accessTokenExpiresAt: access.expiresAt,
    refreshToken,
    refreshTokenExpiresAt: refreshExpiresAt,
  };
}

/**
 * POST /auth/apple
 * { identityToken, authorizationCode?, fullName?, timezone? }
 * → { accessToken, accessTokenExpiresAt, refreshToken, refreshTokenExpiresAt,
 *     userId, isNewUser, name, needsName }
 */
http.route({
  path: "/auth/apple",
  method: "POST",
  handler: httpAction(async (ctx, req) => {
    const body = await readBody(req);
    const identityToken = optionalString(body?.identityToken);
    if (!body || !identityToken) return badRequest();

    let appleSub: string;
    try {
      appleSub = (await verifyAppleIdentityToken(identityToken)).sub;
    } catch (e) {
      const message = (e as Error).message;
      if (message.startsWith("Apple JWKS fetch failed")) {
        console.error(message);
        return json({ code: "apple_unavailable" }, 503);
      }
      console.warn("Apple identity token rejected:", message);
      return invalidToken();
    }

    const code = optionalString(body.authorizationCode);
    const appleRefreshToken = code ? await exchangeAuthorizationCode(code) : null;

    const refreshToken = newRefreshToken();
    const refreshExpiresAt = Date.now() + REFRESH_TOKEN_TTL_MS;
    const user = await ctx.runMutation(internal.sessions.signInWithApple, {
      appleSub,
      name: fullNameString(body.fullName),
      timezone: optionalString(body.timezone)?.slice(0, 64),
      appleRefreshToken: appleRefreshToken ?? undefined,
      refreshTokenHash: await hashToken(refreshToken),
      refreshExpiresAt,
    });
    return json({ ...(await issueTokens(user.userId, refreshToken, refreshExpiresAt)), ...user });
  }),
});

/**
 * POST /auth/refresh { refreshToken } → same token fields as /auth/apple.
 * The old refresh token stops working; using it again signs the session out.
 */
http.route({
  path: "/auth/refresh",
  method: "POST",
  handler: httpAction(async (ctx, req) => {
    const body = await readBody(req);
    const presented = optionalString(body?.refreshToken);
    if (!presented) return badRequest();
    const refreshToken = newRefreshToken();
    const refreshExpiresAt = Date.now() + REFRESH_TOKEN_TTL_MS;
    const result = await ctx.runMutation(internal.sessions.rotateRefreshToken, {
      tokenHash: await hashToken(presented),
      newTokenHash: await hashToken(refreshToken),
      newExpiresAt: refreshExpiresAt,
    });
    if (!result.ok) return invalidToken();
    return json({ ...(await issueTokens(result.userId, refreshToken, refreshExpiresAt)), userId: result.userId });
  }),
});

/** POST /auth/logout { refreshToken } → 204, always. */
http.route({
  path: "/auth/logout",
  method: "POST",
  handler: httpAction(async (ctx, req) => {
    const body = await readBody(req);
    const presented = optionalString(body?.refreshToken);
    if (presented) {
      await ctx.runMutation(internal.sessions.revokeSession, {
        tokenHash: await hashToken(presented),
      });
    }
    return new Response(null, { status: 204 });
  }),
});

/** Public keys Convex uses to verify our access tokens (auth.config.ts). */
http.route({
  path: "/.well-known/jwks.json",
  method: "GET",
  handler: httpAction(async () => {
    return new Response(JSON.stringify(await publicJwks()), {
      status: 200,
      headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=3600" },
    });
  }),
});

export default http;
