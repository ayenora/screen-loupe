# Screen Loupe — Product

**A zoomed monitor exactly where you need it.** Pin a frame over any part of the screen, keep working there with your normal mouse and keyboard, and watch that spot magnified — live, pixel-true and perfectly still — in a window next to it.

Status: the positioning and principles below are the owner's direction. Tier 1 is being built in this order: cursor in the Viewer → Color Meter → pixel grid → Viewer that fits the area; the first three are in (docs/design.md §4). Tiers 2 and 3 are **proposed, not settled**.

## Who it is for

- **UI designers** checking how a design actually renders: 1 px misalignments, blurry half-pixel edges, antialiasing, icon rendering, shadows, borders — while still editing in Figma, Sketch or the browser.
- **Front-end and Apple-platform developers** tuning layout and styling: change the code, hot-reload, and see the result magnified next to it without taking a screenshot and zooming into it.
- **Anyone preparing a design review or a bug report** who needs a crisp, zoomed picture of exactly what is on screen.

## The core experience

What makes Screen Loupe different is one workflow: **you work in place, and the magnified view sits beside you.** Four principles protect it.

1. **Work in place, watch nearby.** The Capture Area stays where you put it. Clicks inside it go to the app underneath, so you keep working there with your ordinary cursor while the Viewer shows it big — on the same display or another one.
2. **Nothing moves unless you move it.** The Viewer never re-centres, re-fits or jumps on its own. Its zoom and position change only when you change them. Resizing the Capture Area keeps the zoom and keeps every pixel already on screen where it is: dragging the right or bottom edge reveals more to the right or below, dragging the left or top edge reveals more to the left or above. Moving the area keeps the Viewer's framing and shows the new place. Fit is a command, applied once to the first frame and then only when asked for. Frames arrive at up to 60 fps with no visible lag.
3. **Pixel-true.** At integer zoom every screen pixel is an exact square; nothing is smoothed. What you copy is exactly what you see, and colours are the real values from the screen.
4. **Out of the way.** At rest the frame is a hairline with a small size label; handles appear only when the cursor comes near. The Viewer can float above other apps.

## How it compares

| | Screen Loupe | macOS Zoom (Accessibility) | Digital Color Meter | xScope Loupe | Colour pickers (ColorSlurp, ColorSnapper, Picky Colors…) |
|---|---|---|---|---|---|
| Magnifies a **fixed region you choose**, independent of the cursor | Yes | No — even with a stationary picture-in-picture window, the magnified image follows the pointer [1] | No — area under the cursor | No — follows the mouse [2] | No — loupe under the cursor [3] |
| **Separate, resizable window**, can live on another display | Yes | Picture-in-picture window or screen edge [1] | Small fixed window | Floating loupe | Transient loupe while picking |
| Keep **working normally** in the magnified spot | Yes | Cursor drives the view | Cursor drives the view | Cursor drives the view | Picking mode takes over the cursor |
| **Crisp pixels** (no smoothing) | Always at integer zoom | Optional ("Smooth images" can be turned off) [1] | Yes | Yes | Yes |
| **Copy / save the zoomed view** | Yes, exactly as shown | — | Copies colour values | Copies colour values [2] | Copies colour values |
| **Copy the source region** at native resolution | Yes | — | — | — | — |
| Pixel colour (HEX/RGB) | Planned (Color Meter) | — | Yes | Yes [2] | Yes, many formats [3] |
| Main purpose | Inspecting UI while working | Accessibility | Colour sampling | Designer measurement toolkit (10 tools) [2] | Colour picking and palettes |

Rows marked with sources describe the vendors' documentation; the table should be rechecked before it is used publicly.

**In short:** every existing magnifier is tied to the cursor — to look at a spot you must point at it, so you can't work there at the same time. Screen Loupe separates *where you look* from *where you work*.

## Proposed features

Proposed, not settled. Ordered by how much each strengthens the core experience. TASK.md §22 stays in force: no OCR, annotations, drawing, image editing, accounts, telemetry or AI features.

### Tier 1 — makes "a zoomed monitor where you need it" real (decided, in this order)

- **Cursor in the Viewer.** The capture hides the real cursor so it doesn't cover pixels. Draw a thin crosshair (or the pointer's hotspot) in the Viewer where the real cursor is inside the Capture Area, so you see exactly what you point at, magnified. This is the single most important piece for working in place.
- **Viewer that fits the area exactly.** A command (and an optional link) that sizes the Viewer window to *area × zoom*, so the whole magnified area is visible without panning — "zoom this spot of my monitor 4×".
- **Built-in Color Meter** (the Pixel Inspector of TASK.md §8, extended):
  - reads the pixel under the cursor in the Viewer **or under the real cursor inside the Capture Area**;
  - X/Y in area pixels, HEX and RGB in sRGB, plus the native display value (Display P3);
  - click to copy in a chosen format: HEX, `rgb()`, SwiftUI `Color`, `UIColor`/`NSColor`;
  - pin two colours to compare them and show their WCAG contrast ratio.
- **Pixel grid** (TASK.md §9).

### Tier 2 — the designer's daily loop (proposed, not settled)

- **Freeze frame.** Pause the live view (Space) to study a transient state — a hover, a pressed button, a frame of an animation — then resume.
- **Measure in the Viewer.** Drag between two points to get the distance in px and pt, snapping to colour edges, at full magnification.
- **Overlay a reference.** Drop a design export (PNG from Figma) onto the Viewer and see it over the live pixels with opacity or a difference blend: an exact design-vs-implementation check. No existing loupe does this live.
- **Attach the area to a window.** The Capture Area follows a window when it moves (the iOS Simulator, a browser window).
- **Several Capture Areas**, each with its own Viewer, for comparing two places.

### Tier 3 — later, each needs its own decision

- **Record the zoomed view** as a short video or GIF of an interaction.
- **Act through the Viewer.** Clicks and scrolls in the Viewer go to the real spot on screen, making the Viewer a true zoomed monitor. Needs the Accessibility permission to post events, and has to feel safe; a bigger design question than the rest.

## Open

1. Distribution: direct download (as now, no sandbox) or the Mac App Store (needs the sandbox; docs/design.md §4).

## Sources

1. Apple Support, *Change Zoom advanced options for accessibility on Mac*: https://support.apple.com/guide/mac-help/change-zoom-advanced-options-accessibility-mh35715/mac ; AbilityNet, *How to magnify what's on the screen in macOS 15 Sequoia*: https://mcmw.abilitynet.org.uk/how-to-magnify-whats-on-the-screen-in-macos-15-sequoia
2. xScope features: https://xscopeapp.com/features
3. Setapp, *Best color pickers for Mac*: https://setapp.com/lifestyle/best-color-picker ; Picky Colors on the App Store: https://apps.apple.com/us/app/picky-colors/id6759072554?mt=12 ; ColorSlurp: https://colorslurp.com/
