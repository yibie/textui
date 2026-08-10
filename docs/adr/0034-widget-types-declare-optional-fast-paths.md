# Widget types declare optional TextUI fast paths

Package-owned `widget.el` types may add two inherited properties to their
ordinary `define-widget` definitions:

- `:textui-measure` receives a converted widget and returns the exact
  single-line string that ordinary creation would present.
- `:textui-attach` receives a converted widget and the bounds of that already
  inserted string, attaches normal widget.el behavior without changing its
  width, and leaves exact `:from` and `:to` markers.

TextUI uses each property independently and retains ordinary creation for a
phase whose property is absent. Measurement and attachment errors remain direct
errors. A fast path therefore changes the cost of presenting a widget, not its
action, notification, validation, keymap, or inheritance semantics.

This is the public extension seam for a package that already owns widget types.
It needs no TextUI type registration and does not require inheriting from a
TextUI-defined control. `textui-widgets.el` exports reusable measurement and
attachment functions for padded text buttons, text-only checkboxes, and
fixed-width editable fields. Its `textui-button`, `textui-checkbox`, and
`textui-field` types are small examples built from the same properties, not a
recommended control layer. Packages should continue defining their controls
with widget.el and add the two fields to package-owned types when useful.

TextUI does not provide `:textui-enhanced t`. Skipping widget creation requires
an exact presentation string and type-specific attachment behavior; those facts
cannot be inferred safely from a boolean or from widget ancestry. TextUI also
does not add a widget adapter or profile registry. A different presentation may
supply its own two functions through widget.el's existing property inheritance.

This decision narrows the earlier universal two-pass decisions in ADRs 0016 and
0019 without replacing them: undeclared widget types continue through the
original path unchanged.
