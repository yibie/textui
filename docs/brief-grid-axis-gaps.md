# Task brief: separate column and row gaps for `:grid`

Authorized by the maintainer. Downstream evidence: supertag Tag Cards needs
three cells between card tracks and one blank line between card rows. With
one `:gap` it had to render one `:grid` per visual row of cards, which
duplicates the responsive column calculation and loses the single-element
grid. Read first: `CONTEXT.md`, README "Grid", ADR 0039, and the existing
`:gap` handling (`textui--validate-layout-container`,
`textui--validate-grid`, `textui--grid-column-count`,
`textui--render-grid-content`, the natural-size and minimum-width
calculations near line 555, and the grid spec construction near lines
1369 and 1388). Follow TextUI conventions (ADR, CHANGELOG, README, tests,
Emacs 29, batch-only verification). Do not commit.

## Scope

`:grid` only. `:flex` stays as it is: its `:gap` already applies to the
main axis alone (cells between row children, blank lines between column
children), and wrapped flex rows insert no cross-axis gap today; record
that in the ADR as deliberately out of scope.

## Change

1. **New grid properties.** `:column-gap` (cells between tracks) and
   `:row-gap` (blank lines between grid rows), both non-negative integers.
   `:gap` stays as the shorthand for both, so every existing grid renders
   byte-identically. Precedence: an axis-specific property overrides
   `:gap` for its axis; when neither is given the axis default stays what
   it is today (1).
2. **Validation.** Accept the two keys in `textui--validate-grid`, reject
   negative or non-integer values with the same error style as `:gap`,
   and keep rejecting unknown keys.
3. **Everywhere the grid uses its gap.** Column count
   (`textui--grid-column-count` with `:min-column-width`), available width
   and track shares, the pixel row composer from ADR 0039, the
   natural/minimum width measurement used by parents, and the blank lines
   inserted between grid rows. Audit every `:gap` read for grids so no path
   still uses the shorthand for the wrong axis.
4. **Tests.** Column gap only, row gap only, both with `:gap` present
   (overrides win), responsive column reduction honouring `:column-gap`,
   validation errors, a pixel-metrics test proving edges stay exact with a
   non-default column gap, and a fixture check that existing `:gap`-only
   grids are unchanged. Full suite green with
   `native-comp-enable-subr-trampolines` nil; byte-compile with warnings as
   errors.
5. **Docs.** ADR (next number), CHANGELOG, README Grid section with an
   example using `:column-gap 3 :row-gap 1`, and a short report at
   `docs/report-grid-axis-gaps.md`.
