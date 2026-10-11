# Screen Loupe — Roadmap

What comes after the current version. Every item is measured against the app's principles: work in place, nothing moves on its own, pixel-true, out of the way. Nothing here is committed until it ships.

## Next: recording inside the lens

To study motion up close — an animation, a transition, a hover appearing — in the Viewer. Not a screen recorder: what is recorded is the Capture Area at its native pixels, as a snapshot keeps it.

- **Record** the view's area, from the toolbar or with a global shortcut, so recording can start while the mouse is held in another app.
- **Play it back,** pause it and drag through it: paused, a frame is a picture like any other in the Viewer, so zoom, pan, the ruler, the Color Meter and references work on it.
- **Save it** as recorded, at its native pixels.

## The version after: colour

Screen Loupe already reads exact colours off any screen. The next version could turn that into work designers and brand managers do by hand today, to be researched before it is designed.

**First, find out:** what brand managers and designers use today to build and keep palettes and themes, where it hurts, and what they hand over to developers. Talk to people, not only read about tools. The aim is to automate the tedious part, not to add another palette toy.

### Colour studio

A generator that builds a complete, balanced colour system from a few colours, with a live preview.

- **Seeds** from anywhere on screen: pick them with the Color Meter.
- **Presets as starting moods:** deep, standard, pastel, corporate, gold on black, and more.
- **Light and dark themes together,** tints and shades balanced by perceived lightness rather than by numbers, text and background pairs chosen so they stay readable in both. The Color Meter checks the contrast of one pair of colours; here every pair in both themes is checked, next to a text preview.
- **Previews that look like real UI:** text at several sizes, cards, buttons, surfaces, shadows, in both themes side by side.
- **Export:** CSS custom properties and an HTML preview page first; later design tokens and native colour sets.

## Candidates

Ordered by how much each strengthens the core experience.

### The designer's daily loop

- **Several Capture Areas**, each with its own Viewer, for comparing two places.

### Only if a need shows up

- **Act through the Viewer.** Clicks and scrolls in the Viewer go to the real spot on screen, making the Viewer a true zoomed monitor. Needs the Accessibility permission to post events and has to feel safe; taken up only if many people ask for it.
- **Smoother zoom-out.** Below 50% the image aliases, because the texture has no mipmaps. A loupe is about magnification, so this waits for a real complaint.

## Not planned

No image editing, a screenshot library, cloud sync, accounts, telemetry, subscriptions or AI features, and no web technologies in the app.
