# Open reuses one stable buffer

`(textui-open NAME RENDER-FUNCTION)` obtains NAME with `get-buffer-create`,
associates the render function, displays the buffer through ordinary
`display-buffer` policy, performs the initial render using the resulting real
window width, and returns the buffer object. An existing TextUI buffer with that
name is reused and reinitialized; an existing live non-TextUI buffer signals an
error instead of being overwritten or renamed. V1 accepts no display-action
argument and never creates `<2>`-style duplicate interface buffers on its own.
Opening installs a thin `textui-mode` derived from `special-mode`, leaves the
buffer writable so native editable fields work, and composes `widget-keymap`
ahead of `special-mode-map` for standard control navigation and activation.
Emacs labels rapid presses and releases as double- and triple-mouse events.
widget.el's ordinary button command waits for a release but does not recognize
those repeated-release variants, so routing repeated presses into that command
can consume later clicks. Following Emacs's own window-tool-bar pattern, the
mode ignores double- and triple-press events for mouse-1 and mouse-2, then
directly applies the native widget action on the matching repeated release.
This preserves one action per physical click without adding a TextUI event API.
TextUI adds no replacement focus commands, and v1 accepts no alternate-mode
argument.
