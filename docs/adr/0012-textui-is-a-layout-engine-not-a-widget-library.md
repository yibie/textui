# TextUI is a layout engine, not a widget library

The layout-only framing is superseded by
[ADR 0031](0031-textui-owns-buffer-runtime-lifecycle.md). TextUI now also owns
the buffer runtime lifecycle; the decision not to replace `widget.el` remains.

The "no leaf types" part of this decision is superseded by
[ADR 0028](0028-prototypes-extract-proven-layout-primitives.md): TextUI may own
small rendering leaves such as `:text` and `:image` when real prototypes prove
that their geometry is layout work rather than application component policy.

TextUI's main product is the automatic layout missing from Emacs `widget.el`,
similar in purpose to web flex and grid layout. It owns layout elements but no
leaf types: text, buttons, fields, and other controls come directly from
`widget.el`, while TextUI reserves keyword types for layout elements such as
`:flex` and `:grid`. Headings, badges, progress displays, toolbars, and other
convenience vocabulary are built from widget types and layout elements by package-owned
element expanders. This keeps TextUI focused on measurement, responsive
arrangement, and redraw rather than growing into a component catalogue.
