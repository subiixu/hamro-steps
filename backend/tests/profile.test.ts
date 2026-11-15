import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "../convex/_generated/api";
import { Id } from "../convex/_generated/dataModel";
import { expectCode, makeUser, newTest, setNow, T, User } from "./helpers";

let t: T;
beforeEach(() => {
  t = newTest();
});
afterEach(() => {
  vi.useRealTimers();
});

function store(type: string, bytes = 10) {
  return t.run((ctx) => ctx.storage.store(new Blob([new Uint8Array(bytes)], { type })));
}
function blobExists(id: Id<"_storage">) {
  return t.run(async (ctx) => (await ctx.db.system.get("_storage", id)) !== null);
}
function userDoc(u: User) {
  return t.run((ctx) => ctx.db.get(u.id));
}

describe("photo avatar", () => {
  test("upload URL needs a signed-in user", async () => {
    const u = await makeUser(t);
    expect(typeof (await u.as.mutation(api.users.generateAvatarUploadUrl, {}))).toBe("string");
    await expectCode(t.mutation(api.users.generateAvatarUploadUrl, {}), "not_authenticated");
  });

  test("setAvatar sets the photo, and replacing it deletes the old blob", async () => {
    const u = await makeUser(t);
    const first = await store("image/jpeg");
    expect(await u.as.mutation(api.users.setAvatar, { storageId: first })).toBeNull();
    expect((await userDoc(u))!.photoId).toBe(first);
    expect((await u.as.query(api.users.me, {})).photoUrl).toEqual(expect.any(String));

    const second = await store("image/png");
    await u.as.mutation(api.users.setAvatar, { storageId: second });
    expect((await userDoc(u))!.photoId).toBe(second);
    expect(await blobExists(first)).toBe(false);
    expect(await blobExists(second)).toBe(true);
  });

  test("rejects a non-image or oversize blob and keeps the current photo", async () => {
    const u = await makeUser(t);
    const good = await store("image/jpeg");
    await u.as.mutation(api.users.setAvatar, { storageId: good });

    const text = await store("text/plain");
    await expectCode(u.as.mutation(api.users.setAvatar, { storageId: text }), "invalid_photo");
    const huge = await store("image/jpeg", 5 * 1024 * 1024 + 1);
    await expectCode(u.as.mutation(api.users.setAvatar, { storageId: huge }), "invalid_photo");

    expect((await userDoc(u))!.photoId).toBe(good);
    expect(await blobExists(good)).toBe(true);
  });

  test("cannot claim another user's photo, so cannot delete it", async () => {
    const a = await makeUser(t, "Asha");
    const b = await makeUser(t, "Bikash");
    const photo = await store("image/jpeg");
    await a.as.mutation(api.users.setAvatar, { storageId: photo });
    const urlBefore = (await a.as.query(api.users.me, {})).photoUrl;

    await expectCode(b.as.mutation(api.users.setAvatar, { storageId: photo }), "invalid_photo");
    expect((await userDoc(b))!.photoId).toBeUndefined();
    await b.as.mutation(api.users.removeAvatar, {});

    expect(await blobExists(photo)).toBe(true);
    expect((await userDoc(a))!.photoId).toBe(photo);
    expect((await a.as.query(api.users.me, {})).photoUrl).toBe(urlBefore);
    expect(urlBefore).toEqual(expect.any(String));
  });

  test("a blob of exactly 5 MB is accepted", async () => {
    const u = await makeUser(t);
    const id = await store("image/heic", 5 * 1024 * 1024);
    await u.as.mutation(api.users.setAvatar, { storageId: id });
    expect((await userDoc(u))!.photoId).toBe(id);
  });

  test("removeAvatar deletes the blob and clears the photo", async () => {
    const u = await makeUser(t);
    const id = await store("image/jpeg");
    await u.as.mutation(api.users.setAvatar, { storageId: id });
    expect(await u.as.mutation(api.users.removeAvatar, {})).toBeNull();
    expect((await userDoc(u))!.photoId).toBeUndefined();
    expect(await blobExists(id)).toBe(false);
    expect((await u.as.query(api.users.me, {})).photoUrl).toBeNull();
    // No photo: a no-op.
    expect(await u.as.mutation(api.users.removeAvatar, {})).toBeNull();
  });

  test("account deletion deletes the photo blob", async () => {
    const u = await makeUser(t);
    const id = await store("image/jpeg");
    await u.as.mutation(api.users.setAvatar, { storageId: id });
    await t.mutation(internal.users.deleteAccountData, { userId: u.id });
    expect(await blobExists(id)).toBe(false);
    expect(await userDoc(u)).toBeNull();
  });
});

