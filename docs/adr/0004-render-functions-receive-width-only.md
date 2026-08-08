# Render functions receive width only

TextUI calls each render function with exactly one integer: the available window
body width. Caller state remains in ordinary variables and closures, and v1 does
not pass a general environment plist, height, buffer, window, or dispatcher.
Width is the only framework-owned input required by the agreed responsive
state-to-buffer model; keeping it explicit prevents a generic context object from
becoming a second API surface.
