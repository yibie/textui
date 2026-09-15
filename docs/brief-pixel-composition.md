# Task brief: pixel-aware row and box composition in TextUI core

Authorized by the maintainer after a downstream proof (supertag Tag Cards
composes card rows locally with relative pixel padding; in the user's GUI
every card edge is now exact to the pixel). Read first, in this order:
`CONTEXT.md`, `docs/adr/0033-textui-extends-widget-el-instead-of-replacing-it.md`,
`README.md` (Flex, Grid, "Design constraints"),
`docs/report-card-alignment-probe.md`, `examples/textui-card-alignment-probe.el`,
and the downstream implementation for reference only:
`/Users/chenyibin/Documents/emacs/package/supertag/supertag-view-tag-cards.el`
(`--fit-label-to-target`, `--pad-right`, `--pad-between`,
`--compose-card-row-line`, `--append-to-cell`) and its Round 5 to 8 notes in
`/Users/chenyibin/Documents/emacs/package/supertag/doc/report-tag-cards-textui.md`.
Follow TextUI's own conventions (ADR for the decision, CHANGELOG entry,
tests under `test/`, Emacs 29 compatibility, no external deps). Do not
commit; the maintainer reviews the diff.

## Problem

`textui--compose-row-blocks` and `textui--render-layout-box` pad by
`string-width` and join blocks with literal spaces. On graphical frames a
glyph's advance is not always `char-width × frame-char-width`: measured in
`emacs -Q` on macOS, two CJK characters are 24px against a 28px column
estimate, and `…` is 14px against 7px. Every such glyph shifts everything
to its right, the error accumulates across columns, and borders drawn by
columns expose it. The probe report shows stock composition drifting
24px/48px while relative pixel padding (variant C) holds every edge.

## Change

1. **One pixel-aware padding primitive.** Add an internal helper that pads
   an attributed string to a pixel budget: whole ordinary spaces while
   they fit, then one residual `(space :width (N))` display spacer for the
   remainder, preserving faces and existing display properties. Measure
   with `string-pixel-width` against the target frame's `frame-char-width`
   (the frame of the window the buffer is rendered for; fall back to the
   selected frame). On non-graphical frames, or when the frame has no
   pixel geometry, behave exactly like today (columns only), so terminal
   and batch output are byte-identical to the current output.
2. **Use it at every boundary.** In `textui--compose-row-blocks`, pad each
   block and each gap from the cumulative rendered prefix of the line so a
   wide glyph in block N cannot move block N+1. In
   `textui--render-layout-box`, apply the same budget to the interior
   padding, the right border, the horizontal rules and blank padding rows,
   so a box's right edge is straight on every line.
3. **Overflow is explicit.** Keep today's rule that a block wider than its
   allocation grows the track, but compute "wider" in pixels on graphical
   frames, and document it. Do not add negative spacers. Add a
   `textui-overflow` (or similarly named) option only if you find the
   existing natural-width rule insufficient for the probe; if you add it,
   record the choice in the ADR.
4. **Measurement fidelity and caching.** Measure with the effective faces
   of the string (the attributed string as it will be inserted) and route
   through the existing text-layout cache with
   `textui-invalidate-text-layout-cache` semantics for font and scale
   changes. Logical column metadata used for focus and location ids must
   stay column-based; only the visual padding changes.
5. **Tests.** Turn the probe into regression coverage: a fake pixel
   measurer (7px cell, CJK 17px, `…` 9px, space 7px) that composes the
   probe's ten-row card twice side by side and asserts every line's
   right-edge pixel position is identical for stock `:grid`/`:flex`
   composition and for `:border t` boxes; a batch test that proves
   terminal output is unchanged from a captured fixture; the existing test
   suite stays green. Keep `examples/textui-card-alignment-probe.el`
   working and make its variant A report PASS under the new core.
6. **Docs.** ADR 0034 (or next number) "Compose rows and boxes by pixels on
   graphical frames", a CHANGELOG entry, and a README paragraph under
   Flex/Grid stating the guarantee: block edges are pixel-exact on
   graphical frames regardless of CJK, ambiguous-width or fallback-font
   glyphs; the trade-off is that a row may end a fraction of a cell short
   of its column budget.

Report in `docs/report-pixel-composition.md`: what changed, the fixture
outputs before/after, any public behaviour that changed, and what the
downstream Tag Cards view can now delete (its local composer) once it
switches back to `:grid`.

## Round 2: review finding

`textui--string-pixel-width` memoizes in a hash table with test `equal`,
which ignores text properties. `string-pixel-width` measures the attributed
string, so two strings with the same characters but different faces (a bold
chip title and the same text in the default face, or a face with a different
`:family` or `:height`) share one cache entry and the second caller gets the
first caller's width. Verified in batch: a table keyed by
`(propertize "ab" 'face 'bold)` returns its value for plain `"ab"`.

1. Key the cache by the attributed string: define a hash table test with
   `define-hash-table-test` using `equal-including-properties` and
   `sxhash-equal-including-properties` (both available since Emacs 28), and
   use it for the pixel-width table.
2. Add a test with a fake measurer that returns a different width for a
   bold-faced string than for the same plain string, calls
   `textui--string-pixel-width` on both, and asserts both widths are
   returned correctly. Keep it batch-safe by binding the measurement the way
   the existing pixel tests do, or by testing the cache layer directly.
3. Rerun the full suite with `native-comp-enable-subr-trampolines` nil,
   byte-compile with warnings as errors, and append a Round 2 note to
   `docs/report-pixel-composition.md`. Do not commit.
