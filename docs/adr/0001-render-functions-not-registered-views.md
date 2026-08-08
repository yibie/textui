# Render functions, not registered views

TextUI's public API opens a buffer backed by a render function; it does not expose
named view registration, view IDs, context builders, or a global view registry.
Ordinary Lisp variables and closures hold state, while callers own any commands or
domain-specific context they need. This keeps `org-supertag` concepts out of the
standalone package; its existing registered-view API belongs in its migration
translation boundary instead. A render function returns a proper list of zero
or more interface elements; even a single element is wrapped, and `nil` is an
empty frame. Top-level elements are presented in order without implicit spacing,
line breaks, or layout, so callers use an explicit layout element when
arrangement is required.
