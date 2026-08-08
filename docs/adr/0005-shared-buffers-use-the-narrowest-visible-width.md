# Shared buffers use the narrowest visible width

When one TextUI buffer is visible in multiple windows, its available width is
one column less than the smallest live `window-body-width`. A logical line that
occupies the complete body width receives an empty visual continuation line, so
TextUI reserves that final display column. Emacs shares buffer text across windows, so v1
cannot present a different responsive frame in each window without clones or
window-specific rendering. Choosing the narrowest width makes every visible copy
fit deterministically, at the accepted cost of a narrow layout in wider copies.
TextUI automatically refreshes a visible interface only when this computed width
changes; callers do not install window-size hooks, and height-only changes do not
redraw the buffer.

While an interface is hidden, explicit refresh uses its last successfully used
width rather than borrowing the selected window's unrelated width or deferring
work. When the interface becomes visible again, TextUI refreshes once if its
computed visible width differs.
