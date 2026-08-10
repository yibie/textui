# Measure elements by temporary rendering

The universal fallback remains, but package widget types may now declare the
optional fast path recorded in
[ADR 0034](0034-widget-types-declare-optional-fast-paths.md).

TextUI has no widget-adapter registry. Each refresh calls its render function
and element expanders once, then uses that same computed frame first in a
temporary buffer to measure widest lines and again in the real buffer after
layout, so a custom widget's creation code must tolerate being called twice.
Native widget elements pass their type and non-layout properties directly to
`widget-create`; `widget.el` remains the sole authority for control behavior
while TextUI owns measurement, layout, and refresh. This universal two-pass
mechanism avoids inconsistent frames, guessed widths, and a duplicate widget
type hierarchy inside TextUI. TextUI does not track or individually call
`widget-delete` on measurement widgets: Emacs discards the temporary buffer,
and creation or measurement errors propagate immediately. Any external resource
created by a custom widget remains that widget author's responsibility. A
TextUI layout element with numeric `:layout :width` already has a starting width
and may skip natural-width measurement. A native widget is always measured,
even when it supplies that property, because its starting width must be the
larger of the declared width and the natural width that TextUI cannot reduce.
Measurement also requires every native widget to produce exactly one logical
line and signals an error before real presentation if it contains a newline.
TextUI saves the measured plain text as a deferred placeholder carrying the
original element, rather than trying to move a temporary widget into the real
buffer.
