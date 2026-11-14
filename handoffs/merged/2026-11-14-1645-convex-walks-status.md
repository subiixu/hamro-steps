# Convex backend 2a: walks and status (contract F9–F12)
status: done
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-1630-convex-walks-status.md
## What the user asked
(T-7, T-8) The Walks and Status sections of `docs/contract-activity.md` in Convex, with convex-test coverage. No pushes or feed events yet: phases 2b and 2c add those.

## What changed
- **Walks.** `walks.startWalk()` returns `{walkId, startedAt, endsAt}`, and every walk lasts 2 h. It errors with `already_walking` while a walk is open, and with `walk_limit_reached` on the 4th start in the same Nepal day. A walk counts toward the day it started, even if it runs past midnight. Each start schedules `internal.walks.autoStop` at `endsAt` with `ctx.scheduler.runAt`. `autoStop` does nothing when the walk was already stopped or was deleted along with its account. `walks.stopWalk()` returns null and does nothing when the user isn't walking.
  - A walk is "open" while `endedAt` is unset **and** `endsAt` is still in the future. If a walk is past `endsAt` but its autoStop hasn't run yet, it already counts as ended: `familyToday` hides it and a new `startWalk` is allowed. `startWalk` closes such a walk (sets `endedAt = endsAt`) before starting the new one.
  - In `startWalk`, one call site is marked `// 2b/2c: feed event + push`.
- **Status.** `status.setStatus({preset?, text?, expiresAt?})` returns `{preset|null, text|null, expiresAt}`. It takes exactly one of `preset` (one of the 7 enum keys) or `text`. Text is trimmed and must be 1–30 UTF-16 units (`.length`). Anything else gives `invalid_status`; an unknown preset key is also `invalid_status`, not a validator error. `expiresAt` defaults to now + 24 h. It must be greater than now and at most now + 7 days, otherwise `invalid_expiry`. Each user has one row, replaced on every set. `status.clearStatus()` returns null and does nothing when no status is set.
- **`familyToday`.** Each member now has `walkingSince: number|null`, `walkEndsAt: number|null` and `status: {preset, text, expiresAt}|null`. Status is null once `expiresAt` has passed. All of these are read through indexes (`walks.by_user_open`, `statuses.by_user`).
- **Cleanup.** Account deletion (`deleteUserData`) deletes the user's walks and status. Leaving or removal changes nothing, because walks and status belong to the user, not the family. I updated the phase-2 comments in `cleanup.ts` to say so.
- I also fixed the stale doc comment on `APPLE_REVOKE_RETRY_DELAYS_MS` that phase 1 flagged.

**API additions for the iOS worker:**
- New error codes: `already_walking`, `walk_limit_reached`, `invalid_status`, `invalid_expiry`.
- `api.walks.startWalk`, `api.walks.stopWalk`, `api.status.setStatus` and `api.status.clearStatus`.

**Schema:**
- `walks`: userId, startedAt, endsAt, endedAt?, nepalDay. Indexes `by_user_open` [userId, endedAt] and `by_user_day` [userId, nepalDay].
- `statuses`: userId, preset?, text?, expiresAt, updatedAt. Index `by_user`.

## Files
- backend/convex/walks.ts — created
- backend/convex/status.ts — created
- backend/convex/lib/activity.ts — created
- backend/convex/schema.ts — modified
- backend/convex/home.ts — modified
- backend/convex/lib/cleanup.ts — modified
- backend/convex/lib/constants.ts — modified
- backend/convex/lib/errors.ts — modified
- backend/convex/_generated/api.d.ts — modified
- backend/tests/walks.test.ts — created
- backend/tests/status.test.ts — created

## Checks run
`ultron check`: FAILED · 0 of 2 passed · 8.6 s
- `scripts/check-ios.sh` · exit 65 · 8.6 s
  ```
  Testing failed:
  	Type 'FamilyMember' does not conform to protocol 'Encodable'
  	Value of type 'FamilyMember' has no member 'walkingSince'
  	Value of type 'FamilyMember' has no member 'walkEndsAt'
  	Value of type 'FamilyMember' has no member 'status'
  	Cannot find 'walkingSince' in scope
  	Cannot find 'walkEndsAt' in scope
  	Cannot find 'status' in scope
  	Type 'Icon' has no member 'cheer'
  	Testing cancelled because the build failed.
  ** TEST FAILED **
  ```
- `scripts/check-backend.sh` · not run (an earlier check failed)

The iOS failure comes from in-progress Swift edits by the iOS workers (`FamilyMember`, `Icon.cheer` in `ios/`). I didn't touch any of that. Because `ultron check` stops at the first failure, I ran the backend check directly:
- `bash scripts/check-backend.sh`, run twice: typecheck clean (`convex/` and `tests/`) and **88/88 tests** passing across 6 files. That is the 61 existing tests plus 27 new ones (15 walks, 12 status/deletion).

