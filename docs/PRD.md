# Hamro Steps — PRD (v1)

Nov 14, 2026 · @Subaz

## Overview

Hamro Steps is an iOS app where a family of 3 to 8 people walks toward one shared daily step goal, such as 50,000 steps. Steps come straight from Apple Health, so nobody logs anything by hand.

The problem: families spread across cities and countries lose day-to-day contact. Step apps exist, but they are built for individuals or friends, not families. The first market is the Nepali diaspora in Australia and the US, and their families in Nepal.

One line: walk together as a family, wherever you live.

## Goals and non-goals

v1 is family steps only: one shared goal, a live walking alert, status and reactions.

**Goals**

- A family is set up and counting steps in under 5 minutes, with one organiser doing most of the work.
- Every member sees the family's progress toward today's goal at a glance.
- Walking becomes a shared moment, through the "I'm walking" alert, status and reactions.

**Not in v1**

- Habit tracking of any kind, personal or shared.
- Family tree with location, local time and weather.
- Family-vs-family leaderboard.
- In-app video calls; families keep using their own call apps.
- Photo stories, comments, voice notes, widgets.
- Nepali language; v1 is English only.
- Android.
- Pricing and payments.

## Target users

Three kinds of people sit in every family, and the parent in Nepal is the one the design must not lose.

| Persona | Who | What they need |
| --- | --- | --- |
| Organiser | Adult child abroad, 25 to 40, comfortable with apps | Set up the family fast and invite everyone without hand-holding each person |
| Parent | 50 to 70, in Nepal or another city, low tech confidence | Join once, then never touch settings; big text, clear progress, feel included |
| Sibling or cousin | Casual user, motivated by banter | Quick check-ins, reactions, a reason to walk today |

Every member needs an iPhone in v1, since steps come from Apple Health.

## Core flows

Six flows make up v1; the first two decide whether families ever get started.

1. **Create a family.** The organiser signs in, names the family, sets a custom daily goal (50,000 suggested) and gets an invite link to share on WhatsApp or Messenger.
2. **Join a family.** A member taps the link, installs the app, signs in with Apple, allows Health access and lands in the family. Target: under 2 minutes, no typing beyond their name.
3. **Daily check-in.** Steps sync in the background. Opening the app shows the family total against the goal and what each person added.
4. **Going for a walk.** A member taps "I'm walking". Everyone else gets a push alert and can react, or call them on their usual app to walk together.
5. **Set a status.** A member picks a status like "At work" or "On a hike", so family know whether it's a good time to call.
6. **React.** Members tap an emoji on feed events such as "Mum passed 8,000 steps" or "Family hit today's goal".

## Functional requirements

Must-haves cover setup, step syncing, the shared goal and the walking alert; the rest can slip without breaking v1.

| ID | Area | Requirement | Priority |
| --- | --- | --- | --- |
| F1 | Accounts | Sign in with Apple; in-app account deletion | Must |
| F2 | Family | Organiser creates one family of 3 to 8 members, names it and sets a custom daily step goal (50,000 suggested) | Must |
| F3 | Family | Invite by shareable link or 6-character code; organiser can remove members; a person can belong to more than one family, with a family switcher on Home | Must |
| F4 | Steps | Read daily step count from HealthKit (read-only), with background sync and a "last synced" time | Must |
| F5 | Steps | Family total = sum of all members' steps for the day in Nepal time (UTC+5:45); "today" closes at midnight Nepal time for everyone | Must |
| F6 | Home | Progress ring showing family total vs goal and percentage | Must |
| F7 | Home | Contribution list in a fixed family order, not ranked; members with no sync show "not synced yet", not zero | Must |
| F8 | Home | This week: which days the family hit the goal | Should |
| F9 | Walking | "I'm walking" button sends a push to all members and shows a live "walking now" badge | Must |
| F10 | Walking | Walk ends when the member taps stop, or automatically after 2 hours | Must |
| F11 | Walking | Limit of 3 walk alerts per member per day | Should |
| F12 | Status | Presets (At work, At home, Commuting, Working out, On a hike, Resting, Travelling) plus custom text up to 30 characters; clears after 24 hours or a chosen time | Must |
| F13 | Feed | Auto events: member passes 5k and 10k, family reaches 50% and 100% of goal, walk started | Must |
| F14 | Feed | One-tap emoji reactions from a fixed set of 5 | Must |
| F15 | Notifications | Push for walk started, family goal hit, and reactions to your events; each type can be muted | Must |
| F16 | Notifications | Optional evening nudge if the family is under goal, with supportive wording | Should |

## Design principles

The app should feel like a family group chat about walking, not a fitness scoreboard.

- **Relationship first.** Lead with who is walking and how the family is doing, not with charts.
- **Celebrate, never shame.** No ranking inside the family and no red failure states. Someone always at the bottom will quietly quit.
- **The team goal beats the individual.** Every step counts toward one number, so a parent's 4,000 matters as much as a sibling's 15,000.
- **One person sets up, everyone else just joins.** Like Apple's family sharing, the organiser carries the setup.
- **Built for parents.** Large text, few screens, plain words, and nothing to configure after joining.

## Privacy, permissions and tech

v1 shares only daily step totals, walk alerts and status, with no location at all.

- **Permissions:** HealthKit (step count, read only) and push notifications. Nothing else.
- **Data shared with family:** daily step total, walk start and stop, status, reactions.
- **Apple rules:** Health data is never used for ads or sold; onboarding explains why steps are needed; a privacy policy is in place before TestFlight.
- **Leaving:** leaving a family removes that member's shared data from it; deleting the account removes everything.
- **Stack:** native SwiftUI, HealthKit background delivery, APNs for push. Backend is Convex: it stores families, members and daily step totals, a scheduled job closes each day at Nepal midnight, and a server action sends walk alerts to APNs. Subaz builds all of v1 for now: the iOS app, the Convex backend and the design.
- **Apple Watch:** watch steps flow in through Health automatically; no watch app in v1.

## Success metrics

The pilot starts with both founders' families; these targets are proposals to agree on before launch.

| Metric | Target |
| --- | --- |
| Invited members who join within 48 hours | 80% |
| Members whose steps sync on a given day | 70% |
| Days per week the family hits its goal | 3 or more |
| Walk alerts or reactions per member per week | 1 or more |
| Families still active after 4 weeks | Both pilot families |

The softer signal from the call also counts: families talking about the app outside it.

## After v1

Everything below came up in the call and waits until the pilot shows families stick with steps.

- **Family leaderboard:** opt-in, weekly, family vs family by total steps ("You're the 21st most active family"), later with leagues.
- **Family tree view:** each member's city, local time and weather.
- **Location sharing:** opt-in, with exact or general location.
- **Habits:** a free personal habit tracker, then shared family habits like water, gym visits or no sugar.
- **Richer reactions:** comments, voice notes, 24-hour photo stories.
- **Home screen widget.**
- **Android.**
- **Paid family plan**, Spotify-style: free personal use, paid groups.
- **Friend groups** alongside families.

## Risks

The biggest risk is parents never finishing setup.

| Risk | Mitigation |
| --- | --- |
| Parents get stuck on install or the Health permission | Organiser-led setup, a short guide to send, and a screen-share call if needed |
| Family members on Android can't join | Measure how often this blocks a family during the pilot |
| Walk alerts become spam | Daily cap per member and per-type mute |
| The lowest walker feels guilty | No ranking inside the family; contributions shown in a fixed order |
| Looks like every other step app | Lead all messaging with family and the shared goal |
