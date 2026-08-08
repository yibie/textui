# Focus anchors restore navigation after full refresh

Any interactive element may carry an optional frame-unique `:focus-id` inside
its `:layout` plist. TextUI uses it only to restore point and an intra-element
offset after full redraw; it does not drive diffing, reuse, identity, or lifecycle.
Every measured native element also receives an internal source-order location ID.
Its placeholder carries that ID through layout, and the materialized widget keeps
it as a text property. Without a matching explicit anchor, TextUI restores the
same native element and intra-element offset when that location still exists.
Every layout element likewise receives an internal source-order ID.
Its owned border, padding, and gap cells carry that ID together with their row
and display column inside the layout element; cells owned by a nested layout or
native widget keep the more specific location. TextUI therefore follows the
innermost layout element when responsive reflow moves it. The absolute
line-and-column fallback, clamped to the new buffer, applies only when point has
neither location.
Explicit `:focus-id` remains necessary when inserted, removed, or reordered
elements can change source-order locations between frames.

TextUI records the current anchor and offset in `pre-command-hook`. If a native
widget action refreshes synchronously, TextUI rebuilds the buffer immediately
but performs the final `goto-char` from `post-command-hook`, after the native
command has returned. This ordering is required because `widget-button-click`
uses its own `save-excursion`; erasing the old frame collapses that saved marker
to the beginning, and its later restoration would otherwise overwrite TextUI's
correct point. Refreshes outside an input command restore point immediately.
For every live window showing the buffer, TextUI also records the semantic
window point and its vertical row relative to `window-start`. It restores both
after rebuilding so a long interface does not jump back to the top while its
buffer point remains logically correct. Action-triggered restoration defers
this viewport step to `post-command-hook` together with point restoration.

Width-triggered refreshes keep laying out the buffer in real time, but hide its
cursor while resize events continue. TextUI restores the buffer's original
`cursor-type` 0.1 seconds after the last width change, avoiding visible cursor
movement without delaying responsive layout or changing logical focus.

Ordinary Emacs markers cannot provide this semantic restoration across
`erase-buffer`: they collapse to the deleted region's beginning or end. Native
`replace-buffer-contents` can preserve markers through text differences, but it
introduces diff semantics and is not directly compatible with live editable
widgets, so it is outside v1's full-redraw model. The `org-supertag` legacy
translation boundary may rewrite its old `:key` as
`:layout (:focus-id ...)`.

## What the cursor-drift investigation taught us

The original symptom appeared while resizing a complex nested dashboard: point
looked stable in the buffer but left the visual area the user considered its
owner. The first mitigation hid the cursor while resize events were arriving.
That removed visible intermediate jumps, but it did not preserve logical point.
Visual jitter and logical drift are separate problems and require separate
tests.

A later complex widget gallery exposed a third distinction: logical point and
the visible viewport are separate state. The semantic anchor correctly restored
the same field and offset, but `erase-buffer` reset `window-start`; the cursor
therefore moved from row 5 to row 28 in the window. The regression test now
uses a scrollable 40-line interface and checks the cursor's window-relative row
after both an explicit refresh and a deferred widget-action refresh. Restoring
only point is insufficient for a full-redraw interface.

Restoring the old buffer position was the first incorrect model. Restoring the
old line and display column was better for blank layout space, but remained an
absolute coordinate: when earlier content wrapped and moved a panel, point stayed
behind. Adding native-element IDs fixed widgets while leaving borders, padding,
and gaps with the same flaw. A position can be outside a native widget yet still
belong semantically to the innermost layout element surrounding it.

We also tested the proposal to retain an Emacs marker. A marker placed at buffer
position 4 moved to position 1 after `erase-buffer` and insertion of the new
frame. This is expected: a marker follows edits to old text; it cannot identify
which newly created widget or layout element represents the old semantic owner.
Widget start and end markers have the same limitation. Marker insertion type can
choose which edge of a deletion receives the marker, but cannot restore identity.

The resulting restoration order is deliberately semantic and most-specific
first:

1. An explicit `:focus-id` plus the offset inside its native widget.
2. A native source-order location plus its intra-widget offset.
3. The innermost layout source-order location plus its relative row and display
   column for borders, padding, and gaps.
4. The old absolute line and display column only when no semantic owner exists.

The regression test must therefore make absolute and semantic restoration
produce different results. `textui-refresh-restores-space-relative-to-its-layout`
first places point in the gap between `HOME` and `PROJECTS`, then makes preceding
content wrap so the entire owning panel moves downward. It passes only when point
moves with that panel and remains between the same two labels. A test that checks
only the final line or column can accidentally lock in the bug instead of the
intended behavior.
