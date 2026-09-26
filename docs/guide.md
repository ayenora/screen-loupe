---
title: Guide — Screen Loupe
---

# Screen Loupe Guide

Screen Loupe shows one spot of your screen magnified in a window of its own, while you keep working in that spot. The workflow is **place → zoom → pan → inspect → copy**.

[Home](.) · [Download](https://github.com/ayenora/screen-loupe/releases/latest)

## Getting started

1. Open the DMG and drag Screen Loupe to Applications. It needs macOS 14 Sonoma or later.
2. Open it. The first time, the Viewer asks for **Screen Recording** access: click Grant Access, turn Screen Loupe on in System Settings › Privacy & Security › Screen Recording, and reopen the app when macOS asks.
3. A blue frame — the **Capture Area** — appears on screen, and the **Viewer** window beside it shows what is inside the frame, live.

Closing the Viewer hides the frame too; the app stays in the menu bar (the magnifier icon). Show Viewer there, or click the Dock icon, brings both back.

## The Capture Area

- **Move** it by its line or the grip tab above it; **resize** it by the handles that appear when the pointer comes near.
- **Clicks inside go to the app underneath**, so you keep working there.
- **Arrow keys** move it by one pixel (Shift: ten); with Option they resize it. Click the frame first.
- **Snap with ⌘:** hold ⌘ while moving or resizing, and an edge near a window's or a display's edge snaps onto it.
- **Fit to a window:** the window button beside the tab, Window › Fit Capture Area to Window…, or ⌃⌥⌘W. Point at a window — it is tinted — and click: the frame takes exactly that window. The click doesn't reach the app, so nothing is tapped. Escape cancels.
- **Pin** (the pin beside the tab) locks the frame against stray drags. The next button brings the Viewer forward when another window covers it.
- The tab shows the size in points and pixels; on hover a box beside the frame shows its edges from the display's top-left corner.

## The Viewer

- **Zoom:** the presets Fit, 100%–1600% in the toolbar, pinch, ⌘ + scroll wheel, `+` / `-`, or type a percentage in the zoom field. Zoom keeps the point under the pointer in place.
- **Pan:** drag, or scroll with two fingers.
- **Nothing moves on its own.** Moving or resizing the frame keeps the Viewer's zoom and framing; Fit applies only when you ask for it.
- **Size Window to Area** (View menu, ⌥⌘0) sizes the window to show the whole magnified area.
- **Keep on Top** (the pin at the right of the toolbar) keeps the Viewer above other apps.
- The pointer inside the frame shows in the Viewer as a crosshair, an arrow, or the original cursor captured with the pixels; the ▾ beside its button chooses.

## Copying and saving

| Command | What you get |
|---|---|
| **Copy View** ⌘C | Exactly what the Viewer shows, at its zoom. |
| **Copy Source** ⇧⌘C | The area as it is on screen, unmagnified, at native resolution. |
| **Save View…** ⌘S / **Save Source…** ⇧⌘S | The same as a PNG file. |

To copy just a part of the view:

- **⌥-drag** a rectangle in the Viewer: that region is copied on letting go.
- **Select** (⌘E, or the dashed-rectangle button): drag a selection snapped to whole screen pixels, adjust it by its handles, then ⌘C copies just the selection. ⌘A selects the whole Capture Area, at the current zoom, even where it reaches beyond the window. Space-drag pans while Select is on; Escape clears.

## Freezing a moment

- **Space** in the Viewer freezes the current frame — a hover, a pressed button, an animation frame. Space again resumes.
- **F13** freezes from any app, so you can hold the mouse down somewhere else, press F13, let go, and copy the frozen state.
- **Freeze later:** the ▾ beside the pause button freezes in 3, 5 or 10 seconds, no keyboard needed.

## Tools

- **Color Meter** (eyedropper button): the pixel under the pointer as HEX, CSS `rgb()`, SwiftUI, AppKit and the display's native value, with its position. Click a pixel to pin its colour.
- **Ruler** (⌘R): a corner ruler in screen pixels. Drag the line to move it, an arm's end to stretch it; pin it to keep it on its pixels while you zoom and pan.
- **Pixel grid:** lines on the pixel boundaries from 800% on.
- **References:** lay design exports over the live pixels, set opacity, or switch to Difference — matching pixels turn black. To try it, open the [example page](examples/reference-check/) and add its [design export](examples/reference-check/design-export.png) as a reference.
- **Recent Captures:** your last four copies and saves, kept to zoom, measure and pick colours on later. The Live row goes back to the live view.

## Keyboard shortcuts

In the Viewer:

| Shortcut | Action |
|---|---|
| ⌘C / ⇧⌘C | Copy View / Copy Source |
| ⌘S / ⇧⌘S | Save View… / Save Source… |
| Space | Freeze / resume |
| ⌘E | Select tool |
| ⌘A | Select the whole Capture Area |
| ⌘R | Ruler |
| ⌘0 | Reset zoom |
| ⌥⌘0 | Size Window to Area |
| `+` / `-` | Zoom in / out |
| ⌥-drag | Copy a region |
| Escape | Cancel a countdown, clear a selection, back to live |

On the Capture Area (click it first): arrows move by 1 px, ⇧ by 10 px, ⌥ resizes; hold ⌘ while dragging to snap.

Global, from any app — each can be changed or cleared in Settings › Shortcuts:

| Shortcut | Action |
|---|---|
| ⌃⌥⌘L | Show / Hide Capture Area |
| ⌃⌥⌘V | Show / Hide Viewer |
| ⌃⌥⌘C | Copy View |
| ⌃⌥⇧⌘C | Copy Source |
| F13 | Freeze / Resume Viewer |
| ⌃⌥⌘W | Fit Capture Area to Window |

## Settings

Settings… (⌘,) has five tabs: General (launch at login, Dock or menu bar only), Capture Area (frame colour and line), Viewer (background, grid, crosshair colour, wheel zoom), Screenshots (folder, file names) and Shortcuts.

## If something doesn't work

- **The Viewer asks for access although you granted it:** quit and reopen the app; macOS applies Screen Recording access on launch.
- **A global shortcut is marked in Settings:** macOS or another app already uses it; choose another.
- Something else: [open an issue](https://github.com/ayenora/screen-loupe/issues).
