import { exportPKCS8, generateKeyPair, jwtVerify, decodeProtectedHeader } from "jose";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { Id } from "../convex/_generated/dataModel";
import { ApnsResponse, resetApnsStateForTests, setApnsTransportForTests } from "../convex/lib/apns";
import { expectCode, makeUser, newTest, T, User } from "./helpers";

const MIN = 60 * 1000;
const TEAM_ID = "TEAM123456";
const KEY_ID = "KEY1234567";
const TOKEN_A = "a1".repeat(32);
const TOKEN_B = "b2".repeat(32);

let t: T;
let publicKey: CryptoKey;
beforeEach(async () => {
  t = newTest();
  vi.useFakeTimers({ toFake: ["Date", "setTimeout", "clearTimeout"] });
  vi.setSystemTime(new Date("2026-11-14T06:00:00Z"));
  resetApnsStateForTests();
  const pair = await generateKeyPair("ES256", { extractable: true });
  publicKey = pair.publicKey;
  // Stored the way the Convex dashboard often holds it: escaped newlines.
  vi.stubEnv("APNS_PRIVATE_KEY", (await exportPKCS8(pair.privateKey)).replace(/\n/g, "\\n"));
  vi.stubEnv("APPLE_TEAM_ID", TEAM_ID);
  vi.stubEnv("APNS_KEY_ID", KEY_ID);
});
afterEach(() => {
  setApnsTransportForTests(null);
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
  vi.useRealTimers();
});

type Call = { host: string; path: string; headers: Record<string, string>; body: string };
/** A stand-in APNs. `respond` picks the answer per device token. */
function fakeApns(respond: (token: string) => ApnsResponse = () => ({ status: 200, body: "" })) {
  const calls: Call[] = [];
  let closed = 0;
  setApnsTransportForTests(() => ({
    async send(host, path, headers, body) {
      calls.push({ host, path, headers, body });
      return respond(path.split("/").pop()!);
    },
    close() {
      closed++;
    },
  }));
  return { calls, closed: () => closed };
}

async function familyOf(...users: User[]) {
  const f = await users[0]!.as.mutation(api.families.createFamily, { name: "Family", dailyGoal: 50_000 });
  for (const u of users.slice(1)) await u.as.mutation(api.families.joinFamily, { code: f.inviteCode });
  return f.familyId as Id<"families">;
}
const register = (u: User, apnsToken: string, environment: "sandbox" | "production" = "production") =>
  u.as.mutation(api.notifications.registerDevice, { apnsToken, environment });
const devices = () => t.run((ctx) => ctx.db.query("devices").collect());

async function sendTo(userIds: Id<"users">[], familyId: Id<"families">) {
  return await t.action(internal.pushNode.send, {
    userIds,
    alert: { title: "Aama started a walk", body: "Want to join? Give them a call." },
    data: { type: "walk_started", familyId },
  });
}

describe("devices", () => {
  test("registerDevice stores a lowercased token and moves it between users", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    await register(a, TOKEN_A.toUpperCase(), "sandbox");
    expect(await devices()).toMatchObject([{ apnsToken: TOKEN_A, userId: a.id, environment: "sandbox" }]);
    // Same phone, now signed in as b.
    await register(b, TOKEN_A, "production");
    expect(await devices()).toMatchObject([{ apnsToken: TOKEN_A, userId: b.id, environment: "production" }]);
    // Re-registering is idempotent.
    await register(b, TOKEN_A);
    expect(await devices()).toHaveLength(1);
  });

  test("rejects tokens that aren't hex", async () => {
    const a = await makeUser(t);
    for (const bad of ["", "xyz", "abc", "a1".repeat(4), "zz".repeat(32)]) {
      await expectCode(register(a, bad), "invalid_device_token");
    }
    expect(await devices()).toHaveLength(0);
  });

  test("unregisterDevice removes only the caller's token", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    await register(a, TOKEN_A);
    await b.as.mutation(api.notifications.unregisterDevice, { apnsToken: TOKEN_A });
    expect(await devices()).toHaveLength(1);
    await a.as.mutation(api.notifications.unregisterDevice, { apnsToken: TOKEN_A.toUpperCase() });
    expect(await devices()).toHaveLength(0);
  });

  test("keeps 10 phones per user, retiring the least recently registered", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    const token = (i: number) => i.toString(16).padStart(2, "0").repeat(32);
    await register(b, token(99));
    for (let i = 0; i < 10; i++) {
      await register(a, token(i));
      vi.advanceTimersByTime(MIN);
    }
    await register(a, token(0)); // re-registering refreshes phone 0
    vi.advanceTimersByTime(MIN);
    await register(a, token(10)); // the 11th phone retires phone 1, now the oldest
    const mine = (await devices()).filter((d) => d.userId === a.id).map((d) => d.apnsToken);
    expect(mine).toHaveLength(10);
    expect(mine).not.toContain(token(1));
    expect(mine).toContain(token(0));
    expect(mine).toContain(token(10));
    expect((await devices()).filter((d) => d.userId === b.id)).toHaveLength(1); // others untouched

    // Delivery reaches every one of them.
    const apns = fakeApns();
    const f = await familyOf(a);
    expect(await sendTo([a.id], f)).toEqual({ sent: 10, failed: 0, removed: 0 });
    expect(apns.calls).toHaveLength(10);
  });

  test("a token moved from another user counts toward the new owner's cap", async () => {
    const a = await makeUser(t);
    const b = await makeUser(t);
    const token = (i: number) => i.toString(16).padStart(2, "0").repeat(32);
    for (let i = 0; i < 10; i++) {
      await register(a, token(i));
      vi.advanceTimersByTime(MIN);
    }
    await register(b, token(50));
    vi.advanceTimersByTime(MIN);
    await register(a, token(50));
    const mine = (await devices()).filter((d) => d.userId === a.id).map((d) => d.apnsToken);
    expect(mine).toHaveLength(10);
    expect(mine).not.toContain(token(0));
    expect(mine).toContain(token(50));
    expect((await devices()).filter((d) => d.userId === b.id)).toHaveLength(0);
  });
});

