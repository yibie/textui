# Widget actions use native :action

TextUI does not define `:on-activate`, `:on-click`, or another control-event
property. A native widget element uses widget.el's effective `:action`, whether
the element supplies it or the widget type inherits it, which preserves the
control's keyboard, mouse, and other input behavior; TextUI wraps only that
resolved outer action so a normal return triggers one refresh. If the action
already called `textui-refresh-region`, TextUI does not add a full refresh. A
custom element may expose a domain-specific event name, but its pure expander
must translate that property to `:action` rather than adding an alias to TextUI
core. TextUI does not wrap widget.el's `:notify` and does not refresh after it implicitly,
because editable fields may notify after every change; a notify callback that
needs a redraw calls `textui-refresh` explicitly.
