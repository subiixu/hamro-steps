# Profile backend: photo avatar, city, birthday
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-15-1812-profile-backend.md
## What the user asked
T-39 part 1: members can set a profile photo, a typed city and a birthday, and family members see them. The brief fixes the API contract because the iOS worker is building against it.

## What changed
Built to the contract, with no renames.
- Schema `users`: optional `photoId`, `city`, `birthday`, plus a new `by_photoId` index. `avatarColor` is kept and still returned.
- `users:me` returns `photoUrl`, `city`, `birthday`.
- `users:updateProfile` takes `city` (trimmed, max 40, "" clears) and `birthday` (real "YYYY-MM-DD", year ≥ 1900, not in the future; null clears). Leaving either out leaves it unchanged.
  - "Not in the future" is judged against today's date at UTC+14, so a user anywhere can set today's date.
- `users:generateAvatarUploadUrl` returns an upload URL and needs a signed-in user.
- `users:setAvatar`:
  - Sets the photo and deletes the previous blob.
  - Fix from the second review: a blob another user's photo already points at is rejected with `invalid_photo`, and nothing is deleted. Before this fix, a caller could adopt someone else's photo and then delete it by removing or replacing their own photo, or by deleting their account.
  - A blob over 5 MB or not `image/*` (or missing) is rejected with `invalid_photo`. The current photo stays.
  - The rejected blob stays in storage until the sweep removes it: Convex undoes everything a failed call did, including a delete.
- `users:removeAvatar` deletes the blob and clears the photo. It does nothing if there is no photo.
- Ruling 1(a): a new hourly cron, "sweep orphan storage blobs" (minute :50), calls `internal.users.sweepOrphanBlobs`.
  - It deletes `_storage` files more than an hour old that no `users.photoId` points at.
  - It pages through 200 at a time and reschedules itself until it reaches the cutoff.
  - The comment on it says any future use of file storage must be added to its keep-list (`isKept`).
- `home:familyToday` members return `photoUrl`, `city`, `timezone`, `birthday`. Feed actors (`feed.ts`) return `photoUrl`, `city`, `timezone`.
  - `home:familyWeek` has no member objects, and `families.ts` returns no per-member lists (only counts and family views), so neither changed.
- Account deletion (`deleteUserData` in lib/cleanup.ts) deletes the photo blob.
- New error codes: `invalid_photo`, `invalid_city`, `invalid_birthday`.

## Files
- backend/convex/schema.ts — modified
- backend/convex/users.ts — modified
- backend/convex/home.ts — modified
- backend/convex/feed.ts — modified
- backend/convex/crons.ts — modified
- backend/convex/lib/cleanup.ts — modified
- backend/convex/lib/constants.ts — modified
- backend/convex/lib/errors.ts — modified
- backend/convex/lib/profile.ts — created
- backend/tests/profile.test.ts — created
- backend/tests/feed.test.ts — modified (the actor assertion now includes the three new fields)

## Checks run
```
## Checks run
`ultron check`: FAILED · 0 of 2 passed · 4.9 s
- `scripts/check-ios.sh` · exit 65 · 4.9 s
  Testing failed:
  	Extra argument 'avatarColor' in call  (×3, ios FeedActor mock data)
  	Testing cancelled because the build failed.
- `scripts/check-backend.sh` · not run (an earlier check failed)
```
- The iOS failure isn't from this brief: I touched nothing under `ios/`. It's the T-39 iOS worker's in-progress `FeedActor` change, so the iOS check should go green when that worker finishes.
- Because `ultron check` stops at the first failure, I ran `scripts/check-backend.sh` directly: **10 test files, 154 tests passed**, typecheck clean (re-run after the second-review fix).
- New tests in `tests/profile.test.ts` (13) cover:
  - setAvatar replaces the photo and deletes the old blob.
  - Regression for the second review: B can't claim A's photo (`invalid_photo`). After B's attempt and B's removeAvatar, A's blob, photoId and photoUrl are unchanged.
  - setAvatar rejects a non-image and a blob over 5 MB, keeping the current photo; exactly 5 MB is accepted.
  - removeAvatar works, and is a no-op without a photo.
  - Account deletion deletes the blob.
  - The sweep deletes an orphan over 1 h old and keeps a fresh orphan and a current photo.
  - city: trim, clear, the 40/41 boundary, and leaving it out.
  - birthday: a real date, 29 Feb in a leap year, 1900, today at UTC+14 and null are accepted; malformed, impossible dates, 1899 and future dates are rejected.
  - me and familyToday return the new fields, with nulls for a member who set nothing.
- Not checked:
  - The sweep's self-rescheduling when there are more than 200 files (the tests use fake Date timers and don't run scheduled functions).
  - Real Convex storage URLs: convex-test only. Not deployed.

## Libraries used
none touched

## Notes for Jarvis
- The iOS worker needs the error codes `invalid_photo`, `invalid_city` and `invalid_birthday`. A rejected photo returns `invalid_photo`, and the old photo stays.
- Deploy after merge, since the schema adds an index and a cron. All new fields are optional, so no migration is needed.
- Suggested commit: `Backend: profile photo, city and birthday (T-39) — avatar upload/set/remove, hourly orphan blob sweep, profile fields on me/familyToday/feed`

## Checks (run by Ultron)
Failed: scripts/check-ios.sh · 0 of 2 passed · 2026-11-15 18:17 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · exit 65 · 5.2 s
- `scripts/check-backend.sh` · not run (an earlier check failed)

Last 6 lines of `scripts/check-ios.sh`:
```text
/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/HamroSteps-own-target-headers.hmap -Xcc -I/var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/HamroSteps-all-non-framework-target-headers.hmap -Xcc -ivfsoverlay -Xcc /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps-8289d74471ffcde075059555aff1dea0-VFS-iphonesimulator/all-product-headers.yaml -Xcc -iquote -Xcc /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/HamroSteps-project-headers.hmap -Xcc -I/var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Products/Debug-iphonesimulator/include -Xcc -I/var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/DerivedSources-normal/arm64 -Xcc -I/var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/DerivedSources/arm64 -Xcc -I/var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/DerivedSources -Xcc -DDEBUG\=1 -no-auto-bridging-header-chaining -module-name HamroSteps -const-gather-protocols-file /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/HamroSteps_const_extract_protocols.json -disable-clang-spi -clang-target arm64-apple-ios27.1-simulator -target-sdk-version 27.1 -target-sdk-name iphonesimulator27.1 -in-process-plugin-server-path /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/libSwiftInProcPluginServer.dylib -o /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/SessionStore.o -o /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/SignOutMarker.o -o /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/StatusLabel.o -o /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/StatusPicker.o -o /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/StepFormatter.o -debug-module-path /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/HamroSteps.swiftmodule -index-unit-output-path /HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/SessionStore.o -index-unit-output-path /HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/SignOutMarker.o -index-unit-output-path /HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/StatusLabel.o -index-unit-output-path /HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/StatusPicker.o -index-unit-output-path /HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/StepFormatter.o -index-store-path /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Index.noindex/DataStore -index-system-modules
Testing failed:
	Extra argument 'avatarColor' in call
	Testing cancelled because the build failed.

** TEST FAILED **
```

## Checks override
Merged anyway: iOS check red only from the in-progress T-39 iOS worker; backend tests 154/154 pass, run by Jarvis (2026-11-15 18:21)
