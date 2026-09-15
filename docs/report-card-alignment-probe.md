# Bordered card alignment probe

## Result

A separate macOS GUI Emacs (`-Q`, Emacs 32.0.50) reproduced mixed-width
CJK drift without loading the user's configuration. With a 7px cell, two
CJK glyphs measured 24px rather than 28px. The arrow actually used Menlo,
not Apple Color Emoji; this is not a reproduction of the user's exact fontset.

| Variant | Card 1 right-edge spread | Card 2 spread | Verdict |
| --- | ---: | ---: | --- |
| A. Stock | 24px | 48px | FAIL |
| B. Align-to | 4px | 4px | FAIL |
| C. Pixel-padded | 4px | 4px | FAIL |

**Both explicit-spacing techniques eliminate the glyph-induced drift on
all non-overfull rows. Neither can make the unchanged sample fit a strict
40-cell card.** In B/C every right edge is at 273px / 574px except rendered
line 09 (the timestamp), which reaches 277px / 578px. Their second card's
left edge stays at 301px, including that overflowing line. Stock's second
left edge moves from 322px to 298px on the CJK contract row: the neighbour
really does propagate its width error.

### Important width-budget conflict

The supplied strings have column widths `(37 37 38 37 6 6 39 29 12 8)`.
A 40-cell border box with padding 1 has only 36 content cells. The probe
preserves every sample character and space instead of trimming, wrapping,
changing fonts, or silently widening B/C. Stock expands to a 43-cell box
because of its existing natural-width rule. B/C target right-border starts
at columns 39 and 82 (40 cells per box, 3-cell gap), and log negative
padding budgets rather than clipping content or pretending a spacer can
move backwards. In this GUI the timestamp exceeds the right-edge target
by 4px; it also consumes the nominal right padding. PASS tests edge spread,
not whether padding, content fit, or requested total width are correct.

## Implementation and contracts

- **A:** two ordinary `:flex :direction :column :border t :padding 1`
  cards, `:layout (:width 40)`, item rows, and `:gap 0`. A stock row
  container joins them with three literal spaces. A one-child outer row
  supplies a 100-column layout request; the command also widens the frame
  to at least 110 columns and uses a single window to avoid responsive
  stacking. No core renderer is replaced or advised.
- **B:** the probe builds top, bottom, padding and content lines itself.
  Display spaces align to absolute columns for content starts, right
  borders, and the neighbour's start. Their underlying spaces retain a
  useful (but not authoritative) column-only representation. Absolute
  positions are intentionally tied to the complete pair's line origin.
- **C:** the probe measures each growing, attributed line with
  `string-pixel-width`, pads to cell targets derived from
  `(* 40 (frame-char-width))`, uses whole ordinary spaces, then a
  `(space :width (N))` spacer for a nonzero pixel remainder. Re-measuring
  the complete prefix also compensates at the inter-card boundary.
- B/C use the existing top-level native **attached-block** interface:
  `:textui-layout` returns precomposed text, and `:textui-attach` installs
  span markers plus a delete callback without changing it. Ordinary item
  value rendering was observed to strip the display properties, so it
  cannot transport these precomposed lines reliably. Neither block uses
  `:text`, nor is it nested in a layout that could re-pad it. This respects
  the attached-block contract, but deliberately bypasses the core's
  cell-based sizing, layout-cell tagging and nested layout participation.
- All three fill rows receive the same non-extending background face,
  including the fill up to the right border. Reports are inserted only
  after materialization and after collecting all measurements. This is a
  **snapshot**, not a reconciled TextUI subtree: the probe removes the
  buffer-local resize-refresh hook. Run the command again after a font or
  window change. Explicit external `textui-refresh` replaces the snapshot.
- `spw` is `string-pixel-width` of the inclusive border substring.
  `left-x` and `right-x` independently use `window-text-pixel-size` from
  the live logical line beginning, with a large x limit so offscreen
  columns are measurable. All 14 rendered lines per card are checked,
  including horizontal borders and vertical padding (84 records).
  `max-deviation` is max minus min right-border x, computed separately
  for each card; the variant passes only if both spreads are <=1px.
  B's second substring measures 581px in isolation because its absolute
  align-to coordinates still refer to the full line. That is expected,
  and is why substring width is not used as the edge verdict.

## Recommendation for core (not implemented)

