# Complete state reconciliation replaces manual routes

ADR 0032 added `textui-route-state`, a manually maintained mapping from
top-level plist keys to named refresh-region producers. It made a routed btop
update faster, but a route was also a promise that each listed key affected
only those regions. When a routed key later affected the frame shell, another
region, responsive layout, or a lifecycle effect, TextUI could leave part of
the interface stale without reporting an error.

The route-free experiment in commit `315ee79` changed ordinary
`textui-update` calls to evaluate the complete frame and let the existing
block reconciler patch changed named regions. A regression test reproduced the
stale-shell failure before that change and passed afterward.

In a byte-compiled btop fixture with 1,000 process rows, a 120-column window,
42 visible rows, and 31 samples, the routed path measured a 2.39 ms median.
The route-free path measured 4.13 ms with a 4.30 ms p95. At 150 columns, the
heaviest route-free fixture measured 5.02 ms with a 5.19 ms p95. These are
fixed-fixture measurements on one machine, not cross-machine guarantees; the
runnable benchmark is `test/performance/textui-btop-reconcile-benchmark.el`.

## Decision

- Remove `textui-route-state`, its key comparison, stored route graph, and
  btop-specific routing helper.
- Every ordinary `textui-update` and `textui-set-state` evaluates the complete
  frame. Existing reconciliation preserves unchanged named regions and patches
  changed regions when the frame shell is stable.
- Keep `textui-refresh-region`, `textui-request-refresh-region`, and the
  `:region`/`:producer` form of `textui-update`. They serve explicit external
  updates whose caller already knows the owning complete-line region; they are
  not inferred from application state.
- Do not replace manual routes with automatic dependency tracking, a retained
  component tree, or another state model. The measured complete-frame path is
  already within the experiment's interaction budget.

This supersedes ADR 0032 and narrows the state-routing language in ADR 0033.
ADR 0031's buffer state and lifecycle-effect decisions remain unchanged.
