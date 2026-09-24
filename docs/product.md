# Screen Loupe — Product

**A zoomed monitor exactly where you need it.** Pin a frame over any part of the screen, keep working there with your normal mouse and keyboard, and watch that spot magnified — live, pixel-true and perfectly still — in a window next to it.

This document holds the product decisions: who the app is for, the principles every UX decision is measured against, what each feature does, and what the app deliberately doesn't do. How it is built is in [design.md](design.md); what comes next is in [roadmap.md](roadmap.md).

## Who it is for

- **UI designers** checking how a design actually renders: 1 px misalignments, blurry half-pixel edges, antialiasing, icon rendering, shadows, borders — while still editing in Figma, Sketch or the browser.
- **Front-end and Apple-platform developers** tuning layout and styling: change the code, hot-reload, and see the result magnified next to it without taking a screenshot and zooming into it.
- **Anyone preparing a design review or a bug report** who needs a crisp, zoomed picture of exactly what is on screen.

## Principles

The app is one workflow — **place → zoom → pan → inspect → copy** — built around one idea: **you work in place, and the magnified view sits beside you.** Four principles protect it.

1. **Work in place, watch nearby.** The Capture Area stays where you put it. Clicks inside it go to the app underneath, so you keep working there with your ordinary cursor while the Viewer shows it big — on the same display or another one.
2. **Nothing moves unless you move it.** The Viewer never re-centres, re-fits or jumps on its own. Its zoom and position change only when you change them. Resizing the Capture Area keeps the zoom and keeps every pixel already on screen where it is: dragging the right or bottom edge reveals more to the right or below, dragging the left or top edge reveals more to the left or above. Moving the area keeps the Viewer's framing and shows the new place. Fit is a command, applied once to the first frame and then only when asked for. Frames arrive at up to 60 fps with no visible lag.
3. **Pixel-true.** At integer zoom every screen pixel is an exact square; nothing is smoothed. What you copy is exactly what you see, and colours are the real values from the screen.
4. **Out of the way.** At rest the frame is a hairline with a small size label; handles appear only when the cursor comes near. The Viewer can float above other apps. The app never shows up in its own capture.

## Features

### Capture Area

A frame above every other window that marks the region being inspected.

- Moved by its line or its grip tab, resized by eight handles on the corners and edges; minimum 64×64 pt.
- Transparent inside: nothing covers the content, and clicks go through to the app underneath.
- Shows its size in points and pixels (`220 × 150 pt · 440 × 300 px`), so the numbers mean something on Retina and non-Retina displays alike.
- Arrow keys move it by one pixel, Shift + arrow by ten; Option resizes instead of moving.
- It doesn't follow the mouse and doesn't depend on the Viewer: it stays where you placed it.

### Viewer

A regular macOS window that shows the Capture Area live.

- Moved, resized, taken full screen or placed on another display; none of that changes the Capture Area.
- Toolbar: zoom presets and the current zoom on the left; grid, crosshair, Color Meter, Copy, Save and Keep on Top on the right.
- **Keep Viewer on Top** keeps it above other apps' windows.
- When access to the screen is missing or capture breaks, the Viewer says so and offers a way out; it is never an empty window without an explanation.

### Zoom and pan

- Presets **Fit, 100%, 200%, 400%, 800%, 1600%**, plus any zoom by pinch, ⌘ + wheel, `+`/`-` or a typed percentage.
- Zoom keeps the point under the cursor in place.
- At integer zoom one screen pixel is an exact N×N square: 800% is a crisp 8×8 block, never a blur.
- Zoom is measured in display pixels per screen pixel, so 800% is exact whatever displays the source and the Viewer are on.
- Pan by dragging, two-finger or horizontal scrolling.
- Zoom and pan never move the Capture Area.

### Screenshots

| Mode | What you get |
|---|---|
| **Copy/Save Source** | The Capture Area as it is on screen, unmagnified, at native resolution: a 500×300 pt area on a 2× display is a 1000×600 PNG. |
| **Copy/Save View** | Exactly what the Viewer shows: its zoom, pan and viewport. |