Prefer **C's relative pixel padding** for a minimally invasive GUI path;
keep the existing column path for terminal frames. B also corrects drift,
but absolute align-to positions require threading/rebasing line origins
through nested flex/grid composition and make standalone block width
measurements misleading.

The smallest coherent change would introduce one pixel-aware pad-to-budget
helper, then use it in `textui--render-layout-box` for the interior/right
border and in `textui--compose-row-blocks` for each cumulative block/gap
boundary. Carry whole spaces plus one exact residual spacer, preserving
faces and display properties. Apply the same edge budget to horizontal
rules and blank padding rows; do not fix only content lines. Keep this
metric separate from logical columns used for focus/location metadata.

Also make overflow explicit: either grow the common card budget using the
maximum rendered pixel width plus borders/padding, or establish a clipping/
wrapping policy before padding. Negative-width spaces cannot solve the
sample's width conflict. Measurement must use the target window/frame's
fonts and effective faces, with invalidation on font/scale/window changes.
A spacer-only change without overflow and property-preservation tests is
not a complete fix. These measurements favour C for composability, not
because C achieved a strict-width PASS on this overfull input.

## Validation and reproduction

```sh
emacs -Q --batch -l examples/textui-card-alignment-probe.el \
  --eval '(textui-card-alignment-probe-report)'
emacs -Q --batch -L . --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile examples/textui-card-alignment-probe.el
emacs -Q -l examples/textui-card-alignment-probe.el \
  --eval '(textui-card-alignment-probe)'
```

- Byte compilation passed with warnings treated as errors. The generated
  `.elc` was removed. Only Emacs 32.0.50 was available for execution;
  the source uses Emacs 29-compatible APIs, but was not runtime-tested on 29.
- An external temporary ERT test passed: 84 live measurement records,
  preserved display properties and fill face, every literal sample row
  present six times, expected batch verdicts, and identical output on
  repeated invocation.
- Batch reports `A PASS COLUMN-ONLY` (0col), `B FAIL COLUMN-ONLY` (4col),
  `C FAIL COLUMN-ONLY` (2col). These ignore display spacers and are explicitly
  **not pixel verdicts**. Font family is unavailable in batch.
- The GUI was launched as its own `emacs -Q` process, saved the returned
  report to `/tmp/card-probe-gui.txt`, and exited itself with `kill-emacs`.
  No emacsclient, existing Emacs connection, or user configuration was used.
- A supplemental attempt to map just U+2197 to Apple Color Emoji in that
  isolated process still reported Menlo and identical results. It therefore
  provides no evidence about actual emoji-font behaviour; the user's
  fontset needs its own run.
- No library files were edited and no commit was made. Pre-existing
  untracked files were left alone. Source is ASCII except the sample rows.

## GUI output (unmodified sample, default -Q fonts)

The complete captured output follows. Plain-text export does not preserve
spacer display properties or the background face; the numeric measurements
were taken from the live, attributed TextUI buffer before export.

