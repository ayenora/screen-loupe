# Screen Loupe — Technical Design

The technical and architectural decisions: the constraints, the ScreenCaptureKit API the app relies on, the capture/render pipeline, the coordinate systems, the windows, the project structure, the risks and how the app is verified. What the app does and why is in [product.md](product.md); what comes next is in [roadmap.md](roadmap.md).

API facts below come from the macOS 26.2 SDK headers (`ScreenCaptureKit.framework/Headers`), not from memory.

## Constraints

- **Stack:** Swift, AppKit, ScreenCaptureKit, Metal. SwiftUI only for isolated UI pieces; windows, the overlay and mouse/keyboard handling stay in AppKit. The app stays small and native.
- **Not allowed:** Electron or any web/WebView UI; deprecated capture APIs (`CGWindowListCreateImage`, `CGDisplayStream`); paid SDKs. No third-party dependencies.
- **Pixels:** magnification is nearest-neighbor; pixels are never interpolated at integer zoom.
- **Frames:** no per-frame `CGImage → NSImage → bitmap` conversions. Frames go `SCStream` → `CMSampleBuffer`/`IOSurface` → `MTLTexture` → `MTKView`.
- **Performance:** up to 60 fps, no visible lag between the Capture Area and the Viewer; an idle screen costs nothing.
- **Self-exclusion:** the app's own windows never appear in the capture.
- **Project:** a plain Xcode project that builds and runs from Xcode or `make`; macOS target, deployment target 14.0 (§1).

## 1. ScreenCaptureKit: what the design relies on

| API | Availability | What it gives us |
|---|---|---|
| `SCShareableContent.current` | 12.3 | Displays (`SCDisplay.displayID`, `frame`), windows, running applications. Needs Screen Recording permission. |
| `SCContentFilter(display:excludingApplications:exceptingWindows:)` | 12.3 | Captures one display with every window of the listed apps removed. **This is the self-exclusion mechanism**: we exclude our own app, which removes both the Capture Area overlay and the Viewer. |
| `SCStreamConfiguration.sourceRect` | 12.3 | The captured sub-rect. **Points, in the display's logical coordinate system (top-left origin, relative to the display).** |
| `SCStreamConfiguration.width` / `.height` | 12.3 | Output size **in pixels** (default 1920×1080). Must be set to `sourceRect.size × scale`, or the output is resampled. |
| `SCStreamConfiguration.captureResolution = .best` | 14.0 | Captures at the display's backing resolution instead of letting the system pick. |
| `SCStreamConfiguration.minimumFrameInterval` | 12.3 | Default `1/60`; `kCMTimeZero` = native refresh rate. |
| `SCStreamConfiguration.queueDepth` | 12.3 | Surfaces kept in flight (default 8). |
| `SCStreamConfiguration.showsCursor` | 12.3 | On by default. We turn it **off**: the cursor would sit over the pixels being inspected. On only for Original Cursor in the Capture (§4). |
| `SCStream.updateConfiguration(_:)` | 12.3 | Changes the source rect and output size **without restarting** the stream. |
| Sample buffer attachments | 12.3 | `SCStreamFrameInfo.status` (`complete` / `idle` / `blank` / …), `.contentRect`, `.scaleFactor`, `.dirtyRects`. Idle frames carry no image — the last frame stays on screen. |
| `SCScreenshotManager.captureImage(contentFilter:configuration:)` | 14.0 | One-shot capture with the same filter; not used (see §2.4). |
| `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` | 10.15 | Check and request the Screen Recording permission. |
| `NSScreen.deviceDescription["NSScreenNumber"]` | — | `CGDirectDisplayID` of an `NSScreen`. (`NSScreen.CGDirectDisplayID` exists only from macOS 26, so we don't rely on it.) |

**Deployment target: macOS 14.0.** Everything above is available on 14.0; `captureResolution` is the newest API we depend on. Nothing in the design needs 15.x or 26.x. Only macOS 27 is available on this machine for testing.

## 2. Capture and render pipeline

```
Capture Area (AppKit window frame, global points)
        │  DisplayCoordinateConverter
        ▼
SCContentFilter(display, excluding: [this app])
SCStreamConfiguration(sourceRect: pt, width/height: px, BGRA, cursor off)
        │  SCStream → sample handler queue
        ▼
CMSampleBuffer → CVPixelBuffer (IOSurface-backed)
        │  FrameStore (latest complete frame, lock-protected)
        ▼
CVMetalTextureCache → MTLTexture (zero-copy)
        │  ViewerRenderer: one scene — background, frame quad (with the grid), reference layers —
        │  placed by ZoomPanController
        ├──────────────────────────────────────────────┐
        ▼                                              ▼
MTKView (drawn on each new frame               offscreen texture → CGImage
and on every zoom/pan change)                  (Copy View / Save View, §2.4)
```

### 2.1 Stream

- **One stream for one display at a time.** It captures the display that holds the larger part of the Capture Area.
- **Pixel format:** BGRA, SDR, in the source display's own color space (ScreenCaptureKit's default). The Viewer's layer is tagged with that color space, so the system color-matches when the Viewer sits on a display with another profile; on the same display the values pass through unchanged. The Pixel Inspector converts to sRGB for display (§4).
- **Self-exclusion:** `excludingApplications: [our SCRunningApplication]`, found in `SCShareableContent.applications` by `processID`. This removes every window we own, including Settings and alerts, with no window bookkeeping.
- **Moving or resizing the Capture Area** calls `updateConfiguration` with the new `sourceRect`, `width` and `height`. The calls are coalesced so that at most one update is in flight, and the newest rect wins when it completes.
- **Moving the Capture Area to another display** replaces the stream with a new one for that display. Swapping the filter of a running stream would apply the old display's source rect to the new display until the configuration update follows.
- **Frame bookkeeping:** `FrameStore` tags each frame with the geometry the stream is configured for and drops frames whose pixel size doesn't match it (frames from before a resize). While the area moves without resizing, a frame produced just before a reconfiguration can carry the new geometry for one frame; that is invisible in the Viewer and settled by the time anything is copied.
- **Timeouts and retries:** every ScreenCaptureKit call has a 5 s timeout. When the connection to the capture service drops, a call in flight may never return, and without the timeout it would block every later update. A broken capture is restored automatically in up to four attempts: the first at once, then after 2, 4 and 6 s. Meanwhile the Viewer shows "Capture interrupted" with a spinner, "Reconnecting — attempt 2 of 4 in 3 s" counting down, the system's reason and Try Now. Success shows "Capture restored" for a moment. When all attempts fail the panel says "Capture stopped" with Try Again; if that Try Again fails too, it suggests quitting and reopening the app and offers Restart Screen Loupe. Debug builds have a Debug menu that simulates an interruption that recovers or one that keeps failing, to check these states by hand.
- **Update bookkeeping:** when the system stops the stream or the displays change while an update is in flight, a generation counter makes that update's result void, so the next pass rebuilds the stream instead of believing it is running. A display AppKit knows but ScreenCaptureKit doesn't list yet is retried after a second, not in a loop.
- **Failures** are shown, never left as an empty Viewer: `SCStreamError.userDeclined` switches the Viewer to the permission explanation (until relaunch, because the preflight check can stay stale); any other error shows "Capture stopped" with the reason and Try Again.
- **Display changes:** `SCShareableContent` is cached and refreshed on `NSApplication.didChangeScreenParametersNotification`. If the system stops the stream (for example, the display was unplugged), it is rebuilt from the current display list.
- **Stop Sharing** in the system's screen-sharing menu stops the stream with `SCStreamError.userStopped`. That is the user's choice, so the stream is not restarted: the Viewer closes together with the Capture Area, exactly like its close button, and Show Viewer starts capturing again.

