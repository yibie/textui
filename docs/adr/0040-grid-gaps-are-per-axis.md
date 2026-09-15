# Grid gaps are per axis

## Context

`:grid` had one `:gap` that served two different quantities: cells between
tracks, and blank lines between the grid's visual rows. The two were never the
same number in practice. Downstream supertag Tag Cards needs three cells
between card tracks and one blank line between card rows; because one `:gap`
could not express that, the package rendered one `:grid` per visual row of
cards and recomputed the responsive column count, the track widths, and the
pixel padding itself. That duplicated TextUI's column arithmetic outside the
framework, lost the single-element grid, and gave up TextUI's focus
reconciliation for the buttons inside those rows.

ADR 0039 made the track gaps and box interiors pixel-exact, which prompted an
audit of every `:gap` read. The audit found the shorthand used for the wrong
axis in several places, all reachable from the same element: the natural-width
measurement and `textui--grid-column-count` need the column gap, the track
shares need the column gap, and the blank lines between rows need the row gap.
`:flex` does not share this problem: its `:gap` applies to the main axis alone
(cells between row children, blank lines between column children), and wrapped
flex rows insert no cross-axis gap today.

## Decision

`:grid` accepts two new properties, both non-negative integers:

```elisp
(:type :grid
 :columns 3
 :min-column-width 20
 :column-gap 3
 :row-gap 1
 :children (...))
```

- `:column-gap` is the number of cells between tracks.
- `:row-gap` is the number of blank lines between grid rows.
- `:gap` remains the shorthand for both axes, as it was before this ADR.
- Precedence is per axis: `:column-gap` overrides `:gap` for the column axis
  and `:row-gap` overrides it for the row axis. A shorthand-only grid therefore
  renders exactly as it did, and a mixed grid (say `:gap 1 :row-gap 2`) changes
  only the overridden axis.
- An axis with neither property keeps its current default of one cell.

`textui--grid-gaps` is the single reader: it returns `(COLUMN-GAP . ROW-GAP)`
after applying the shorthand and the per-axis overrides.
`textui--validate-grid` accepts both keys, rejects negative or non-integer
values with the same error style as `:gap`, and keeps rejecting unknown keys;
`:flex` still rejects both keys because its gap is main-axis only.

Every grid path reads the axis it needs: natural-width measurement in
`textui--make-spec`, `textui--grid-column-count`, the available width and
track shares in `textui--render-grid-content`, and the row separators in the
same function, which now receives both gaps explicitly instead of one `gap`.

`:flex` is deliberately unchanged. Adding cross-axis gaps to flex is a separate
design question (wrapped rows currently have no cross-axis gap at all), and a
main-axis `:gap` on the two `:flex :direction` values is already unambiguous.

## Consequences

- Every existing `:gap`-only grid renders byte-identically; the shorthand is
  the same value for both axes it already fed.
- A responsive column calculation can keep its track count while a grid row
  separator uses a different height, so one `:grid` can replace a package's
  per-row grid duplication.
- The two properties are layout input only: no new public function, no vertical
  allocation model, and `:row-gap` inserts blank lines rather than reserving
  space.
- Column-track arithmetic keeps one source of truth in the framework, so a
  downstream package no longer needs to reproduce it.
