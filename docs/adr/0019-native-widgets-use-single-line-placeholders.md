# Native widgets use single-line placeholders

Placeholder geometry remains unchanged, while
[ADR 0034](0034-widget-types-declare-optional-fast-paths.md) allows a widget
type to measure and attach without running its ordinary creation path.

TextUI v1 requires each native widget to present exactly one logical line;
multi-line interfaces are composed from those leaves with TextUI layout
elements. Measurement creates the widget in a temporary buffer, copies its plain
single-line output into a string carrying the original element as a TextUI text
property together with an internal source-order location ID, and discards the
temporary buffer. Flex lays out those placeholder strings like ordinary text,
writes the completed multi-line result into the real buffer, then scans
placeholder ranges from last to first and replaces each with a fresh
`widget-create` before one final `widget-setup`. The real widget retains the
location ID as a text property so point can return to the same native leaf after
responsive reflow. This follows the proven org-supertag dashboard pipeline
without its per-control placeholder registry and needs neither widget adapters
nor layout markers. A real widget whose width differs from its measured
placeholder signals an error immediately. A widget that produces a newline is
rejected during measurement because horizontal composition would split its
placeholder into non-contiguous regions; support for such controls is deferred
until a concrete need justifies another placement model.

When widget.el replaces fallback text with a narrower image glyph, TextUI uses
the image's `display` text property to cap it at one canonical-character height,
center it vertically, and reserve the fallback text's character width. If the
image is wider than its fallback or the fallback is too short to hold both image
and spacing, TextUI removes that `display` property and shows the fallback text.

Before replacing a later frame, TextUI calls `widget-delete` on every widget it
created in the real buffer and only then calls `erase-buffer`. `erase-buffer`
alone does not delete widget overlays: an old editable-field overlay can collapse
to the beginning and then expand across newly inserted text, turning the whole
row into one field. Measurement widgets need no matching cleanup because their
temporary buffer is discarded.
