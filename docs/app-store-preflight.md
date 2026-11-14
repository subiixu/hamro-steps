# App Store preflight: ios/ (2026-11-14)

Audited by reading the code in the main checkout. The Convex client (`Services/Convex`) and `Push/` live on other workers' branches, so those parts are marked "recheck after merge". The `app-store-preflight-skills` skill is not available to workers in this session, so this is a manual pass over the same areas.

Severity: **REJECT** = would reject, **FIX** = should fix, **OK** = fine.

| # | Sev | Where | Finding | Fix |
|---|-----|-------|---------|-----|
| 1 | OK | `Features/Me/MeView.swift:3,198`, `App/SessionStore.swift:92` | Account deletion is in-app (Me tab), confirms, then calls backend delete then Apple revoke path. Backend stores the Apple refresh token to revoke it (`backend/convex/schema.ts` appleTokens). | Recheck after the Convex client merges that `deleteMyAccount` really calls the backend. |
| 2 | OK | `ios/project.yml:64` | `NSHealthShareUsageDescription` is present and says why. HealthKit is read-only (`HealthKitStepSource.swift:19`, `toShare: []`), so no `NSHealthUpdateUsageDescription` is needed. | None. |
| 3 | FIX | `ios/project.yml` (entitlements) | `com.apple.developer.healthkit.access` is an empty array. Fine for steps only, no clinical records. | None, noted so nobody adds clinical access by accident. |
| 4 | OK | whole app | HealthKit data is not used for ads, tracking or sale (no ad or analytics SDK, `NSPrivacyTracking` false). | Keep the review notes and App Privacy answers saying so. |
| 5 | OK | `Features/Onboarding/WelcomeView.swift:47` | Sign in with Apple is the only sign-in, with `.fullName` scope. Entitlement `com.apple.developer.applesignin` is set. | None. |
| 6 | REJECT | `ios/project.yml` entitlements, no `Push/` yet | No `aps-environment` entitlement and no `UIBackgroundModes: remote-notification`. Walk alerts need push. | The push worker adds `aps-environment` (XcodeGen `entitlements.properties`, not the .entitlements file) and background mode. Also enable Push in the App ID. Recheck after the push branch merges. |
| 7 | FIX | `HealthKitStepSource.swift:43` | `enableBackgroundDelivery` needs `com.apple.developer.healthkit.background-delivery`: present. | None. |
| 8 | REJECT | app (no link found by grep) | The privacy policy URL is not shown anywhere in the app. Apple wants it in App Store Connect, and an in-app link is the norm for apps that collect health data. | Add a link to https://subiixu.github.io/hamro-steps/privacy/ on the Me tab or Welcome screen, and enter it in App Store Connect. The page exists in `web/privacy/`. |
| 9 | FIX | `ios/project.yml` | `ITSAppUsesNonExemptEncryption` is not set, so App Store Connect asks on every upload. The app only uses HTTPS (and Apple's CryptoKit/SHA hashing is server-side). | Add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO`. |
| 10 | OK | `AppIcon.appiconset/Contents.json` | 1024 light, dark and tinted are all present and wired. | None. |
| 11 | FIX | `AppIcon-1024-tinted.png` | Has an alpha channel (`sips hasAlpha: yes`). Light and dark have none. Apple rejects a marketing icon with alpha. The tinted variant is usually accepted, but not verified. | Flatten the tinted PNG to no alpha if the upload complains. |
| 12 | FIX | `ios/project.yml:24-25` | Version is 0.1.0 (1). Fine for TestFlight. Build number must increase on every upload. | Bump `CURRENT_PROJECT_VERSION` per upload. |
| 13 | FIX | `Features/Onboarding/WelcomeView.swift:~55` | The debug sample-account button is inside `#if DEBUG`, so it does not ship. | None. Confirm the release build has no mock services wired (`HamroStepsApp.swift:83` area) after the Convex client merges. |
| 14 | OK | `ios/project.yml` | `UIRequiredDeviceCapabilities: healthkit`, iPhone only, portrait only. iPad is not targeted, so no iPad screenshots are needed. | None. |
| 15 | FIX | App Store Connect (not code) | App Privacy answers must match `PrivacyInfo.xcprivacy`: Health & Fitness, User ID, Name, Device ID, all linked, none for tracking, purpose App Functionality. Add the support URL and a review demo account note (Sign in with Apple only, so reviewers use their own Apple ID: say so). | User fills these in. |
| 16 | FIX | `docs/PRD.md:90-100` vs manifest | PRD says "Nothing else" is collected. The manifest also declares Name, User ID and Device ID, because the backend stores them. | Keep PRD and policy wording in step (policy page already approved). |

## Privacy manifest: what it declares and why

File: `ios/HamroSteps/Resources/PrivacyInfo.xcprivacy`

- **Required-reason APIs:** UserDefaults only, reason `CA92.1` (app's own data). Used in `SessionStore.swift:28`, `HomeModel.swift:26`, `StepSync.swift:25`, `HamroStepsApp.swift:83`, `FamilySetupView.swift:150`, `MockAuthService.swift:14`. grep found no file timestamp, boot time or disk space calls in the app code.
- **Collected, all linked to the user, none for tracking, purpose App Functionality:** Fitness (daily step totals), User ID (Apple `sub`), Name (`users.name`, from Sign in with Apple or typed), Device ID (APNs token, once push lands).
- **Not declared:** location, contacts, analytics, crash data (none collected).
- **Recheck after the Convex client and push branches merge:** if they add Keychain use (no manifest entry needed), `FileManager` timestamps, or a third-party SDK, update the manifest. ThinkingOrbsKit is the only package; recheck that it ships its own manifest if Apple's list requires one.