```text
Card alignment probe | Emacs 32.0.50 | graphic=t
frame-char-width=7; target=40 cells; gap=3 cells
"中中"=24; "ab"=14; "→"=7; "↗"=7; "…"=7 (px); arrow-font-family=Menlo
Sample row columns=(37 37 38 37 6 6 39 29 12 8); content budget=36.
Stock may expand beyond 40; B/C preserve content on overflow.
spw measures the inclusive substring in isolation; right-x is live line-relative.
PASS means right-edge spread <=1px, not absence of overflow.

A. Stock
┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐                    
│                                         │   │                                         │                    
│  TAG / CONTACT                     26   │   │  TAG / CONTACT                     26   │                    
│ + CONTACT / FRIEND                 19   │   │ + CONTACT / FRIEND                 19   │                    
│ ↗ 签字汪炜提供的合同解除书           4  │   │ ↗ 签字汪炜提供的合同解除书           4  │                    
│ ◆ DONE                              4   │   │ ◆ DONE                              4   │                    
│ → 姑姑                                  │   │ → 姑姑                                  │                    
│ → 老妈                                  │   │ → 老妈                                  │                    
│ → [2025-09-08 Mon 16:19] 很郁闷，其…  2 │   │ → [2025-09-08 Mon 16:19] 很郁闷，其…  2 │                    
│ → Andreessen Horowitz（a16z）           │   │ → Andreessen Horowitz（a16z）           │                    
│ → iSouthRain                            │   │ → iSouthRain                            │                    
│ → 施宏斌                                │   │ → 施宏斌                                │                    
│                                         │   │                                         │                    
└─────────────────────────────────────────┘   └─────────────────────────────────────────┘                    
  line=01 card=1 spw=301 left-x=0 right-x=294 px
  line=01 card=2 spw=301 left-x=322 right-x=616 px
  line=02 card=1 spw=301 left-x=0 right-x=294 px
  line=02 card=2 spw=301 left-x=322 right-x=616 px
  line=03 card=1 spw=301 left-x=0 right-x=294 px
  line=03 card=2 spw=301 left-x=322 right-x=616 px
  line=04 card=1 spw=301 left-x=0 right-x=294 px
  line=04 card=2 spw=301 left-x=322 right-x=616 px
  line=05 card=1 spw=277 left-x=0 right-x=270 px
  line=05 card=2 spw=277 left-x=298 right-x=568 px
  line=06 card=1 spw=301 left-x=0 right-x=294 px
  line=06 card=2 spw=301 left-x=322 right-x=616 px
  line=07 card=1 spw=297 left-x=0 right-x=290 px
  line=07 card=2 spw=297 left-x=318 right-x=608 px
  line=08 card=1 spw=297 left-x=0 right-x=290 px
  line=08 card=2 spw=297 left-x=318 right-x=608 px
  line=09 card=1 spw=291 left-x=0 right-x=284 px
  line=09 card=2 spw=291 left-x=312 right-x=596 px
  line=10 card=1 spw=297 left-x=0 right-x=290 px
  line=10 card=2 spw=297 left-x=318 right-x=608 px
  line=11 card=1 spw=301 left-x=0 right-x=294 px
  line=11 card=2 spw=301 left-x=322 right-x=616 px
  line=12 card=1 spw=295 left-x=0 right-x=288 px
  line=12 card=2 spw=295 left-x=316 right-x=604 px
  line=13 card=1 spw=301 left-x=0 right-x=294 px
  line=13 card=2 spw=301 left-x=322 right-x=616 px
  line=14 card=1 spw=301 left-x=0 right-x=294 px
  line=14 card=2 spw=301 left-x=322 right-x=616 px
A FAIL max-deviation=48px (card1=24 card2=48)

B. Align-to
┌────────────────────────────────────── ┐  ┌────────────────────────────────────── ┐
│                                      │   │                                      │
│  TAG / CONTACT                     26 │  │  TAG / CONTACT                     26 │
│ + CONTACT / FRIEND                 19 │  │ + CONTACT / FRIEND                 19 │
│ ↗ 签字汪炜提供的合同解除书           4 │ │ ↗ 签字汪炜提供的合同解除书           4 │
│ ◆ DONE                              4 │  │ ◆ DONE                              4 │
│ → 姑姑                               │   │ → 姑姑                               │
│ → 老妈                               │   │ → 老妈                               │
│ → [2025-09-08 Mon 16:19] 很郁闷，其…  2 │ │ → [2025-09-08 Mon 16:19] 很郁闷，其…  2 │
│ → Andreessen Horowitz（a16z）        │   │ → Andreessen Horowitz（a16z）        │
│ → iSouthRain                         │   │ → iSouthRain                         │
│ → 施宏斌                             │   │ → 施宏斌                             │
│                                      │   │                                      │
└────────────────────────────────────── ┘  └────────────────────────────────────── ┘
  line=01 card=1 spw=280 left-x=0 right-x=273 px
  line=01 card=2 spw=581 left-x=301 right-x=574 px
  line=02 card=1 spw=280 left-x=0 right-x=273 px
  line=02 card=2 spw=581 left-x=301 right-x=574 px
  line=03 card=1 spw=280 left-x=0 right-x=273 px
  line=03 card=2 spw=581 left-x=301 right-x=574 px
  line=04 card=1 spw=280 left-x=0 right-x=273 px
  line=04 card=2 spw=581 left-x=301 right-x=574 px
  line=05 card=1 spw=280 left-x=0 right-x=273 px
  line=05 card=2 spw=581 left-x=301 right-x=574 px
  line=06 card=1 spw=280 left-x=0 right-x=273 px
  line=06 card=2 spw=581 left-x=301 right-x=574 px
  line=07 card=1 spw=280 left-x=0 right-x=273 px
  line=07 card=2 spw=581 left-x=301 right-x=574 px
  line=08 card=1 spw=280 left-x=0 right-x=273 px
  line=08 card=2 spw=581 left-x=301 right-x=574 px
  line=09 card=1 spw=284 left-x=0 right-x=277 px
  line=09 card=2 spw=585 left-x=301 right-x=578 px
  line=10 card=1 spw=280 left-x=0 right-x=273 px
  line=10 card=2 spw=581 left-x=301 right-x=574 px
  line=11 card=1 spw=280 left-x=0 right-x=273 px
  line=11 card=2 spw=581 left-x=301 right-x=574 px
  line=12 card=1 spw=280 left-x=0 right-x=273 px
  line=12 card=2 spw=581 left-x=301 right-x=574 px
  line=13 card=1 spw=280 left-x=0 right-x=273 px
  line=13 card=2 spw=581 left-x=301 right-x=574 px
  line=14 card=1 spw=280 left-x=0 right-x=273 px
  line=14 card=2 spw=581 left-x=301 right-x=574 px
B FAIL max-deviation=4px (card1=4 card2=4)


C. Pixel-padded
┌──────────────────────────────────────┐   ┌──────────────────────────────────────┐
│                                      │   │                                      │
│  TAG / CONTACT                     26│   │  TAG / CONTACT                     26│
│ + CONTACT / FRIEND                 19│   │ + CONTACT / FRIEND                 19│
│ ↗ 签字汪炜提供的合同解除书           4   │   │ ↗ 签字汪炜提供的合同解除书           4   │
│ ◆ DONE                              4│   │ ◆ DONE                              4│
│ → 姑姑                                │   │ → 姑姑                                │
│ → 老妈                                │   │ → 老妈                                │
│ → [2025-09-08 Mon 16:19] 很郁闷，其…  2│   │ → [2025-09-08 Mon 16:19] 很郁闷，其…  2│
│ → Andreessen Horowitz（a16z）         │   │ → Andreessen Horowitz（a16z）         │
│ → iSouthRain                         │   │ → iSouthRain                         │
│ → 施宏斌                              │   │ → 施宏斌                              │
│                                      │   │                                      │
└──────────────────────────────────────┘   └──────────────────────────────────────┘
  line=01 card=1 spw=280 left-x=0 right-x=273 px
  line=01 card=2 spw=280 left-x=301 right-x=574 px
  line=02 card=1 spw=280 left-x=0 right-x=273 px
  line=02 card=2 spw=280 left-x=301 right-x=574 px
  line=03 card=1 spw=280 left-x=0 right-x=273 px
  line=03 card=2 spw=280 left-x=301 right-x=574 px
  line=04 card=1 spw=280 left-x=0 right-x=273 px
  line=04 card=2 spw=280 left-x=301 right-x=574 px
  line=05 card=1 spw=280 left-x=0 right-x=273 px
  line=05 card=2 spw=280 left-x=301 right-x=574 px
  line=06 card=1 spw=280 left-x=0 right-x=273 px
  line=06 card=2 spw=280 left-x=301 right-x=574 px
  line=07 card=1 spw=280 left-x=0 right-x=273 px
  line=07 card=2 spw=280 left-x=301 right-x=574 px
  line=08 card=1 spw=280 left-x=0 right-x=273 px
  line=08 card=2 spw=280 left-x=301 right-x=574 px
  line=09 card=1 spw=284 left-x=0 right-x=277 px
  line=09 card=2 spw=284 left-x=301 right-x=578 px
  line=10 card=1 spw=280 left-x=0 right-x=273 px
  line=10 card=2 spw=280 left-x=301 right-x=574 px
  line=11 card=1 spw=280 left-x=0 right-x=273 px
  line=11 card=2 spw=280 left-x=301 right-x=574 px
  line=12 card=1 spw=280 left-x=0 right-x=273 px
  line=12 card=2 spw=280 left-x=301 right-x=574 px
  line=13 card=1 spw=280 left-x=0 right-x=273 px
  line=13 card=2 spw=280 left-x=301 right-x=574 px
  line=14 card=1 spw=280 left-x=0 right-x=273 px
  line=14 card=2 spw=280 left-x=301 right-x=574 px
C FAIL max-deviation=4px (card1=4 card2=4)


Padding budget deficits (content is never clipped):
B target=39 deficit=4px
B target=82 deficit=4px
C target=39 deficit=4px
C target=82 deficit=4px
```
