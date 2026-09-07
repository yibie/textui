# Changelog

This file records user-visible changes to TextUI. Dates use the release tag's
calendar date.

## Unreleased

## [0.8.0] - 2026-09-06

### Added

- Add orthogonal `:text :align` values `justify`, `left`, `center`, and `right`.
  Center and right alignment use display-only pixel spacing and preserve source
  characters and source-offset properties. See ADR 0038.
- Add `textui-layout-widget`, a standalone API that asks a package-owned
  `widget.el` block widget to lay itself out at an allocated character width.
- Add `textui-attach-widget`, a standalone API that attaches an already
  rendered block widget to existing text in any buffer without requiring
  `textui-mode`.
- Add the inherited `:textui-layout` block-widget protocol. Its callback
  receives the converted widget and allocated width and returns non-empty
  multiline text; `:textui-attach` then adopts that text without rewriting it.

### Changed

- Permit width-aware block widgets as top-level TextUI frame elements while
  retaining the existing single-line contract for ordinary native widgets.
- Keep block widgets explicitly top-level-only. Flex and grid children still
  require composable line blocks rather than embedded multiline native text.

### Fixed

- Allocate native location IDs consistently across ordinary and block widgets,
  beginning at zero and preserving source order.
- Validate standalone attachment bounds, marker ownership, deletion lifecycle,
  and plain-text preservation before accepting a block widget.

## Performance history

| Release | Fixture | Before | After | Change |
|---|---|---:|---:|---:|
| 0.5.1 | btop, 1,000 process rows at 120 columns | 4.14 ms, automatic reconciliation | 2.36 ms, explicit region update | 1.75x faster opt-in path |
| 0.5.0 | btop, 1,000 process rows at 120 columns | 2.39 ms, state routing | 4.13 ms, complete reconciliation | 1.74 ms spent to remove manual dependencies |
| 0.2.0 | btop, one routed detail update across 50 process rows | 11.65 ms, full refresh | 5.67 ms, state-to-region routing | 2.05x faster |
| 0.3.0, public extension in 0.4.0 | Full refresh of 3,000 native controls | 596.55 ms, generic native path | 238.58 ms, attached path | 2.50x faster |

These are medians from fixed fixtures on the release machine, not
cross-machine guarantees. The retained diagnostic programs and instructions
are under [`test/performance/`](test/performance/README.md).

## [0.7.1] - 2026-09-05

### Fixed

- Preserve a complete-line refresh region's ownership when an outer layout
  box pads that child to the width of a wider sibling. This prevents image
  pixel rounding and similar one-cell width differences from making a valid
  refresh region fail the complete-line invariant.

## [0.7.0] - 2026-09-04

### Added

- Add the optional `textui-keyed-region` deep module for incrementally
  reconciling ordered, stable items inside one bounded complete-line column.
  It preserves unchanged rendered items and widgets, while width changes and
  unrelated refreshes safely invalidate the optimization. See ADR 0037.

## [0.6.0] - 2026-09-01

### Added

- `:text` accepts `:wrap` with `balanced` (default, Knuth–Plass) or `greedy`,
  a linear-time low-latency break strategy for interactive readers.
- A bounded paragraph layout cache (`textui-text-layout-cache-size`, default
  2048 entries) memoizes text planning per content, pixel width, and wrap
  strategy, with `textui-invalidate-text-layout-cache` as the manual escape
  hatch. See ADR 0036 for the alignment contract.

### Changed

- `:text :wrap greedy` changes break selection without changing TextUI's
  non-final-line pixel-justification contract. It remains kinsoku-aware and
  preserves attributed source characters.
- Paragraph cache keys include resolved named-face metrics and a theme/font
  environment generation, and they track `face-remap-alist` entries in both
  proper-list and dotted-pair forms. A zero cache size plans text directly.

### Fixed

- The graphical `:image` path built its rows as unibyte strings and spliced
  the alternative text with `store-substring`, so a CJK alt signaled
  "Attempt to store non-byte value into unibyte string" and text properties
  on the alt were dropped. Rows are now multibyte and property-preserving.
- Alt splicing is now bounded by both display width and character count, so
  combining-mark or variation-selector sequences whose character count
  exceeds their display width no longer signal `args-out-of-range`.
- A letterboxed image places its alt and its property carrier on the leaf's
  first row, so external row-range bookkeeping starts at the leaf instead of
  the first visible slice.

