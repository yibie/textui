# Keyed regions reconcile bounded complete-line items

## Context

ADR 0033 rejected a retained component tree, per-element frame comparison,
and component identity namespaces. Complete-line refresh regions were enough
for the retained 10,000-row table prototype because each simple row was cheap
to render.

An EPUB reader exposed a different cost shape. Its chapter window stays
bounded at 64 semantic blocks, but shifting that window replaced and reflowed
all 64 blocks. In two public books, ordinary page motion took below 1 ms while
chunk-boundary motion repeatedly took 100--260 ms synchronously. Idle
recentering added another 70--210 ms. Profiling attributed most synchronous
time to paragraph wrapping inside `textui--render-specs`; locator lookup was
below 1 ms. A typical shift retained 46 blocks and introduced only 18.

The existing region API cannot express that overlap. Making the reader splice
rendered buffer text would move TextUI-owned markers, widgets, focus anchors,
and layout invalidation into an application package.

## Decision

TextUI provides the optional `textui-keyed-region` module and one public
operation:

```elisp
(textui-reconcile-keyed-region buffer region-id producer)
```

The producer receives the installed region width and returns ordered, unique
`(KEY ELEMENT)` entries. Keys identify only the direct, complete-line children
of that one bounded column region. TextUI compares the previous and desired
orders, retains their longest common subsequence, renders new or changed
entries, and splices the intervening ranges. A stale generation or changed
width falls back to rendering the full desired region.

This is not identity in the general element tree:

- keys are local to one refresh region and are not valid outside it;
- keyed entries cannot nest keyed regions;
- no component instance, hook state, dependency graph, or reactive update is
  retained;
- the module retains only the current bounded entries and their rendered
  templates;
- the surrounding frame and region container still use ordinary TextUI
  reconciliation.

The container must remain a complete-line column Flex region without border or
padding. Column gaps are supported. Validation and rendering finish before the
buffer is changed; TextUI continues to own widget deletion/materialization,
focus-anchor shifts, region markers, and the rendered-frame cache.

## Consequences

- Sliding a bounded viewport lays out only entering or changed items while
  unchanged text and widgets retain identity.
- Applications provide stable domain keys and desired elements, but never
  buffer positions or edit instructions.
- Full refresh, width change, or any unrelated region commit invalidates the
  retained generation and safely pays one full keyed-region render next time.
- LCS comparison is quadratic in the bounded item count. This is intentional:
  it minimizes rendered items without adding a persistent element tree, and
  callers remain responsible for keeping the region bounded.
- The module is opt-in with `(require 'textui-keyed-region)`; ordinary TextUI
  users retain the simpler complete-region model from ADR 0027.
