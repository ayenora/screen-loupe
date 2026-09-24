# Screen Loupe

A small native macOS magnifier for designers and developers.

Place a **Capture Area** rectangle over any part of the screen and inspect it in a separate **Viewer** window. The Viewer shows the area in real time and supports:

- pixel-sharp zoom up to 1600%;
- panning around the magnified image;
- a pixel inspector (coordinates, RGB, HEX);
- a pixel grid;
- screenshots of either the original area or the zoomed view.

Built with Swift, AppKit, ScreenCaptureKit and Metal, with no third-party dependencies.

> Status: in development. The specification is in [TASK.md](TASK.md).

## Requirements

- macOS with Screen Recording permission granted to the app
- Xcode 26 to build

## Build

```sh
make build   # Debug build
make test    # unit tests
make help    # all targets
```
