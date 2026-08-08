# Flex layout starts at natural width

Flex children start at the width their presented content naturally needs. A row
does not divide all available space equally or stretch short text and buttons by
default; unused space remains empty unless a child explicitly opts into growth.
This gives TextUI predictable text-first behavior while preserving automatic
measurement.

After subtracting all child natural widths and gaps from the row's available
width, TextUI distributes positive remaining columns in proportion to each
child's non-negative numeric `:layout` `:grow` value; the default is zero. A leaf
keeps its content unchanged and pads its assigned area, while a nested layout
receives the assigned width for its own calculation.

When a row is too wide, TextUI first shrinks TextUI layout children from their
natural widths without taking any below their layout `:min-width`. Native
widget.el leaves are atomic: TextUI can measure, pad, or wrap the whole widget,
but cannot crop or shorten it, so its minimum always equals its measured natural
width and specifying `:min-width` on it is an error. Only if the row still cannot
fit after shrinkable layout children reach their minima does TextUI wrap later
children onto the next row. Emacs windows remain freely resizable; minimum width
is a layout rule, not a minimum window-size promise.

If layout `:min-width` is absent, a layout element's minimum equals its natural
width, so it does not shrink and wraps as a whole when necessary. TextUI does not
guess where labels may split, how narrow an input remains usable, or which table
column may be sacrificed; callers opt a layout into shrinking by supplying the
limit.

When several layout children can shrink, each absorbs overflow in proportion to
its shrink capacity (`natural width - minimum width`). They therefore consume
the same fraction of their permitted reduction, without a separate `:shrink`
property. Atomic widget leaves contribute no shrink capacity.

Wrapping packs children from left to right without reordering. Once a child
cannot join the current row at minimum widths, it starts the next row and later
children follow it; a smaller later child never jumps ahead merely to fill a
gap. Visual and keyboard order therefore remain stable across window widths.

Minimum width cannot constrain an Emacs window. If one TextUI layout child
already occupies a row by itself and its minimum still exceeds the row's actual
width, TextUI assigns the actual row width and lets that layout reflow its
contents. A wider atomic widget remains governed by Emacs's normal display
behavior because TextUI cannot reformat it.

If no child grows and the row is narrower than its available width, children
remain packed at the left and unused columns stay at the right. V1 adds no
centering or automatic space-distribution mode; layout `:grow` is the single way
to consume surplus width.

A positive integer layout `:width` replaces natural width as a TextUI layout
child's starting width. It remains eligible for growth when layout `:grow` is
positive and for shrinking when a smaller layout `:min-width` is present;
without either, it behaves as a fixed width. A native widget is still measured,
and its starting width is the larger of its natural width and numeric layout
`:width`, so the property may add surrounding space but cannot squeeze the
atomic widget.

V1 has no `:max-width`. A child's allocation is already capped by its parent
container, and siblings divide that bounded space through natural width, growth,
minimum width, and wrapping. A separate upper cap adds no required first-release
capability.
