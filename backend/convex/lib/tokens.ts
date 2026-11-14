import { calculateJwkThumbprint, exportJWK, importPKCS8, JWK, SignJWT } from "jose";
import { ACCESS_TOKEN_TTL_MS, JWT_AUDIENCE } from "./constants";

/**
 * Our access JWTs: RS256, signed with env JWT_PRIVATE_KEY (PKCS8 PEM),
 * verified by Convex through the JWKS served at /.well-known/jwks.json.
 */

type Keys = { pem: string; privateKey: CryptoKey; publicJwk: JWK & { kid: string } };
let cached: Keys | null = null;

async function keys(): Promise<Keys> {
  const raw = process.env.JWT_PRIVATE_KEY;
  if (!raw) throw new Error("JWT_PRIVATE_KEY is not set");
  if (cached && cached.pem === raw) return cached;
  // Dashboard env values often carry literal "\n"; accept both forms.
  const pem = raw.includes("\\n") ? raw.replace(/\\n/g, "\n") : raw;
  const privateKey = (await importPKCS8(pem, "RS256", { extractable: true })) as CryptoKey;
  const { kty, n, e } = await exportJWK(privateKey);
  const base = { kty: kty!, n: n!, e: e! };
  const kid = await calculateJwkThumbprint(base);
  cached = { pem: raw, privateKey, publicJwk: { ...base, kid, alg: "RS256", use: "sig" } };
  return cached;
}

export function issuer(): string {
  const url = process.env.CONVEX_SITE_URL;
  if (!url) throw new Error("CONVEX_SITE_URL is not set");
  return url;
}

export async function signAccessToken(userId: string, now: number) {
  const { privateKey, publicJwk } = await keys();
  const expiresAt = now + ACCESS_TOKEN_TTL_MS;
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "RS256", kid: publicJwk.kid, typ: "JWT" })
    .setIssuer(issuer())
    .setAudience(JWT_AUDIENCE)
    .setSubject(userId)
    .setIssuedAt(Math.floor(now / 1000))
    .setExpirationTime(Math.floor(expiresAt / 1000))
    .sign(privateKey);
  return { token, expiresAt };
}

export async function publicJwks(): Promise<{ keys: JWK[] }> {
  return { keys: [(await keys()).publicJwk] };
}

function base64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** A fresh opaque refresh token (256 random bits). */
export function newRefreshToken(): string {
  return base64url(crypto.getRandomValues(new Uint8Array(32)));
}

/** SHA-256 hex; only hashes are stored. */
export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
