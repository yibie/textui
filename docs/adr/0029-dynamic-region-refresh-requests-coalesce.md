# Dynamic region refresh requests coalesce

Timers, process sentinels, and other external callbacks may call
`textui-request-refresh-region BUFFER ID PRODUCER`. TextUI schedules the region
refresh after the current Emacs command returns. Repeated pending requests for
the same buffer and refresh ID keep only the latest producer, so a burst of
state changes renders the latest state once instead of building obsolete
frames.

The interface is deliberately narrower than a live-data system. TextUI does
not create or own timers, processes, subscriptions, pause state, data fetching,
or teardown. The application updates its state and requests a redraw. The
producer performs no I/O and has the same width-to-children contract as
`textui-refresh-region`.

Immediate `textui-refresh` and `textui-refresh-region` continue to reject
reentrant calls as programming errors. A requested refresh may be made during
an immediate refresh because its work is deferred. A dead buffer returns `nil`,
and a request whose region disappears during a later full render is stale and
is discarded.

The btop capability prototype is the first consumer. Its macOS sampler remains
application-owned, while its CPU and lower-panel redraws are requested together
and executed once on the next event-loop turn.
