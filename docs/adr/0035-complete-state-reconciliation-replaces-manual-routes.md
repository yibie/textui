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
  `:region`/`:producer` form of `textui-update`. The latter is an explicit
  performance fast path for a measured state update confined to one
  complete-line region. The state change, target, and producer remain together
  at the call site instead of forming a retained dependency graph. The same
  region APIs also serve external updates whose caller already knows the
  owning region.
- Do not replace manual routes with automatic dependency tracking, a retained
  component tree, or another state model. The measured complete-frame path is
  already within the experiment's interaction budget.

Automatic reconciliation is the default because TextUI can verify the complete
result. The explicit fast path is a caller-owned promise that the state change
does not affect the frame shell, responsive layout, another region, or a
lifecycle effect. It should be introduced only after measuring the automatic
path.

After retaining that fast path, the benchmark was changed to compare both
modes on the same revision. In the byte-compiled 1,000-row, 120-column fixture,
automatic reconciliation measured a 4.14 ms median and 4.31 ms p95; explicit
region update measured a 2.36 ms median and 2.48 ms p95. The fast path was
about 1.75 times faster while keeping its dependency promise local to the
update call.

This supersedes ADR 0032 and narrows the state-routing language in ADR 0033.
ADR 0031's buffer state and lifecycle-effect decisions remain unchanged.
