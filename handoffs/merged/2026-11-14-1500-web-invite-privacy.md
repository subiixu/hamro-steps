# Static web pages: family invite page and privacy policy
status: done
agent: claude sonnet-5-5
brief: handoffs/briefs/2026-11-14-1440-web-invite-privacy.md
## What the user asked
(T-4) Two static pages in `web/` (plain HTML + one CSS file, no build): a family invite page and a privacy policy.
## What changed
- `/invite/?code=K7M2QX` shows the code large and spaced, a Copy button (clipboard, with a fallback), and 3 plain steps. `TESTFLIGHT_URL` is one constant at the top of the page script (still the `XXXX` placeholder). A missing or malformed code (not 6 letters/digits) shows a friendly "couldn't find a code" message.
- `/privacy/` is a plain-English policy built from the PRD's privacy section, effective 14 November 2026, with a clear "draft for the founders to review" notice. Contact is `privacy@example.com` (placeholder, appears once in the file).
- Warm palette (`#E2672F` accent, off-white background), system fonts, 20px base text, light and dark mode. No tracking, no external scripts. The copy icon is the Hugeicons one already in the iOS assets, inlined with `currentColor`.
## Files
- web/style.css — created
- web/invite/index.html — created
- web/privacy/index.html — created
- handoffs/screens/2026-11-14-web-invite-iphone.png — created
- handoffs/screens/2026-11-14-web-invite-desktop.png — created
- handoffs/screens/2026-11-14-web-invite-invalid-iphone.png — created
- handoffs/screens/2026-11-14-web-privacy-iphone.png — created
- handoffs/screens/2026-11-14-web-privacy-desktop.png — created
## Checks run
`ultron check` not run (static pages, not covered, per the brief).
- `npx html-validate` on both pages: clean after fixing the one doctype-case error.
- Screenshots taken with headless Chrome from `file://`, with the iPhone width (390px) in an iframe. **Not checked in Safari**, and dark mode wasn't screenshotted. The dark-mode palette was only written, not viewed. The desktop and the privacy iPhone shots weren't viewed after capture.
## Libraries used
Hugeicons — copy icon on the invite page (inline SVG, stroke-rounded, currentColor)
## Notes for Jarvis
- Before launch: replace `XXXX` in `TESTFLIGHT_URL` and `privacy@example.com`.
- The invite page's code check assumes 6 characters, A–Z and 0–9. Confirm that matches the backend generator.
- Suggested commit: "Add static invite page and draft privacy policy"
