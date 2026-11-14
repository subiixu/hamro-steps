"use node";

import { v } from "convex/values";
import { internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { ApnsResponse, ApnsTransport, apnsEnv, apnsTransportOverride, deliver } from "./lib/apns";

/** The real transport: one HTTP/2 connection per APNs host per batch. */
function http2Transport(): ApnsTransport {
  const sessions = new Map<string, import("node:http2").ClientHttp2Session>();
  return {
    async send(host, path, headers, body) {
      const http2 = await import("node:http2");
      let session = sessions.get(host);
      if (!session || session.closed || session.destroyed) {
        session = http2.connect(`https://${host}`);
        session.on("error", (e) => console.warn(`APNs connection error: ${e.message}`));
        sessions.set(host, session);
      }
      const s = session;
      return await new Promise<ApnsResponse>((resolve, reject) => {
        const req = s.request({
          ":method": "POST",
          ":path": path,
          "content-type": "application/json",
          ...headers,
        });
        let status = 0;
        let data = "";
        req.setEncoding("utf8");
        req.on("response", (h) => {
          status = Number(h[":status"]);
        });
        req.on("data", (chunk) => {
          data += chunk;
        });
        req.on("end", () => resolve({ status, body: data }));
        req.on("error", reject);
        req.setTimeout(10_000, () => {
          req.close(http2.constants.NGHTTP2_CANCEL);
          reject(new Error("APNs request timed out"));
        });
        req.end(body);
      });
    },
    close() {
      for (const s of sessions.values()) s.close();
      sessions.clear();
    },
  };
}

type SendResult =
  | { skipped: "no_env" | "no_devices" | "bad_key" }
  | { sent: number; failed: number; removed: number };

/**
 * Delivers one push to every device of `userIds` (contract F15). Scheduled by
 * mutations with `runAfter(0, …)`; never called inline. Dead tokens (410, or
 * 400 BadDeviceToken / Unregistered) are deleted.
 */
export const send = internalAction({
  args: {
    userIds: v.array(v.id("users")),
    alert: v.object({ title: v.string(), body: v.string() }),
    data: v.object({
      type: v.string(),
      familyId: v.id("families"),
      eventId: v.optional(v.id("feedEvents")),
    }),
  },
  handler: async (ctx, args): Promise<SendResult> => {
    const env = apnsEnv();
    if (!env) return { skipped: "no_env" };
    const devices = await ctx.runQuery(internal.push.devicesFor, { userIds: args.userIds });
    if (devices.length === 0) return { skipped: "no_devices" };
    const transport = (apnsTransportOverride() ?? http2Transport)();
    let result;
    try {
      result = await deliver(env, devices, { alert: args.alert, data: args.data }, transport);
    } catch (e) {
      // Only signing can throw here: a malformed APNS_PRIVATE_KEY.
      console.warn(`APNs push skipped: ${(e as Error).message}`);
      return { skipped: "bad_key" };
    } finally {
      transport.close();
    }
    for (const r of result.removed) {
      await ctx.runMutation(internal.push.removeDevice, r);
    }
    return { sent: result.sent, failed: result.failed, removed: result.removed.length };
  },
});
