import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { createLocalJWKSet, generateKeyPair, exportPKCS8, jwtVerify } from "jose";
import { api, internal } from "../convex/_generated/api";
import { Id } from "../convex/_generated/dataModel";
import { APPLE_REVOKE_RETRY_DELAYS_MS } from "../convex/lib/constants";
import crons from "../convex/crons";
import { APPLE_REVOKE_RECOVERY_GRACE_MS, appleRevokeDelay } from "../convex/users";
import { expectCode, fakeApple, newTest, post, rowsFor, setServerEnv, SITE_URL, T } from "./helpers";

let t: T;
let apple: Awaited<ReturnType<typeof fakeApple>>;

beforeEach(async () => {
  await setServerEnv();
  apple = await fakeApple();
  t = newTest();
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

async function signIn(sub: string, extra: Record<string, unknown> = {}) {
  return await post(t, "/auth/apple", { identityToken: await apple.identityToken(sub), ...extra });
}

describe("POST /auth/apple", () => {
  test("verifies Apple's token, creates the user and issues our tokens", async () => {
    const res = await signIn("apple-1", {
      fullName: { givenName: "Sita", familyName: "Sharma" },
      timezone: "Australia/Sydney",
    });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ isNewUser: true, name: "Sita Sharma", needsName: false });
    expect(typeof res.body.refreshToken).toBe("string");
    expect(res.body.accessTokenExpiresAt - Date.now()).toBeGreaterThan(59 * 60 * 1000);

    // The access token verifies against the JWKS we serve, as Convex would.
    const jwksRes = await t.fetch("/.well-known/jwks.json");
    const jwks = await jwksRes.json();
    const { payload } = await jwtVerify(res.body.accessToken, createLocalJWKSet(jwks), {
      issuer: SITE_URL,
      audience: "hamro-steps",
      algorithms: ["RS256"],
    });
    expect(payload.sub).toBe(res.body.userId);
    expect(apple.calls.some((c) => c.url === "https://appleid.apple.com/auth/keys")).toBe(true);

    const me = await t.withIdentity({ subject: res.body.userId }).query(api.users.me, {});
    expect(me).toMatchObject({ name: "Sita Sharma", timezone: "Australia/Sydney", needsName: false });
    expect(me.avatarColor).toMatch(/^#[0-9A-F]{6}$/);
  });

  test("signing in again finds the same user and keeps the name", async () => {
    const first = await signIn("apple-2", { fullName: "Hari Thapa" });
    const second = await signIn("apple-2");
    expect(second.status).toBe(200);
    expect(second.body).toMatchObject({ userId: first.body.userId, isNewUser: false, name: "Hari Thapa" });
  });

  test("without a name from Apple the user is asked to type one", async () => {
    const res = await signIn("apple-3");
    expect(res.body).toMatchObject({ name: null, needsName: true });
    const as = t.withIdentity({ subject: res.body.userId });
    await expectCode(as.mutation(api.users.updateProfile, { name: "   " }), "invalid_name");
    await as.mutation(api.users.updateProfile, { name: "  Aama  " });
    expect(await as.query(api.users.me, {})).toMatchObject({ name: "Aama", needsName: false });
  });

  test("rejects bad Apple tokens", async () => {
    const wrongAud = await apple.identityToken("x", { aud: "com.someone.else" });
    const wrongIss = await apple.identityToken("x", { iss: "https://evil.example.com" });
    const expired = await apple.identityToken("x", { expiresIn: -60 });
    const { privateKey: otherKey } = await generateKeyPair("RS256");
    const wrongKey = await apple.identityToken("x", { key: otherKey });
    for (const identityToken of [wrongAud, wrongIss, expired, wrongKey, "not-a-jwt"]) {
      const res = await post(t, "/auth/apple", { identityToken });
      expect(res.status).toBe(401);
      expect(res.body).toEqual({ code: "invalid_token" });
    }
    expect((await post(t, "/auth/apple", {})).status).toBe(400);
    const users = await t.run((ctx) => ctx.db.query("users").collect());
    expect(users).toHaveLength(0);
  });

  test("Apple being unreachable is a 503, not a bad token", async () => {
    const token = await apple.identityToken("apple-down");
    vi.stubGlobal("fetch", vi.fn(async () => new Response("down", { status: 502 })));
    // A new key id forces a JWKS fetch even if an earlier test cached Apple's keys.
    const res = await post(t, "/auth/apple", { identityToken: token });
    expect(res).toEqual({ status: 503, body: { code: "apple_unavailable" } });
  });

  test("honours APPLE_BUNDLE_ID", async () => {
    vi.stubEnv("APPLE_BUNDLE_ID", "com.example.other");
    expect((await signIn("apple-4")).status).toBe(401);
    const ok = await post(t, "/auth/apple", {
      identityToken: await apple.identityToken("apple-4", { aud: "com.example.other" }),
    });
    expect(ok.status).toBe(200);
  });
});

describe("refresh and logout", () => {
  test("rotates refresh tokens and rejects reuse by revoking the session", async () => {
    const signedIn = await signIn("apple-r");
    const r1 = await post(t, "/auth/refresh", { refreshToken: signedIn.body.refreshToken });
    expect(r1.status).toBe(200);
    expect(r1.body.refreshToken).not.toBe(signedIn.body.refreshToken);
    expect(r1.body.userId).toBe(signedIn.body.userId);

    const r2 = await post(t, "/auth/refresh", { refreshToken: r1.body.refreshToken });
    expect(r2.status).toBe(200);

    // Reusing an already-rotated token signs the whole session out…
    const reuse = await post(t, "/auth/refresh", { refreshToken: r1.body.refreshToken });
    expect(reuse.status).toBe(401);
    // …so even the newest token stops working.
    const after = await post(t, "/auth/refresh", { refreshToken: r2.body.refreshToken });
    expect(after.status).toBe(401);

    // A separate sign-in (another device) is unaffected.
    const other = await signIn("apple-r");
    expect((await post(t, "/auth/refresh", { refreshToken: other.body.refreshToken })).status).toBe(200);
  });

  test("rejects unknown and expired refresh tokens", async () => {
    expect((await post(t, "/auth/refresh", { refreshToken: "nope" })).status).toBe(401);
    expect((await post(t, "/auth/refresh", {})).status).toBe(400);
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-11-14T00:00:00Z"));
    const signedIn = await signIn("apple-e");
    vi.setSystemTime(new Date("2027-02-13T00:00:00Z")); // 91 days later
    expect((await post(t, "/auth/refresh", { refreshToken: signedIn.body.refreshToken })).status).toBe(401);
  });

  test("logout ends the session", async () => {
    const signedIn = await signIn("apple-l");
    const res = await t.fetch("/auth/logout", {
      method: "POST",
      body: JSON.stringify({ refreshToken: signedIn.body.refreshToken }),
    });
    expect(res.status).toBe(204);
    expect((await post(t, "/auth/refresh", { refreshToken: signedIn.body.refreshToken })).status).toBe(401);
  });

  test("purgeExpired clears dead tokens and empty sessions", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-11-14T00:00:00Z"));
    await signIn("apple-p");
    vi.setSystemTime(new Date("2027-03-01T00:00:00Z"));
    const { internal } = await import("../convex/_generated/api");
    expect(await t.mutation(internal.sessions.purgeExpired, {})).toEqual({ deleted: 1 });
    expect(await t.run((ctx) => ctx.db.query("sessions").collect())).toHaveLength(0);
  });
});