describe("orphan blob sweep", () => {
  test("deletes orphans over an hour old; keeps fresh orphans and current photos", async () => {
    setNow("2026-11-15T10:00:00Z");
    const u = await makeUser(t);
    const photo = await store("image/jpeg");
    await u.as.mutation(api.users.setAvatar, { storageId: photo });
    const oldOrphan = await store("text/plain");

    setNow("2026-11-15T10:59:00Z");
    const freshOrphan = await store("image/jpeg");

    setNow("2026-11-15T11:30:00Z");
    expect(await t.mutation(internal.users.sweepOrphanBlobs, {})).toEqual({ deleted: 1 });
    expect(await blobExists(oldOrphan)).toBe(false);
    expect(await blobExists(freshOrphan)).toBe(true);
    expect(await blobExists(photo)).toBe(true);
  });
});

describe("city", () => {
  test("trims, clears on empty, max 40 chars", async () => {
    const u = await makeUser(t);
    await u.as.mutation(api.users.updateProfile, { city: "  Sydney   NSW " });
    expect((await u.as.query(api.users.me, {})).city).toBe("Sydney NSW");

    await u.as.mutation(api.users.updateProfile, { city: "x".repeat(40) });
    expect((await u.as.query(api.users.me, {})).city).toBe("x".repeat(40));
    await expectCode(u.as.mutation(api.users.updateProfile, { city: "x".repeat(41) }), "invalid_city");

    await u.as.mutation(api.users.updateProfile, { city: "   " });
    expect((await u.as.query(api.users.me, {})).city).toBeNull();
    expect((await userDoc(u))!.city).toBeUndefined();
  });

  test("omitting city leaves it alone", async () => {
    const u = await makeUser(t);
    await u.as.mutation(api.users.updateProfile, { city: "Pokhara" });
    await u.as.mutation(api.users.updateProfile, { name: "Sita" });
    expect((await u.as.query(api.users.me, {})).city).toBe("Pokhara");
  });
});

describe("birthday", () => {
  test("accepts a real past date and today; null clears", async () => {
    setNow("2026-11-15T11:00:00Z");
    const u = await makeUser(t);
    await u.as.mutation(api.users.updateProfile, { birthday: "1960-02-29" });
    expect((await u.as.query(api.users.me, {})).birthday).toBe("1960-02-29");
    await u.as.mutation(api.users.updateProfile, { birthday: "1900-01-01" });
    // Already the 16th in Kiritimati (UTC+14), so that's not "future".
    await u.as.mutation(api.users.updateProfile, { birthday: "2026-11-16" });
    await u.as.mutation(api.users.updateProfile, { birthday: null });
    expect((await u.as.query(api.users.me, {})).birthday).toBeNull();
    expect((await userDoc(u))!.birthday).toBeUndefined();
  });

  test("rejects malformed, impossible, pre-1900 and future dates", async () => {
    setNow("2026-11-15T03:00:00Z");
    const u = await makeUser(t);
    for (const bad of ["1990-2-3", "03/02/1990", "", "1990-02-30", "1961-02-29", "1990-13-01", "1899-12-31", "2026-11-16", "2030-01-01"]) {
      await expectCode(u.as.mutation(api.users.updateProfile, { birthday: bad }), "invalid_birthday");
    }
    expect((await u.as.query(api.users.me, {})).birthday).toBeNull();
  });
});

describe("what family members see", () => {
  test("me and familyToday return photo, city, timezone and birthday", async () => {
    const a = await makeUser(t, "Asha");
    const b = await makeUser(t, "Bikash");
    const f = await a.as.mutation(api.families.createFamily, { name: "Family" });
    await b.as.mutation(api.families.joinFamily, { code: f.inviteCode });

    const photo = await store("image/jpeg");
    await a.as.mutation(api.users.setAvatar, { storageId: photo });
    await a.as.mutation(api.users.updateProfile, {
      city: "Sydney",
      birthday: "1980-05-01",
      timezone: "Australia/Sydney",
    });

    const me = await a.as.query(api.users.me, {});
    expect(me).toMatchObject({ city: "Sydney", birthday: "1980-05-01", avatarColor: "#E4572E" });
    expect(me.photoUrl).toEqual(expect.any(String));

    const today = await b.as.query(api.home.familyToday, { familyId: f.familyId });
    const asha = today.members.find((m) => m.userId === a.id)!;
    const bikash = today.members.find((m) => m.userId === b.id)!;
    expect(asha).toMatchObject({
      city: "Sydney",
      timezone: "Australia/Sydney",
      birthday: "1980-05-01",
      avatarColor: "#E4572E",
    });
    expect(asha.photoUrl).toEqual(expect.any(String));
    expect(bikash).toMatchObject({ photoUrl: null, city: null, timezone: null, birthday: null });
  });
});
