# Refresh regions replace whole-line blocks

TextUI exposes bounded refresh through a frame-unique `:refresh-id` on a column
flex and `textui-refresh-region`, which replaces that container's children at
its existing width. A region must occupy one continuous sequence of complete
buffer lines: row/grid fragments and arbitrary text diffs are rejected because
their rendered cells are interleaved with surrounding layout. TextUI owns the
region markers, widget cleanup and recreation, and point restoration; callers
own state updates, data access, and deciding when to request the refresh.
