# Reference check example

A page and a design export of one of its components, to try reference layers in Difference.

- [index.html](index.html) — the page as built: a pricing card with an "Upgrade to Pro" button. Online: <https://ayenora.github.io/screen-loupe/examples/reference-check/>.
- [design-export.png](design-export.png) — the card as designed, at 2× (816 × 776 px for 408 × 388 pt).

The build differs from the design in two places: the button sits 2 px lower and its corner radius is 8 instead of 10.

## Try it

1. Open the page in Chrome at 100% zoom, on a Retina display. The export was rendered by Chrome, so Safari's text rendering differs slightly.
2. Place the Capture Area over the card, a little larger than it.
3. In the Viewer, open References, add `design-export.png`, set opacity to 100% and the blend to Difference.
4. Drag the layer, or type X and Y, until the card turns black. Only the button's edges stay lit: that is the mismatch.

## Regenerating the export

`index.html#design` shows the page as designed, and `index.html#export` shows only the designed card at the window's top-left. With Chrome:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --hide-scrollbars \
  --force-device-scale-factor=2 --window-size=408,388 \
  --screenshot=design-export.png "file://$PWD/index.html#export"
```

Chrome may keep running after it writes the file; stop it once the file is there.
