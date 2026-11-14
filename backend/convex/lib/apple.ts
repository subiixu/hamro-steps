import { createLocalJWKSet, importPKCS8, JSONWebKeySet, jwtVerify, SignJWT } from "jose";
import { DEFAULT_BUNDLE_ID } from "./constants";

/**
 * Everything that talks to Apple. All network calls go through `fetch`, so
 * tests stub `fetch` to stand in for Apple.
 */

export const APPLE_ISSUER = "https://appleid.apple.com";
export const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";

export function bundleId(): string {
  return process.env.APPLE_BUNDLE_ID || DEFAULT_BUNDLE_ID;
}

let jwksCache: { fetchedAt: number; jwks: JSONWebKeySet } | null = null;
const JWKS_TTL_MS = 60 * 60 * 1000;

async function appleJwks(forceRefresh: boolean): Promise<JSONWebKeySet> {
  if (!forceRefresh && jwksCache && Date.now() - jwksCache.fetchedAt < JWKS_TTL_MS) {
    return jwksCache.jwks;
  }
  const res = await fetch(APPLE_KEYS_URL);
  if (!res.ok) throw new Error(`Apple JWKS fetch failed: ${res.status}`);
  const jwks = (await res.json()) as JSONWebKeySet;
  jwksCache = { fetchedAt: Date.now(), jwks };
  return jwks;
}

/**
 * Verifies an Apple identity token (signature, iss, aud = our bundle id,
 * expiry). Throws on anything wrong. Refetches Apple's keys once when the
 * token's key id isn't in the cached set (Apple rotates keys).
 */
export async function verifyAppleIdentityToken(identityToken: string): Promise<{ sub: string }> {
  const verify = async (jwks: JSONWebKeySet) =>
    jwtVerify(identityToken, createLocalJWKSet(jwks), {
      issuer: APPLE_ISSUER,
      audience: bundleId(),
      algorithms: ["RS256"],
    });
  let result;
  try {
    result = await verify(await appleJwks(false));
  } catch (e) {
    if ((e as { code?: string }).code !== "ERR_JWKS_NO_MATCHING_KEY") throw e;
    result = await verify(await appleJwks(true));
  }
  const sub = result.payload.sub;
  if (!sub) throw new Error("Apple token has no sub");
  return { sub };
}

/** Whether the env needed to call Apple's token and revoke endpoints is set. */
export function hasAppleClientEnv(): boolean {
  return !!(process.env.APPLE_TEAM_ID && process.env.APPLE_KEY_ID && process.env.APPLE_PRIVATE_KEY);
}

/** The ES256 client secret Apple wants, or null when the env isn't set. */
async function clientSecret(): Promise<string | null> {
  const teamId = process.env.APPLE_TEAM_ID;
  const keyId = process.env.APPLE_KEY_ID;
  const raw = process.env.APPLE_PRIVATE_KEY;
  if (!teamId || !keyId || !raw) return null;
  const pem = raw.includes("\\n") ? raw.replace(/\\n/g, "\n") : raw;
  const key = await importPKCS8(pem, "ES256");
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setSubject(bundleId())
    .setAudience(APPLE_ISSUER)
    .setIssuedAt(now)
    .setExpirationTime(now + 300)
    .sign(key);
}

/**
 * Trades the one-time authorizationCode from sign-in for Apple's refresh
 * token, which is what /auth/revoke needs at account deletion. Returns null
 * (and logs) when the Apple env isn't set or Apple refuses.
 */
export async function exchangeAuthorizationCode(code: string): Promise<string | null> {
  const secret = await clientSecret();
  if (!secret) {
    console.log("Apple env not set: skipping authorizationCode exchange");
    return null;
  }
  const res = await fetch(APPLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: bundleId(),
      client_secret: secret,
      code,
      grant_type: "authorization_code",
    }).toString(),
  });
  if (!res.ok) {
    console.warn(`Apple code exchange failed: ${res.status}`);
    return null;
  }
  const body = (await res.json()) as { refresh_token?: string };
  return body.refresh_token ?? null;
}

/**
 * Revokes the user's Apple sign-in. Returns what happened, for logs and
 * tests. Never throws: a network error or an Apple error response is
 * "failed", which the caller retries (see `users.retryAppleRevoke`).
 */
export async function revokeAppleToken(
  refreshToken: string | null,
): Promise<"revoked" | "skipped" | "failed"> {
  if (!refreshToken) {
    console.log("No Apple refresh token stored: skipping Apple revoke");
    return "skipped";
  }
  let secret: string | null;
  try {
    secret = await clientSecret();
  } catch (e) {
    console.warn(`Apple revoke failed: bad APPLE_PRIVATE_KEY: ${(e as Error).message}`);
    return "failed";
  }
  if (!secret) {
    console.log("Apple env not set: skipping Apple revoke");
    return "skipped";
  }
  let res: Response;
  try {
    res = await fetch(APPLE_REVOKE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: bundleId(),
        client_secret: secret,
        token: refreshToken,
        token_type_hint: "refresh_token",
      }).toString(),
    });
  } catch (e) {
    console.warn(`Apple revoke failed: ${(e as Error).message}`);
    return "failed";
  }
  if (!res.ok) {
    console.warn(`Apple revoke failed: ${res.status}`);
    return "failed";
  }
  return "revoked";
}
