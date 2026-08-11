# Manual performance experiments

These files are reproducible diagnostic experiments, not ERT tests. Run each
one in a fresh Emacs process from the repository root because several scripts
temporarily replace an internal function to isolate one hypothesis.

For example:

```sh
emacs -Q --batch -L . -L test -L test/performance \
  -l test/performance/textui-widget-phase-profile.el
```

Use byte-compiled `textui.el` and `textui-widgets.el` for release-like numbers.
Source loading is useful for relative comparisons but includes interpreter and
closure-conversion costs that are absent from an installed package.

| File | Question |
|---|---|
| `textui-widget-phase-profile.el` | Which full-refresh phase owns the time? |
| `textui-widget-cpu-profile.el` | Where does a field-heavy refresh spend CPU? |
| `textui-widget-cpu-profile-mixed.el` | Where does a mixed attached refresh spend CPU? |
| `textui-widget-region-benchmark.el` | How does a three-control region refresh scale by position? |
| `textui-widget-region-cpu-profile.el` | Where does region refresh spend CPU? |
| `textui-layout-shape-profile.el` | How do nested and flat layouts compare? |
| `textui-widget-attach-floor.el` | What is the native overlay attach/delete floor? |
| `textui-widget-forward-profile.el` | Does placeholder replacement direction matter? |
| `textui-widget-detach-profile.el` | Do explicitly detached markers change the result? |
| `textui-widget-inhibit-hooks-profile.el` | What changes when framework commits suppress modification hooks? |
| `textui-clear-field-registry-benchmark.el` | Does clearing the field registry before teardown help? |
| `textui-btop-reconcile-benchmark.el` | How do automatic reconciliation and the explicit region fast path compare? |

The forward, detach, inhibit-hooks, and clear-field-registry experiments are
deliberately retained negative controls. A result showing no improvement is
evidence against that hypothesis, not a broken test.