describe("pushNode.send", () => {
  test("posts the payload to each device's APNs host with the right headers", async () => {
    const apns = fakeApns();
    const a = await makeUser(t);
    const b = await makeUser(t);
    const f = await familyOf(a, b);
    await register(a, TOKEN_A, "production");
    await register(b, TOKEN_B, "sandbox");

    expect(await sendTo([a.id, b.id], f)).toEqual({ sent: 2, failed: 0, removed: 0 });
    const byPath = Object.fromEntries(apns.calls.map((c) => [c.path, c]));
    expect(byPath[`/3/device/${TOKEN_A}`]!.host).toBe("api.push.apple.com");
    expect(byPath[`/3/device/${TOKEN_B}`]!.host).toBe("api.sandbox.push.apple.com");
    for (const c of apns.calls) {
      expect(c.headers).toMatchObject({
        "apns-topic": "com.bixustudio.hamrosteps",
        "apns-push-type": "alert",
      });
      expect(c.headers.authorization).toMatch(/^bearer /);
      expect(JSON.parse(c.body)).toEqual({
        aps: { alert: { title: "Aama started a walk", body: "Want to join? Give them a call." }, sound: "default" },
        type: "walk_started",
        familyId: f,
      });
    }
    expect(apns.closed()).toBe(1);
  });

  test("apns-topic follows APPLE_BUNDLE_ID", async () => {
    vi.stubEnv("APPLE_BUNDLE_ID", "com.example.other");
    const apns = fakeApns();
    const a = await makeUser(t);
    const f = await familyOf(a);
    await register(a, TOKEN_A);
    await sendTo([a.id], f);
    expect(apns.calls[0]!.headers["apns-topic"]).toBe("com.example.other");
  });

  test("the provider token is an ES256 JWT from the team and key, reused for 50 minutes", async () => {
    const apns = fakeApns();
    const a = await makeUser(t);
    const f = await familyOf(a);
    await register(a, TOKEN_A);
    const jwtOf = (i: number) => apns.calls[i]!.headers.authorization!.replace("bearer ", "");

    await sendTo([a.id], f);
    const first = jwtOf(0);
    expect(decodeProtectedHeader(first)).toMatchObject({ alg: "ES256", kid: KEY_ID });
    const { payload } = await jwtVerify(first, publicKey);
    expect(payload).toMatchObject({ iss: TEAM_ID, iat: Math.floor(Date.now() / 1000) });

    vi.setSystemTime(Date.now() + 49 * MIN);
    await sendTo([a.id], f);
    expect(jwtOf(1)).toBe(first);

    vi.setSystemTime(Date.now() + 2 * MIN); // 51 minutes after signing
    await sendTo([a.id], f);
    expect(jwtOf(2)).not.toBe(first);
    expect((await jwtVerify(jwtOf(2), publicKey)).payload.iat).toBe(Math.floor(Date.now() / 1000));
  });

  test("a 403 ExpiredProviderToken drops the cached token", async () => {
    let expire = true;
    const apns = fakeApns(() =>
      expire ? { status: 403, body: JSON.stringify({ reason: "ExpiredProviderToken" }) } : { status: 200, body: "" },
    );
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const a = await makeUser(t);
    const f = await familyOf(a);
    await register(a, TOKEN_A);
    await sendTo([a.id], f);
    expire = false;
    vi.setSystemTime(Date.now() + 1000); // a new iat, so a new token
    await sendTo([a.id], f);
    expect(apns.calls[1]!.headers.authorization).not.toBe(apns.calls[0]!.headers.authorization);
    expect(await devices()).toHaveLength(1);
  });

  test("deletes devices APNs calls dead: 410, 400 BadDeviceToken / Unregistered", async () => {
    const tokens = ["c3", "d4", "e5", "f6"].map((p) => p.repeat(32));
    const [gone, bad, unregistered, tooBig] = tokens as [string, string, string, string];
    vi.spyOn(console, "warn").mockImplementation(() => {});
    fakeApns((token) => {
      if (token === gone) return { status: 410, body: JSON.stringify({ reason: "Unregistered", timestamp: Date.now() + 60_000 }) };
      if (token === bad) return { status: 400, body: JSON.stringify({ reason: "BadDeviceToken" }) };
      if (token === unregistered) return { status: 400, body: JSON.stringify({ reason: "Unregistered" }) };
      if (token === tooBig) return { status: 400, body: JSON.stringify({ reason: "PayloadTooLarge" }) };
      return { status: 200, body: "" };
    });
    const a = await makeUser(t);
    const f = await familyOf(a);
    for (const tok of [...tokens, TOKEN_A]) await register(a, tok);

    expect(await sendTo([a.id], f)).toEqual({ sent: 1, failed: 4, removed: 3 });
    expect((await devices()).map((d) => d.apnsToken).sort()).toEqual([TOKEN_A, tooBig].sort());
  });

  test("a 410 doesn't delete a token registered again after APNs dropped it", async () => {
    const a = await makeUser(t);
    const f = await familyOf(a);
    const droppedAt = Date.now() - 60_000;
    fakeApns(() => ({ status: 410, body: JSON.stringify({ reason: "Unregistered", timestamp: droppedAt }) }));
    await register(a, TOKEN_A); // updatedAt = now, after droppedAt
    expect(await sendTo([a.id], f)).toEqual({ sent: 0, failed: 1, removed: 1 });
    expect(await devices()).toHaveLength(1);
  });

  test("a network error counts as failed and keeps the device", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    setApnsTransportForTests(() => ({
      async send() {
        throw new Error("ECONNRESET");
      },
      close() {},
    }));
    const a = await makeUser(t);
    const f = await familyOf(a);
    await register(a, TOKEN_A);
    expect(await sendTo([a.id], f)).toEqual({ sent: 0, failed: 1, removed: 0 });
    expect(await devices()).toHaveLength(1);
  });

  test("skips, logging once, when any APNs env is missing", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const apns = fakeApns();
    const a = await makeUser(t);
    const f = await familyOf(a);
    await register(a, TOKEN_A);
    for (const missing of ["APPLE_TEAM_ID", "APNS_KEY_ID", "APNS_PRIVATE_KEY"]) {
      const value = process.env[missing]!;
      vi.stubEnv(missing, "");
      expect(await sendTo([a.id], f)).toEqual({ skipped: "no_env" });
      vi.stubEnv(missing, value);
    }
    expect(apns.calls).toHaveLength(0);
    expect(log.mock.calls.filter((c) => String(c[0]).includes("APNs env not set"))).toHaveLength(1);
  });

  test("never falls back to the Sign in with Apple key", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    const apns = fakeApns();
    const a = await makeUser(t);
    const f = await familyOf(a);
    await register(a, TOKEN_A);
    const siwa = await generateKeyPair("ES256", { extractable: true });
    vi.stubEnv("APPLE_KEY_ID", "SIWAKEY123");
    vi.stubEnv("APPLE_PRIVATE_KEY", await exportPKCS8(siwa.privateKey));
    vi.stubEnv("APNS_KEY_ID", "");
    expect(await sendTo([a.id], f)).toEqual({ skipped: "no_env" });
    vi.stubEnv("APNS_KEY_ID", KEY_ID);
    vi.stubEnv("APNS_PRIVATE_KEY", "");
    expect(await sendTo([a.id], f)).toEqual({ skipped: "no_env" });
    expect(apns.calls).toHaveLength(0);
  });

  test("skips on a malformed private key, and when nobody has a device", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const apns = fakeApns();
    const a = await makeUser(t);
    const f = await familyOf(a);
    expect(await sendTo([a.id], f)).toEqual({ skipped: "no_devices" });
    await register(a, TOKEN_A);
    vi.stubEnv("APNS_PRIVATE_KEY", "not a key");
    expect(await sendTo([a.id], f)).toEqual({ skipped: "bad_key" });
    expect(apns.calls).toHaveLength(0);
  });
});

describe("end to end", () => {
  test("a walk start reaches the other member's phone through the scheduler", async () => {
    const apns = fakeApns();
    const a = await makeUser(t, "Aama");
    const b = await makeUser(t);
    const f = await familyOf(a, b);
    await register(a, TOKEN_A);
    await register(b, TOKEN_B);
    await a.as.mutation(api.walks.startWalk, {});
    expect(apns.calls).toHaveLength(0); // never inline
    await t.finishAllScheduledFunctions(() => vi.advanceTimersByTime(1));
    expect(apns.calls.map((c) => c.path)).toEqual([`/3/device/${TOKEN_B}`]);
    const body = JSON.parse(apns.calls[0]!.body);
    expect(body).toMatchObject({ type: "walk_started", familyId: f, aps: { alert: { title: "Aama started a walk" } } });
    expect(typeof body.eventId).toBe("string");
  });
});
