# Screen Loupe — Roadmap

What comes after the current version. Every item is measured against the principles in [product.md](product.md): work in place, nothing moves on its own, pixel-true, out of the way. Nothing here is committed until it moves into product.md.

## Next: 1.3

- **The Mac App Store,** besides the signed, notarized download on GitHub Releases.

Decided to build; the details settle when each moves into product.md.

### Images in the Viewer

- **A frozen frame is an image.** To the Viewer, freezing and looking at a picture are the same thing, technically and as a concept: every tool works on both, as it already does on a recent capture. The items below follow from that.
- **Open an image** in the Viewer: it shows as a row of Recent Captures, with zoom, ruler, Color Meter and references, to look at a file with the same pixel-true tools.
- **Drop images onto the Viewer:** with References open they become reference layers, with Recent Captures open they open for inspection, and otherwise a menu asks which.

### Capture Area

- **Magnet to a window.** Besides the pin, the area can be attached to a chosen window: while the window is on screen and moves, the area moves with it and keeps its place from the window's corner (the iOS Simulator, a browser window). A resized window leaves the area's size as it is. When the window closes, hides or minimises, the Space changes or the displays do, the magnet lets go and the area stays where it is.
- **The part the Viewer shows, on the frame.** At a high zoom the Viewer shows a small part of the area; a thin outline inside the frame marks which, and fades when it isn't needed.
- **Viewport handle:** a mode that keeps the outline of the part the Viewer shows on the frame, with a handle that pans the Viewer.
- **A square area with Shift** while dragging a corner.
- **A fixed position:** the area can't be moved by a stray drag, and its handles still resize it.

### Viewer

- **The ruler's length labels move it,** as the size tab moves the Capture Area.

### Screenshot studio

A screenshot tool on the same capture, apart from the Capture Area and the Viewer: its own frame and a panel of buttons, shown and hidden on their own, with their own section in the menu. It can capture anything on screen, the Viewer included, and leaves its own windows out of the picture without hiding them. Exact pixel sizes and clean backgrounds for App Store and website screenshots, docs and bug reports.

Sizes and custom sizes with Aspect Lock; a timer; a clean background of a colour, a gradient or an image; one window alone, with or without its shadow; the pointer if wanted; and the output's format, colours and scale, with no personal metadata.

## The version after: colour

Screen Loupe already reads exact colours off any screen. The next version could turn that into work designers and brand managers do by hand today. Two directions, both to be researched before they are designed.

**First, find out:** what brand managers and designers use today to build and keep palettes and themes, where it hurts, and what they hand over to developers. Talk to people, not only read about tools. The aim is to automate the tedious part, not to add another palette toy.

### Colour studio

A generator that builds a complete, balanced colour system from a few colours, with a live preview.

- **Seeds** from anywhere on screen: pick them with the Color Meter.
- **Presets as starting moods:** deep, standard, pastel, corporate, gold on black, and more.
- **Light and dark themes together,** tints and shades balanced by perceived lightness rather than by numbers, text and background pairs chosen so they stay readable in both. Contrast checking lives here, next to a text preview — not as a bare ratio in the Color Meter.
- **Previews that look like real UI:** text at several sizes, cards, buttons, surfaces, shadows, in both themes side by side.
- **Export:** CSS custom properties and an HTML preview page first; later design tokens and native colour sets.

### Colour skins over live UI

Apply a palette to a running app or website as a skin: its colours remapped live in the Viewer — a brand swap, a dark theme, a seasonal theme — to see a redesign on the real product before anyone builds it.

- **The bar is Apple's:** perceptual colour mapping that keeps hierarchy, contrast and gradients, no banding, crisp text. Not a photo filter laid over the screen.
- **Open questions:** telling UI colours from photos and illustrations, which should stay as they are; whether the skin stays in the Viewer or can cover the app itself; saving and sharing a skin; how it connects to the colour studio's palettes.

## Candidates

Ordered by how much each strengthens the core experience.

### The designer's daily loop

- **Several Capture Areas**, each with its own Viewer, for comparing two places.

### Each needs its own decision

- **Record the zoomed view** as a short video or GIF of an interaction. Close to the screenshot-library line in "Not in scope". It uses Original Cursor in the Capture (product.md, Crosshair and cursor), so a recorded animation shows the pointer that drives it.
- **Act through the Viewer.** Clicks and scrolls in the Viewer go to the real spot on screen, making the Viewer a true zoomed monitor. Needs the Accessibility permission to post events and has to feel safe; a bigger design question than the rest.

### Technical, only if a need shows up

- **Smoother zoom-out.** Below 50% the image aliases, because the texture has no mipmaps. A loupe is about magnification, so this waits for a real complaint.

## Not planned

The line in product.md, "Not in scope", holds: no OCR, annotations, drawing, image editing, a screenshot library, cloud sync, accounts, telemetry, subscriptions or AI features, and no web technologies in the app.
