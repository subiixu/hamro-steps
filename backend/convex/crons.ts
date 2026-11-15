import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// Nepal midnight (UTC+5:45) is 18:15 UTC every day.
crons.daily("close Nepal day", { hourUTC: 18, minuteUTC: 15 }, internal.days.closeDay, {});

// Expired refresh tokens are dead weight; clear them out once a day.
crons.daily("purge expired refresh tokens", { hourUTC: 19, minuteUTC: 0 }, internal.sessions.purgeExpired, {});

// Queued Apple revokes whose scheduled retry was lost get rescheduled.
crons.hourly("recover Apple revokes", { minuteUTC: 30 }, internal.users.recoverAppleRevocations, {});
crons.daily("purge old feed events", { hourUTC: 19, minuteUTC: 30 }, internal.feed.purgeOld, {});
crons.daily("purge old walks", { hourUTC: 19, minuteUTC: 45 }, internal.walks.purgeOld, {});

// Evening nudge at 19:00 Nepal (UTC+5:45) = 13:15 UTC.
crons.cron("evening nudge", "15 13 * * *", internal.notifications.eveningNudge, {});

// Uploaded files no profile points at (rejected or abandoned photo uploads),
// once over an hour old. See users.sweepOrphanBlobs for the keep-list.
crons.hourly("sweep orphan storage blobs", { minuteUTC: 50 }, internal.users.sweepOrphanBlobs, {});

export default crons;
