# iOS: simulator screenshots of every v1 screen + visual issues list
status: done
agent: claude sonnet
brief: handoffs/briefs/2026-11-14-1530-ios-screenshots.md
## What the user asked
Screenshots of each v1 iOS screen (debug launch args, `-mockSteps`), plus a short list of visual problems. No code changes.
## What changed
Nothing in code. Ten screens captured on iPhone 17 Pro (light, default text size), plus Home in dark mode and at accessibility-extra-large text. Simulator appearance and text size were reset to light / medium afterwards.

## Visual issues seen
Most serious first.
1. **Settings sheet, invite card seam** (`ios-settings.png`, y≈1620): the Invite code card has rounded bottom corners, then "Share invite / Get a new code" sit in a second white block with square top corners and a divider that starts mid-width. The two read as one broken card. Likely a Card plus a List section stacked.
2. **Join, Paste button** (`ios-join.png`): white text and icon on pale peach. It looks disabled and is hard to read. Needs the accent colour for text, as "Copy code" does on the invite screen.
3. **Home at accessibility text size** (`ios-home-ax.png`): family name wraps to "Thapa / Family" and the chevron floats mid-height, detached from the text. The settings button drops to the middle of the two-line title. The ring fills the full card width, so the card is about one screen tall; the "more steps to go, together" line only shows behind the tab bar until scrolled. Consider capping the ring size at large type sizes.
4. **Settings, remove-member icon** (`ios-settings.png`, right of Aama): very faint peach icon, low contrast, and no label.
5. **Me, Delete account** (`ios-me.png`): neutral black label with an orange trash icon, same as ordinary rows. A destructive action usually gets a red or distinct treatment. "Sign out" in accent orange on white is also on the low side for contrast.
6. **Tab bar over lists** (home light, dark, ax): the floating tab bar sits directly over the third member row. It cuts the name ("B…") and blurs the avatar. Fine while scrolling, but check there is enough bottom inset at the end of the list.
7. **Welcome** (`ios-welcome.png`): feature lines wrap early ("the / whole family", "at / a glance") with a wide empty right margin. The text column seems narrower than the screen.
8. **Me, top spacing** (`ios-me.png`): the "Me" title starts about 370px down, with a large empty gap above it. Home's title sits much higher, so the two tabs don't line up.
9. Minor: secondary grey text (subtitles, "On the next screen…", "Not now") is a light grey on cream, close to the contrast limit. Disabled Continue / Next / Join family buttons are grey on grey, which is acceptable for disabled but faint.
10. Dark mode home looks fine. Ring track and avatar B (dim blue) are low-contrast but readable. Not a bug.

Not an app bug: several screenshots show no Dynamic Island. That's a simulator capture quirk.

## Files
- handoffs/screens/2026-11-14-ios-welcome.png — created
- handoffs/screens/2026-11-14-ios-name.png — created
- handoffs/screens/2026-11-14-ios-health.png — created
- handoffs/screens/2026-11-14-ios-create-name.png — created
- handoffs/screens/2026-11-14-ios-create-goal.png — created
- handoffs/screens/2026-11-14-ios-invite.png — created
- handoffs/screens/2026-11-14-ios-join.png — created
- handoffs/screens/2026-11-14-ios-home.png — created
- handoffs/screens/2026-11-14-ios-home-dark.png — created
- handoffs/screens/2026-11-14-ios-home-ax.png — created
- handoffs/screens/2026-11-14-ios-settings.png — created
- handoffs/screens/2026-11-14-ios-me.png — created
- handoffs/2026-11-14-1530-ios-screenshots.md — created

## Checks run
None. The brief says no code changes, so `ultron check` was not run. The app built clean with the brief's `xcodegen generate` + `xcodebuild build` command. Not covered: the `setup` screen and the `-signedOut`, `-newUser` and `-mockStepsLoading` variants, which weren't in the brief's list.

## Libraries used
none touched

## Notes for Jarvis
- `xcodegen generate` regenerated `ios/HamroSteps.xcodeproj`. It is a generated file, so check whether it is gitignored before committing.
- Build output went to `/tmp/hamro-dd`, outside the repo.
- Suggested commit message: "Add iOS v1 screen screenshots and visual issues list"