### 2.2 Threading (Swift 6 strict concurrency)

- `SCStreamOutput` callbacks arrive on a private serial queue. The handler does nothing but put the `CVPixelBuffer` and its frame info into `FrameStore` — a `Sendable` final class guarded by an `NSLock` — and then asks the view to redraw on the main actor.
- Everything that touches AppKit, window state or the `MTKView` is `@MainActor`.
- `CVMetalTextureCache` lookups happen in the draw call on the main actor. Creating a texture from an IOSurface is cheap and involves no copy.
- Reference images are decoded, and drawn into their textures, off the main actor (`@concurrent` functions); the result comes back to the main actor, which stores it and redraws. Values that aren't `Sendable` (`CGImage`, `MTLTexture`) cross in `UncheckedSendable`, handed over once and never shared.
- Copy View renders on the main actor and waits for the GPU (`waitUntilCompleted`): a user command, one frame's GPU work.

### 2.3 Rendering

- `MTKView` with `isPaused = true` and `enableSetNeedsDisplay = false`: the view calls `draw()` itself, at most once per main run-loop turn, when a new frame arrives, the zoom/pan changes or the window is shown again. An idle screen costs nothing. (With `setNeedsDisplay` nothing was drawn any more after the window had been closed and reopened.)
- The renderer puts one scene together (`ViewerRenderer.Scene`: size, zoom/pan state, frame, style, reference layers, colour space) and encodes it the same way for the screen and for Copy View's offscreen target: the checkerboard when chosen, the frame texture as a quad with the grid in its fragment shader, then each reference layer as a quad. The quads' placement comes from `ZoomPanController`. The drawable and the offscreen target share one pixel format (`ViewerRenderer.pixelFormat`).
- The shaders are compiled at launch from source (`ViewerShaders.swift`, `makeLibrary(source:)`), not from a `.metal` file: Xcode 26 ships the Metal compiler as a separate download, and runtime compilation keeps the project buildable without it.
- **Sampler:** `magFilter = .nearest`, `minFilter = .linear`. Magnification is always nearest-neighbor, so pixels are crisp squares; zooming out below 1:1 (for example Fit on a large area) is linearly filtered. Without mipmaps that still aliases below 50%; acceptable for a loupe, whose point is magnification.
- **Stable framing** (product.md, principle 2): Fit is applied once to the first frame and then only on request. A resize of the window or the Capture Area keeps the zoom; `ZoomPanState.resizingContent` shifts the offset by the move of the area's top-left corner, so pixels already visible stay put when the left or top edge is dragged. Clamping keeps an image smaller than the viewport wholly inside it without re-centring it.
- **Pixel-exact placement:** the pan offset is snapped to whole drawable pixels. At an integer zoom every source pixel then covers exactly N×N drawable pixels, so there are no uneven columns and the pixel grid lines up.
- **The pixel grid** is drawn in the same shader from the source-pixel coordinate, so it stays aligned by construction (§4).

### 2.4 Screenshots

