# External state changes use explicit refresh

The lifecycle-ownership part of this decision is superseded by
[ADR 0031](0031-textui-owns-buffer-runtime-lifecycle.md).

The no-queue part of this decision is superseded by
[ADR 0029](0029-dynamic-region-refresh-requests-coalesce.md). Immediate full
and region refreshes still reject reentrancy; external callbacks may instead
request a coalesced asynchronous region refresh.

State changes from timers, process filters, or other callbacks request a
synchronous redraw with `textui-refresh BUFFER`. TextUI does not create or own
subscriptions, timers, processes, observers, or an effects system; callers keep
those lifecycles and retain the buffer returned by `textui-open`. Framework event
handlers should not call this function because successful events already refresh
once automatically. Refreshing a dead buffer object returns `nil` to tolerate a
normal asynchronous teardown race, while passing a live non-TextUI buffer signals
an error; buffer names are not accepted.

An immediate refresh call made while the same interface is already refreshing
signals a programming error instead of being queued or coalesced. This prevents
recursive render functions from creating an unbounded redraw loop; external
callbacks use the deliberately bounded request interface from ADR 0029.
