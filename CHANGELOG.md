# Changelog

## 1.0.2

- Fix the panel never closing once opened. Assigning to the bar's read-only
  `centerHoverRevealSuppressed` threw, and the throw aborted `close()` before
  it hid the panel; the setter the plugin bar API exposes is used instead.

## 1.0.1

- New default bar icon (globe with a clock badge) — the previous globe glyph
  rendered smaller and lower than sibling bar icons at bar size, a font
  hinting quirk
 - Icon customizable via `icon` in the widget's `shell.json` entry;
  see README's Configure section for alternatives.

## 1.0.0

- Initial release.
