# Screen Loupe

A small native macOS magnifier for designers and developers.

Place a **Capture Area** rectangle over any part of the screen and inspect it in a separate **Viewer** window. The Viewer shows the area in real time and supports:

- pixel-sharp zoom, panning, and a window sized to the magnified area;
- a crosshair on the real cursor, and a freeze frame for transient states;
- a Color Meter (HEX, CSS, SwiftUI, AppKit, pinned colours) and a pixel grid;
- a corner ruler in screen pixels;
- reference layers: design exports over the live pixels, with a Difference blend;
- copies of either the original area or the zoomed view.

Built with Swift, AppKit, ScreenCaptureKit and Metal, with no third-party dependencies.

> Status: in development.

## Documentation

- [Product](docs/product.md) — who it is for, principles, features
- [Technical design](docs/design.md) — pipeline, coordinate systems, architecture, risks, verification
- [Roadmap](docs/roadmap.md) — what comes next

## Requirements

- macOS with Screen Recording permission granted to the app
- Xcode 26 to build

## Build

```sh
make build   # Debug build
make test    # unit tests
make help    # all targets
```

## License

[MIT](LICENSE)