- An action-triggered refresh read `textui--focus-before-command` and
  `textui--position-before-command` as plain variables. Both are buffer-local
  and are written in the refreshed buffer, so a widget action running while
  another buffer was current read the global `nil`, and the refresh reported
  `wrong-type-argument number-or-marker-p nil` from `post-command-hook` while
  losing point. Both are now read with `buffer-local-value` from the target
  buffer, matching the guards beside them.
- When an action has no pre-command snapshot, a full-frame refresh now captures
  focus and position from the target buffer before replacing its contents.
  Window-view capture and post-command restoration therefore receive valid
  fallbacks instead of aborting on `nil`.

## [0.5.1] - 2026-08-11

### Documentation

- Document `textui-update` with `:region` and `:producer` as an opt-in
  performance fast path for a measured state update confined to one region.
  Automatic complete-frame reconciliation remains the default, and no
  key-to-region dependency graph is restored.

### Performance

- Expand the retained btop benchmark to compare both supported state-update
  modes on the same revision. With 1,000 rows at 120 columns, automatic
  reconciliation measured 4.14 ms median and the explicit region fast path
  measured 2.36 ms, about 1.75 times faster on that fixture.

## [0.5.0] - 2026-08-11

### Changed

- Remove `textui-route-state` and its manually maintained state dependency
  graph. Ordinary state updates now always evaluate the complete frame and let
  TextUI automatically patch changed named regions when the shell is stable.
- Keep explicit region refresh for external updates whose caller already knows
  the owning complete-line region.

### Performance

- In the byte-compiled 1,000-row btop fixture at 120 columns, complete
  reconciliation measured a 4.13 ms median and 4.30 ms p95 versus 2.39 ms for
  state routing. TextUI accepts the 1.74 ms median cost to remove a stale-UI
  failure mode and the caller-maintained dependency graph.

### Documentation

- Clarify that the bundled `textui-button`, `textui-checkbox`, and
  `textui-field` definitions are small protocol examples, not a recommended
  replacement widget layer. Package authors should continue defining controls
  with Emacs `widget.el` and add TextUI fast-path fields only when needed.

## [0.4.0] - 2026-08-10

### Added

- Make the inherited `:textui-measure` and `:textui-attach` widget properties
  the public fast-path protocol for package-owned `widget.el` types.
- Export measurement and attachment helpers for padded text buttons, text-only
  checkboxes, and fixed-width editable fields.
- Document the extension contract and its invariants in ADR 0034.

### Changed

- Preserve custom widget actions, notifications, validation, keymaps, and type
  identity while accelerating only measurement and buffer attachment.
- Keep the protocol registration-free: packages add fields to their ordinary
  `define-widget` definitions instead of adopting another widget hierarchy.

### Performance

- In the 3,000-control release fixture, the attached path measured 238.58 ms
  versus 596.55 ms for the generic native path. These figures describe that
  fixture and machine, not a cross-system guarantee.

## [0.3.0] - 2026-08-10

### Added

- Add the optional `textui-widgets` fast-path implementation and retain the
  diagnostic widget benchmarks under `test/performance/`.

### Changed

- Reuse rendered placeholders when attaching supported native controls instead
  of deleting and recreating their presentation.
- Use real per-gap ideal, shrink, and stretch widths in the vendored
  Knuth–Plass implementation.

### Fixed

- Keep editable fields and display glyphs inside bordered layout widths.
- Exclude identifier break points from visible-space accounting.
- Fall back to natural ragged-right wrapping before an emergency line can
  overflow at narrow widths.

## [0.2.0] - 2026-08-09

### Added

- Add buffer state coordination and `textui-update`.
- Route top-level plist state changes to named refresh regions.
- Add dependency-aware lifecycle effects for timers, processes, and cleanup.
- Add lifecycle-safe asynchronous callbacks that ignore stale work.

### Changed

- Coalesce repeated regional updates and fall back to full reconciliation for
  structural changes.
- Update the btop prototype to use automatic state routing and managed live
  sampling.

### Performance

- In the btop 50-process fixture, routed detail updates improved from a median
  of 11.65 ms to 5.67 ms while retaining native `widget.el` push-button rows.

[0.8.0]: https://github.com/yibie/textui/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/yibie/textui/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/yibie/textui/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/yibie/textui/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/yibie/textui/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/yibie/textui/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/yibie/textui/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/yibie/textui/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/yibie/textui/releases/tag/v0.2.0
