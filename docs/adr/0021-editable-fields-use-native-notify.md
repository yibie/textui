# Editable fields use native :notify

TextUI adds no `:bind`, model object, or two-way state system. An editable native
widget receives its current `:value` from ordinary Lisp state when the render
function builds a frame. Its widget.el `:notify` callback reads
`(widget-value widget)` and writes that value back to the caller's state.

TextUI does not automatically refresh after `:notify`. widget.el already shows
the newly typed text, so rebuilding the whole frame after every character would
be unnecessary and would repeatedly replace the active field. When another
part of the interface must immediately show the changed state, the callback may
call `textui-refresh` explicitly. Otherwise the next action, external refresh,
or width-driven refresh presents the saved value naturally.
