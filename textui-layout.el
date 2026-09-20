;;; textui-layout.el --- Pure layout geometry for TextUI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 chenyibin
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; The geometry behind TextUI's responsive containers, as pure functions over
;; integers and plists.  Nothing here touches a buffer, a widget, a marker, a
;; text property, or a frame, and nothing here measures: the caller measures
;; its own content and hands the numbers in.  That boundary is what lets the
;; rules be tested on their own and compared against another engine; see the
;; shared-seam exploration in https://github.com/yibie/textui/issues/1.
;;
;; Vocabulary:
;;
;; - A SPEC constrains one child's width, as a plist:
;;
;;     :start    preferred width, already measured and already raised to any
;;               width the caller declared (default 0)
;;     :minimum  floor the child may shrink to (default: :start, that is, not
;;               shrinkable)
;;     :grow     weight for distributing surplus width (default 0)
;;     :rigid    non-nil when the child renders at one width and cannot be
;;               re-rendered narrower, so it keeps :start even when it is
;;               alone on a row too narrow for it
;;
;;   Unknown keys are ignored, so TextUI's own internal specs, which carry
;;   their element and children alongside these four, are valid input as they
;;   stand.
;;
;; - A PLACEMENT is the result for one child, in source order:
;;   (:row R :column C :width W).  `textui-layout-solve' and
;;   `textui-layout-grid' return placements; the caller renders its own
;;   children into that geometry.  TextUI's renderer keeps buffers, text
;;   properties, refresh ownership, and pixel padding on its side of this
;;   boundary.
;;
;; Widths are non-negative integers in whichever unit the caller measured
;; with.  TextUI measures in character cells, so a TextUI width is a cell
;; count, but no function here depends on that.
;;
;; Semantics:
;;
;; - Partition: children fill a row while they fit at their minimum widths, in
;;   source order; the next child starts the next row.  No reordering and no
;;   balancing.  A row is never empty.
;; - Allocation: when the preferred widths fit, the surplus goes to growers in
;;   proportion to their weights; when they do not, the deficit shrinks
;;   children in proportion to their capacity (:start minus :minimum), never
;;   below :minimum.  A lone child whose minimum still overflows the row is
;;   clamped to the available width unless it is rigid.
;; - Grid: equal integer tracks with the remainder on the earlier tracks; the
;;   column count falls with the available width but never below one;
;;   children fill rows in source order, so the last row may be incomplete.
;; - Overflow: an assignment is a target, not a clip.  A block that renders
;;   wider than its assignment widens its column rather than being truncated
;;   (`textui-layout-columns').
;; - Height is content-driven: a row is as tall as its tallest block, which is
;;   the caller's business, not this module's.
;;
;; Where these rules match the engine in d12frosted/vui.el, that is
;; deliberate, so conformance comparison between the two stays meaningful.
;; The two vocabularies map exactly:
;;
;;     TextUI spec        vui-layout spec
;;     :start             :natural (after an explicit :min raises it)
;;     :minimum           :min
;;     :grow              :grow
;;     :rigid             :rigid
;;
;; TextUI keeps a third number, the measured natural width, on its internal
;; specs; only :start and :minimum reach this module, because only those two
;; take part in allocation.

;;; Code:

(require 'cl-lib)

(defun textui-layout--sum (numbers)
  "Return the sum of NUMBERS."
  (let ((sum 0))
    (dolist (number numbers sum)
      (setq sum (+ sum number)))))

(defun textui-layout-start (spec)
  "Return SPEC's preferred width, defaulting to zero."
  (or (plist-get spec :start) 0))

(defun textui-layout-minimum (spec)
  "Return SPEC's minimum width, defaulting to its preferred width."
  (or (plist-get spec :minimum) (textui-layout-start spec)))

(defun textui-layout-grow (spec)
  "Return SPEC's grow weight, defaulting to zero."
  (or (plist-get spec :grow) 0))

(defun textui-layout-rigid-p (spec)
  "Return non-nil when SPEC cannot be re-rendered narrower than its width."
  (and (plist-get spec :rigid) t))

;;;; Proportional shares

(defun textui-layout-shares (amount weights &optional limits)
  "Split integer AMOUNT in proportion to WEIGHTS.
Return one non-negative integer share per weight, together summing to at most
AMOUNT.  Every share starts at its floored proportion; the integer remainder
is then handed out one unit at a time, starting from the first weight that is
positive and still under its limit, so the result is deterministic.  Optional
LIMITS caps each share, and when every positive weight sits at its limit the
rest of AMOUNT stays unassigned."
  (let ((total (float (textui-layout--sum weights)))
        (shares (make-list (length weights) 0))
        (remaining amount))
    ;; Both passes walk the lists with cons cursors.  Indexing into them makes
    ;; each pass quadratic in the row's child count, and this runs on every
    ;; re-render of every shrinking row.
    (when (> total 0)
      (let ((ws weights) (ls limits) (ss shares))
        (while ws
          (let* ((raw (floor (* amount (/ (float (car ws)) total))))
                 (limit (car ls))
                 (share (if limit (min raw limit) raw)))
            (setcar ss share)
            (setq remaining (- remaining share)
                  ws (cdr ws)
                  ls (cdr ls)
                  ss (cdr ss)))))
      (while (> remaining 0)
        (let ((ws weights) (ls limits) (ss shares)
              progressed)
          (while (and ss (> remaining 0))
            (when (and (> (car ws) 0)
                       (or (null (car ls)) (< (car ss) (car ls))))
              (setcar ss (1+ (car ss)))
              (setq remaining (1- remaining)
                    progressed t))
            (setq ws (cdr ws)
                  ls (cdr ls)
                  ss (cdr ss)))
          (unless progressed
            (setq remaining 0)))))
    shares))

;;;; Rows

(defun textui-layout-partition (specs width gap)
  "Partition SPECS into ordered rows fitting WIDTH at their minima with GAP.
Return a list of rows, each a list of specs in source order.  A child joins
the current row while the row's minimum widths plus gaps still fit WIDTH, and
otherwise starts the next row.  A row is never empty, so a child too wide even
at its minimum still gets a row of its own."
  (let ((available (max 0 width))
        current
        (current-width 0)
        rows)
    (dolist (spec specs)
      (let* ((minimum (textui-layout-minimum spec))
             (joined (+ current-width (if current gap 0) minimum)))
        (if (or (null current) (<= joined available))
            (progn
              (push spec current)
              (setq current-width joined))
          (push (nreverse current) rows)
          (setq current (list spec)
                current-width minimum))))
    (when current
      (push (nreverse current) rows))
    (nreverse rows)))

(defun textui-layout-allocate (specs width gap)
  "Return one width per spec for the single row SPECS inside WIDTH using GAP.
Surplus width goes to growers in proportion to their weights.  A deficit
shrinks children in proportion to their capacity, which is :start minus
:minimum, and never past :minimum.  A lone child whose minimum exceeds the
available width is clamped to it, unless the child is rigid and therefore
cannot be re-rendered narrower, in which case it keeps its preferred width and
overflows."
  (let* ((count (length specs))
         (available (max 0 (- width (* gap (max 0 (1- count))))))
         (starts (mapcar #'textui-layout-start specs))
         (minimums (mapcar #'textui-layout-minimum specs))
         (start-total (textui-layout--sum starts)))
    (cond
     ((null specs) nil)
     ((and (= count 1) (> (car minimums) available))
      (if (textui-layout-rigid-p (car specs))
          (list (car starts))
        (list available)))
     ((<= start-total available)
      (let* ((extra (- available start-total))
             (weights (mapcar #'textui-layout-grow specs))
             (shares (textui-layout-shares extra weights)))
        (cl-mapcar #'+ starts shares)))
     (t
      (let* ((overflow (- start-total available))
             (capacities (cl-mapcar #'- starts minimums))
             (capacity (textui-layout--sum capacities))
             (reductions (textui-layout-shares
                          (min overflow capacity) capacities capacities)))
        (cl-mapcar #'- starts reductions))))))

(defun textui-layout-solve (specs width gap)
  "Lay SPECS out inside WIDTH with GAP and return one placement per child.
Partition the children into rows at their minimum widths, allocate each row,
and return (:row R :column C :width W) per child in source order, where the
column is the child's position within its own row."
  (let ((placements nil)
        (row-index 0))
    (dolist (row (textui-layout-partition specs width gap))
      (let ((column 0))
        (dolist (assigned (textui-layout-allocate row width gap))
          (push (list :row row-index :column column :width assigned)
                placements)
          (setq column (1+ column))))
      (setq row-index (1+ row-index)))
    (nreverse placements)))

;;;; Grid

(defun textui-layout-grid-columns (columns minimum width gap)
  "Return the responsive column count for a grid inside WIDTH.
COLUMNS is the declared maximum and MINIMUM the narrowest acceptable track;
GAP separates tracks.  The count falls while MINIMUM-wide tracks no longer
fit, and never falls below one.  MINIMUM must be a positive integer: a grid
with no floor has no defined response to narrowing, so TextUI requires the
property at validation and keeps this arithmetic guard-free."
  (max 1 (min columns (/ (+ width gap) (+ minimum gap)))))

(defun textui-layout-grid-tracks (count width gap)
  "Split WIDTH, net of the GAP between tracks, into COUNT equal track widths.
The integer remainder goes to the earlier tracks, one unit each, so the tracks
of every row start at the same offsets."
  (textui-layout-shares (max 0 (- width (* gap (max 0 (1- count)))))
                        (make-list count 1)))

(defun textui-layout-grid (count width gap columns minimum)
  "Place COUNT children on an equal-track grid inside WIDTH using GAP.
COLUMNS and MINIMUM choose the column count as in
`textui-layout-grid-columns'.  Children fill rows in source order, so the last
row may be incomplete.  Return one placement per child, whose width is the
width of the track it sits in."
  (let* ((column-count (textui-layout-grid-columns columns minimum width gap))
         (tracks (textui-layout-grid-tracks column-count width gap))
         (placements nil))
    (dotimes (index count)
      (let ((column (% index column-count)))
        (push (list :row (/ index column-count)
                    :column column
                    :width (nth column tracks))
              placements)))
    (nreverse placements)))

;;;; Overflow

(defun textui-layout-columns (widths rendered)
  "Widen assigned WIDTHS to the RENDERED widths that overflow them.
Return one width per column, each the larger of the two.  An assignment is a
target and not a clip: a block that renders wider than its assignment widens
its whole column instead of being truncated, so the columns after it stay
aligned.  The rule is `max', so it is idempotent and order-independent; a
caller may apply it once for a flex row, or accumulate it over every row of a
grid track."
  (cl-mapcar #'max widths rendered))

(provide 'textui-layout)
;;; textui-layout.el ends here
