# Screen Loupe

A small native macOS magnifier for designers and developers.

Place a **Capture Area** rectangle over any part of the screen and inspect it in a separate **Viewer** window. The Viewer shows the area in real time and supports:

- pixel-sharp zoom, panning, and a window sized to the magnified area;
- a crosshair on the real cursor, and a freeze frame for transient states;
- a Color Meter (HEX, CSS, SwiftUI, AppKit, pinned colours) and a pixel grid;
- a corner ruler in screen pixels;
- reference layers: design exports over the live pixels, with a Difference blend;
- copies of either the original area or the zoomed view;
- snapping the frame to window edges with ⌘, and fitting it to a window in one click.

Built with Swift, AppKit, ScreenCaptureKit and Metal, with no third-party dependencies.

## Download

Get the signed, notarized DMG from [Releases](https://github.com/ayenora/screen-loupe/releases/latest), open it and drag Screen Loupe to Applications. On first launch, grant Screen Recording access when the Viewer asks. The [Guide](https://ayenora.github.io/screen-loupe/guide) covers every feature and shortcut.

The app collects no data and sends nothing anywhere: [privacy policy](https://ayenora.github.io/screen-loupe/privacy).

## Documentation

- [Guide](docs/guide.md) — how to use the app
- [Product](docs/product.md) — who it is for, principles, features
- [Technical design](docs/design.md) — pipeline, coordinate systems, architecture, risks, verification
- [Roadmap](docs/roadmap.md) — what comes next

## Requirements

- macOS 14 Sonoma or later, with Screen Recording permission granted to the app
- Xcode 26 to build

## Build

```sh
make build   # Debug build
make test    # unit tests
make help    # all targets
```

## License

[MIT](LICENSE)
