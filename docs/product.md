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
- **Snapping with ⌘.** Hold ⌘ while moving or resizing, and an edge that comes within 8 pt of a window's or a display's edge snaps to it, from inside or outside. An edge snaps only to windows beside it: a left edge to a window that spans some of its height. Without ⌘ nothing snaps, and the arrow keys never do.
- **Fit to a window.** The window button beside the tab, Window › Fit Capture Area to Window…, the menu bar item or the global shortcut: the window under the pointer is tinted, a click makes the area exactly that window, Escape or a click on no window cancels. The click goes to no app, so a tap in the Simulator doesn't happen. It works on a pinned area too: the pin guards against a stray drag, and this is a deliberate command. A closed Viewer opens to show it.
- Transparent inside: nothing covers the content, and clicks go through to the app underneath.
- Shows its size in points and pixels (`220 × 150 pt · 440 × 300 px`), so the numbers mean something on Retina and non-Retina displays alike.
- Arrow keys move it by one pixel, Shift + arrow by ten; Option resizes instead of moving.
- On hover a narrow box beside the frame shows its edges — L, T, R, B — from the top-left corner of its display, in the tab's units (points, or pixels when only pixels are chosen). It sits right of the frame, or left of it when there is no room.
- The pin button right of the tab (left of it at the screen's edge) locks the frame: pinned, it neither moves nor resizes, and shows no handles. The pin is kept between launches.
- The button beside the pin brings the Viewer forward, pinned or not: a click in the area can bring another app's window over the Viewer, a maximized one hiding it altogether.
- It doesn't follow the mouse and doesn't depend on the Viewer: it stays where you placed it.

### Viewer

A regular macOS window that shows the Capture Area live.

- Moved, resized, taken full screen or placed on another display; none of that changes the Capture Area.
- Toolbar: zoom presets and the current zoom on the left; freeze (with a menu of delays), Select, ruler, grid, the pointer (with a menu of styles), Color Meter, References, Recent Captures, Copy, Save and Keep on Top on the right.
- **Keep Viewer on Top** keeps it above other apps' windows. Not over an app in macOS full screen (the green button), which has a Space of its own: a window stretched over the screen works almost the same and keeps the Viewer over it.
- **Size Window to Area** (View menu, ⌥⌘0) sizes the Viewer so the whole magnified area shows at the current zoom, without panning. The zoom doesn't change. The window never grows beyond its screen: it moves to stay on it, and an image bigger than the screen still pans.
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
| **Copy/Save View** | Exactly what the Viewer shows: its zoom, pan and viewport, with the reference layers. The crosshair, the drawn cursor and the ruler are tools, not content, and stay out. |

| Shortcut | Action |
|---|---|
| `⌘C` | Copy View |
| `⇧⌘C` | Copy Source |
| `⌘S` | Save View… |
| `⇧⌘S` | Save Source… |

Saved files are PNGs with the display's colour profile, named like macOS screenshots, in the folder used last. Copy View is the point of the app for reviews and bug reports: zoom into a detail at 800–1600%, frame it, copy exactly that.

An image holds at most 16 megapixels, as many as 4096 × 4096. A copy or a saved file that would be bigger — a large selection at a high zoom, a huge Capture Area — keeps its top-left part: a side shorter than 4096 stays whole and the other is cut to fit, and with both sides longer 4096 × 4096 is kept. Nothing is scaled down.

A part of the view is copied without resizing the window or panning, in two ways:

- **Option-drag, the quick way.** Hold ⌥ and drag a rectangle in the Viewer; on letting go, that region of the view is on the clipboard ("Region copied"). It is free, not snapped to pixels, and there is nothing to adjust afterwards. While dragging, a label shows the size of the image it copies. A plain drag still pans.
- **The Select tool, the precise way.** The toolbar's Select button or View › Select (⌘E) turns on a mode like the eyedropper: while it is on, a drag selects instead of panning, and Space-drag pans. The selection always snaps to whole screen pixels, with the grid shown or not, and a label under it gives its size in pixels and its place from the Capture Area's top-left (`12 × 5 px · x 11, y 11`). Its handles resize it and dragging inside moves it. Edit › Select All (⌘A) selects the whole Capture Area, turning the tool on if it is off. It stays on its pixels when the Capture Area is resized by its left or top edge. While there is a selection, Copy View and Save View (⌘C, ⌘S, the toolbar's buttons, the global Copy View shortcut) take just the selection, at the current zoom, even where it reaches beyond the window; otherwise the whole view. A click outside it or Escape clears it; turning the tool off drops it.

### Freeze frame

Space in the Viewer, the pause button in the toolbar, View › Freeze Frame or the global Freeze shortcut stops the live view on the current frame, to study a transient state — a hover, a pressed button, a frame of an animation. Space again resumes.

- While frozen, a blue border runs around the image with "Frozen · Space to resume" at its top.
- **Freezing while holding a state in another app.** The mouse is held down in an emulator or a browser to keep a pressed or dragged state, and the frame has to be taken without letting go. Two ways:
  - *The global Freeze shortcut*, F13 by default. It freezes the Viewer from any app; then the mouse is let go and the frozen frame is framed, copied or saved as usual. A function key alone is allowed for this shortcut only, so no modifier reaches the app under the mouse (in the iOS Simulator ⌥ means pinch). Frozen this way from another app, the Viewer also says so at its bottom: "Frozen by F13 from Simulator — let go of the mouse, then zoom, pan, copy".
  - *Freeze after a delay.* The ▾ beside the pause button opens Freeze Now and Freeze in 3, 5 or 10 Seconds; View › Freeze Later has the same delays. The live view runs on while the countdown shows over the image — a dashed border and "Freezing in 2 s · Esc to cancel" with a shrinking ring — and at zero it freezes as Space does. No keyboard at all; the price is the wait. The pause button or Escape stops the countdown.
- Copy, Save and the Color Meter use the frozen frame.
- The Capture Area can still be moved and resized; the image updates when the view resumes.
- Closing the Viewer resumes.

### Recent Captures

The last four pictures copied or saved in the Viewer, kept to study later: take a transient state quickly, then zoom, measure and pick colours on it at leisure instead of on the live view. The toolbar's Recent Captures button opens the panel.

- Every copy and save in the Viewer adds one, newest on top: Copy View and Copy Source, Save View and Save Source, an Option-drag, a selection, and the global Copy View and Copy Source shortcuts. A fifth pushes out the oldest. They are kept in memory only and gone when the app quits.
- A capture keeps the Capture Area's pixels at native resolution, not the copied image, so every tool works on real screen pixels; a copy keeps just the screen pixels it covers — a view the part the window showed, a selection or an Option-drag their pixels — and only a source copy keeps the whole area. For the whole area at a zoom: ⌘A, then ⌘C. It opens as it was shown: its zoom, pan and selection. The clipboard and the file still get what was asked for.
- On top, apart from the captures, a Live row that can't be deleted: the live view, what the Capture Area shows now. It is chosen whenever no capture shows, and clicking it goes back to live.
- Below it one row per capture: a thumbnail of what was copied, what it was (View 800%, Selection, Region, Source), the size of that image in pixels and the time. The × deletes it. The list scrolls when the column is short.
- Clicking a row shows that capture in the Viewer in place of the live view, with a purple border and "Capture 2 of 4 · 14:20:05 · Esc for live" at its top. Zoom, pan, the ruler, the grid, Select, the Color Meter, Copy and Save work on it as on the live view; each capture keeps its own zoom, pan and selection. Copies made from a capture add none.
- Freeze and the pointer have nothing to do on a capture and are off while it shows.
- The Live row, Escape, closing the panel or closing the Viewer goes back to live, as it was left.
- The capture stays in the Viewer while its panel is collapsed to a strip, so the Color Meter can be expanded and its eyedropper used on it.
- References and Recent Captures take turns below the Color Meter: opening one closes the other.

### Ruler

A corner ruler over the image, for measuring in screen pixels at any zoom. The toolbar's ruler button or View › Ruler (⌘R) turns it on and off; turning it off forgets it.

- A corner and two arms, one horizontal and one vertical. Each arm shows its length, `32 px · 16 pt` (just `px` on a 1× display), with a tick per pixel when they are far enough apart.
- Drag the line to move the ruler, an arm's end to stretch that arm, the corner to move it while the ends stay. An arm dragged past the corner flips to the other side. Everything moves in whole pixels, so the ends sit on pixel edges.
- No arm looks shorter than 32 pt, so its handles never touch.
- Unpinned, the ruler stays where it is in the Viewer while the image pans and zooms under it.
- On hover a translucent band shows along the line — the part that moves the ruler — and a pin button outside the corner; both stay a moment after the pointer leaves. While the image pans or zooms, an unpinned ruler stays perfectly still in the Viewer, off the pixel grid, with its lengths dimmed as approximate; once the image settles it eases onto the nearest pixel edges, less than a pixel away, and the lengths are exact again. It never hides, also while it is being dragged.
- The pin button pins the ruler to the pixels under it. Panning and zooming then carry it along, and so does resizing the Capture Area by its left or top edge; it can't be moved, only its arms stretched. Zooming out lengthens an arm that would look too short, and zooming back in returns it to the length it was set to.

### Crosshair and cursor

The capture hides the real cursor so it doesn't cover the pixels. The Viewer shows instead where the real cursor is inside the Capture Area, so you see exactly what you point at, magnified. On by default; a toolbar toggle, whose ▾ chooses how it shows:

- **Crosshair:** lines across the Viewer through the pixel pointed at, and a box around it.
- **Cursor:** an arrow at its usual size, its tip on the outlined pixel. Readable at any zoom and hides little.
- **Original Cursor in the Capture:** the capture records the real pointer, in the shape the app under it sets (arrow, I-beam, hand). It is part of the pixels, so it grows with the zoom and goes into copies, saved files and recent captures. While the Color Meter's eyedropper is on, the capture leaves it out, so the Color Meter never reads the pointer itself; the menu says so, and the pointer comes back when the Color Meter collapses or closes.

The crosshair and the drawn cursor are tools, not content: they stay out of copies.

### Color Meter

A panel beside the image for the pixel under the cursor — in the Viewer, or under the real cursor inside the Capture Area.

- Position in Capture Area pixels, not in the magnified image.
- HEX and CSS `rgb()` in sRGB, matching design tools; SwiftUI `Color` and AppKit `NSColor`; the native display value (for example Display P3). Each has a copy button.
- Click a pixel to pin its colour: the last 8 stay, newest first, kept between launches.

### References

Images laid over the live pixels — a design export, an earlier screenshot — for an exact check of the screen against them. PNG, JPEG, TIFF, HEIC, BMP and GIF are accepted. An image over the same 16-megapixel limit keeps its top-left part, as a copy does (Screenshots). The toolbar's References button opens the panel, in place of Recent Captures; the layers show and take the mouse only while it is open.

- Up to 10 layers, top first, one row each like layers in an image editor: grip ⠿, eye, thumbnail, name, opacity, pin. A row drags as a whole to reorder, and the others make room. The list scrolls.
- Below the list, the Layer section holds the selected layer's settings, where nothing drags: opacity, Normal or Difference, X and Y of the top-left corner in pixels from the Capture Area's top-left (resizing the area by its left or top edge keeps the layer on its pixels and changes these), scale, a reset of position and scale, and Delete.
- Difference shows the absolute difference from the live capture: pixels that match turn black. The image is converted to the display's colour space first, so a design colour that renders exactly matches exactly.
- In the Viewer, dragging a layer moves it in whole pixels; the selected layer has corner handles that scale it with its proportions kept. Exact values go in the panel: type them, or drag a field's caption (X, Y, Scale) left or right, one pixel or percent per point, Shift ×10, Option ×0.1.
- A pinned layer lets the mouse through: a drag takes the next unpinned layer under it, or pans the image.
- Copy View and Save View include the layers as shown.

The Color Meter and References share the column at the right, top down in that order. With both open one is expanded and fills the height, and the other is a strip at its place; clicking the strip expands it and collapses the other. The eyedropper works only while the Color Meter is expanded, and then it comes first: reference layers don't take the mouse or show their handles. Dragging the column's left edge widens it from 250 to 320 pt, and everything in it grows in proportion; the width is kept between launches.

### Project

What you set up to inspect a spot — the reference layers and the ruler — is the working project. There is one: it is saved as you work and restored at launch. Added images are copied into it, so a reference keeps working when its original file moves.

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

- A menu bar item: Show Viewer, Show/Hide Capture Area, Fit Capture Area to Window, Keep Viewer on Top, Copy View, Copy Source, Reset Zoom, Settings, the guide, Quit.
- Help › Screen Loupe Guide (⌘?) and Keyboard Shortcuts open the guide on the project's website; with the menu bar only, the menu bar item has the guide.
- Closing the Viewer hides the Capture Area too, so no frame is left on screen without its Viewer; the app keeps running in the menu bar.
- One copy runs at a time: launching another — a second build, `open -n` — brings the running one's Viewer forward and quits.

### Global shortcuts

Work from any app, with defaults chosen to avoid system shortcuts; each can be changed or cleared in Settings.

| Shortcut | Action |
|---|---|
| `⌃⌥⌘L` | Show/Hide Capture Area |
| `⌃⌥⌘V` | Show/Hide Viewer |
| `⌃⌥⌘C` | Copy View |
| `⌃⌥⇧⌘C` | Copy Source |
| `F13` | Freeze / Resume Viewer |
| `⌃⌥⌘W` | Fit Capture Area to Window |

### Settings

Opened with Settings… (⌘,) in the app menu or the menu bar item. Five tabs; every change applies at once, with no Save button.

- **General:** launch at login; Dock and menu bar, or the menu bar only; on launch show the Capture Area and Viewer, or nothing. Without Screen Recording access the Viewer opens anyway, to ask for it.
- **Capture Area:** frame colour (six presets or any colour), line width 1 or 2 pt, the size label at rest, size units, with a preview. The grip tab is a darker shade of the frame colour with white or black text, whichever reads better.
- **Viewer:** background dark, light or checkerboard (8 pt squares); the pixel grid's threshold, 4× to 32×, and line colour; crosshair colour; whether a mouse wheel needs ⌘ to zoom. On a trackpad two fingers always pan.
- **Screenshots:** the folder the save panel opens in; the grid in Copy View and Save View (only while it is visible in the Viewer); file names like macOS screenshots or `ScreenLoupe-View-20260924-142005.png`; revealing saved files in Finder.
- **Shortcuts:** the six global shortcuts. Click, press the new combination; Escape cancels, Delete clears. A combination already taken moves to the new action. A shortcut needs ⌃, or ⌥ with ⌘, so it can't take ⌘C and the like from other apps; Freeze / Resume Viewer may also be F13–F19 alone. One that macOS refuses is marked in Settings.

### Kept between launches

The Capture Area's place, size and pin, the Viewer's frame, zoom, the toolbar toggles, which side panel is expanded, pinned colours, the screenshot folder and every setting — and the project: the reference layers and the ruler. Freeze, a countdown, the Select tool and its selection, and the recent captures are not kept; the Viewer always opens live.

## Not in scope

These stay out, to keep the app small and focused on looking at pixels: OCR, annotations, drawing arrows or text, image editing, a screenshot library kept on disk, cloud sync, accounts, telemetry, subscriptions, AI features. The app collects no data.
