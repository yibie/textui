# TextUI does not own multi-buffer app shells

TextUI interfaces remain one stable buffer. A package may compose several
TextUI buffers with ordinary Emacs windows, but TextUI will not present that
composition as one interface or add a multi-buffer application abstraction.

## Experiment

The K9s demo was split into three dedicated TextUI buffers and windows: a fixed
header, a natively scrollable row buffer, and a fixed footer. This achieved the
performance goal: scrolling changed the row window's `window-start` without
calling `textui-refresh`, rerunning the DSL, rebuilding widgets, or fetching
data. The prototype used 99 widgets across three buffers, so its direct runtime
and memory overhead was small.

The interaction recording nevertheless exposed the ownership boundary. Emacs
presented separate scroll-bar regions and beginning/end-of-buffer messages;
the table's side borders disappeared between the final data row and the fixed
footer; focus, point, scrolling, and empty space visibly belonged to different
editor windows. The result behaved like three coordinated buffers rather than
one TUI application.
The prototype is therefore rejected as reference architecture and must not be
copied into TextUI core as the solution to scrolling performance.

## Consequences

TextUI remains responsible for layout and refresh inside one buffer, not for
splitting windows or coordinating buffer creation, teardown, reopening,
resizing, focus, key routing, and cross-buffer state. The prototype already
required a header action to refresh the row buffer explicitly, showing how a
multi-buffer shell moves application lifecycle into TextUI.

The follow-up experiment below proves that scrolling performance does not
require a multi-buffer shell. Reconsider a TextUI-owned multi-buffer shell only
if the project's scope deliberately expands from a layout engine into an Emacs
window manager.

## Follow-up: one-buffer bounded viewport replacement

`examples/textui-k9s-local-refresh-prototype.el` keeps the complete K9s-like
interface in one buffer and marks only its data viewport for replacement. It
loaded 10,000 deterministic pod rows into one vector, cached the current scope,
and sliced only the visible rows for each scroll action. Jumping directly to the
final viewport therefore cost the same kind of work as scrolling near the
beginning; the renderer never walked through the preceding 9,988 rows.

The first attempt located the viewport by an absolute header line count. That
failed immediately when the responsive header wrapped in a narrow window. The
working prototype then derived Emacs markers from semantic anchors around the
viewport. The framework version now derives and owns those markers from the
column flex's `:layout (:refresh-id rows)` declaration.

A scroll action performs one bounded replacement rather than a per-cell diff:

1. Reduce the viewport offset and slice the visible rows.
2. Render only those rows into TextUI's deferred-widget placeholder string.
3. Delete real widgets and focus anchors beginning inside the marked region.
4. Delete the marked text, insert the new string, and materialize its widgets.
5. Restore point to the same viewport-relative row and display column.

Deleting and inserting text alone is insufficient because stale widget
overlays and markers would survive. Conversely, comparing individual cells is
unnecessary: replacing the entire small region remained fast and kept widget
lifecycle explicit. Header, footer, cached data, and other widgets are not
rebuilt during ordinary scrolling.

The application, not TextUI's layout engine, computes viewport height. It uses
the live `window-body-height`, subtracts the responsive header's actually
rendered line count and one footer line, and keeps at least one data row. A
height-only resize replaces the marked region with more or fewer rows; it does
not perform a full frame render. Width changes and scope changes may still use a
full render because they can change surrounding layout.

On the local batch probe, creating all 10,000 row records took about 29 ms,
jumping to offset 9,988 replaced the viewport in about 0.78 ms, and 100 ordinary
local scroll replacements averaged about 1.12 ms with no additional full
render. Changing the simulated body height from 20 to 35 rows changed the
viewport from 2 to 17 rows, again with no full render. These timings include row
layout, buffer mutation, widget recreation, and point restoration, but exclude
Emacs's subsequent screen redisplay; they are evidence of feasibility, not a
performance guarantee.

This experiment became the public `textui-refresh-region` capability recorded
in ADR 0027. The K9s prototype now uses that public function and no longer owns
markers, widget deletion, placeholder materialization, or point restoration.
