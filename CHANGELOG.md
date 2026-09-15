# Changelog

## Unreleased

- Show sub-hour UTC offsets in the hour grid: a zone offset by `:30`/`:45`
  (Kathmandu, Kolkata, Chatham) drew a strip identical to a whole-hour zone,
  because the cell kept only the truncated hour. Those minutes are now drawn
  under it.

## 1.1.0

- Fix the panel never closing once opened on Omarchy shells that hand
  plugins the `PluginBarApi` facade: assigning to its read-only
  `centerHoverRevealSuppressed` threw and aborted `close()` before the
  panel was hidden, leaving its keyboard grab up. The facade's setter is
  used instead, with the assignment kept for hosts that expose the real
  `Bar`. Reported and fixed independently in #8 (memelet) and #9 (censey).
- Keyboard navigation in the popup: `h`/`l` and `←`/`→` step the selected
  column (based on #5 by gabrielvincent), `n` returns to now, `r` refreshes,
  `w` opens worldtimebuddy, `Esc` closes.
- Display modes via `hourFormat` in `shell.json`: `24h` (default), `12h`
  (AM/PM, based on #4 by ryanyogan) and `utc` (24-hour plus a UTC reference
  row under home). `t` in the popup cycles through them for the session, on
  every monitor at once; also exposed as `toggleHourFormat` over IPC.
- `p` (or `y`, vim yank) in the popup copies it as a PNG to the clipboard, selected column and
  converted times included, for sharing a meeting slot. Also `screenshot`
  over IPC.
- New default bar icon `` (fa-bars_staggered, U+EE19). Falls back to the
  previous `󱉊` automatically when no installed font has the glyph
  (Nerd Fonts < 3.3). `icon` still overrides both.

## 1.0.1

- New default bar icon (globe with a clock badge) — the previous globe glyph
  rendered smaller and lower than sibling bar icons at bar size, a font
  hinting quirk
 - Icon customizable via `icon` in the widget's `shell.json` entry;
  see README's Configure section for alternatives.

## 1.0.0

- Initial release.
