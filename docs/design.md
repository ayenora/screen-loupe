# Screen Loupe — Technical Design

Status: **approved.** This covers TASK.md §24 steps 1–6: the ScreenCaptureKit API, the capture/render pipeline, the coordinate-system strategy, the project structure, the risks and the implementation plan. What is still open is listed in [Open](#8-open).

API facts below come from the macOS 26.2 SDK headers (`ScreenCaptureKit.framework/Headers`), not from memory.

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
| `SCStreamConfiguration.showsCursor` | 12.3 | On by default. We turn it **off**: the cursor would sit over the pixels being inspected. |
| `SCStream.updateConfiguration(_:)` | 12.3 | Changes the source rect and output size **without restarting** the stream. |
| Sample buffer attachments | 12.3 | `SCStreamFrameInfo.status` (`complete` / `idle` / `blank` / …), `.contentRect`, `.scaleFactor`, `.dirtyRects`. Idle frames carry no image — the last frame stays on screen. |
| `SCScreenshotManager.captureImage(contentFilter:configuration:)` | 14.0 | One-shot capture with the same filter; not needed for the MVP (see §2.4). |
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
        │  ViewerRenderer: one textured quad, transform from ZoomPanController
        ▼
MTKView (drawn on each new frame and on every zoom/pan change)
```

### 2.1 Stream

- **One stream for one display at a time.** It captures the display that holds the larger part of the Capture Area.
- **Pixel format:** BGRA, SDR, in the source display's own color space (ScreenCaptureKit's default). The Viewer's layer is tagged with that color space, so the system color-matches when the Viewer sits on a display with another profile; on the same display the values pass through unchanged. The Pixel Inspector converts to sRGB for display (§4).
- **Self-exclusion:** `excludingApplications: [our SCRunningApplication]`, found in `SCShareableContent.applications` by `processID`. This removes every window we own, including any we add later (Preferences, alerts), with no window bookkeeping.
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

### 2.3 Rendering

- `MTKView` with `isPaused = true` and `enableSetNeedsDisplay = false`: the view calls `draw()` itself, at most once per main run-loop turn, when a new frame arrives, the zoom/pan changes or the window is shown again. An idle screen costs nothing. (With `setNeedsDisplay` nothing was drawn any more after the window had been closed and reopened.)
- One vertex/fragment shader pair draws the frame texture as a quad. The quad's placement in the viewport comes from `ZoomPanController`.
- The shaders are compiled at launch from source (`ViewerShaders.swift`, `makeLibrary(source:)`), not from a `.metal` file: Xcode 26 ships the Metal compiler as a separate download, and runtime compilation keeps the project buildable without it.
- **Sampler:** `magFilter = .nearest`, `minFilter = .linear`. Magnification is always nearest-neighbor, so pixels are crisp squares; zooming out below 1:1 (for example Fit on a large area) is linearly filtered. Without mipmaps that still aliases below 50%; acceptable for a loupe, whose point is magnification.
- **Stable framing** (docs/product.md, principle 2): Fit is applied once to the first frame and then only on request. A resize of the window or the Capture Area keeps the zoom; `ZoomPanState.resizingContent` shifts the offset by the move of the area's top-left corner, so pixels already visible stay put when the left or top edge is dragged. Clamping keeps an image smaller than the viewport wholly inside it without re-centring it.
- **Pixel-exact placement:** the pan offset is snapped to whole drawable pixels. At an integer zoom every source pixel then covers exactly N×N drawable pixels, so there are no uneven columns and the pixel grid lines up.
- **The pixel grid (post-MVP)** is drawn in the same shader from the source-pixel coordinate. It stays aligned by construction.

### 2.4 Screenshots

- **Capture Source:** the latest frame's `CVPixelBuffer` is converted to a `CGImage` tagged with the frame's color space, then written as PNG or placed on the pasteboard. It is exactly the source pixels the Viewer shows, at native resolution. A new `SCScreenshotManager` capture isn't needed, and it could differ from what's on screen.
- **Capture View:** CoreGraphics draws the frame into an image of the drawable's size with the placement the renderer uses (`ZoomPanState.imageRect`), the Viewer's background, and no interpolation when magnifying. At integer zoom every source pixel is an exact N×N block (checked pixel by pixel). The grid, once it exists, is included only when `Include pixel grid in screenshot` is on.
- **Output:** the clipboard gets PNG and TIFF; Save writes a PNG with the source display's color profile embedded, named like macOS screenshots (`Screen Loupe View 2026-09-24 at 14.20.05.png`), into the folder used last (Desktop at first). A short confirmation ("View copied") appears at the bottom of the Viewer.
- **Commands:** Edit > Copy View `⌘C`, Copy Source `⇧⌘C`; File > Save View… `⌘S`, Save Source… `⇧⌘S`; the Viewer toolbar's Copy and Save buttons; Copy View and Copy Source in the menu bar item. They are enabled while there is a frame.

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

**Zoom is defined as drawable pixels per source pixel** (Photoshop convention). 800% always means one source pixel is exactly 8×8 device pixels, whatever the scale of the source and Viewer displays — the crispness guarantee of TASK.md §4 holds in every display combination. With two Retina displays 100% is true size; with a Retina source and a non-Retina Viewer, 100% is twice the physical size but still pixel-exact.

**A Capture Area straddling two displays** is allowed. The stream captures the display holding the larger share; the part on the other display shows as empty in the Viewer.

**Arrow-key step** follows the pt/px switch: 1 pt or 1 px. Until the switch exists (post-MVP), the step is 1 px of the display the area is on — 0.5 pt on a 2× display.

The Capture Area frame is drawn **outside** the captured rect: the window is the rect plus a border and handle margin. The user sees exactly the captured pixels inside the line. The frame never shows up in the capture either way, because it is excluded.

The unit tests cover:
- a 1× and a 2× display side by side;
- a display placed left of or above the primary one (negative global coordinates);
- a display arrangement with vertical offsets;
- a rect straddling two displays;
- snapping on 1× and 2×;
- viewer ↔ source mapping at integer and fractional zoom, including zoom-around-cursor invariance.

## 4. Windows and interaction

- **Capture Area:** a borderless, non-opaque `NSPanel` at `.statusBar` level that joins all Spaces, so it stays on top across Spaces and full-screen apps.
  - The interior is fully transparent. **Clicks inside go through to the app underneath**, so hover states in Figma or Safari stay live. The frame therefore carries explicit handles:
    - **At rest** only the 1 pt line and a muted size label are shown, so nothing covers the inspected interface.
    - **On hover** eight square resize handles appear on the corners and edge midpoints, and a grip tab with the size in pt and px appears above the frame. The tab and the line move the frame; the handles resize it. Cursors: resize arrows over handles, an open hand over the line and the tab, a closed hand while dragging.
    - **Grabbing the line:** on hover a translucent 5 pt band appears outside the whole line. The band is the move zone, so the user sees exactly where the frame can be taken.
    - **Tab placement:** above the frame → below it → inside the frame at its top (with a shadow). Horizontally it is centred on the frame but never closer than 6 pt to a screen edge. A change of placement is animated (~150 ms).
    - **At-rest size label:** below the frame on the right; inside the bottom-right corner when there is no room below.
    - Placement, hit zones and resize math are pure functions in `Geometry/OverlayLayout.swift`, covered by tests.
  - It can become key (a borderless window can't by default, so the panel overrides this) for the arrow-key nudges of TASK.md §10.
  - Minimum size: 64×64 pt. A smaller area saved by an earlier version grows to it on launch.
- **Viewer:** a regular titled, resizable `NSWindow` with an `NSToolbar` (presets, zoom value) and full-screen support.
  - **Pan:** drag, two-finger scroll and horizontal scroll.
  - **Zoom:** `Cmd` + wheel, pinch, `+`/`-`, around the cursor.
- **App mode:** a regular app with a Dock icon and a main menu, plus the menu bar item of TASK.md §16. Closing the Viewer also hides the Capture Area, so no frame is left on screen without its Viewer; the app keeps running in the menu bar. Show Viewer (menu bar, Window menu, Dock icon) brings both back. Show/Hide Capture Area still toggles the frame on its own.
- **Keep Viewer on Top:** a pin toggle at the right of the Viewer toolbar and a checkmarked item in the Window menu and the menu bar item. On, the Viewer is a `.floating` window: it stays above other apps' windows while they are active, and still below the Capture Area frame (`.statusBar`). The choice is persisted.
- **Permission flow:** `PermissionsManager` checks with `CGPreflightScreenCaptureAccess`. If access is missing, the Viewer shows an explanation panel with **Grant Access** (`CGRequestScreenCaptureAccess`), **Open System Settings** (the Screen Recording pane) and a restart hint, instead of an empty view. The check runs again when the app becomes active.
- **Sandbox:** off, with the hardened runtime on. Outside the App Store the sandbox only adds security-scoped bookmarks for the persisted screenshot folder. This can be revisited if App Store distribution becomes a goal.
- **Persistence:** a `Codable` settings struct in `UserDefaults`, covering the Capture Area rect (global points), the Viewer frame (`setFrameAutosaveName`), zoom, grid, inspector, screenshot folder and preferences.
- **Inspected pixel:** the pixel under the mouse in the Viewer, or — when the mouse is elsewhere — the one under the real cursor inside the Capture Area (a global mouse monitor, no permission needed). `PixelInspector` reads its colour straight from the latest frame's `CVPixelBuffer`; `ColorSample` converts it to sRGB for HEX and RGB, matching design tools and CSS, and keeps the native display value.
- **Crosshair** (toolbar toggle, on by default; mockup variant A): marks the pixel under the real cursor inside the Capture Area — not the mouse over the Viewer, whose pointer already marks the spot. Lines across the Viewer through that pixel and a box around it, white under orange so they read on any content. A transparent `ViewerOverlayView` over the image, placed with `ZoomPanState.imageRect`.
- **Pixel grid** (toolbar toggle; TASK.md §9): drawn in the fragment shader from 8× on. The first drawable pixel of every source pixel becomes the line, so lines sit exactly on pixel boundaries and are one pixel wide; dark over light content, light over dark. Not included in Copy View.
- **Color Meter** (toolbar toggle; mockup variant C): a 250 pt panel right of the image — swatch; HEX, CSS `rgb()`, SwiftUI, AppKit, native value and position, each with a copy button; pinned colours (up to 12, newest first, persisted), each copyable and removable; the WCAG contrast of the two newest pins. While it is open the Viewer's cursor is an eyedropper and a click without dragging pins the colour under it; dragging still pans.
- **Global hotkeys (post-MVP):** Carbon `RegisterEventHotKey`. It needs no Accessibility permission, unlike an `NSEvent` global monitor.

## 5. Project structure

```
ScreenLoupe.xcodeproj           file-system-synchronized groups; the app and test targets
ScreenLoupe/
  App/          AppController, AppDelegate/main, WindowManager, StatusItemController, Settings
  Capture/      ScreenCaptureManager, FrameStore, PermissionsManager
  Overlay/      CaptureAreaController, CaptureOverlayWindow, CaptureOverlayView, OverlayStyle
  Viewer/       ViewerWindowController, ViewerView (MTKView), ViewerRenderer, ViewerShaders,
                ViewerToolbar, CaptureStatusView, PermissionView, ZoomPanController, PixelInspector
  Export/       ScreenshotExporter
  Geometry/     DisplayCoordinateConverter, DisplayLayout, coordinate types, ZoomPanMath,
                OverlayLayout (frame layout, hit zones, editing), SizeText
  Resources/    Assets.xcassets (the app icon, drawn by scripts/make_icon.swift); Info.plist is generated from build settings, no entitlements file
ScreenLoupeTests/
  Geometry/     converter, snapping, display layouts
  Viewer/       zoom/pan math, zoom around cursor, viewer ↔ source mapping
```

`Geometry/` imports only Foundation and CoreGraphics, never AppKit. That keeps it fully unit-testable and stops window state from leaking into the math.

## 6. Risks

| # | Risk | Mitigation |
|---|---|---|
| 1 | **Lag while dragging.** `updateConfiguration` is asynchronous, so the Viewer could trail the frame by a few frames during a drag. | Coalesced updates plus trusting each frame's own `contentRect`. Measured in stage 5. If it's visible, the fallback is to capture the whole display and crop in the shader — moving becomes instant, at the cost of full-display surfaces in memory (a 5K display is about 59 MB per frame). |
| 2 | **Blurry capture from sub-pixel rects.** | Rects are snapped to the display's backing grid, with `width`/`height` equal to the pixel size and `captureResolution = .best`. Checked by comparing Capture Source against a `screencapture -R` crop. |
| 3 | **Mixed displays:** different scales, negative coordinates, a rect straddling two displays, hot-plugging. | A pure converter with table-driven tests; the stream follows the display with the larger intersection; the stream is rebuilt on screen-parameter changes and stream errors. |
| 4 | **Self-exclusion.** Our app might be missing from `SCShareableContent.applications`. | Check at startup. Fallback: `excludingWindows` with our windows matched by `windowNumber`. |
| 5 | **Screen Recording permission (TCC).** An ad-hoc signature can drop the grant on every rebuild; recent macOS versions may ask the user to reconfirm the permission from time to time (to be verified on macOS 27); `CGPreflightScreenCaptureAccess` may report a stale result until relaunch. | Sign with the existing Apple Development identity; show a restart hint in the permission panel; a `userDeclined` stream error switches the Viewer to the permission panel (§2.1). |
| 6 | **Color accuracy of HEX/RGB.** The frames are in the display's color space (for example Display P3), so HEX values differ from sRGB design tokens. HDR/EDR content complicates this further. | Capture SDR. The Inspector converts the pixel to sRGB with ColorSync/`CGColor` conversion and shows the native value next to it. |
| 7 | **Fractional zoom** (for example 250%) with nearest-neighbor gives alternating 2- and 3-pixel columns. | Accepted: the integer presets are exact, and TASK.md requires crispness at integer zoom. |
| 8 | **Swift 6 concurrency** around ScreenCaptureKit callbacks and `CVPixelBuffer` (not `Sendable`). | Confine the buffers to `FrameStore` behind a lock; mark it `@unchecked Sendable` with a written invariant; everything else is `@MainActor`. |
| 9 | **The Xcode project must be created without XcodeGen/Tuist.** | Write a minimal `project.pbxproj` with synchronized root groups by hand, then check it with `xcodebuild -list` and a build. |

## 7. Implementation plan

Each stage ends with `make build` and the relevant tests passing.

1. **Project skeleton.** `ScreenLoupe.xcodeproj` with the app and test targets, deployment target 14.0, hardened runtime, Apple Development signing → verify: `make build`, `make test`, `make lint`.
2. **Geometry.** Coordinate types, `DisplayLayout`, `DisplayCoordinateConverter`, snapping, `ZoomPanMath` → verify: table-driven unit tests for every case in §3.
3. **App shell and permissions.** `AppController`, `WindowManager`, main menu, status item, `PermissionsManager` with the explanation panel → verify: build; manual — first launch without the grant shows the panel.
4. **Capture Area.** Overlay panel, drag/resize, minimum size, size labels (pt and px), arrow-key nudges, snapping, persistence → verify: build; manual on a 1× and a 2× display.
5. **Capture stream.** `ScreenCaptureManager`, the self-excluding filter, `sourceRect` updates, display switching, `FrameStore`; measure drag latency (risk 1) → verify: build; frames arrive with the expected pixel size (logged); a latency number reported.
6. **Metal Viewer.** Texture cache, the renderer with the nearest sampler, presets and Fit, pan, zoom around the cursor (pinch, `Cmd`+wheel, `+`/`-`) → verify: zoom-math tests; manual — crisp 8×8 pixels at 800%.
7. **Export.** Copy View, Save View, Copy Source; shortcuts; toolbar buttons → verify: an export-geometry test (sizes); manual — paste matches the view.
8. **Persistence and MVP pass.** All state from TASK.md §20 → the owner runs the TASK.md §21/§25 checks.
9. **Post-MVP**, in TASK.md order: Pixel Inspector, pixel grid, the pt/px switch, zoom-percentage entry, Preferences, global hotkeys.

## 8. Open

Nothing is open.
