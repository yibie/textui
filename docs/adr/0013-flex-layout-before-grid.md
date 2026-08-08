# Flex layout before grid

The grid deferral in this decision ended with the accepted equal-track prototype
recorded in ADR 0025. The remaining flex-specific decisions below still apply.

TextUI v1 implements one-dimensional flex layout: rows, columns, gaps, width
allocation, and wrapping when space runs out. It does not promise a
two-dimensional grid with track sizing or row and column spans. Nested flex
layouts cover the first real dashboards already demonstrated by `org-supertag`;
grid will be designed only after a concrete interface cannot be expressed
clearly that way.

Both directions use one public `:flex` element with `:direction :row` or
`:direction :column`, rather than separate row and column types with duplicate
spacing and sizing rules.

V1 is width-driven. A row allocates horizontal space, while a column only stacks
children vertically, inserts gaps, and passes its assigned width downward. It
does not measure the window height, stretch children vertically, or apply
the layout `:grow` option to height.

Both directions use a non-negative integer `:gap` with a default of one. It
means spaces between row children and blank lines between column children; zero
packs children directly together.

Row children that are multi-line TextUI layout blocks align at their top edge.
Shorter blocks receive blank lines below them; v1 has no center, bottom, or
vertical-stretch alignment modes. Each native widget leaf remains single-line.
