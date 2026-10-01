# Screen Loupe

A small native macOS magnifier for designers and developers.

https://github.com/user-attachments/assets/fa2e3ef7-8ac3-4e69-b9fc-c11959146e5c

Place a **Capture Area** rectangle over any part of the screen and inspect it in a separate **Viewer** window. The Viewer shows the area in real time and supports:

- pixel-sharp zoom that glides between levels, panning, and a window sized to the magnified area;
- a crosshair on the real cursor, a freeze frame for transient states, and snapshots kept across launches to inspect later, linked to share one zoom and position;
- a Color Meter (HEX, CSS, SwiftUI, AppKit, recent and favourite colours, WCAG contrast) and a pixel grid;
- a corner ruler and a selection ruler in screen pixels, and the selection's size in pixels and points;
- colour vision simulation: six modes over everything the Viewer shows, in copies of the view too;
- reference layers: design exports over the live pixels, with a Difference blend, or a snapshot or the frozen frame as a before-and-after check;
- image files opened, dropped or pasted, inspected with the same tools;
- copies of either the original area or the zoomed view;
- snapping the frame to window edges with ⌘, fitting it to a window in one click, and a magnet that keeps it on a moving window, following its size when fitted, with margins to capture only an inner part of it;
- an outline of the part the Viewer shows, with a handle to pan the Viewer from the frame.

A separate **Screenshot studio** takes exact, clean pictures — App Store and website screenshots, docs, bug reports: preset and custom pixel sizes, a timer, a backdrop of a colour, gradient or image seen on screen, one window alone with or without its shadow, and PNG, JPEG or HEIC output in sRGB or the display's colours, with no personal metadata.

Built with Swift, AppKit, ScreenCaptureKit and Metal, with no third-party dependencies.

## Download

Get the signed, notarized DMG from [Releases](https://github.com/ayenora/screen-loupe/releases/latest), open it and drag Screen Loupe to Applications. Or install it with Homebrew:

```sh
brew install --cask ayenora/tap/screen-loupe
```

On first launch, grant Screen Recording access when the Viewer asks. The [Guide](https://ayenora.github.io/screen-loupe/guide) covers every feature and shortcut.

The app collects no data and sends nothing anywhere: [privacy policy](https://ayenora.github.io/screen-loupe/privacy).

## Documentation

- [Guide](docs/guide.md) — how to use the app
- [Roadmap](docs/roadmap.md) — what comes next

## Requirements

- macOS 15.2 Sequoia or later, with Screen Recording permission granted to the app
- Xcode 26 or later to build; the 1.4.0 release is built with Xcode 27

## Build

```sh
make build   # Debug build
make test    # unit tests
make help    # all targets
```

## License

[MIT](LICENSE). The two Lucide icons the app uses are under the ISC licence: [third-party notices](THIRD_PARTY_NOTICES.md).
