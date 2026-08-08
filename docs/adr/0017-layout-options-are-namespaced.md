# Layout options are namespaced

Every element keeps parent-facing TextUI metadata in a nested `:layout` plist.
Starting width, minimum width, grow weight, and focus ID therefore cannot collide
with same-named properties used by a rendered element. Flex's own direction,
gap, padding, border, and children remain properties of the flex element because
they describe how that container arranges its inside.
