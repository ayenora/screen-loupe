# Screen Loupe — Roadmap

What comes after the current version. Every item is measured against the principles in [product.md](product.md): work in place, nothing moves on its own, pixel-true, out of the way. Nothing here is committed until it moves into product.md.

## Next

- **First public release.** A signed, notarized download and possibly the Mac App Store; the plan is in [release.md](release.md).

## Candidates

Ordered by how much each strengthens the core experience.

### The designer's daily loop

- **Freeze frame.** Pause the live view (Space) to study a transient state — a hover, a pressed button, a frame of an animation — then resume.
- **Measure in the Viewer.** Drag between two points to get the distance in px and pt, snapping to colour edges, at full magnification.
- **Overlay a reference.** Drop a design export (PNG from Figma) onto the Viewer and see it over the live pixels with opacity or a difference blend: an exact design-vs-implementation check. No existing loupe does this live.
- **Attach the area to a window.** The Capture Area follows a window when it moves (the iOS Simulator, a browser window).
- **Several Capture Areas**, each with its own Viewer, for comparing two places.
- **Viewer that fits the area.** A command that sizes the Viewer to *area × zoom*, so the whole magnified area is visible without panning.
- **Position readout.** X and Y of the Capture Area next to its size, for placing it by numbers.

### Each needs its own decision

- **Record the zoomed view** as a short video or GIF of an interaction. Close to the screenshot-history line in "Not in scope".
- **Act through the Viewer.** Clicks and scrolls in the Viewer go to the real spot on screen, making the Viewer a true zoomed monitor. Needs the Accessibility permission to post events and has to feel safe; a bigger design question than the rest.
- **HDR/EDR content.** The capture is SDR today, so HDR highlights are clipped in the Viewer and the Color Meter.

### Technical, only if a need shows up

- **Instant dragging.** If the Viewer ever visibly trails a dragged Capture Area, capture the whole display and crop in the shader (design.md §6, risk 1).
- **Smoother zoom-out.** Below 50% the image aliases, because the texture has no mipmaps. A loupe is about magnification, so this waits for a real complaint.

## Not planned

The line in product.md, "Not in scope", holds: no OCR, annotations, drawing, image editing, screenshot history, cloud sync, accounts, telemetry, subscriptions or AI features, and no web technologies in the app.
