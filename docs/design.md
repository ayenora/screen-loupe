# Screen Loupe — Technical Design

Status: **approved.** This covers TASK.md §24 steps 1–6: the ScreenCaptureKit API, the capture/render pipeline, the coordinate-system strategy, the project structure, the risks and the implementation plan. What is still open is listed in [Open](#8-open).

API facts below come from the macOS 26.2 SDK headers (`ScreenCaptureKit.framework/Headers`), not from memory.

## 1. ScreenCaptureKit: what the design relies on

| API | Availability | What it gives us |
|---|---|---|
| `SCShareableContent.current` | 12.3 | Displays (`SCDisplay.displayID`, `frame`), windows, running applications. Needs Screen Recording permission. |
| `SCContentFilter(display:excludingApplications:exceptingWindows:)` | 12.3 | Captures one display with every window of the listed apps removed. **This is the self-exclusion mechanism**: we exclude our own app, which removes both the Capture Area overlay and the Viewer. |
| `SCContentFilter.pointPixelScale`, `.contentRect` | 14.0 | The display's pixel-to-point scale and its rect as ScreenCaptureKit sees it. Used to cross-check our own scale math. |
| `SCStreamConfiguration.sourceRect` | 12.3 | The captured sub-rect. **Points, in the display's logical coordinate system (top-left origin, relative to the display).** |
| `SCStreamConfiguration.width` / `.height` | 12.3 | Output size **in pixels** (default 1920×1080). Must be set to `sourceRect.size × scale`, or the output is resampled. |
| `SCStreamConfiguration.captureResolution = .best` | 14.0 | Captures at the display's backing resolution instead of letting the system pick. |
| `SCStreamConfiguration.minimumFrameInterval` | 12.3 | Default `1/60`; `kCMTimeZero` = native refresh rate. |
| `SCStreamConfiguration.queueDepth` | 12.3 | Surfaces kept in flight (default 8). |
| `SCStreamConfiguration.showsCursor` | 12.3 | On by default. We turn it **off**: the cursor would sit over the pixels being inspected. |
| `SCStream.updateConfiguration(_:)` / `updateContentFilter(_:)` | 12.3 | Change the source rect or the display **without restarting** the stream. |
| Sample buffer attachments | 12.3 | `SCStreamFrameInfo.status` (`complete` / `idle` / `blank` / …), `.contentRect`, `.scaleFactor`, `.dirtyRects`. Idle frames carry no image — the last frame stays on screen. |
| `SCScreenshotManager.captureImage(contentFilter:configuration:)` | 14.0 | One-shot capture with the same filter; not needed for the MVP (see §2.4). |
| `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` | 10.15 | Check and request the Screen Recording permission. |
| `NSScreen.deviceDescription["NSScreenNumber"]` | — | `CGDirectDisplayID` of an `NSScreen`. (`NSScreen.CGDirectDisplayID` exists only from macOS 26, so we don't rely on it.) |

**Deployment target: macOS 14.0.** Everything above is available on 14.0; `captureResolution` and `pointPixelScale` are the newest APIs we depend on. Nothing in the design needs 15.x or 26.x. Only macOS 27 is available on this machine for testing.

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
- **Pixel format:** BGRA, SDR, with the display's own color space. The Pixel Inspector converts to sRGB for display (§4).
- **Self-exclusion:** `excludingApplications: [our SCRunningApplication]`, found in `SCShareableContent.applications` by `processID`. This removes every window we own, including any we add later (Preferences, alerts), with no window bookkeeping.
- **Moving or resizing the Capture Area** calls `updateConfiguration` with the new `sourceRect`, `width` and `height`. The calls are coalesced so that at most one update is in flight, and the newest rect wins when it completes.
- **Moving the Capture Area to another display** calls `updateContentFilter` with a filter for the new display, and then `updateConfiguration`.
- **Frame bookkeeping:** every frame carries its `contentRect`/`scaleFactor` attachments. The renderer trusts the frame's own geometry, not the latest requested rect, so a frame produced for an old rect is never stretched into the new one.
- **Display changes:** `SCShareableContent` is cached and refreshed on `NSApplication.didChangeScreenParametersNotification`. If the stream stops with an error (for example, the display was unplugged), it is rebuilt from the current display list.

### 2.2 Threading (Swift 6 strict concurrency)

- `SCStreamOutput` callbacks arrive on a private serial queue. The handler does nothing but put the `CVPixelBuffer` and its frame info into `FrameStore` — a `Sendable` final class guarded by `OSAllocatedUnfairLock` — and then asks the view to redraw on the main actor.
- Everything that touches AppKit, window state or the `MTKView` is `@MainActor`.
- `CVMetalTextureCache` lookups happen in the draw call on the main actor. Creating a texture from an IOSurface is cheap and involves no copy.

### 2.3 Rendering

- `MTKView` with `isPaused = true` and `enableSetNeedsDisplay = true`. It redraws only when a new frame arrives or the zoom/pan changes, so an idle screen costs nothing.
- One vertex/fragment shader pair draws the frame texture as a quad. The quad's placement in the viewport comes from `ZoomPanController`.
- **Sampler:** `magFilter = .nearest`, `minFilter = .linear`. Magnification is always nearest-neighbor, so pixels are crisp squares; zooming out below 1:1 (for example Fit on a large area) is filtered and doesn't shimmer.
- **Pixel-exact placement:** the pan offset is snapped to whole drawable pixels. At an integer zoom every source pixel then covers exactly N×N drawable pixels, so there are no uneven columns and the pixel grid lines up.
- **The pixel grid (post-MVP)** is drawn in the same shader from the source-pixel coordinate. It stays aligned by construction.

### 2.4 Screenshots

- **Capture Source:** the latest frame's `CVPixelBuffer` is converted to a `CGImage` tagged with the frame's color space, then written as PNG or placed on the pasteboard. It is exactly the source pixels the Viewer shows, at native resolution. A new `SCScreenshotManager` capture isn't needed, and it could differ from what's on screen.
- **Capture View:** the same render pass runs once more into an offscreen texture of the drawable's size, and that texture becomes a `CGImage`. This guarantees what-you-see-is-what-you-get for zoom, pan and viewport. The grid is included only when `Include pixel grid in screenshot` is on.
- **Shortcuts:** `Cmd+C` (Copy View), `Cmd+Shift+C` (Copy Source) and `Cmd+S` (Save View) are main-menu key equivalents, active while the Viewer is key.

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
  - Minimum size: 8×8 pt.
- **Viewer:** a regular titled, resizable `NSWindow` with an `NSToolbar` (presets, zoom value) and full-screen support.
  - **Pan:** drag, two-finger scroll and horizontal scroll.
  - **Zoom:** `Cmd` + wheel, pinch, `+`/`-`, around the cursor.
- **App mode:** a regular app with a Dock icon and a main menu, plus the menu bar item of TASK.md §16. Closing the Viewer keeps the app running in the menu bar.
- **Permission flow:** `PermissionsManager` checks with `CGPreflightScreenCaptureAccess`. If access is missing, the Viewer shows an explanation panel with **Grant Access** (`CGRequestScreenCaptureAccess`), **Open System Settings** (the Screen Recording pane) and a restart hint, instead of an empty view. The check runs again when the app becomes active.
- **Sandbox:** off, with the hardened runtime on. Outside the App Store the sandbox only adds security-scoped bookmarks for the persisted screenshot folder. This can be revisited if App Store distribution becomes a goal.
- **Persistence:** a `Codable` settings struct in `UserDefaults`, covering the Capture Area rect (global points), the Viewer frame (`setFrameAutosaveName`), zoom, grid, inspector, screenshot folder and preferences.
- **Pixel Inspector (post-MVP):** HEX and RGB are reported in sRGB, matching design tools and CSS, with the native display value next to them. The pixel is read straight from the latest frame's `CVPixelBuffer`.
- **Global hotkeys (post-MVP):** Carbon `RegisterEventHotKey`. It needs no Accessibility permission, unlike an `NSEvent` global monitor.

## 5. Project structure

```
ScreenLoupe.xcodeproj           file-system-synchronized groups; the app and test targets
ScreenLoupe/
  App/          AppController, AppDelegate/main, WindowManager, StatusItemController, Settings
  Capture/      ScreenCaptureManager, FrameStore, PermissionsManager
  Overlay/      CaptureOverlayWindow, CaptureOverlayView
  Viewer/       ViewerWindowController, ViewerView (MTKView), ViewerRenderer, Shaders.metal,
                ZoomPanController, PixelInspector
  Export/       ScreenshotExporter
  Geometry/     DisplayCoordinateConverter, DisplayLayout, coordinate types, ZoomPanMath
  Resources/    Assets.xcassets, Info.plist, ScreenLoupe.entitlements
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
| 5 | **Screen Recording permission (TCC).** An ad-hoc signature can drop the grant on every rebuild; recent macOS versions may ask the user to reconfirm the permission from time to time (to be verified on macOS 27); `CGPreflightScreenCaptureAccess` may report a stale result until relaunch. | Sign with the existing Apple Development identity; show a restart hint in the permission panel; handle the stream-start error as "no permission". |
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
