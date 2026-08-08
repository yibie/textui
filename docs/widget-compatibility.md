# widget.el display compatibility

TextUI can place a widget.el type when its chosen properties render exactly one
logical line during measurement and the real presentation has the same width.
The compatibility test measures the fallback text below and then materializes
all 21 representatives together in one real TextUI buffer.

| Type | Tested fallback width | Notes |
| --- | ---: | --- |
| `item` | 4 | Uses `:format "%v"` to remove its default newline. |
| `push-button` | 6 | Includes the textual button brackets. |
| `link` | 6 | Includes the textual link brackets. |
| `editable-field` | 8 | Fixed `:size 8`. |
| `toggle` | 2 | Uses a one-line format and `ON`/`OFF` text. |
| `checkbox` | 3 | `[X]`/`[ ]`; an image glyph retains this fallback width. |
| `radio-button` | 3 | `(*)`/`( )`; an image glyph retains this fallback width. |
| `visibility` | 4 | `Show`/`Hide`. |
| `choice-item` | 6 | Uses a one-line format. |
| `const` | 2 | Uses `:format "%v"` to remove its default newline. |
| `string` | 8 | Fixed `:size 8`. |
| `regexp` | 8 | Fixed `:size 8`. |
| `file` | 10 | Fixed `:size 10`. |
| `directory` | 10 | Fixed `:size 10`. |
| `symbol` | 8 | Fixed `:size 8`. |
| `integer` | 6 | Fixed `:size 6`. |
| `natnum` | 6 | Fixed `:size 6`. |
| `number` | 6 | Fixed `:size 6`. |
| `float` | 6 | Fixed `:size 6`. |
| `character` | 1 | One character. |
| `color` | 20 | One editable field plus widget.el's `Choose` button. |

This is a tested sample, not an allowlist. Package-owned widgets derived from
these types use the same path; the test suite separately covers inherited
buttons, image-glyph toggles, editable fields, and a custom `:value-create`
renderer.

Composite types such as `text` with a multiline value, `checklist`,
`radio-button-choice`, `editable-list`, and the collection editors generally
produce more than one logical line and are therefore not native TextUI leaves.
Build their presentation from TextUI layout elements and single-line widget
leaves instead. A `menu-choice` using its normal child presentation also
produced a newline in the compatibility probe and was rejected before the real
buffer changed.
