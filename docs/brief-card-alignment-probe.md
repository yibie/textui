# Experiment brief: bordered card alignment under mixed-width glyphs

Repository: this TextUI checkout. Do not modify `textui.el`,
`textui-widgets.el`, `textui-keyed-region.el` or `textui-kp-core.el` in this
round. Deliverable is one new example file plus a short report. No commits.

## Why

A downstream package (supertag Tag Cards) renders a 3-column grid of
bordered cards whose rows mix ASCII, CJK, arrows (`→ ↗ ◆`) and `…`. In the
user's GUI Emacs the card contents and borders drift by one or two columns
per row. Diagnosis: `textui--compose-row-blocks` and
`textui--render-layout-box` pad by `string-width` and join blocks with
literal spaces, so any glyph whose pixel advance is not exactly
`char-width × frame-char-width` shifts everything to its right. In the
user's fontset CJK is not exactly two cells and the `symbol` script is
mapped to Apple Color Emoji, so `↗` renders emoji-wide.

This experiment must answer, with numbers, whether text inside one bordered
card can be made to align, and which technique does it.

## Deliverable 1: `examples/textui-card-alignment-probe.el`

`M-x textui-card-alignment-probe` opens one TextUI buffer showing the same
card content rendered by three techniques, side by side or stacked (your
choice, label each clearly):

- **A. Stock**: a `:flex :direction :column :border t :padding 1` card with
  `:layout (:width 40)`, rows as `item` widgets, exactly what TextUI does
  today.
- **B. Align-to**: same content, but the card is composed by the probe
  itself: every row's right border and every gap is positioned with a
  space carrying `display (space :align-to COL)` (column units), so a row's
  left/right edges are pinned to absolute columns regardless of the pixel
  width of what precedes them. Render it as one `:text`-free block of
  pre-composed lines (an `item` per line is fine) so TextUI does not re-pad
  it.
- **C. Pixel-padded**: same content, composed by the probe with padding
  computed from `string-pixel-width` against `(* 40 (frame-char-width))`,
  inserting whole spaces plus one final `(space :width (N))` pixel spacer to
  hit the exact pixel edge.

Card content (identical in A, B, C), ten rows:

```
 TAG / CONTACT                     26     <- fill line, face with :background
+ CONTACT / FRIEND                 19
↗ 签字汪炜提供的合同解除书           4
◆ DONE                              4
→ 姑姑
→ 老妈
→ [2025-09-08 Mon 16:19] 很郁闷，其…  2
→ Andreessen Horowitz（a16z）
→ iSouthRain
→ 施宏斌
```

Put a second identical card to the right of each variant (two cards per
row) so the "neighbour pushes me" effect is visible.

## Deliverable 2: built-in measurement

Under each variant the probe prints, from the live buffer after
materialization:

- for every rendered line, `string-pixel-width` of the text between the
  card's left and right border characters (inclusive), and the pixel
  x-position of the right border via `posn-x-y`/`window-text-pixel-size`
  or `(car (window-text-pixel-size nil (line-beginning-position) POS))`;
- `PASS` if all lines of a card share the same right-border x within one
  pixel, else `FAIL` with the max deviation in pixels.

Also print, once at the top: `(frame-char-width)`,
`(string-pixel-width "中中")`, `(string-pixel-width "ab")`,
`(string-pixel-width "→")`, `(string-pixel-width "↗")`,
`(string-pixel-width "…")`, and the font family that actually renders `↗`
(`(font-get (font-at POS) :family)` on that char). These numbers are the
whole point; the user will run this in their GUI and paste the output.

In batch (`emacs -Q --batch -l examples/textui-card-alignment-probe.el
--eval '(textui-card-alignment-probe-report)'`) the report must still run
and print column-based results with a note that pixel checks need a GUI.

## Deliverable 3: `docs/report-card-alignment-probe.md`

- what each technique needed, and any TextUI contract it violated;
- your own GUI run if you can start a GUI Emacs from the terminal
  (`emacs -Q -l ...` on macOS opens a GUI frame; do NOT use emacsclient or
  the user's running Emacs) with the output pasted; if you cannot, say so;
- a recommendation: which technique TextUI core should adopt in
  `textui--compose-row-blocks` / `textui--render-layout-box`, and the
  minimal change to get there (do not make that change yet).

Constraints: Emacs 29 compatible, `lexical-binding`, byte-compiles with no
warnings, ASCII-only source except in the sample strings.
