# Grid starts with equal responsive tracks

TextUI adds a `:grid` layout with a positive maximum `:columns`, a positive
`:min-column-width`, one shared `:gap`, and source-order `:children`. It uses as
many equal-width columns as fit, reduces the column count before going below the
declared minimum, keeps track starts shared across every row, and uses the
tallest cell as each row's height. This is the smallest behavior validated by
the interactive grid prototype; explicit track expressions and row or column
spans remain unsupported until a concrete interface requires them.
