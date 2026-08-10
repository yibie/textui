# Changelog

This file records user-visible changes to TextUI. Dates use the release tag's
calendar date.

## Performance history

| Release | Fixture | Before | After | Change |
|---|---|---:|---:|---:|
| 0.2.0 | btop, one routed detail update across 50 process rows | 11.65 ms, full refresh | 5.67 ms, state-to-region routing | 2.05x faster |
| 0.3.0, public extension in 0.4.0 | Full refresh of 3,000 native controls | 596.55 ms, generic native path | 238.58 ms, attached path | 2.50x faster |

These are medians from fixed fixtures on the release machine, not
cross-machine guarantees. The retained diagnostic programs and instructions
are under [`test/performance/`](test/performance/README.md).

## Unreleased

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

[0.4.0]: https://github.com/yibie/textui/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/yibie/textui/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/yibie/textui/releases/tag/v0.2.0
