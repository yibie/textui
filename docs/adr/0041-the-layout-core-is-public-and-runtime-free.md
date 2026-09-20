# The layout core is public and runtime-free

## Context

TextUI's layout geometry lived in private functions inside `textui.el`:
`textui--partition-row`, `textui--allocate-row`, `textui--proportional-shares`,
`textui--grid-column-count`, and the track arithmetic inlined in the grid
renderer. Nothing about these functions is TextUI-specific. They are integer
arithmetic over width constraints; they do not measure, and they never touch a
buffer, a widget, a marker, or a text property.

The shared-layout exploration in [issue #1] made the cost of keeping them
private concrete. VUI implemented the same rules independently in
`vui-layout.el` and ran TextUI's own conformance set, plus 11,000 seeded fuzz
cases, against both engines. Zero mismatches: the two allocators are one
algorithm under two sets of key names. Doing that comparison required pinning
a TextUI commit and calling five private functions, which has two consequences.
A private function can change shape in any release, so the comparison is only
valid for the pinned commit. And the harness had to reproduce TextUI's
composition step itself, because overflow widening was not in any function it
could call: it lived in the two renderer call sites,
`textui--render-row-line-block` and `textui--render-grid-content`. The
comparison therefore proved the rule and not TextUI's implementation of it.

Extraction into a shared package is a separate question, and the answer today
is no: the shared surface is about a hundred lines on each side, and a new
dependency for a hundred lines does not pay for itself. What the comparison
showed is worth keeping regardless of that answer.

## Decision

The geometry moves to `textui-layout.el` and becomes public as
`textui-layout-*`. The file requires `cl-lib` and nothing else, and its
Commentary carries the contract: the spec vocabulary (`:start`, `:minimum`,
`:grow`, `:rigid`), the placement shape, the semantics of partitioning,
allocation, grids and overflow, and the exact mapping onto vui-layout's
vocabulary.

The public surface has two levels, because the two have different users:

- End-to-end. `textui-layout-solve` lays out a row of specs and returns one
  placement, `(:row R :column C :width W)`, per child in source order;
  `textui-layout-grid` does the same for a responsive equal-track grid. A
  consumer that wants geometry asks one question and gets an answer it can
  compare, rather than having to know that partitioning happens before
  allocation and that rows are independent.
- Parts. `textui-layout-shares`, `textui-layout-partition`,
  `textui-layout-allocate`, `textui-layout-grid-columns`, and
  `textui-layout-grid-tracks` remain separately callable, because a
  conformance harness that disagrees with an end-to-end result needs to see
  which step disagreed. The end-to-end entries are compositions of these
  parts, and a test holds them to that, so neither level can drift from the
  other.

`textui-layout-columns` publishes the overflow rule: assigned widths widened
to the widths blocks actually rendered to. That is the half of composition
that is geometry, and both renderer call sites now go through it. Overflow is
part of the contract, as the issue concluded it should be, and it is now
reachable by an external harness. The other half of composition stays private
and stays in `textui.el`, because TextUI's padding is not generic: it carries
`textui--refresh-id` ownership onto the padding it appends, and on graphical
frames it pads to cumulative pixel budgets with display spacers (ADR 0039).
A composer parameterised over measuring and padding would either lose that or
leak it.

Rigidity stops being inferred from the element kind. `textui--make-spec` marks
native specs `:rigid t`, and allocation reads that flag instead of testing for
`:kind :native`. The layout core has no opinion about widgets; it only needs
to know which children cannot be re-rendered narrower.

The shared conformance cases live in
`test/textui-layout-conformance-cases.el` as one constant of plain data, with
no requires and no engine named. Expectations there were worked out from the
written rules rather than recorded from a run, so a failure means an engine
disagrees with the contract. `test/textui-layout-test.el` runs them against
TextUI; another implementation can load the same file and run them against
itself.

`textui--partition-row`, `textui--allocate-row`, and
`textui--proportional-shares` remain as obsolete aliases, so code already
calling the private spellings, including the pinned harness, keeps working.

`:min-column-width` stays a required positive integer (ADR 0025), and
`textui-layout-grid-columns` documents why rather than guarding at use: a grid
with no floor has no defined response to narrowing, so TextUI rejects it at
validation and keeps the arithmetic guard-free. An engine that accepts a
missing minimum differs from TextUI only on inputs TextUI refuses.

## Consequences

- Another engine can compare itself against a stable API and a written
  contract instead of a pinned commit, and the comparison now covers TextUI's
  own overflow code rather than a reimplementation of the rule.
- The geometry is testable without a buffer, a frame, or a widget, which is
  why the conformance suite runs in well under a millisecond.
- `textui-layout.el` is small, pure and dependency-free, so if pixel units,
  spans, or Knuth–Plass measurement later make a shared package worth its
  cost, extraction is a file move rather than a redesign. That remains a
  future decision, not this one.
- The public surface is a compatibility commitment: these names now change
  only through the deprecation path, where before they could change in any
  release. If a shared package is ever worth its cost, its prefix should
  belong to neither package, so these names would move once, through that same
  path; the contract they carry would not change with them.
- `textui-layout-shares` adopts vui-layout's cons-cursor walk over the
  previous index-based one, which was quadratic in the number of children in a
  row and ran on every re-render of every shrinking row. The grid renderer's
  per-track maximum loses its `nthcdr` indexing for the same reason.

[issue #1]: https://github.com/yibie/textui/issues/1
