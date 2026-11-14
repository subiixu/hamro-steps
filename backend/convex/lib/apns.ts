import { importPKCS8, SignJWT } from "jose";
import { bundleId } from "./apple";
import { APNS_HOSTS, APNS_JWT_TTL_MS } from "./constants";

/**
 * APNs delivery, independent of the network: `pushNode.ts` supplies the
 * HTTP/2 transport, and tests stub it with `setApnsTransportForTests`.
 */

export type ApnsResponse = { status: number; body: string };
export interface ApnsTransport {
  send(host: string, path: string, headers: Record<string, string>, body: string): Promise<ApnsResponse>;
  /** Called once after a delivery batch. */
  close(): void;
}

let transportOverride: (() => ApnsTransport) | null = null;
export function setApnsTransportForTests(factory: (() => ApnsTransport) | null) {
  transportOverride = factory;
}
export function apnsTransportOverride() {
  return transportOverride;
}

type ApnsEnv = { teamId: string; keyId: string; privateKey: string };
let warnedMissingEnv = false;
let jwtCache: { jwt: string; signedAt: number; teamId: string; keyId: string } | null = null;

/** Clears the JWT cache and the "env missing" log flag. Tests only. */
export function resetApnsStateForTests() {
  warnedMissingEnv = false;
  jwtCache = null;
}

/**
 * The APNs key env: APPLE_TEAM_ID plus the APNs key's own APNS_KEY_ID and
 * APNS_PRIVATE_KEY. That's a separate .p8 from the Sign in with Apple one
 * (APPLE_KEY_ID / APPLE_PRIVATE_KEY), which is never used here. Null, logged
 * once per instance, when any of the three is missing.
 */
export function apnsEnv(): ApnsEnv | null {
  const teamId = process.env.APPLE_TEAM_ID;
  const keyId = process.env.APNS_KEY_ID;
  const privateKey = process.env.APNS_PRIVATE_KEY;
  if (teamId && keyId && privateKey) return { teamId, keyId, privateKey };
  if (!warnedMissingEnv) {
    warnedMissingEnv = true;
    console.log("APNs env not set (APPLE_TEAM_ID, APNS_KEY_ID, APNS_PRIVATE_KEY): skipping pushes");
  }
  return null;
}

/** The ES256 provider token, reused for 50 minutes. */
export async function providerToken(env: ApnsEnv, now = Date.now()): Promise<string> {
  if (
    jwtCache &&
    jwtCache.teamId === env.teamId &&
    jwtCache.keyId === env.keyId &&
    now - jwtCache.signedAt < APNS_JWT_TTL_MS
  ) {
    return jwtCache.jwt;
  }
  const pem = env.privateKey.includes("\\n") ? env.privateKey.replace(/\\n/g, "\n") : env.privateKey;
  const key = await importPKCS8(pem, "ES256");
  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: env.keyId })
    .setIssuer(env.teamId)
    .setIssuedAt(Math.floor(now / 1000))
    .sign(key);
  jwtCache = { jwt, signedAt: now, teamId: env.teamId, keyId: env.keyId };
  return jwt;
}

export type PushDevice = { apnsToken: string; environment: "sandbox" | "production" };
export type PushPayload = {
  alert: { title: string; body: string };
  data: { type: string; familyId: string; eventId?: string };
};
export type DeliveryResult = {
  sent: number;
  failed: number;
  removed: { apnsToken: string; invalidSince?: number }[];
};

/** Reasons that mean the token is dead for good. */
const DEAD_TOKEN_REASONS = new Set(["BadDeviceToken", "Unregistered"]);

function parseBody(body: string): { reason?: string; timestamp?: number } {
  try {
    return JSON.parse(body) as { reason?: string; timestamp?: number };
  } catch {
    return {};
  }
}

/**
 * Sends one notification to every device. Never throws for a device: a
 * network error counts as failed. Returns the tokens APNs said are dead,
 * which the caller deletes.
 */
export async function deliver(
  env: ApnsEnv,
  devices: PushDevice[],
  payload: PushPayload,
  transport: ApnsTransport,
): Promise<DeliveryResult> {
  const jwt = await providerToken(env);
  const body = JSON.stringify({
    aps: { alert: payload.alert, sound: "default" },
    ...payload.data,
  });
  const headers = {
    authorization: `bearer ${jwt}`,
    "apns-topic": bundleId(),
    "apns-push-type": "alert",
    "apns-priority": "10",
  };
  const result: DeliveryResult = { sent: 0, failed: 0, removed: [] };
  await Promise.all(
    devices.map(async (d) => {
      let res: ApnsResponse;
      try {
        res = await transport.send(APNS_HOSTS[d.environment], `/3/device/${d.apnsToken}`, headers, body);
      } catch (e) {
        result.failed++;
        console.warn(`APNs send failed: ${(e as Error).message}`);
        return;
      }
      if (res.status === 200) {
        result.sent++;
        return;
      }
      result.failed++;
      const { reason, timestamp } = parseBody(res.body);
      if (res.status === 410 || (res.status === 400 && reason && DEAD_TOKEN_REASONS.has(reason))) {
        result.removed.push({ apnsToken: d.apnsToken, ...(timestamp ? { invalidSince: timestamp } : {}) });
      } else if (res.status === 403 && (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken")) {
        jwtCache = null;
        console.warn(`APNs rejected the provider token: ${reason}`);
      } else {
        console.warn(`APNs send failed: ${res.status} ${reason ?? ""}`);
      }
    }),
  );
  return result;
}
