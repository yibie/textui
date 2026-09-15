# Pixel-aware row and box composition

Task: `docs/brief-pixel-composition.md`. This report records what changed, the
before/after fixture and probe evidence, the public behaviour that changed, and
what the downstream Tag Cards view can delete.

## What changed

`textui.el` composes flex and grid rows and layout boxes by pixel budget on
graphical frames. One internal primitive owns padding:

- `textui--pixel-pad-right` pads an attributed string to a cell budget with
  whole ordinary spaces and, for the remainder, one residual
  `(space :width (N))` display spacer — the absolute-pixel form of the `space`
  display specification. It preserves faces, existing display properties, and
  `textui--refresh-id` ownership of the padding.
- `textui--pixel-metrics` returns `(MEASURE . CELL-WIDTH)` for the frame that
  displays the buffer, falling back to the selected frame. It returns nil on
  non-graphical frames and on frames without pixel geometry.
- `textui--string-pixel-width` measures the attributed string and memoizes the
  result per display-environment generation in a table whose test compares
  text properties, so a face change cannot reuse another string's width and
  `textui-invalidate-text-layout-cache` discards measured widths for font,
  theme, and scale changes exactly like paragraph layouts.
- `textui--rendered-string-width` converts a measured advance to the cells it
  occupies on graphical frames, which is what makes the natural-width overflow
  rule compare in pixels. The previous `textui--pixel-justified` conversion is
  kept for the column path.

Callers:

- `textui--compose-row-blocks` now pads each block and each following gap from
  the cumulative rendered prefix of the line
  (`textui--compose-pixel-row-blocks`). A glyph that is not a whole cell wide
  cannot move a later block.
- `textui--render-layout-box` pads each interior line to the interior budget
  and pads the prefix of every border, rule, and blank padding line to the cell
  offset of the right border before appending it
  (`textui--pixel-box-lines`), so a box's right edge is straight even when a
  rule or content glyph is not exactly one cell wide.

Overflow is unchanged and explicit: no negative spacers, no clipping, and a
block wider than its allocation still grows its track — now measured in
pixels. No `textui-overflow` option was added; the probe's widest card row is
handled by the natural-width rule. The reasoning is in
[ADR 0039](adr/0039-compose-rows-and-boxes-by-pixels-on-graphical-frames.md).

## Terminal fixture, before and after

The fixture is `test/fixtures/terminal-composition.txt`, captured from the
pre-change core with the probe's ten-row card pair (`:flex` and `:grid`), a
left-aligned `:text` leaf, and a mixed-width item grid, rendered at 110
columns. Capture command:

```sh
emacs -Q --batch -L . -L test -l test/textui-pixel-composition-test.el \
  --eval '(let ((coding-system-for-write (quote utf-8-unix)))
            (write-region
             (concat (substring-no-properties
                      (textui--render-frame
                       (textui-pixel-test--fixture-frame) 110))
                     "\n")
             nil textui-pixel-test--fixture))'
```

The post-change render is byte-identical: the fixture test passes, and the
probe example's own batch report is unchanged (see below). First fixture lines,
unchanged before and after:

```text
┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐
│                                         │   │                                         │
│  TAG / CONTACT                     26   │   │  TAG / CONTACT                     26   │
│ + CONTACT / FRIEND                 19   │   │ + CONTACT / FRIEND                 19   │
│ ↗ 签字汪炜提供的合同解除书           4  │   │ ↗ 签字汪炜提供的合同解除书           4  │
```

Ragged right edges are expected here: terminals and batch compose in columns
only, and that contract is deliberately unchanged.

## Probe variant A, before and after

The live GUI probe measured 24px and 48px right-edge spread for the stock
composition (`docs/report-card-alignment-probe.md`). Batch output cannot
reproduce that, so the pixel path is exercised with the probe's fake metrics
(7px cell, 17px CJK, 9px ellipsis, 7px space) on the probe's exact stock card
element and pair geometry. Reproduce from the checked-in test helper:

```sh
emacs -Q --batch -L . -L test -l test/textui-pixel-composition-test.el \
  --eval '(textui-pixel-test--with-metrics
            (princ (textui--render-frame (list (textui-pixel-test--pair :flex))
                                         110)))'
```

To reproduce the pre-change numbers, replace the padding primitive with the
pre-change column padding for that render:

```elisp
(cl-letf (((symbol-function 'textui--pixel-pad-right)
           #'textui--pad-right))
  (textui-pixel-test--with-metrics
    (textui--render-frame (list (textui-pixel-test--pair :flex)) 110)))
```

| Composition | Card 1 right edge | Card 2 right edge | Verdict |
| --- | --- | --- | --- |
| Pre-change padding | 323, 324, 328, 329 px | 674, 676, 684, 686 px | FAIL, 6px / 12px spread |
| New core | 329 px on every line | 686 px on every line | PASS, 0px / 0px |

The probe example itself still runs and still reports variant A as
`A PASS COLUMN-ONLY max-deviation=0col`, and its full batch report is
byte-identical to the pre-change one (`diff` empty).

## Public behaviour that changed

- No public function, option, or element property was added, removed, or
  renamed. The composition guarantee is new behaviour behind the existing
  Flex, Grid, `:border`, and `:padding` semantics.