What the new tests cover:
- `startWalk` returns a 2 h walk, gives `already_walking` while walking, and needs a sign-in.
- The limit across Nepal midnight: 3 starts and the 4th is refused, still refused at 18:14:59 UTC, allowed again at 18:15:00 UTC.
- A walk that crosses midnight counts toward the day it started.
- A walk past `endsAt` whose autoStop hasn't run doesn't block a new start.
- `stopWalk` ends the walk, and is a no-op both when never walking and when already stopped.
- `autoStop` doesn't fire at 2 h − 1 ms and ends the walk at exactly `endsAt`, using convex-test's scheduler with fake timers. It's idempotent: called twice on a walk the user stopped, it changes nothing. A pending autoStop for a walk deleted with its account is harmless.
- Status validation:
  - All 7 presets accepted, an unknown preset refused.
  - Both fields or neither refused.
  - 30 chars accepted after trimming, 31 refused, blank refused.
  - Emoji counted in UTF-16 units: 15 × 🚶 = 30 accepted, +1 refused, and 28 + 🏔️ = 31 units (29 graphemes) refused.
  - Expiry: now and past refused, now + 7 d + 1 ms refused, now + 1 ms and exactly now + 7 d accepted. The default is now + 24 h.
  - One row per user, and `clearStatus` works.
- `familyToday` shows the walk in both of the walker's families and null for others, and goes null at `endsAt` and after `stopWalk`. It shows preset and text statuses and hides a status at its `expiresAt`.
- Account deletion removes only the deleted user's walks and status. Leaving a family keeps them.

Not checked:
- A real Convex deployment and its real scheduler.
- iOS.

`_generated/api.d.ts` was edited by hand: three module imports (`walks`, `status`, `lib/activity`), in the same form codegen writes. I didn't run `npx convex codegen` against a deployment. The other generated files are type-derived and need no change.

## Libraries used
none touched (backend only)

## Notes for Jarvis
- The iOS `FamilyMember` model needs `walkingSince`, `walkEndsAt` and `status` to decode the new `familyToday` fields. The build errors above show the iOS workers are already on it.
- For phases 2b and 2c, the feed and push call site is the marked comment in `walks.startWalk`. `lib/cleanup.ts` still has the marked spots for feed events, reactions, devices and mutes.
- Suggested commit message: `Convex walks and status: start/stop with 3-per-Nepal-day limit and scheduled 2 h auto-stop, presets or 30-char text with expiry, shown in familyToday, removed on account deletion`

## Checks (run by Ultron)
Failed: scripts/check-ios.sh · 0 of 2 passed · 2026-11-14 14:44 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · exit 65 · 10.8 s
- `scripts/check-backend.sh` · not run (an earlier check failed)

Last 13 lines of `scripts/check-ios.sh`:
```text
ngled-names -file-compilation-dir /Users/subixu/BIXUSTUDIO/DEV/hamro-steps/ios -Xcc -D_LIBCPP_HARDENING_MODE\=_LIBCPP_HARDENING_MODE_DEBUG -Xcc -ivfsstatcache -Xcc /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/SDKStatCaches.noindex/iphonesimulator27.1-24A94232-35d3147121984ba087c28d913653d626.sdkstatcache -Xcc -fmodules-prune-interval\=86400 -Xcc -fmodules-prune-after\=345600 -Xcc -iquote -Xcc /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/HamroSteps-generated-files.hmap -Xcc -I/var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/HamroSteps-own-target-headers.hmap -Xcc -I/var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/HamroSteps-all-non-framework-target-headers.hmap -Xcc -ivfsoverlay -Xcc /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps-8289d74471ffcde075059555aff1dea0-VFS-iphonesimulator/all-product-headers.yaml -Xcc -iquote -Xcc /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/HamroSteps-project-headers.hmap -Xcc -I/var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Products/Debug-iphonesimulator/include -Xcc -I/var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/DerivedSources-normal/arm64 -Xcc -I/var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/DerivedSources/arm64 -Xcc -I/var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/DerivedSources -Xcc -DDEBUG\=1 -no-auto-bridging-header-chaining -module-name HamroSteps -const-gather-protocols-file /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/HamroSteps_const_extract_protocols.json -disable-clang-spi -clang-target arm64-apple-ios27.1-simulator -target-sdk-version 27.1 -target-sdk-name iphonesimulator27.1 -in-process-plugin-server-path /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/libSwiftInProcPluginServer.dylib -o /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/Family.o -o /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/FeedList.o -debug-module-path /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Build/Intermediates.noindex/HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/HamroSteps.swiftmodule -index-unit-output-path /HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/Family.o -index-unit-output-path /HamroSteps.build/Debug-iphonesimulator/HamroSteps.build/Objects-normal/arm64/FeedList.o -index-store-path /var/folders/s9/4nkd8_5j01z87pk4vyxjgsc00000gn/T/hamro-dd-8cbc433b/Index.noindex/DataStore -index-system-modules
Testing failed:
	Type 'FamilyMember' does not conform to protocol 'Encodable'
	Value of type 'FamilyMember' has no member 'walkingSince'
	Value of type 'FamilyMember' has no member 'walkEndsAt'
	Value of type 'FamilyMember' has no member 'status'
	Cannot find 'walkingSince' in scope
	Cannot find 'walkEndsAt' in scope
	Cannot find 'status' in scope
	Type 'Icon' has no member 'cheer'
	Testing cancelled because the build failed.

** TEST FAILED **
```

## Second opinion
Skipped at merge: Jarvis read walks.ts/home.ts/schema diff; 88 backend tests green; combined second opinion planned over backend 2a–2c after 2c (2026-11-14 14:44)

## Checks override
Merged anyway: iOS check red only from iOS placement worker adding FamilyMember fields; backend green (2026-11-14 14:44)
