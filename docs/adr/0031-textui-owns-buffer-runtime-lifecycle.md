# TextUI owns the buffer runtime lifecycle

This decision supersedes the lifecycle-ownership parts of
[ADR 0008](0008-external-state-changes-use-explicit-refresh.md),
[ADR 0029](0029-dynamic-region-refresh-requests-coalesce.md), and
[ADR 0030](0030-six-focused-examples.md). Their refresh and example-set
decisions remain in force.

TextUI is a buffer-level UI runtime built on `widget.el`, not a replacement
widget library. `widget.el` continues to own controls, input behavior,
validation, and custom widget definitions. TextUI owns application-state
coordination, effect lifetime, refresh reconciliation, focus preservation, and
responsive layout. The package using TextUI still owns domain data, commands,
parsing, and the native timers, processes, or subscriptions it creates.

A render function may declare a keyed `textui-effect` with explicit dependency
values. TextUI starts it after committing the frame, retains it while those
values remain `equal`, and runs its cleanup before a dependency change, when a
later frame omits it, or when the TextUI buffer is killed. A
`textui-async-callback` created by the setup restores the owning buffer and
ignores late calls after that effect stops. This is sufficient to coordinate
native Emacs timers, process sentinels, and subscriptions without wrapping them
in a second resource system. Effects reconcile when the complete render
function runs; direct region refreshes deliberately skip both layout and effect
evaluation.

State remains one ordinary buffer-local Lisp value. `textui-update` supports
arbitrary state, while `textui-set-state` is the concise plist-key path used by
most widget actions. TextUI does not introduce a retained component tree,
component-local state, automatic Lisp dependency inference, or another control
protocol. Those additions require separate evidence; buffer-level identity is
the current seam.
