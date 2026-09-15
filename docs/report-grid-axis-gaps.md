# Separate column and row gaps for `:grid`

Task: `docs/brief-grid-axis-gaps.md`. This report records what changed, the
before/after evidence, the public behaviour that changed, and what the
downstream Tag Cards view can delete.

## What changed

`:grid` gained two element properties, both non-negative integers:

- `:column-gap`, the number of cells between tracks;
- `:row-gap`, the number of blank lines between grid rows.

`:gap` stays the shorthand for both axes. Precedence is per axis: an
axis-specific property overrides `:gap` for its own axis, and an axis with
neither keeps the current default of one cell.

`textui.el`:

- `textui--validate-grid` accepts both keys and rejects negative or
  non-integer values with the same `"%S must be a non-negative integer: %S"`
  error style as `:gap`; unknown keys, and grid-only keys on `:flex`, are
  still rejected.
- `textui--grid-gaps` is the single reader and returns
  `(COLUMN-GAP . ROW-GAP)` after applying the shorthand and per-axis
  overrides.
- Every grid path reads its own axis: the grid natural width in
  `textui--make-spec`, `textui--grid-column-count`, and the available width,
  track shares, and row separators in `textui--render-grid-content`, which now
  takes both gaps instead of one `gap`.
- `:flex` is unchanged; its `:gap` was already main-axis only (ADR 0040 records
  the cross-axis gap as deliberately out of scope).

## Existing grids are unchanged

Every `:gap`-only grid renders byte-identically. Twelve cases were rendered
with the pre-change core and the new core in batch and compared (a script that
prints each frame's plain text): responsive column reduction at widths 20, 13
and 6, shared track widths across rows, tallest-cell row height, border plus
padding, `:gap 0`, `:gap 2` with four tracks, CJK content, a `:text` child, a
nested grid, and an empty grid. `diff` between the two runs is empty. The
comparison loaded the old core from a scratch directory ahead of the working
tree (`emacs -Q --batch -L . -L /tmp/oldcore -l <script>`), so the two runs
differ only in `textui.el`.

The captured terminal fixture (`test/fixtures/terminal-composition.txt`), which
contains grids using `:gap 3` and `:gap 1`, still passes unchanged, and the
card-alignment probe's batch report is still `diff`-identical to its
pre-change output.

## Tests

Six layout tests in `test/textui-test.el`:

- `textui-grid-column-gap-separates-tracks-only` — three-cell track gap, row
  gap still one blank line, exact track positions;
- `textui-grid-row-gap-inserts-blank-rows-only` — two blank rows, column gap
  still one cell;
- `textui-grid-axis-gaps-override-the-gap-shorthand` — `:gap 9` with
  `:column-gap 2 :row-gap 3` renders byte-identically to the grid without the
  shorthand;
- `textui-grid-column-gap-controls-responsive-columns` — `textui--grid-column-count`
  reports two columns with a three-cell gap and three columns with the default
  at the same width, and the render drops from three to five lines;
- `textui-grid-axis-gaps-are-validated` — negative, float, string and nil
  values, an unknown key, and grid-only keys on `:flex`;
- `textui-grid-gap-shorthand-keeps-existing-grids-unchanged` — `:gap 2` equals
  `:column-gap 2 :row-gap 2` and is pinned against the exact pre-change rows.

One pixel-metrics test in `test/textui-pixel-composition-test.el`:

- `textui-pixel-composition-axis-gaps-keep-edges-exact` — four probe cards in
  one `:grid` with `:column-gap 5 :row-gap 2`; the two-row grid inserts exactly
  two blank lines, and every card border stays on the same pixel with the fake
  7px metrics.

Test summary lines:

```text
Ran 6 tests, 6 results as expected, 0 unexpected (2026-09-14 20:39:49-0700, 0.002049 sec)
Ran 6 tests, 6 results as expected, 0 unexpected (2026-09-14 20:39:49-0700, 0.055047 sec)
Ran 152 tests, 152 results as expected, 0 unexpected (2026-09-14 20:39:50-0700, 0.199146 sec)
```

The first line selects the six new grid tests, the second is the pixel
composition file, and the third is the full suite with
`native-comp-enable-subr-trampolines` nil. Byte-compiling `textui.el` and the
test files with `byte-compile-error-on-warn t` exits 0.

## Public behaviour that changed

- Two new element properties for `:grid`: `:column-gap` and `:row-gap`.
  Nothing was removed, renamed, or changed in meaning; `:gap` is still the
  shorthand it was.
- A grid whose column count or track widths previously had to be computed by a
  package can now be expressed as one grid, because the column gap drives the
  responsive calculation while the row gap only inserts blank lines.
- No vertical allocation model was added: `:row-gap` inserts blank lines
  between rows, exactly as `:gap` did.

## What Tag Cards can delete

Once the view switches its card field back to one `:grid` with
`:column-gap 3 :row-gap 1`:

- `supertag-view-tag-cards--card-rows` (splitting cards into one visual row
  per grid) and the responsive column count it feeds;
- `supertag-view-tag-cards--grid-columns` and
  `supertag-view-tag-cards--card-track-widths`, which exist to reproduce
  TextUI's track arithmetic (`--card-content-budget` callers that only need
  it for the same reason);
- the per-row grid construction around `--card-row-block` /
  `--compose-card-row`, together with the row-height equalization that went
  with it.

What should stay package-side: truncation and fill policy
(`--fit-label-to-target`, `--filled-string`, `--filled-title-string`), the
card row's own accent faces, and the measurement command.

## Not covered here

No live graphical confirmation was run; verification is batch-only as the task
requires. The pixel path is covered by the fake-metrics test above.
