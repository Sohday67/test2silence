# Assets

## Icon

The extension icon is `Icon.svg` — a red rounded square containing a
forward-skip glyph and a small "silence" visualizer at the bottom,
representing both Smart Speed (fast-forward through silence) and Skip
Silence (jump past silence).

For shipping, convert to PNG at the following sizes:

```bash
# Requires rsvg-convert or `qlmanage` (macOS) or Inkscape
rsvg-convert -w 120 -h 120 Icon.svg -o Icon@2x.png
rsvg-convert -w 180 -h 180 Icon.svg -o Icon@3x.png
rsvg-convert -w  60 -h  60 Icon.svg -o Icon.png
```

The `.png` files are intentionally not checked in — generate them as part of
your build.
