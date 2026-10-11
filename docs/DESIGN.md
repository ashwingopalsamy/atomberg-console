# Design

The app is one popover. It should feel like part of macOS 26, answer one question per screen, and stay out of
the way. This page is the reference for how it is built; the values live in `Sources/ATOMBERG/UI/Tokens.swift`.

## Principles

1. **One fact, one place.** A speed is shown once per screen. Status is a glyph or a word, never both.
2. **Colour is scarce.** Teal marks an active switch. Orange marks something that needs you. Everything else is
   label colours and neutral fills.
3. **Symbols over sentences.** Rows carry SF Symbols; words are for things a symbol cannot say.
4. **Motion explains.** Things move to show a change or a command in flight. Reduce Motion is honoured.
5. **Honest state.** What is shown is what the device reported, or visibly pending. Never optimistic and silent.

## Tokens

| | |
|---|---|
| Type | SF Pro. 13 for titles and rows, 12 for values, 11 for status and footers. Tabular digits for numbers. |
| Grid | 8 pt. Side inset 16. Cards inset 8 from the popover edge, 12 pt radius (concentric with the 20 pt popover). |
| Rows | 36 pt device rows, 40 pt setting rows, 48 pt with a subtitle. Hit targets 28 pt or more. |
| Fills | `systemFill` wells, `tertiarySystemFill` cards, hairlines one device pixel. No borders, no shadows on cards. |
| Hues | `systemTeal` fan switches, `systemBlue` purifier switches, `systemOrange` attention glyph only. |

## Layout

- **Home.** Header (title, local check, settings, quit), an optional notice, then the device list. A running fan
  shows its six-step speed control under its name.
- **Right-hand columns on every row.** Value · transport glyph · 42 pt control. The glyph and control columns
  share an x position, so symbols line up down the list.
- **Detail.** One-line header (back, title, transport, switch), cards, one footer line (model and usage).
- **Settings, FAQ, About.** Same card language as the detail screens.

## Status glyphs

| Glyph | Meaning |
|---|---|
| `wifi` | controlled over your local network |
| `cloud` | controlled through Atomberg's cloud (counts toward the 100 calls a day) |
| `icloud.slash` | offline; the tooltip says when it was last seen |
| `exclamationmark.triangle.fill` | needs you: a purifier fault or a low lock battery |

## Window mechanics

The popover's window has one frame while it is open: tall enough for the tallest screen, clear, and pinned to
the menu bar. Moving between screens only changes the height of the glass surface drawn inside it. Resizing
the window itself moved the whole popover by a pixel at each step, which read as shaking. Below the surface the
window ignores the mouse, so it never blocks the windows behind it.

## Accessibility

Every control has a label; rows are one button with a spoken state; symbols are hidden from VoiceOver where text
carries the meaning. Increase Contrast draws card strokes. Reduce Motion replaces movement with a short fade.