| Shortcut | Action |
|---|---|
| `⌘C` | Copy View |
| `⇧⌘C` | Copy Source |
| `⌘S` | Save View… |
| `⇧⌘S` | Save Source… |

Saved files are PNGs with the display's colour profile, named like macOS screenshots, in the folder used last. Copy View is the point of the app for reviews and bug reports: zoom into a detail at 800–1600%, frame it, copy exactly that.

### Crosshair

The capture hides the real cursor so it doesn't cover the pixels. The crosshair shows in the Viewer where the real cursor is inside the Capture Area, so you see exactly what you point at, magnified. On by default; a toolbar toggle.

### Color Meter

A panel beside the image for the pixel under the cursor — in the Viewer, or under the real cursor inside the Capture Area.

- Position in Capture Area pixels, not in the magnified image.
- HEX and CSS `rgb()` in sRGB, matching design tools; SwiftUI `Color` and AppKit `NSColor`; the native display value (for example Display P3). Each has a copy button.
- Click a pixel to pin its colour (up to 12, kept between launches); the WCAG contrast ratio of the two newest pins.

### Pixel grid

- Lines exactly on the boundaries of screen pixels, from 800% on (the threshold is a setting).
- A toolbar toggle; off by default.
- Not in Copy View unless the setting for it is on; never in Copy Source.

### Retina and multiple displays

- The Capture Area works on any display: Retina and non-Retina side by side, any arrangement, displays left of or above the main one.
- Moving it to another display switches the capture automatically.
- An area that looks 400×300 always captures exactly that region, never an offset or rescaled one.

### Permissions

Screen Recording access is needed to see the screen. Without it the Viewer explains why, asks for access, opens System Settings and says when the app has to be reopened. The app never crashes or shows an empty window over a missing permission.

### Menu bar and app mode

- A menu bar item: Show Viewer, Show/Hide Capture Area, Copy View, Copy Source, Reset Zoom, Keep Viewer on Top, Settings, Quit.
- Closing the Viewer hides the Capture Area too, so no frame is left on screen without its Viewer; the app keeps running in the menu bar.

### Global shortcuts

Work from any app, with defaults chosen to avoid system shortcuts; each can be changed or cleared in Settings.

| Shortcut | Action |
|---|---|
| `⌃⌥⌘L` | Show/Hide Capture Area |
| `⌃⌥⌘V` | Show/Hide Viewer |
| `⌃⌥⌘C` | Copy View |
| `⌃⌥⇧⌘C` | Copy Source |

### Settings

Opened with Settings… (⌘,) in the app menu or the menu bar item. Five tabs; every change applies at once, with no Save button.

- **General:** launch at login; Dock and menu bar, or the menu bar only; on launch show the Capture Area and Viewer, or nothing. Without Screen Recording access the Viewer opens anyway, to ask for it.
- **Capture Area:** frame colour (six presets or any colour), line width 1 or 2 pt, the size label at rest, size units, with a preview. The grip tab is a darker shade of the frame colour with white or black text, whichever reads better.
- **Viewer:** background dark, light or checkerboard (8 pt squares); the pixel grid's threshold, 4× to 32×, and line colour; crosshair colour; whether a mouse wheel needs ⌘ to zoom. On a trackpad two fingers always pan.
- **Screenshots:** the folder the save panel opens in; the grid in Copy View and Save View (only while it is visible in the Viewer); file names like macOS screenshots or `ScreenLoupe-View-20260924-142005.png`; revealing saved files in Finder.
- **Shortcuts:** the four global shortcuts. Click, press the new combination; Escape cancels, Delete clears. A combination already taken moves to the new action. A shortcut needs ⌃, or ⌥ with ⌘, so it can't take ⌘C and the like from other apps; one that macOS refuses is marked in Settings.

### Kept between launches

The Capture Area's place and size, the Viewer's frame, zoom, the toolbar toggles, pinned colours, the screenshot folder and every setting.

## Not in scope

