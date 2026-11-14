import { convexTest } from "convex-test";
import { exportJWK, exportPKCS8, generateKeyPair, SignJWT } from "jose";
import { vi } from "vitest";
import schema from "../convex/schema";
import { Id } from "../convex/_generated/dataModel";
import {
  APPLE_ISSUER,
  APPLE_KEYS_URL,
  APPLE_REVOKE_URL,
  APPLE_TOKEN_URL,
} from "../convex/lib/apple";

export const modules = import.meta.glob("../convex/**/*.*s");
export const SITE_URL = "https://hamro-test.convex.site";
export const BUNDLE_ID = "com.bixustudio.hamrosteps";

export function newTest() {
  return convexTest(schema, modules);
}
export type T = ReturnType<typeof newTest>;

/** A throwaway signing key for our own JWTs, set as env per test file. */
export async function setServerEnv() {
  const { privateKey } = await generateKeyPair("RS256", { extractable: true });
  vi.stubEnv("JWT_PRIVATE_KEY", await exportPKCS8(privateKey));
  vi.stubEnv("CONVEX_SITE_URL", SITE_URL);
}

/** Pins Date to an instant (UTC ISO string). */
export function setNow(iso: string) {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(iso));
}

let userCounter = 0;
/** Inserts a user directly and returns a client signed in as them. */
export async function makeUser(t: T, name: string | null = "Member") {
  const id = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      appleSub: `sub-${++userCounter}-${Math.random()}`,
      ...(name ? { name } : {}),
      avatarColor: "#E4572E",
      createdAt: Date.now(),
    }),
  );
  return { id, as: t.withIdentity({ subject: id }) };
}

export type User = Awaited<ReturnType<typeof makeUser>>;

/** Expects a ConvexError with `code`. */
export async function expectCode(p: Promise<unknown>, code: string) {
  try {
    await p;
  } catch (e) {
    const data = (e as { data?: { code?: string } }).data;
    if (data?.code === code) return;
    throw new Error(`expected ${code}, got ${data?.code ?? (e as Error).message}`);
  }
  throw new Error(`expected ${code}, but it succeeded`);
}

/**
 * A fake Apple: its own RS256 key published as a JWKS, plus a `fetch` stub
 * answering the keys, token and revoke endpoints. Records every call.
 */
export async function fakeApple() {
  const { privateKey, publicKey } = await generateKeyPair("RS256", { extractable: true });
  // A new key id each time, like Apple rotating keys; the cached JWKS is refetched.
  const kid = `apple-test-${Math.random().toString(36).slice(2)}`;
  const jwk = { ...(await exportJWK(publicKey)), kid, alg: "RS256", use: "sig" };
  const calls: { url: string; body: string }[] = [];
  const fetchStub = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    calls.push({ url, body: typeof init?.body === "string" ? init.body : "" });
    if (url === APPLE_KEYS_URL) return Response.json({ keys: [jwk] });
    if (url === APPLE_TOKEN_URL) return Response.json({ refresh_token: "apple-refresh-123" });
    if (url === APPLE_REVOKE_URL) return new Response(null, { status: 200 });
    return new Response("unexpected fetch in test", { status: 500 });
  });
  vi.stubGlobal("fetch", fetchStub);

  async function identityToken(
    sub: string,
    opts: { aud?: string; iss?: string; expiresIn?: number; key?: CryptoKey } = {},
  ) {
    const now = Math.floor(Date.now() / 1000);
    return await new SignJWT({ email: `${sub}@privaterelay.appleid.com` })
      .setProtectedHeader({ alg: "RS256", kid })
      .setIssuer(opts.iss ?? APPLE_ISSUER)
      .setAudience(opts.aud ?? BUNDLE_ID)
      .setSubject(sub)
      .setIssuedAt(now)
      .setExpirationTime(now + (opts.expiresIn ?? 600))
      .sign(opts.key ?? privateKey);
  }

  return { identityToken, calls, fetchStub };
}

export async function post(t: T, path: string, body: unknown) {
  const res = await t.fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

/** Every row in every table that references `userId`, for deletion checks. */
export async function rowsFor(t: T, userId: Id<"users">) {
  return await t.run(async (ctx) => {
    const found: string[] = [];
    if (await ctx.db.get(userId)) found.push("users");
    for (const table of ["memberships", "dailySteps", "sessions", "refreshTokens", "appleTokens", "dayContributions"] as const) {
      const rows = await ctx.db.query(table).collect();
      if (rows.some((r) => r.userId === userId)) found.push(table);
    }
    const families = await ctx.db.query("families").collect();
    if (families.some((f) => f.organiserId === userId)) found.push("families.organiserId");
    return found;
  });
}
