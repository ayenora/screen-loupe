# Screen Loupe — Roadmap

What comes after the current version. Every item is measured against the principles in [product.md](product.md): work in place, nothing moves on its own, pixel-true, out of the way. Nothing here is committed until it moves into product.md.

## Next

- **First public release.** A signed, notarized download and possibly the Mac App Store; the plan is in [release.md](release.md).

## Candidates

Ordered by how much each strengthens the core experience.

### The designer's daily loop

- **Drop images onto the Viewer** to add them as references, besides Add… in the panel.
- **Attach the area to a window.** The Capture Area follows a window when it moves (the iOS Simulator, a browser window).
- **Several Capture Areas**, each with its own Viewer, for comparing two places.

### Each needs its own decision

- **Record the zoomed view** as a short video or GIF of an interaction. Close to the screenshot-history line in "Not in scope".
- **Act through the Viewer.** Clicks and scrolls in the Viewer go to the real spot on screen, making the Viewer a true zoomed monitor. Needs the Accessibility permission to post events and has to feel safe; a bigger design question than the rest.
- **HDR/EDR content.** The capture is SDR today, so HDR highlights are clipped in the Viewer and the Color Meter.

### Technical, only if a need shows up

- **Instant dragging.** If the Viewer ever visibly trails a dragged Capture Area, capture the whole display and crop in the shader (design.md §6, risk 1).
- **Smoother zoom-out.** Below 50% the image aliases, because the texture has no mipmaps. A loupe is about magnification, so this waits for a real complaint.

## Not planned

The line in product.md, "Not in scope", holds: no OCR, annotations, drawing, image editing, screenshot history, cloud sync, accounts, telemetry, subscriptions or AI features, and no web technologies in the app.
