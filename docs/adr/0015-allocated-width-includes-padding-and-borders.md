# Allocated width includes padding and borders

Every numeric layout `:width`, layout `:min-width`, and flex result denotes the
element's total visible width. Horizontal padding and borders consume columns
inside that amount instead of making the element wider than its parent. This
border-box rule makes container sizing composable and prevents framed children
from breaking the right edge after allocation.

Containers accept one non-negative integer `:padding`, defaulting to zero, and
apply it equally on all four sides. V1 does not expose separate per-side padding
properties.

A flex container may set boolean `:border t` to draw one Unicode single-line
frame inside its allocated width; the default is no border. V1 has no border
styles and no separate card, panel, or frame element type.
