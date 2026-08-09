# Plist state keys route to refresh regions

TextUI render functions may declare
`(textui-route-state REGION KEYS PRODUCER)`. `REGION` must name a complete-line
refresh region in the same rendered frame. `KEYS` are top-level keys in
`textui-state`, and `PRODUCER` has the existing `textui-refresh-region`
width-to-children contract.

`textui-update` takes a shallow snapshot of plist state before applying its
updater and compares top-level key presence and values afterward. If every
changed key has at least one route, TextUI coalesces and requests only the
union of those regions. One key may route to several regions, and one region
may cover several keys. If any changed key is not covered, state is not a
plist, or no top-level change is visible, TextUI preserves the previous
behavior and requests complete frame reconciliation.

A routed key is a promise that it affects only its declared regions. Keys that
change the frame shell, responsive layout, or lifecycle effects remain
unrouted, forcing a complete render. Producers read current state when they
run; they must not capture state values from the declaration render. Updaters
replace top-level values instead of mutating nested values in place so the
shallow comparison remains sound.

This is explicit dependency routing, not arbitrary Lisp dependency inference
or a retained component tree. It keeps `widget.el` in charge of controls and
reuses TextUI's existing refresh-region implementation, markers, request
coalescing, focus restoration, and full-render fallback.