describe("account deletion", () => {
  async function setAppleEnv() {
    const { privateKey } = await generateKeyPair("ES256", { extractable: true });
    vi.stubEnv("APPLE_TEAM_ID", "TEAM123");
    vi.stubEnv("APPLE_KEY_ID", "KEY123");
    vi.stubEnv("APPLE_PRIVATE_KEY", await exportPKCS8(privateKey));
  }

  test("stores Apple's refresh token at sign-in and revokes it on deletion", async () => {
    await setAppleEnv();
    const res = await signIn("apple-d", { authorizationCode: "code-abc", fullName: "Gita" });
    expect(apple.calls.find((c) => c.url.endsWith("/auth/token"))?.body).toContain("code=code-abc");
    const userId = res.body.userId as Id<"users">;
    const as = t.withIdentity({ subject: userId });
    await as.mutation(api.families.createFamily, { name: "Sharmas" });

    expect(await as.action(api.users.deleteMyAccount, {})).toEqual({ appleRevoke: "revoked" });
    const revoke = apple.calls.find((c) => c.url.endsWith("/auth/revoke"));
    expect(revoke?.body).toContain("token=apple-refresh-123");
    expect(revoke?.body).toContain("token_type_hint=refresh_token");
    expect(await rowsFor(t, userId)).toEqual([]);
    expect((await post(t, "/auth/refresh", { refreshToken: res.body.refreshToken })).status).toBe(401);
  });

  const revokeCalls = () => apple.calls.filter((c) => c.url.endsWith("/auth/revoke"));
  const pending = () => t.run((ctx) => ctx.db.query("appleRevocations").collect());

  /** Signs in with an Apple token stored, then makes Apple's revoke fail `times` times. */
  async function signedInWithFailingRevoke(times: number, failure: () => Promise<Response>) {
    await setAppleEnv();
    const res = await signIn(`apple-f-${Math.random()}`, { authorizationCode: "code-f", fullName: "Hari" });
    const real = apple.fetchStub.getMockImplementation()!;
    let left = times;
    apple.fetchStub.mockImplementation(async (input, init) => {
      if (String(input).endsWith("/auth/revoke") && left-- > 0) {
        apple.calls.push({ url: String(input), body: String(init?.body ?? "") });
        return await failure();
      }
      return await real(input, init);
    });
    return { userId: res.body.userId as Id<"users">, as: t.withIdentity({ subject: res.body.userId }) };
  }

  test("Apple refusing the revoke still deletes everything and queues a retry that succeeds", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    const { userId, as } = await signedInWithFailingRevoke(1, async () => new Response(null, { status: 503 }));

    expect(await as.action(api.users.deleteMyAccount, {})).toEqual({ appleRevoke: "queued" });
    expect(await rowsFor(t, userId)).toEqual([]);
    expect(await pending()).toMatchObject([{ refreshToken: "apple-refresh-123", attempts: 0 }]);
    expect(revokeCalls()).toHaveLength(1);

    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(revokeCalls()).toHaveLength(2);
    expect(revokeCalls()[1]!.body).toContain("token=apple-refresh-123");
    expect(await pending()).toEqual([]);
  });

  test("a network error at deletion doesn't throw; retries back off and succeed", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    const { userId, as } = await signedInWithFailingRevoke(3, async () => {
      throw new TypeError("fetch failed");
    });

    expect(await as.action(api.users.deleteMyAccount, {})).toEqual({ appleRevoke: "queued" });
    expect(await rowsFor(t, userId)).toEqual([]);

    // First retry (after 1 min) fails too and is rescheduled with a longer wait.
    vi.advanceTimersByTime(60_000);
    await t.finishInProgressScheduledFunctions();
    expect(await pending()).toMatchObject([{ attempts: 1 }]);
    vi.advanceTimersByTime(60_000);
    await t.finishInProgressScheduledFunctions();
    expect(revokeCalls()).toHaveLength(2); // not yet: the next wait is 10 min

    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(revokeCalls()).toHaveLength(4);
    expect(await pending()).toEqual([]);
  });

  const fakeAllTimers = () => vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "Date"] });

  /** Lets retry `attempt` come due and run. */
  async function runRetry(attempt: number) {
    vi.advanceTimersByTime(appleRevokeDelay(attempt));
    await t.finishInProgressScheduledFunctions();
  }

  test("never drops the token: backoff caps at daily and retries until Apple confirms", async () => {
    fakeAllTimers();
    const failingRetries = APPLE_REVOKE_RETRY_DELAYS_MS.length + 3;
    const { as } = await signedInWithFailingRevoke(1 + failingRetries, async () => new Response(null, { status: 500 }));
    expect(await as.action(api.users.deleteMyAccount, {})).toEqual({ appleRevoke: "queued" });
    expect(await pending()).toMatchObject([{ attempts: 0, nextAttemptAt: Date.now() + 60_000 }]);

    for (let i = 0; i < failingRetries; i++) {
      await runRetry(i);
      expect(revokeCalls()).toHaveLength(2 + i);
      const [row] = await pending();
      expect(row).toMatchObject({ refreshToken: "apple-refresh-123", attempts: i + 1 });
      expect(row!.nextAttemptAt).toBe(Date.now() + appleRevokeDelay(i + 1));
    }
    // Past the end of the backoff list the wait stays at a day.
    expect(appleRevokeDelay(failingRetries)).toBe(24 * 60 * 60_000);

    await runRetry(failingRetries); // Apple is back
    expect(revokeCalls()).toHaveLength(2 + failingRetries);
    expect(await pending()).toEqual([]);
  });

  test("a missing Apple env is not a revoke: the token stays queued until the env is back", async () => {
    fakeAllTimers();
    await setAppleEnv();
    const res = await signIn("apple-env", { authorizationCode: "code-env", fullName: "Sita" });
    const as = t.withIdentity({ subject: res.body.userId });

    vi.stubEnv("APPLE_TEAM_ID", "");
    expect(await as.action(api.users.deleteMyAccount, {})).toEqual({ appleRevoke: "queued" });
    expect(await rowsFor(t, res.body.userId)).toEqual([]);
    await runRetry(0);
    await runRetry(1);
    expect(revokeCalls()).toHaveLength(0);
    expect(await pending()).toMatchObject([{ refreshToken: "apple-refresh-123", attempts: 2 }]);

    vi.stubEnv("APPLE_TEAM_ID", "TEAM123");
    await runRetry(2);
    expect(revokeCalls()).toHaveLength(1);
    expect(revokeCalls()[0]!.body).toContain("token=apple-refresh-123");
    expect(await pending()).toEqual([]);
  });

  test("the hourly cron recovers a retry that died before recording its result", async () => {
    fakeAllTimers();
    const { as } = await signedInWithFailingRevoke(3, async () => new Response(null, { status: 503 }));
    expect(await as.action(api.users.deleteMyAccount, {})).toEqual({ appleRevoke: "queued" });

    // The first retry crashes after calling Apple and before recordRevokeAttempt
    // (revokeAppleToken's failure log throws), so nothing reschedules it.
    const warn = vi.spyOn(console, "warn").mockImplementationOnce(() => {
      throw new Error("platform failure");
    });
    vi.spyOn(console, "error").mockImplementation(() => {});
    await runRetry(0);
    warn.mockRestore();
    expect(revokeCalls()).toHaveLength(2);
    const [stuck] = await pending();
    expect(stuck).toMatchObject({ attempts: 0 });
    const jobs = await t.run((ctx) => ctx.db.system.query("_scheduled_functions").collect());
    expect(jobs.filter((j) => j.state.kind === "pending")).toEqual([]);

    // Not yet overdue past the grace period: the cron leaves it alone.
    expect(await t.mutation(internal.users.recoverAppleRevocations, {})).toEqual({ rescheduled: 0 });
    vi.advanceTimersByTime(APPLE_REVOKE_RECOVERY_GRACE_MS + 1);
    expect(await t.mutation(internal.users.recoverAppleRevocations, {})).toEqual({ rescheduled: 1 });
    vi.advanceTimersByTime(0);
    await t.finishInProgressScheduledFunctions();
    expect(revokeCalls()).toHaveLength(3); // fails again (2nd failure) and is rescheduled normally
    const [rescheduled] = await pending();
    expect(rescheduled).toMatchObject({ attempts: 1 });
    // The recovery run fires a tick after the cron (runAfter(0)), hence the slack.
    expect(rescheduled!.nextAttemptAt - Date.now() - appleRevokeDelay(1)).toBeGreaterThanOrEqual(0);
    expect(rescheduled!.nextAttemptAt - Date.now() - appleRevokeDelay(1)).toBeLessThan(1000);

    await t.finishAllScheduledFunctions(vi.runAllTimers); // the normal chain carries on and succeeds
    expect(revokeCalls()).toHaveLength(4);
    expect(await pending()).toEqual([]);
  });

  test("a doubled retry run doesn't fork the retry chain", async () => {
    fakeAllTimers();
    const { as } = await signedInWithFailingRevoke(1000, async () => new Response(null, { status: 500 }));
    await as.action(api.users.deleteMyAccount, {});
    const [row] = await pending();
    const pendingJobs = async () =>
      (await t.run((ctx) => ctx.db.system.query("_scheduled_functions").collect())).filter(
        (j) => j.state.kind === "pending",
      );
    expect(await pendingJobs()).toHaveLength(1);

    // The original run and a recovery run both record attempt 0 as failed.
    await t.mutation(internal.users.recordRevokeAttempt, { id: row!._id, attempt: 0, revoked: false });
    await t.mutation(internal.users.recordRevokeAttempt, { id: row!._id, attempt: 0, revoked: false });
    expect(await pending()).toMatchObject([{ attempts: 1 }]);
    expect(await pendingJobs()).toHaveLength(2); // the untouched original + exactly one next retry
    expect(await t.query(internal.users.pendingRevocation, { id: row!._id, attempt: 0 })).toBeNull();

    // A stale run that gets a confirmed revoke still clears the token.
    await t.mutation(internal.users.recordRevokeAttempt, { id: row!._id, attempt: 0, revoked: true });
    expect(await pending()).toEqual([]);
  });

  test("the recovery cron runs hourly", () => {
    const job = (crons as unknown as { crons: Record<string, { schedule: unknown }> }).crons["recover Apple revokes"];
    expect(job?.schedule).toEqual({ type: "hourly", minuteUTC: 30 });
  });

  test("skips the Apple revoke when the Apple env isn't set", async () => {
    const res = await signIn("apple-s", { authorizationCode: "code-xyz" });
    expect(apple.calls.some((c) => c.url.endsWith("/auth/token"))).toBe(false);
    const as = t.withIdentity({ subject: res.body.userId });
    expect(await as.action(api.users.deleteMyAccount, {})).toEqual({ appleRevoke: "skipped" });
    expect(apple.calls.some((c) => c.url.endsWith("/auth/revoke"))).toBe(false);
    expect(await rowsFor(t, res.body.userId)).toEqual([]);
    expect(await pending()).toEqual([]);
  });

  test("needs a signed-in user", async () => {
    await expectCode(t.action(api.users.deleteMyAccount, {}), "not_authenticated");
    await expectCode(t.query(api.users.me, {}), "not_authenticated");
  });
});
