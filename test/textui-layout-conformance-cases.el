;;; textui-layout-conformance-cases.el --- Shared layout conformance cases -*- lexical-binding: t; -*-

;; Copyright (C) 2026 chenyibin
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Layout cases and their expected geometry, as data.  This file requires
;; nothing, defines one constant, and names no engine, so a second
;; implementation can load it and check itself against the same expectations
;; that TextUI checks itself against; that is the point of it.  TextUI's own
;; runner is `test/textui-layout-test.el'.  See
;; https://github.com/yibie/textui/issues/1 for the comparison this serves.
;;
;; Every expectation here was worked out from the written rules rather than
;; recorded from a run, so a disagreement means an engine and the contract
;; disagree, not that two engines merely differ.
;;
;; A CHILD is described in constraint terms that belong to no engine:
;;
;;     :natural N  measured natural width (default 0)
;;     :min M      floor; a floor above the natural width raises the width the
;;                 child occupies, as CSS min-width overrides width
;;     :grow G     weight for distributing surplus width (default 0)
;;     :rigid t    content that renders at one width and cannot be re-rendered
;;                 narrower, so it never shrinks below its natural width
;;
;; A runner maps those onto its own spec vocabulary.  For TextUI that is
;; :start = max(:natural, :min), :minimum = :min or :start, plus :rigid.
;;
;; Each case is a plist with a :name, an :op, its inputs, and :expect.
;;
;;   :op solve    - :children :width :gap
;;                  expects one placement (:row R :column C :width W) per
;;                  child, in source order
;;   :op grid     - :count :width :gap :columns :min-width
;;                  expects one placement per child
;;   :op shares   - :amount :weights and optional :limits
;;                  expects one integer share per weight
;;   :op columns  - :widths and :rendered, a list of rendered-width rows
;;                  folded over the assigned widths
;;                  expects the widths after overflow has widened them

;;; Code:

(defconst textui-layout-conformance-cases
  '(;; Proportional shares.
    (:name "shares: splits in proportion to the weights"
     :op shares :amount 30 :weights (1 2)
     :expect (10 20))
    (:name "shares: hands the integer remainder to the earlier weights"
     :op shares :amount 10 :weights (1 1 1)
     :expect (4 3 3))
    (:name "shares: caps a share at its limit and redistributes the rest"
     :op shares :amount 10 :weights (1 1) :limits (2 nil)
     :expect (2 8))
    (:name "shares: assigns nothing when every weight is zero"
     :op shares :amount 10 :weights (0 0)
     :expect (0 0))

    ;; Flex rows: partitioning.
    (:name "flex: children that fit at their minima share one row"
     :op solve :width 20 :gap 1
     :children ((:natural 10 :min 4) (:natural 5 :min 5))
     :expect ((:row 0 :column 0 :width 10) (:row 0 :column 1 :width 5)))
    (:name "flex: minima that do not fit split the row in source order"
     :op solve :width 15 :gap 1
     :children ((:natural 10 :min 8) (:natural 10 :min 8))
     :expect ((:row 0 :column 0 :width 10) (:row 1 :column 0 :width 10)))
    (:name "flex: partitioning uses minimum widths, not natural widths"
     :op solve :width 12 :gap 1
     :children ((:natural 10 :min 4) (:natural 10 :min 4))
     :expect ((:row 0 :column 0 :width 5) (:row 0 :column 1 :width 6)))

    ;; Flex rows: growing.
    (:name "flex: surplus goes to growers in proportion to their weights"
     :op solve :width 20 :gap 1
     :children ((:natural 10 :min 4 :grow 1) (:natural 5 :min 5 :grow 3))
     :expect ((:row 0 :column 0 :width 11) (:row 0 :column 1 :width 8)))
    (:name "flex: the grow remainder goes to the earlier growers"
     :op solve :width 21 :gap 1
     :children ((:natural 3 :min 3 :grow 1)
                (:natural 3 :min 3 :grow 1)
                (:natural 3 :min 3 :grow 1))
     :expect ((:row 0 :column 0 :width 7)
              (:row 0 :column 1 :width 6)
              (:row 0 :column 2 :width 6)))
    (:name "flex: without growers the surplus stays unassigned"
     :op solve :width 20 :gap 1
     :children ((:natural 4 :min 4) (:natural 4 :min 4))
     :expect ((:row 0 :column 0 :width 4) (:row 0 :column 1 :width 4)))

    ;; Flex rows: shrinking.
    (:name "flex: a deficit shrinks children in proportion to capacity"
     :op solve :width 15 :gap 1
     :children ((:natural 10 :min 4) (:natural 10 :min 8))
     :expect ((:row 0 :column 0 :width 5) (:row 0 :column 1 :width 9)))
    (:name "flex: a rigid child keeps its width while the row shrinks"
     :op solve :width 16 :gap 1
     :children ((:natural 10 :min 4) (:natural 10 :rigid t))
     :expect ((:row 0 :column 0 :width 5) (:row 0 :column 1 :width 10)))

    ;; Flex rows: minimum above natural.
    (:name "flex: a minimum above the natural width raises the occupied width"
     :op solve :width 30 :gap 1
     :children ((:natural 3 :min 20))
     :expect ((:row 0 :column 0 :width 20)))

    ;; Flex rows: a single child that cannot fit.
    (:name "flex: a lone child below its minimum is clamped to the width"
     :op solve :width 8 :gap 1
     :children ((:natural 30 :min 30))
     :expect ((:row 0 :column 0 :width 8)))
    (:name "flex: a lone rigid child keeps its width and overflows"
     :op solve :width 8 :gap 1
     :children ((:natural 30 :min 30 :rigid t))
     :expect ((:row 0 :column 0 :width 30)))

    ;; Flex rows: degenerate input.
    (:name "flex: no children lay out to no placements"
     :op solve :width 20 :gap 1 :children ()
     :expect ())
    (:name "flex: a zero width still gives the first child a row"
     :op solve :width 0 :gap 1
     :children ((:natural 5 :min 2))
     :expect ((:row 0 :column 0 :width 0)))
    (:name "flex: a zero gap packs children edge to edge"
     :op solve :width 8 :gap 0
     :children ((:natural 4 :min 4) (:natural 4 :min 4))
     :expect ((:row 0 :column 0 :width 4) (:row 0 :column 1 :width 4)))
    (:name "flex: zero-width children still receive grow shares"
     :op solve :width 10 :gap 1
     :children ((:natural 0 :min 0) (:natural 0 :min 0 :grow 1))
     :expect ((:row 0 :column 0 :width 0) (:row 0 :column 1 :width 9)))

    ;; Grid.
    (:name "grid: keeps every column while the minimum track fits"
     :op grid :count 7 :width 40 :gap 1 :columns 4 :min-width 8
     :expect ((:row 0 :column 0 :width 10) (:row 0 :column 1 :width 9)
              (:row 0 :column 2 :width 9) (:row 0 :column 3 :width 9)
              (:row 1 :column 0 :width 10) (:row 1 :column 1 :width 9)
              (:row 1 :column 2 :width 9)))
    (:name "grid: drops columns as the width falls, last row incomplete"
     :op grid :count 7 :width 25 :gap 1 :columns 4 :min-width 8
     :expect ((:row 0 :column 0 :width 12) (:row 0 :column 1 :width 12)
              (:row 1 :column 0 :width 12) (:row 1 :column 1 :width 12)
              (:row 2 :column 0 :width 12) (:row 2 :column 1 :width 12)
              (:row 3 :column 0 :width 12)))
    (:name "grid: never falls below one column"
     :op grid :count 3 :width 10 :gap 1 :columns 4 :min-width 8
     :expect ((:row 0 :column 0 :width 10)
              (:row 1 :column 0 :width 10)
              (:row 2 :column 0 :width 10)))
    (:name "grid: counts the gap when choosing the column count"
     :op grid :count 5 :width 31 :gap 2 :columns 3 :min-width 5
     :expect ((:row 0 :column 0 :width 9) (:row 0 :column 1 :width 9)
              (:row 0 :column 2 :width 9)
              (:row 1 :column 0 :width 9) (:row 1 :column 1 :width 9)))
    (:name "grid: an uneven remainder widens the earlier tracks"
     :op grid :count 3 :width 21 :gap 1 :columns 3 :min-width 1
     :expect ((:row 0 :column 0 :width 7) (:row 0 :column 1 :width 6)
              (:row 0 :column 2 :width 6)))
    (:name "grid: no children lay out to no placements"
     :op grid :count 0 :width 20 :gap 1 :columns 3 :min-width 4
     :expect ())

    ;; Overflow.
    (:name "overflow: a block wider than its assignment widens its column"
     :op columns :widths (10 5) :rendered ((12 3))
     :expect (12 5))
    (:name "overflow: a track keeps the widest block of every row"
     :op columns :widths (10 5) :rendered ((12 3) (4 9))
     :expect (12 9))
    (:name "overflow: applying the rule again changes nothing"
     :op columns :widths (10 5) :rendered ((12 3) (12 3))
     :expect (12 5)))
  "Layout cases and the geometry the layout contract requires for them.
Each case is a plist of :name, :op, that operation's inputs, and :expect.
The file's Commentary documents the vocabulary; it is deliberately not
TextUI's own, so another engine can run these cases unchanged.")

(provide 'textui-layout-conformance-cases)
;;; textui-layout-conformance-cases.el ends here
