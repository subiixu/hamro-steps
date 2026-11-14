# Hamro Steps — three app logo concepts

Tasks: T-38

Phase 1 · 15 November 2026 · Light appearance only

Open [compare.png](compare.png) for all three concepts side by side. The sheet contains literal 1024×1024, 180×180 and 60×60 image placements, followed by a phone home-screen mockup for each. View at 100% zoom to evaluate the 60px row; fitting the entire sheet to a window makes that row smaller than 60px.

## 01 — Homeward · recommended

An orange home encloses a broad, winding white path that opens through its base. The house stands for the family across countries; the path adds everyday walking without footprints or a goal ring. Its rounded roof and generous empty space feel familiar and welcoming, and both the house and path remain visible at 60px. This is the best balance of family, movement and easy recognition for parents. Its tradeoff is that a house can also suggest a home service, so the name “Hamro Steps” remains useful context. Source: [homeward.svg](homeward.svg); [1024 icon](homeward-1024.png), [180 preview](homeward-180.png), [phone mockup](homeward-home-screen.png).

## 02 — Shared Stride

A single broad white ribbon rises through two steps on a solid orange tile. The continuous path suggests separate efforts adding to one family goal, and the stair silhouette gives the most direct connection to the app’s name. The orange field makes it especially easy to locate among surrounding apps; both rises remain clear at 60px. Its tradeoff is meaning: it can suggest stairs or progress tracking more readily than family, and may imply climbing rather than ordinary walking. Source: [shared-stride.svg](shared-stride.svg); [1024 icon](shared-stride-1024.png), [180 preview](shared-stride-180.png), [phone mockup](shared-stride-home-screen.png).

## 03 — Open Embrace

Two rounded shoulders join into a single orange heart-like embrace, with a generous white centre opening at the bottom. It puts affection and belonging first: family members are held together even when apart. The heart silhouette and open centre survive at 60px, although the narrow gap between the lower tips is the least robust detail of the three marks. Its tradeoff is specificity: it may read as a care or wellbeing app, and needs the product name to communicate walking. Source: [open-embrace.svg](open-embrace.svg); [1024 icon](open-embrace-1024.png), [180 preview](open-embrace-180.png), [phone mockup](open-embrace-home-screen.png).

## Recommendation and next phase

Choose **01 — Homeward** for its familiar silhouette and combined home/path meaning. This is a design recommendation based on visual inspection, not a claim of recognition testing with parents. Keep 02 as the strongest option if the priority is a vivid orange app tile and literal steps; choose 03 if emotional connection matters most. The user's choice belongs to the next phase before any production integration.

## Asset and reproduction notes

- Each concept is newly drawn vector geometry, with no stock art, copied assets, national emblems, text in the mark, or gradients. These are brand marks, not UI library icons.
- All icon colors are exactly accent `#E2672F` and surface `#FFFFFF`. The board uses canvas `#F4F4F6` and accent text `#B5481B`; adding green would introduce an unnecessary small detail.
- SVGs are the geometry source. The 1024 and 180 PNGs are opaque square canvases in sRGB. Rounded corners appear only in the comparison and phone presentations, using an approximate mask.
- Each phone PNG is 1170×2532, representing a 390×844-point screen at 3×. Hamro Steps occupies a 60-point tile (180 exported pixels). The comparison displays the phone at 390×844, so its app tile is 60 pixels there.
- Phone views are schematic home-screen mockups with neutral placeholder app tiles, not actual iOS screenshots or a proposed app UI. They deliberately use no third-party app marks or UI glyphs.
- Rebuild on macOS with `swift design/logo/build.swift`. The exporter uses system AppKit, CoreGraphics, Foundation, ImageIO and UniformTypeIdentifiers only; no dependency installation is needed. It does not read or modify the existing app icon assets.
- See [verification.txt](verification.txt) for export and visual checks. Device installation, user testing, dark/tinted variants and production integration are outside this phase.

## Selected logo — phase 2

The user selected **02 — Shared Stride**. Rebuild its app and web assets with `swift design/logo/build.swift --app-assets`; this mode leaves all phase-one concept exports untouched.

- AppIcon light: white on `#E2672F`; dark: `#F07A43` on `#2A1A12`; tinted: `#DDDDDD` on black. Each is a square 1024px sRGB PNG with no alpha channel.
- Web: 64px favicon and 180px apple-touch-icon, using the light appearance.
- Welcome: a white, background-free template SVG copied from the same path. Its square viewBox fits the mark to the existing icon frame without adding the app icon's outer padding again. Existing hero sizing and accent background stay unchanged.
- The exporter copies the existing template/vector imageset settings. It does not modify the AppIcon manifest or the historical `design/app-icon/` files.
