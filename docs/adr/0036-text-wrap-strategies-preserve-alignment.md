# Text wrap strategies preserve one alignment contract

## Context

TextUI originally exposed only paragraph-wide Knuth--Plass break selection and
pixel justification. EPUB reading showed that global optimization dominated
interactive chunk latency, so `:text :wrap greedy` added a linear break
selector. Its first implementation returned natural ragged-right lines. That
made `:wrap` select two concerns at once and silently broke callers which relied
on the existing non-final-line alignment contract.

The same performance work added a bounded paragraph cache. A valid cache key
must describe the display semantics used during measurement, not merely the
symbolic face property. Disabling that cache must remain a rendering mode, not
an empty-frame mode.

## Decision

`:wrap` selects line-break strategy only:

- `balanced` runs the Knuth--Plass optimizer over the paragraph;
- `greedy` takes the furthest legal break in one linear pass.

Both strategies use TextUI's common tokenization, pixel measurement, CJK
kinsoku rules, attributed substrings, and display-only glue allocator. With the
default `:align justify`, both pixel-justify every feasible non-final line and
leave the final line naturally ragged. Callers select ragged or centered layout
through the separate `:align` capability recorded in ADR 0038, not by
overloading the break-strategy value.

The paragraph cache is buffer-local and bounded. Its key includes attributed
text, allocated pixel width, break strategy, face remapping, resolved metrics
of named faces referenced by the text, frame font geometry, and a global
display-environment generation. A size of zero bypasses lookup and storage and
runs the planner directly.

Theme enable/disable and `after-setting-font-hook` advance the generation.
`textui-invalidate-text-layout-cache` is the public escape hatch for direct
fontset mutations or other display changes which do not run those hooks.

## Consequences

- Low-latency callers keep greedy break selection without changing alignment.
- Source characters and their properties remain authoritative; synthetic
  display-only spacing is marked `textui--synthetic-spacing` and carries no
  source offset.
- Cache hits do a small resolved-face signature check. Theme and font changes
  cannot silently reuse old line breaks.
- Direct fontset mutation has an explicit invalidation responsibility when it
  bypasses Emacs's standard font hook.
