# Event errors do not refresh or roll back state

After an event handler returns normally, TextUI refreshes its buffer exactly
once. If the handler signals an error, TextUI leaves the current frame untouched
and re-signals the original error through normal Emacs mechanisms. It neither
shows a framework error state nor rolls back arbitrary Lisp mutations, so a
handler that mutates state before failing may leave state ahead of the visible
frame until the caller repairs it or requests another refresh.