- **Capture Source:** the latest frame's `CVPixelBuffer` is converted to a `CGImage` tagged with the frame's color space, then written as PNG or placed on the pasteboard. It is exactly the source pixels the Viewer shows, at native resolution. A new `SCScreenshotManager` capture isn't needed, and it could differ from what's on screen.
- **Capture View:** the Viewer renders it: the renderer encodes the same scene it draws on screen (background, frame, grid, reference layers) with the same pipelines into an offscreen texture of the drawable's size, waits for the GPU and reads the pixels back, tagged with the colour space the Viewer's layer shows them in. So Copy View is the screen at any zoom, including below 100%, the grid and Difference, and no second renderer has to be kept in step with the shaders. The texture is `.managed` (Intel GPUs don't take shared textures). The pixel grid is included only when the Settings option for it is on. The crosshair and the ruler are tools and stay out. Copy View works while the Viewer is hidden or on another Space: it needs no drawable.
- **Size limit:** every image the app makes or loads goes through `ImageBudget` (pure, tested): at most 4096 × 4096 pixels' worth, 16 megapixels, and no side over Metal's 16384. A bigger one keeps its top-left part, never scaled: a side under 4096 stays whole and the other is cut to fit; with both longer, 4096 × 4096. `ViewerRenderer.renderImage` limits its target, which crops Copy View because the scene is laid out from the top-left; Copy Source crops the area image; reference images are cropped when decoded; a recent capture keeps its frame's top-left part. This keeps a selection at 6400% from asking for a texture beyond the GPU's limit or a gigabyte of memory.
- **Output:** the clipboard gets PNG and TIFF; Save writes a PNG with the source display's color profile embedded, named like macOS screenshots (`Screen Loupe View 2026-09-24 at 14.20.05.png`), into the folder used last (Desktop at first). A short confirmation ("View copied") appears at the bottom of the Viewer.
- **Commands:** Edit > Copy View `⌘C`, Copy Source `⇧⌘C`; ⌘C is the standard `copy:` sent to the first responder, so a focused text field copies its text and `AppController`, the app delegate, turns it into Copy View otherwise (the item reads Copy then); the Edit menu has the standard Undo, Cut, Paste and Select All for the text fields; File > Save View… `⌘S`, Save Source… `⇧⌘S`; the Viewer toolbar's Copy and Save buttons; Copy View and Copy Source in the menu bar item. They are enabled while there is a frame.

## 3. Coordinate-system strategy

Five systems, each with its own type, so the compiler refuses to mix them:

| Type | Unit | Origin / axis | Where it comes from |
|---|---|---|---|
| `GlobalPoint` / `GlobalRect` | points | bottom-left of the primary display, y up; can be negative | AppKit window frames, `NSScreen.frame` |
| `QuartzRect` | points | top-left of the primary display, y down | `SCDisplay.frame`, `CGDisplayBounds` |
| `DisplayLocalRect` | points | top-left of a given display, y down | `SCStreamConfiguration.sourceRect` |
| `SourcePixel` | pixels | top-left of the captured image | frame buffer, Pixel Inspector, Capture Source |
| `ViewerPoint` | view points | view bounds | mouse events in the Viewer |

`DisplayCoordinateConverter` is pure value-type logic over a `DisplayLayout`: a list of `DisplayInfo(id, globalFrame, scale)`, where the primary display is the one at global origin (0, 0). An adapter builds the layout from `NSScreen.screens`; the tests build it by hand. The converter does:

- global ↔ Quartz: `quartzY = primaryHeight − (globalY + height)`;
- global rect → owning display (the largest intersection) → display-local rect;
- display-local points ↔ source pixels (× that display's scale);
- **snapping:** the Capture Area rect is snapped to the backing-pixel grid of its display (0.5 pt steps on a 2× display, 1 pt on 1×). Without it a rect at x = 10.25 pt on 2× would be resampled and blur the capture;
- the Viewer transform, which lives in `ZoomPanController`: viewer point ↔ source pixel, given zoom, pan and the view's backing scale.

**Zoom is defined as drawable pixels per source pixel** (Photoshop convention). 800% always means one source pixel is exactly 8×8 device pixels, whatever the scale of the source and Viewer displays, so the crispness guarantee holds in every display combination. With two Retina displays 100% is true size; with a Retina source and a non-Retina Viewer, 100% is twice the physical size but still pixel-exact.

**A Capture Area straddling two displays** is allowed. The stream captures the display holding the larger share; the part on the other display shows as empty in the Viewer.

**Arrow-key step** is one pixel of the display the area is on — 0.5 pt on a 2× display.

The Capture Area frame is drawn **outside** the captured rect: the window is the rect plus a border and handle margin. The user sees exactly the captured pixels inside the line. The frame never shows up in the capture either way, because it is excluded.

## 4. Windows and interaction

- **Capture Area:** a borderless, non-opaque `NSPanel` at `.statusBar` level that joins all Spaces, so it stays on top across Spaces and full-screen apps.
  - The interior is fully transparent. **Clicks inside go through to the app underneath**, so hover states in Figma or Safari stay live. The frame therefore carries explicit handles:
    - **At rest** only the 1 pt line and a muted size label are shown, so nothing covers the inspected interface.
    - **On hover** eight square resize handles appear on the corners and edge midpoints, and a grip tab with the size in pt and px appears above the frame. The tab and the line move the frame; the handles resize it. Cursors: resize arrows over handles, an open hand over the line and the tab, a closed hand while dragging.
    - **Grabbing the line:** on hover a translucent 5 pt band appears outside the whole line. The band is the move zone, so the user sees exactly where the frame can be taken.
    - **Tab placement:** above the frame → below it → inside the frame at its top (with a shadow). Horizontally it is centred on the frame but never closer than 6 pt to a screen edge. A change of placement is animated (~150 ms).
    - **At-rest size label:** below the frame on the right; inside the bottom-right corner when there is no room below.
    - **Position box and pin:** the L T R B box sits right of the frame, or left when it would leave the screen, and fades in with the tab. A square pin button sits right of the tab, then the raise and pick buttons (all left of the tab at the screen's edge, the pin next to it); a pinned frame hit-tests only these three, so it can't be moved, resized or nudged, and hides its band and handles. The raise button calls `WindowManager.showViewer`, which activates the app and orders the Viewer front.
    - **Snapping:** with ⌘ held during a drag, `EdgeSnapping` (pure, tested) moves each dragged edge — or, for a move, the edge closest to a target — onto a window's or a display's edge within 8 pt; then the result is snapped to pixels as usual. Only targets that overlap the edge along it count. The windows come from `CGWindowListCopyWindowInfo` (ordinary layer-0 windows of other apps, front to back, Quartz frames converted by `DisplayCoordinateConverter`), read once per drag. The list, unlike the deprecated `CGWindowListCreateImage`, reads no pixels.
    - **Fit to a window:** `WindowPicker` covers each display with a transparent panel above the frame that takes every click (`ignoresMouseEvents` set to false explicitly), so no click reaches the app underneath and no Accessibility permission is needed. It tints the frontmost window under the pointer (`EdgeSnapping.window(at:in:)`), a click makes the area that window, and Escape, a right click, a click on no window or the app losing focus cancels. The panels belong to the app, so the capture already excludes them.
    - Placement, hit zones and resize math are pure functions in `Geometry/OverlayLayout.swift`, covered by tests.
  - It can become key (a borderless window can't by default, so the panel overrides this) for the arrow-key nudges.
  - Minimum size: 64×64 pt. A smaller area saved by an earlier version grows to it on launch.
- **Viewer:** a regular titled, resizable `NSWindow` with an `NSToolbar` (presets, zoom value) and full-screen support.
  - **Pan:** drag, two-finger scroll and horizontal scroll.
  - **Zoom:** `Cmd` + wheel, pinch, `+`/`-`, around the cursor.
- **App mode:** a regular app with a Dock icon and a main menu, plus the menu bar item. Closing the Viewer also hides the Capture Area, so no frame is left on screen without its Viewer; the app keeps running in the menu bar. Show Viewer (menu bar, Window menu, Dock icon) brings both back. Show/Hide Capture Area still toggles the frame on its own.
- **Zoom entry and memory:** the toolbar's zoom field takes a typed percentage. The zoom is saved when the Viewer closes or the app quits and restored on the next first frame, centred.
- **Sizes in pt and px:** the grip tab shows both at once (`220 × 150 pt · 440 × 300 px`) instead of a switch; arrow keys step by one pixel of the area's display.
- **Keep Viewer on Top:** a pin toggle at the right of the Viewer toolbar and a checkmarked item in the Window menu and the menu bar item. On, the Viewer is a `.floating` window: it stays above other apps' windows while they are active, and still below the Capture Area frame (`.statusBar`). It doesn't reach into another app's macOS full-screen Space: only a non-activating panel (as the Capture Area is) or an app without a Dock icon may, and each costs more than it gives — hiding the Dock icon and the menu on every toggle, or a Viewer that doesn't take the menu's shortcuts. A window stretched over the screen serves the same purpose. The choice is persisted.
- **Permission flow:** `PermissionsManager` checks with `CGPreflightScreenCaptureAccess`. If access is missing, the Viewer shows an explanation panel with **Grant Access** (`CGRequestScreenCaptureAccess`), **Open System Settings** (the Screen Recording pane) and a restart hint, instead of an empty view. The check runs again when the app becomes active.
- **Sandbox:** off, with the hardened runtime on. The Mac App Store needs it.
- **Persistence:** a `Codable` settings struct in `UserDefaults`, covering the Capture Area rect (global points), zoom, overlays, pinned colours, the screenshot folder and every Settings choice. A key that is missing or unreadable (written by an older or a newer version) decodes to its default, and the rest loads as saved. The Viewer frame is kept by AppKit (`setFrameAutosaveName`).
- **Inspected pixel:** the pixel under the mouse in the Viewer, or — when the mouse is elsewhere — the one under the real cursor inside the Capture Area (a global mouse monitor, no permission needed). `PixelInspector` reads its colour straight from the latest frame's `CVPixelBuffer`; `ColorSample` converts it to sRGB for HEX and RGB, matching design tools and CSS, and keeps the native display value.
- **Crosshair and cursor** (toolbar toggle, on by default; its ▾ sets `Settings.pointerStyle`): marks the pixel under the real cursor inside the Capture Area — not the mouse over the Viewer, whose pointer already marks the spot. The crosshair is lines across the Viewer through that pixel and a box around it; the cursor is `NSCursor.arrow` at its usual size, its hot spot on the centre of the outlined pixel. Both are drawn white under the accent colour so they read on any content, by a transparent `ViewerOverlayView` over the image, placed with `ZoomPanState.imageRect`, so they stay out of Copy View. Original Cursor in the Capture draws nothing: `ScreenCaptureManager.showsCursor` turns on `SCStreamConfiguration.showsCursor` with a configuration update, no restart. `Settings.capturesCursor` decides it: that style, the pointer shown, and the Color Meter not expanded — while the eyedropper is on, the stream leaves the pointer out, so the Color Meter never samples it.
- **Pixel grid** (toolbar toggle): drawn in the fragment shader from the threshold zoom on (8× by default). The first drawable pixel of every source pixel becomes the line, so lines sit exactly on pixel boundaries and are one pixel wide; dark over light content, light over dark.
- **Color Meter** (toolbar toggle): a 250 pt panel right of the image — swatch; HEX, CSS `rgb()`, SwiftUI, AppKit, native value and position, each with a copy button; pinned colours (the last 8, newest first, persisted), each copyable and removable. While it is open the Viewer's cursor is an eyedropper and a click without dragging pins the colour under it; dragging still pans.
- **Clipping:** the image area clips its subviews (`clipsToBounds`, off by default since macOS 14), so the overlay's reference frame and ruler never draw over the side panels.
- **Copying a part of the view:** `SelectionController` holds the Select tool, its selection and an Option-drag's region; the math is pure and tested (`PixelSelection`, `ViewRegion` in `Geometry/ViewerSelection.swift`). A press goes to an Option-drag first, then the ruler, then the Select tool while it is on, then the reference layers, then panning. The selection is kept in source pixels from the Capture Area's top-left, so it stays on its pixels while the Viewer pans and zooms, and is cut to the area when the area shrinks. When the area's left or top edge is dragged, `ViewerView` hands the same `AreaResizeTracker` shift to the zoom and to everything placed from the area's top-left — the selection, a pinned ruler and the reference layers (`PixelSelection.followingAreaOrigin`, `CornerRuler.followAreaOrigin`, `ReferenceStack.followAreaOrigin`) — so all of them stay on their screen pixels. Copy View with a selection renders the same scene with `ZoomPanState.cropped(to:)`: a viewport the selection's size at the current zoom, so the part beyond the window is included. An Option-drag's region is free, in viewport pixels; Copy View renders just that region, the scene's offset moved by its corner. With the tool on, Space held down makes a drag pan; a tap still freezes, on key-up. The real Space state is read again on mouse-down, since a key-up can be lost to another window.
- **Freeze frame:** `FrameStore.isFrozen` drops incoming frames and keeps the frozen one when the stream stops or restarts (a move to another display), so the renderer, the Color Meter and Copy/Save all keep the frame that was showing without any other code knowing about it. The stream keeps running and follows the Capture Area; closing the Viewer unfreezes. A delayed freeze is a one-shot timer in `WindowManager`; the pause button and Escape cancel it, and it freezes through the same path as Space. `FrozenIndicatorView` shows hidden, frozen (with the hint after a freeze from another app) or the countdown, redrawn 30 times a second while it runs.
- **Recent Captures:** `RecentCaptures` (observable, main actor) holds the last four, newest first, and which one the Viewer shows; `RecentCapturesPanel` is the SwiftUI panel, with a Live row on top that is chosen while no capture shows and shows the live view when clicked. A capture keeps the frame, not the copied image: `CapturedFrame.copiedForKeeping` copies the stream's buffer into an IOSurface-backed, Metal-compatible buffer of its own — the stream reuses a small pool of buffers, and holding four would starve it — cut to the copied source pixels by `CaptureGeometry.cropped(toArea:)` — the selection, or `ViewRegion.sourceRect` of the region or, for a view, of the whole viewport; only Copy Source keeps the whole area — and to `ImageBudget` by `CaptureGeometry.fittedToImageBudget` (all pure, tested). It also keeps the zoom, pan and selection it was taken with and a small thumbnail of the copied image. `ViewerContentView.captureKeeper` takes all of that when the command runs; a copy adds it at once, a save once the file is written, and nothing is kept while a capture shows. Showing one sets `FrameStore.shownCapture`, which `latestFrame` returns before the live frame, so the renderer, the Color Meter, Copy View and Copy Source take the capture without knowing about it, as they take a frozen frame. Live frames are still stored meanwhile, but `WindowManager` doesn't pass them on, so the capture stays put and the live view is current when it comes back. Switching puts the zoom, pan and selection of the picture being left away (in the capture, or for the live view) and brings back those of the next, and forgets the area's origin, so the switch doesn't count as an edge drag. While a capture shows, `WindowManager` ignores Freeze and stops following the real cursor; the toolbar disables Freeze and the pointer. A second `FrozenIndicatorView` in its capture state draws the purple border and the label, and hides the frozen indicator of the live view under it.
- **Ruler:** `CornerRuler` (pure, tested) keeps the ruler either in drawable pixels, fixed in the Viewer, or pinned in source pixels with the arm lengths the user set; its placement is always whole source pixels. An arm never looks shorter than 32 pt: the shortest arm in source pixels is recomputed from the zoom, and a pinned ruler keeps its set lengths to return to. `RulerController` hit-tests and drags it; the overlay draws it. An unpinned ruler is fixed in the Viewer but snapped to source pixels, so under a moving image it would jump from cell to cell: it hides on every zoom/pan change and fades back in (ease-out, 0.12 s) 0.12 s after the last one. The pin button and move band stay 0.6 s after the pointer leaves. Its corner is clamped into the viewport, since the drawable-pixel position saved on one display can lie beyond the Viewer on another. Presses go to the ruler first, then to reference layers, then to panning.
- **References:** `ReferenceStack` (pure, tested) holds the layers top first, with place and scale in source pixels from the Capture Area's top-left, so a layer stays on the pixels it was aligned with. The renderer draws each layer as a quad after the frame, from a texture made by drawing the image into the Viewer's colour space (premultiplied BGRA, remade when either changes), so a matching colour has the same values as the capture. Normal is premultiplied source-over at the layer's opacity. Difference is computed in the fragment shader against the live frame texture, not against the layers below: what it answers is "does the screen match the design". The panel is SwiftUI in an `NSHostingView`, observing `ReferencesController`; `SidePanelStack` lays the column out by hand, top down, and the hosting view takes the size it is given (`sizingOptions = []`). The Color Meter sits in a scroll view, so a short column scrolls it rather than squeezing it. Widening the column (250–320 pt) scales everything in it by each panel multiplying its own fonts, sizes and spacings (`ColorMeterPanel.scale`, `PanelStrip.scale`, `ReferencesController.scale`); not a drawing transform, because SwiftUI hit-tests without an ancestor's bounds transform, and Auto Layout and scroll views inside a view with scaled bounds lay out and draw wrongly. The References panel draws its slider and blend switch itself, so they scale too. Rows reorder with the list's own move (`onMove`); a row holds only icon buttons, and the settings live apart in the Layer section, so no control starts a drag. An image past `ImageBudget` is cropped to its top-left part when it is decoded, and a layer imported before that takes the cropped size when it loads. A layer's image is decoded, and its texture made, off the main thread; the layer shows once they are ready, so a large design export doesn't stall the Viewer.
- **Project:** `ProjectStore` keeps `project.json` (the reference stack and the ruler) and copies of the reference images in Application Support, written 0.4 s after the last change and on quit, read at launch. Everything else that persists stays in `Settings`.
- **One instance:** at launch `AppController` looks for another running app with the same bundle id; if there is one, it opens that app's bundle, which reopens it and brings its Viewer forward, and quits before registering shortcuts or touching settings.
- **Global shortcuts:** Carbon `RegisterEventHotKey`. It works from any app and needs no Accessibility permission, unlike an `NSEvent` global key monitor. Freeze defaults to F13 with no modifiers, which `RegisterEventHotKey` takes like any other; `ShortcutRules` (pure, tested) allows F13–F19 alone for that action only. `Shortcuts` saves a cleared shortcut as `null`, so a key missing from saved settings — an action added later — gets its default, while a cleared one stays cleared.
- **Commands:** `AppController` is the app delegate, so it ends the responder chain. The menus target it; the Viewer's toolbar commands (Freeze, Ruler, Copy, Save, Keep on Top) and Space in the Viewer send their command with no target (the toolbar's toggles are settings and change them directly), which reaches it from any window, and its `validateMenuItem` enables and checks the menu forms. Command selectors avoid AppKit's own actions (the ruler's is `toggleMeasuringRuler:`, since `toggleRuler:` belongs to `NSText` and a field being edited would take it). A toolbar toggle shows its model's state, not its own click: it is reset before the command and set by the model after.
- **Settings to views:** a component subscribes to the settings it depends on with `SettingsStore.observe(\.keyPath)`: called at once and after every change of that value, synchronously. Several settings used together are one computed `Equatable` property (`Settings.viewerStyle`, `sidePanelLayout`, `frameStyleSettings`). Observation (`withObservationTracking`) can't do this: the store has one stored property, the whole `Settings` struct, so every reader would be told about every change. The SwiftUI Settings window observes the store as usual.

## 5. Components and project structure

The app is split into components with one job each; none of them is a catch-all view controller.

| Component | Responsibility |
|---|---|
| `AppController` | The app delegate: lifecycle, the app's commands (end of the responder chain), wiring |
| `WindowManager` | The Capture Area and Viewer windows and how they relate |
| `CaptureAreaController`, `CaptureOverlayWindow`, `CaptureOverlayView` | The frame above the screen: drawing, drag/resize, size labels, arrow keys |
| `WindowPicker`, `ScreenWindows` | Fit to a window: picking the window under the pointer; the other apps' window frames, also for snapping |
| `ScreenCaptureManager`, `FrameStore` | The ScreenCaptureKit stream, filter, display switching, recovery; the latest frame, or the recent capture shown |
| `ViewerWindowController`, `ViewerToolbar` | The Viewer window, the permission view swap, and its toolbar |
| `ViewerContentView` | The Viewer's content: image, overlays, status, toast, side column, and their wiring |
| `ViewerView`, `ViewerRenderer`, `ViewerOverlayView` | Rendering the magnified image (on screen and offscreen for Copy View), the crosshair and the cursor |
| `ZoomPanController` | Zoom/pan state and gestures |
| `PixelInspector`, `ColorMeterPanel` | The inspected pixel, its colour and the pinned colours |
| `RulerController`, `CornerRuler` | The corner ruler: state, dragging, pinning |
| `SelectionController`, `PixelSelection`, `ViewRegion` | The Select tool's selection and Option-drag regions |
| `ReferencesController`, `ReferencesPanel`, `ReferenceStack` | Reference layers: the stack, images, the mouse in the Viewer, the panel |
| `RecentCaptures`, `RecentCapturesPanel` | The last four copies and saves, which one shows, the panel |
| `SidePanelStack` | The side column: the Color Meter over References or Recent Captures, one expanded |
| `ProjectStore` | The working project: references, their images and the ruler |
| `ExportController`, `ScreenshotExporter` | Copy and Save: the commands, the save panel, confirmations; Capture Source images, clipboard and PNG |
| `DisplayCoordinateConverter` | All coordinate conversions |
| `PermissionsManager` | Screen Recording permission |
| `GlobalShortcuts`, `Settings` | System-wide shortcuts; persisted state and preferences |

```
ScreenLoupe.xcodeproj           file-system-synchronized groups; the app and test targets
ScreenLoupe/
  App/          AppController (app delegate), ScreenLoupeApp (main), WindowManager,
                StatusItemController, Settings, GlobalShortcuts, MainMenu, ProjectStore
  Capture/      ScreenCaptureManager, FrameStore, PermissionsManager
  Overlay/      CaptureAreaController, CaptureOverlayWindow, CaptureOverlayView, OverlayStyle,
                WindowPicker, ScreenWindows
  Viewer/       ViewerWindowController, ViewerContentView, ViewerView (MTKView), ViewerRenderer, ViewerShaders,
                ViewerToolbar, ViewerOverlayView, ColorMeterPanel, CaptureStatusView,
                PermissionView, ZoomPanController, PixelInspector, RulerController, SelectionController,
                ReferencesController, ReferencesPanel (SwiftUI), RecentCaptures, RecentCapturesPanel (SwiftUI),
                SidePanelStack
  Export/       ExportController, ScreenshotExporter
  Settings/     SettingsWindowController, SettingsViews (SwiftUI), ShortcutRecorder
  Geometry/     DisplayCoordinateConverter, DisplayLayout, coordinate types, ZoomPanMath,
                OverlayLayout (frame layout, hit zones, position box, pin), EdgeSnapping, ColorMath,
                LenientDecoding, SizeText, ViewerWindowFit, CornerRuler, ReferenceLayers,
                ViewerSelection (Select tool, Option-drag), ShortcutRules, ImageBudget
  Resources/    Assets.xcassets (the app icon, drawn by scripts/make_icon.swift); Info.plist is generated from build settings, no entitlements file
ScreenLoupeTests/
  Geometry/     converter, snapping, display layouts, edge-drag framing, Copy Source placement,
                zoom/pan math, overlay layout, colour math, window fit, ruler, reference layers
                and their lenient decoding, selection and region math, shortcut rules, image size limit
```

`Geometry/` imports only Foundation and CoreGraphics, never AppKit. That keeps it fully unit-testable and stops window state from leaking into the math. The test target is hostless: it compiles the Geometry files itself and never launches the app, so tests never trigger the Screen Recording prompt.

## 6. Risks

| # | Risk | Mitigation |
|---|---|---|
| 1 | **Lag while dragging.** `updateConfiguration` is asynchronous, so the Viewer could trail the frame by a few frames during a drag. | Coalesced updates plus trusting each frame's own `contentRect`. If it becomes visible, the fallback is to capture the whole display and crop in the shader — moving becomes instant, at the cost of full-display surfaces in memory (a 5K display is about 59 MB per frame). |
| 2 | **Blurry capture from sub-pixel rects.** | Rects are snapped to the display's backing grid, with `width`/`height` equal to the pixel size and `captureResolution = .best`. Checked by comparing Capture Source against a `screencapture -R` crop. |
| 3 | **Mixed displays:** different scales, negative coordinates, a rect straddling two displays, hot-plugging. | A pure converter with table-driven tests; the stream follows the display with the larger intersection; the stream is rebuilt on screen-parameter changes and stream errors. |
| 4 | **Self-exclusion.** Our app might be missing from `SCShareableContent.applications`. | Check at startup. Fallback: `excludingWindows` with our windows matched by `windowNumber`. |
| 5 | **Screen Recording permission (TCC).** An ad-hoc signature can drop the grant on every rebuild; recent macOS versions may ask the user to reconfirm the permission from time to time (to be verified on macOS 27); `CGPreflightScreenCaptureAccess` may report a stale result until relaunch. | Sign with a stable identity (Apple Development for debug builds, Developer ID or App Store for releases); show a restart hint in the permission panel; a `userDeclined` stream error switches the Viewer to the permission panel (§2.1). |
| 6 | **Color accuracy of HEX/RGB.** The frames are in the display's color space (for example Display P3), so HEX values differ from sRGB design tokens. HDR/EDR content complicates this further. | Capture SDR. The Inspector converts the pixel to sRGB with ColorSync/`CGColor` conversion and shows the native value next to it. |
| 7 | **Fractional zoom** (for example 250%) with nearest-neighbor gives alternating 2- and 3-pixel columns. | Accepted: the integer presets are exact, and crispness is promised at integer zoom. |
| 8 | **Swift 6 concurrency** around ScreenCaptureKit callbacks and `CVPixelBuffer` (not `Sendable`). | Confine the buffers to `FrameStore` behind a lock; mark it `@unchecked Sendable` with a written invariant; everything else is `@MainActor`. |
| 9 | **A reference that should match doesn't turn black in Difference.** The design export is sRGB, the capture is in the display's colour space; an image exported at another scale lands between pixels. | The texture is drawn into the Viewer's colour space before blending; the layer's place is whole source pixels and its scale is set exactly in the panel. |
| 10 | **Memory for reference layers.** Up to 10 images, each kept decoded and as a texture. | Accepted for design exports of screen size; textures are dropped as soon as a layer is deleted or hidden. |
| 11 | **A damaged or foreign `project.json`.** | An unreadable setting of a layer keeps its default, an unreadable layer is dropped, and only an unreadable file starts an empty project; layers whose image file is gone are dropped at launch. |

## 7. Verification

**Unit tests** cover the deterministic logic, where Retina and multi-display bugs hide: coordinate conversion, snapping, zoom/pan math, pixel lookup, export geometry (where the image sits in Copy Source), the framing when the area is resized by its left or top edge (`AreaResizeTracker`), overlay layout, colour math, the ruler, reference layers, lenient decoding of saved data, the Select tool's and Option-drag's math, which shortcuts are allowed, and the image size limit. The Metal path (the screen and Copy View) can't be unit-tested in the hostless test target; step 11 below checks it. The converter tests include:

- a 1× and a 2× display side by side;
- a display placed left of or above the primary one (negative global coordinates);
- a display arrangement with vertical offsets;
- a rect straddling two displays;
- snapping on 1× and 2×;
- viewer ↔ source mapping at integer and fractional zoom, including zoom-around-cursor invariance.

There are no UI or timing-based tests. Window behaviour, live capture, permissions and multi-display setups are checked by hand with the acceptance scenario below, on a Retina display and, where possible, a second display with another scale.

**Acceptance scenario.** It passes when every step works reliably:

1. Launch the app. Without the permission, the Viewer explains why it is needed and offers Grant Access and Open System Settings.
2. A Capture Area frame appears on screen.
3. The Viewer opens next to it: right of it, else left, else below, else above, within the screen.
4. Place the Capture Area over a small button in Safari, Figma or Xcode; the Viewer shows it.
5. Zoom to 800%: individual crisp pixels, no interpolation blur.
6. With the magnified image larger than the Viewer, drag it inside the Viewer; the Capture Area stays where it is.
7. Move the Capture Area to another element: the Viewer shows the new place immediately, with the same zoom and framing.
8. Resize the Capture Area: the Viewer updates immediately, and pixels already visible stay where they are.
9. Point at something inside the Capture Area with the real cursor: the crosshair marks that pixel in the Viewer.
10. Hover over a pixel in the Viewer: the Color Meter shows its position and HEX; a click pins it.
11. Copy View and paste: exactly the magnified viewport, also at 50% zoom, with the grid (when included) and a Difference layer. Copy Source and paste: the source area at native resolution, unmagnified.
12. Move the Viewer over the Capture Area: the Viewer does not capture itself.
13. Drag the Capture Area to a second display: capture keeps working correctly.
14. Hover the frame: the L T R B box sits beside it and flips sides at a screen edge. Pin the frame: it neither moves, resizes nor nudges; unpin it. Click inside the frame on a maximized window so it covers the Viewer, then the button beside the pin: the Viewer comes forward.
15. Press Space in the Viewer: the image freezes with the blue border; Copy View copies the frozen frame; Space resumes.
16. Size Window to Area at 800% on a small area: the whole area shows without panning; on a large area the window stops at the screen's edges.
17. Turn the ruler on, move it, stretch and flip an arm, pin it, zoom and pan: a pinned ruler stays on its pixels and keeps its lengths; an unpinned one stays in place.
18. Add a PNG export of the inspected UI as a reference, align it, switch to Difference: matching pixels are black. Pin it: a drag pans the image. Copy View includes the layer.
19. Quit and relaunch: the references, the ruler, the frame's pin and the panels come back.
20. Hold the mouse down on a button in another app and press F13: the Viewer freezes with "Frozen by F13 from …" at its bottom; let go, Copy View copies the pressed state. F13 again resumes.
21. From the ▾ beside the pause button, or View › Freeze Later, choose Freeze in 3 Seconds, go to another app and press and hold: the countdown runs over the live view and the Viewer freezes at zero. Escape during a countdown stops it.
22. ⌥-drag a rectangle in the Viewer and paste: exactly that region at the current zoom. A plain drag still pans.
23. Turn on Select, drag a selection, resize it by a handle and move it: it snaps to screen pixels and the label gives its size and place. Pan it partly out of the window, ⌘C and paste: the whole selection. Space-drag pans; Escape clears the selection. Drag the Capture Area's left edge: the selection, a pinned ruler and the reference layers stay on their pixels. View › Select (⌘E) turns the tool on and off. With the tool off, ⌘A turns it on and selects the whole area; ⌘C copies all of it at the current zoom.
24. Zoom to 6400% and select 400 × 300 px, ⌘C and paste: a 4096 × 4096 image of the selection's top-left part, no beep. Add a reference image over 16 megapixels: its top-left part shows at full resolution.
25. Copy the view at 800%, ⌥-drag a region, Copy Source, then open Recent Captures: the Live row chosen, and three rows under it, newest on top, with their kind, size and time. Click one: the Viewer shows it with the purple border, as it was copied; zoom, measure, pick a colour with the Color Meter expanded (the panel a strip), copy — no new row. Escape or the Live row: back to live as it was left. A fifth copy pushes out the oldest; opening References closes Recent Captures.
26. With the pointer's ▾ choose Cursor: an arrow at its usual size points at the pixel under the real cursor, and a copy has none. Choose Original Cursor in the Capture: the real pointer shows in the pixels, grows with the zoom and is in copies; expand the Color Meter: it disappears and the menu says it is paused; collapse it: it comes back.
27. Drag the Capture Area's left edge near a window's edge: nothing snaps. Hold ⌘ and drag again: the edge snaps onto the window's edge, from inside and from outside, and to a display's edge; a move with ⌘ snaps the closest edge. Arrow keys don't snap.
28. Click the window button beside the tab (or Window › Fit Capture Area to Window…, or ⌃⌥⌘W from another app) with the Simulator open: the window under the pointer is tinted; a click on the Simulator makes the area exactly its window, and the Simulator gets no tap. Escape cancels. With the Viewer closed, the shortcut and a pick open it.

## 8. Open

1. The Mac App Store as a second channel, after the notarized download on GitHub Releases that comes first: it needs the sandbox (§4), checked on a real build.
