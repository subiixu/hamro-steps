# Second opinion: iOS redesign, phase 1: light-only design system, Home bento, Liquid Glass
verdict: Has concerns
reviewer: codex gpt-6.1-sol · high effort
author: claude claude-opus-5-5
handoff: handoffs/2026-11-14-2336-ios-redesign-1-home.md
findings: 2
at: 2026-11-14T14:37:48Z

Claude wrote it, so Codex reviews it. Read-only review of the worker's checkpoints, b1d217223c..6330b0fae9 (shared checkout) (1166 changed lines).

## Summary
The redesign largely follows the brief, but two large-text overflow paths need attention. Reported checks passed; I did not rerun checks that write files during this read-only review.

## Findings
1. **Should fix** · `ios/HamroSteps/Features/Home/HomeView.swift:692`
   Why: The week summary uses fixedSize(), which prevents wrapping even in the VStack fallback. At accessibility text sizes, “Goal reached on N days” can exceed the tile width and extend beyond its bounds. The supplied accessibility screenshot does not cover this tile.
   Fix: Allow horizontal wrapping in the stacked fallback with fixedSize(horizontal: false, vertical: true), while preserving the horizontal fit check. Verify the lower Home tiles at accessibility XL.
2. **Should fix** · `ios/HamroSteps/Features/Home/HomeView.swift:326`
   Why: ActivityWrapLayout measures and places each chip with an unspecified width. It wraps whole chips between rows but cannot constrain an individual chip, so the new Today chips can overflow on narrower iPhones at the largest Dynamic Type sizes despite their text allowing wrapping.
   Fix: Constrain each chip to the available tile width during measurement and placement, or use a width-constrained stacked layout at accessibility sizes. Verify both chips at the largest text size on a narrow supported iPhone.
