# Text alignment is orthogonal to wrapping

## Context

TextUI already separates source text from display-only justification glue, but
all prose followed one alignment contract. EPUB title and contents pages supply
real evidence for additional alignment: publisher styles commonly center short
headings and links while keeping normal chapter prose justified. Encoding that
choice as a wrapping strategy would repeat the coupling rejected in ADR 0036.

Source characters and `textui--text-source-offset` properties are also used by
callers for navigation, selection, links, and annotations. Alignment therefore
cannot insert padding into the attributed source string.

## Decision

The semantic `:text` leaf accepts an optional `:align` property with four
values:

- `justify` is the default and preserves the existing behavior;
- `left` keeps natural ragged lines;
- `center` offsets each natural line by half its remaining pixel width;
- `right` offsets each natural line by its remaining pixel width.

`:wrap balanced` and `:wrap greedy` remain independent line-break choices.
Non-justified modes reuse the same tokenization, attributed substrings, pixel
measurement, and CJK break constraints, but skip glue expansion. Center and
right alignment prepend one zero-width source character whose display property
occupies the computed pixel offset. That prefix is marked
`textui--synthetic-spacing` and carries no source offset.

Alignment participates in the paragraph-plan cache key. Internal render and
cache helpers may carry it, but no separate public alignment function is
exposed; the `:text` property is the interface.

## Consequences

- Callers can preserve publisher intent without manufacturing source spaces.
- Navigation and annotation offsets still begin on the first real character.
- Existing callers retain justified paragraphs without changes.
- TextUI does not become a CSS engine; adapters normalize their own domain
  styles into the four semantic values.
- Tests must cover validation, display-only spacing, source offsets, and both
  supported Emacs versions.