These stay out, to keep the app small and focused on looking at pixels: OCR, annotations, drawing arrows or text, image editing, a screenshot history manager, cloud sync, accounts, telemetry, subscriptions, AI features. The app collects no data.

## How it compares

Checked against the vendors' documentation in September 2026. "Not documented" means the vendor doesn't say, not that the feature is missing.

| | Screen Loupe | xScope Loupe | macOS Zoom (Accessibility) | Digital Color Meter | Region mirrors (RegionMirror, ZoneShare, Conjuly) | Cursor loupes (ColorSlurp, ColorSnapper, Picky Colors, Loupe) |
|---|---|---|---|---|---|---|
| **Live view of a fixed region** you choose | Yes | Yes, when locked (⌘L) [2] | No — the picture-in-picture window can stay put, but what it shows follows the pointer [1] | Locked aperture: a tiny sample of one spot [3] | Yes [5] | No — the loupe follows the cursor [4] |
| **Separate, resizable window**, on any display | Yes | Resizable loupe window [2] | Picture-in-picture window or screen edge [1] | Small fixed window [3] | Yes [5] | Transient loupe while picking [4] |
| **Crisp pixels** (no smoothing) | Always at integer zoom | Not documented | Optional ("Smooth images" can be turned off) [1] | Yes | Not documented; built for presenting [5] | Yes |
| **Pan** a magnified image larger than the window | Yes | Not documented | Follows the pointer | — | Not documented | — |
| **Real cursor shown** in the magnified view while you work in the region | Yes, crosshair | Not documented | Is the pointer | — | Not documented | — |
| **Copy / save the zoomed view** exactly as shown | Yes | Not documented | — | Colour values and a colour swatch [3] | Not documented | Colour values |
| **Copy the source region** at native resolution | Yes | — | — | — | — | — |
| Pixel colour | HEX, `rgb()`, SwiftUI, AppKit, native value; pinned colours; WCAG contrast | RGB, HSB, HEX, CSS; swatches [2] | — | Yes, several colour spaces [3] | — | Yes, many formats [4] |
| **Pixel grid** on exact pixel boundaries | Yes | Gridlines [2] | — | — | — | — |
| Price | Free, open source (MIT) | $49.99 [2] | Built into macOS | Built into macOS | Free to $19.99 [5] | Free to a few dollars [4] |
| Main purpose | Inspecting UI while working | Designer measurement toolkit | Accessibility | Colour sampling | Sharing part of the screen in calls | Colour picking |

**In short:** most magnifiers are tied to the cursor — to look at a spot you must point at it, so you can't work there at the same time. Region mirrors show a fixed spot live but are made for presenting, not for looking at pixels. The closest tool is xScope's locked Loupe, one of ten tools in a paid suite. Screen Loupe does one thing: it separates *where you look* from *where you work*, and makes what you look at pixel-true — crisp at every integer zoom, pannable, with the real cursor marked, and copyable exactly as shown or at native resolution.

## Sources

1. Apple Support, *Change Zoom advanced options for accessibility on Mac*: https://support.apple.com/guide/mac-help/change-accessibility-zoom-preferences-mh35715/mac ; AbilityNet, *How to magnify what's on the screen in macOS 15 Sequoia*: https://mcmw.abilitynet.org.uk/how-to-magnify-whats-on-the-screen-in-macos-15-sequoia
2. xScope 4 on the Mac App Store ("the content of the window or the mouse position can be locked"): https://apps.apple.com/us/app/xscope-4/id889428659?mt=12 ; xScope guide: https://xscopeapp.com/guide
3. Digital Color Meter User Guide: https://support.apple.com/guide/digital-color-meter/welcome/mac
4. ColorSlurp magnifier: https://colorslurp.com/docs/magnifier ; Picky Colors: https://pickycolors.com/ ; Loupe on the App Store: https://apps.apple.com/us/app/loupe/id1535217393
5. RegionMirror: https://regionmirror.com/ ; ZoneShare: https://zoneshare.app/ ; Conjuly: https://apps.apple.com/app/conjuly/id6758891488