- On graphical frames only, a rendered row or box can now contain one
  display-only spacer per padded boundary. Source text, buffer text, copy,
  search, and source offsets are unchanged. Column metadata for focus and
  location IDs stays column-based, as ADR 0039 records.
- Blocks are measured in pixels on graphical frames, so an overflowing block
  can grow a track one cell earlier than before.
- `textui-invalidate-text-layout-cache` now also discards memoized string
  pixel widths, in addition to paragraph layouts.
- Terminal and batch output, including every existing fixture and the probe
  example, is byte-identical.

## Tests

New coverage in `test/textui-pixel-composition-test.el` (4 tests):

- flex pair and grid pair: every line's card border offsets are identical
  pixels with the fake 7px metrics, for stock composition with `:border t`
  boxes;
- the primitive: whole-space fill, residual spacer width, never clipping
  over-budget content, and exact equality with `textui--pad-right` when no
  pixel metrics exist;
- the captured terminal fixture.

The whole suite, including the pixel tests:

```text
Ran 144 tests, 144 results as expected, 0 unexpected (2026-09-14 19:05:10-0700, 0.174784 sec)
```

Run with `native-comp-enable-subr-trampolines nil`, because the native compiler
is unavailable in this environment and otherwise fails the six image tests
before reaching TextUI code. The pixel path was also stress-run across the
whole suite with the metrics override active (real `string-pixel-width`
measurer): 144 expected, 0 unexpected.

## What Tag Cards can delete

Once `supertag-view-tag-cards.el` returns to a `:grid`/`:flex` card layout, the
core now supplies the composition that Round 5 to Round 8 had to build
locally:

- `supertag-view-tag-cards--compose-card-row-line` and
  `supertag-view-tag-cards--compose-card-row`, together with the
  `supertag-view-tag-cards-card-row-block` widget type and its
  `:textui-layout`/`:textui-attach` pair: a normal TextUI `:grid` now places
  cards on exact tracks and a normal `:flex`/`:border` box pads every line.
- `supertag-view-tag-cards--append-to-cell`,
  `supertag-view-tag-cards--append-to-width`, and
  `supertag-view-tag-cards--spacer-to-width`: TextUI pads every track boundary
  and box interior itself.
- `supertag-view-tag-cards--pad-right` and
  `supertag-view-tag-cards--pad-between` for layout padding: width fitting for
  a track is still the package's job, but the padding no longer is. The
  `:track`/`:budget` bookkeeping that existed only to reproduce TextUI's track
  arithmetic can go as well.

What should stay package-side:

- `supertag-view-tag-cards--fit-label-to-target` and
  `supertag-view-tag-cards--truncate-for-track`: TextUI does not truncate
  native widget text, so the pixel-budget fitter (with its full-prefix
  candidate measurement and reserved suffix) is still required.
- `supertag-view-tag-cards--filled-string` and
  `supertag-view-tag-cards--filled-title-string`: card fill faces and the
  reserved count column are domain styling, not layout.
- The measurement command and its `PASS`/`COLUMN-ONLY` report: it is the
  package's own live-GUI check.

Embedded facet and node buttons, and the focus identity that Round 5 gave up
for them, become TextUI's again: `:grid` children carry `:focus-id`
reconciliation, so the private action text property is no longer needed to
keep them navigable.

## Not covered here

A live graphical confirmation was not run: this change was verified in batch
only. The pixel path is deterministic under the fake metrics, and the residual
spacer is the documented absolute-pixel form, but the maintainer's own GUI
re-run of `M-x textui-card-alignment-probe` remains the end-to-end check.

## Round 2: review finding

**Finding.** `textui--string-pixel-width` memoized into a hash table whose
test was `equal`, and `equal` ignores text properties. Measured in batch:

```text
(equal (propertize "ab" 'face 'bold) "ab")   => t
(gethash "ab" <table keyed by (propertize "ab" 'face 'bold)>) => 42
(sxhash-equal (propertize "ab" 'face 'bold)) => 31265
(sxhash-equal "ab")                           => 31265
```

So a bold chip title and the same characters in the default face shared one
entry, and a face with a different `:family` or `:height` could return another
string's measured advance.

**Fix.** `textui--pixel-width-cache` now uses a named hash table test,
`textui--attributed-string`, defined with `equal-including-properties` and
`sxhash-equal-including-properties` (both available since Emacs 28, inside the
Emacs 29.1 compatibility contract). The table therefore compares attributed
strings, including faces and display properties; font, theme, and scale
invalidation still happens through the display-environment generation.

**Test.** `textui-pixel-composition-width-cache-keys-text-properties` in
`test/textui-pixel-composition-test.el` installs a fake measurer that returns
40px for a bold string and 14px for the same plain string, calls
`textui--string-pixel-width` on both, asserts both widths, that the second
pass is served from the cache, that the table uses the attributed-string test,
and that it holds two entries. Against a copy of the core with the cache test
restored to `equal`, that test fails; with the fix it passes.

**Verification.** Byte-compile with `byte-compile-error-on-warn t` exits 0.
The full suite with `native-comp-enable-subr-trampolines` nil:

```text
Ran 145 tests, 145 results as expected, 0 unexpected (2026-09-14 19:44:49-0700, 0.174902 sec)
```

The same suite with the pixel metrics override forced on, and the probe
example's batch report, are unchanged (`145 expected, 0 unexpected`; `diff`
empty against the pre-change probe output).
