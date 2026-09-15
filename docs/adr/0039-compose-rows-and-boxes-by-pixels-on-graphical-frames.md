# Compose rows and boxes by pixels on graphical frames

## Context

TextUI allocates layout in character cells. Composition then converted those
allocations back into text with `string-width` padding and literal spaces, and
the layout box drew its interior padding, horizontal rules, and borders from
character counts. That is correct only while every glyph advances by exactly
`char-width` times the frame's cell width.

A bordered-card probe measured the difference on a macOS GUI Emacs
(`docs/report-card-alignment-probe.md`). With a 7px cell, two CJK characters
advanced 24px instead of 28px and `…` advanced 14px instead of 7px. Stock
composition therefore drifted 24px on card one and 48px on card two: every
such glyph moved everything to its right, and the error accumulated across
columns and across the gap between cards.

The same probe showed that padding composed from the rendered prefix and
ending in a one-pixel-granularity display spacer holds every card edge. The
downstream supertag Tag Cards view implemented that technique locally, inside
its own block widget, and every card edge became exact to the pixel. Local
composition is the evidence that the missing primitive belongs in the core
(ADR 0028), and it costs the package a private renderer, private buttons, and
focus identity it would otherwise inherit from TextUI. TextUI already measured
pixel advances for `:text` wrapping and alignment; only the composition
boundary was still column-based.

## Decision

One internal primitive pads an attributed string to a cell budget:
`textui--pixel-pad-right` appends whole ordinary spaces while they fit and one
residual `(space :width (N))` display spacer for the remainder. The
parenthesized form is the absolute-pixel form of the `space` display
specification, so the rendered edge lands exactly on the `WIDTH` cell
boundary. It preserves the string's faces, existing display properties, and
`textui--refresh-id` ownership of the padding.

Two callers use it at every composition boundary:

- `textui--compose-row-blocks` pads each block and each following gap from the
  cumulative rendered prefix of the line, so a glyph that is not a whole cell
  wide cannot move a later block. Grid tracks and flex rows share this path.
- `textui--render-layout-box` pads each interior line to the interior budget,
  and pads the prefix of every border, rule, and blank padding line to the
  cell offset of the right border before appending that border.

Metrics are the frame that displays the buffer (`textui--rendered-frame`),
falling back to the selected frame when it is not displayed. When that frame
is not graphical or has no pixel geometry, the primitive is exactly
`textui--pad-right`; terminal and batch composition therefore stays
column-based and byte-identical to the previous output, and no spacer is ever
produced without pixel metrics.

`textui--rendered-string-width` measures the attributed string's pixel advance
on graphical frames and converts it to the cells it occupies. The existing
natural-width overflow rule therefore grows a track by the cells a block
really occupies rather than by its `char-width` estimate. Overflow stays
explicit and unchanged otherwise: no negative spacers, no clipping, and a
block wider than its allocation still grows its track. A `textui-overflow`
option is not added; the probe's widest card row is handled by that rule.

Measurements are attributed strings, measured through `string-pixel-width`,
and memoized per display-environment generation in a table whose test
compares text properties (`equal-including-properties`), so a face change
cannot reuse another string's width.  `textui-invalidate-text-layout-cache`
discards measured widths for font, theme, and scale changes exactly like
paragraph layouts.  Focus, location, and layout-cell metadata stay
column-based; only the visual padding changes.

## Consequences

- Block, card, and border edges are pixel-exact on graphical frames
  regardless of CJK, ambiguous-width, or fallback-font glyphs.
- The trade-off is that the last partial cell is filled by a display-only
  spacer. It adds no source characters, so a row can report a fraction of a
  cell less than its column budget to code that counts characters or columns,
  even though its rendered edge is exact.
- Terminal and batch rendering, tests, and fixtures keep their column-based
  output; the graphical behavior is covered by a fake-metrics regression
  suite plus a captured terminal fixture.
- Packages that compose card rows themselves can return to `:grid`, `:flex`,
  and `:border` and delete their private pixel composition. Truncation of
  native widget text remains the package's own policy; TextUI does not add a
  truncation API in this change.
