;;; textui-layout-test.el --- Tests for the public layout core -*- lexical-binding: t; -*-

;;; Commentary:

;; Two suites.  The first runs the shared conformance cases in
;; `textui-layout-conformance-cases' through TextUI's public layout core; the
;; cases are engine-neutral data, so a second implementation can run the same
;; file (see https://github.com/yibie/textui/issues/1).  The second covers the
;; parts of the public contract that the shared cases do not reach: spec
;; defaults and the building blocks the end-to-end entries are made of.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'textui-layout)
(require 'textui-layout-conformance-cases)

(defun textui-layout-test--spec (child)
  "Return the TextUI spec for a conformance CHILD.
The shared cases describe a child as :natural, :min, :grow and :rigid.  A
minimum above the natural width raises the width the child occupies, and an
absent minimum means the child does not shrink."
  (let* ((natural (max (or (plist-get child :natural) 0)
                       (or (plist-get child :min) 0)))
         (rigid (plist-get child :rigid))
         (minimum (if rigid natural (or (plist-get child :min) natural))))
    (list :start natural
          :minimum minimum
          :grow (or (plist-get child :grow) 0)
          :rigid rigid)))

(defun textui-layout-test--run (case)
  "Return what TextUI's layout core produces for conformance CASE."
  (let ((op (plist-get case :op)))
    (pcase op
      ('shares (textui-layout-shares (plist-get case :amount)
                                     (plist-get case :weights)
                                     (plist-get case :limits)))
      ('solve (textui-layout-solve
               (mapcar #'textui-layout-test--spec (plist-get case :children))
               (plist-get case :width)
               (plist-get case :gap)))
      ('grid (textui-layout-grid (plist-get case :count)
                                 (plist-get case :width)
                                 (plist-get case :gap)
                                 (plist-get case :columns)
                                 (plist-get case :min-width)))
      ('columns (let ((widths (plist-get case :widths)))
                  (dolist (rendered (plist-get case :rendered) widths)
                    (setq widths (textui-layout-columns widths rendered)))))
      (_ (error "Unknown conformance operation: %S" op)))))

(ert-deftest textui-layout-matches-the-shared-conformance-cases ()
  (dolist (case textui-layout-conformance-cases)
    (let ((name (plist-get case :name)))
      (should (equal (cons name (textui-layout-test--run case))
                     (cons name (plist-get case :expect)))))))

(ert-deftest textui-layout-covers-every-conformance-operation ()
  ;; A case whose :op nobody runs would pass silently forever.
  (should (equal (sort (delete-dups
                        (mapcar (lambda (case) (plist-get case :op))
                                textui-layout-conformance-cases))
                       #'string<)
                 '(columns grid shares solve))))

(ert-deftest textui-layout-spec-defaults-fill-in-the-absent-keys ()
  (should (= (textui-layout-start '()) 0))
  (should (= (textui-layout-grow '()) 0))
  (should (= (textui-layout-minimum '(:start 7)) 7))
  (should (= (textui-layout-minimum '(:start 7 :minimum 3)) 3))
  (should-not (textui-layout-rigid-p '(:start 7)))
  (should (textui-layout-rigid-p '(:start 7 :rigid t))))

(ert-deftest textui-layout-ignores-keys-it-does-not-own ()
  ;; TextUI's internal specs carry their element and children alongside the
  ;; four constraint keys, and must stay valid input as they stand.
  (should (equal (textui-layout-allocate
                  '((:kind :text :element (:type :text) :children nil
                     :natural 4 :start 4 :minimum 2 :grow 1))
                  10 1)
                 '(10))))

(ert-deftest textui-layout-partition-returns-the-specs-of-each-row ()
  (let* ((first '(:start 6 :minimum 6))
         (second '(:start 6 :minimum 6))
         (rows (textui-layout-partition (list first second) 10 1)))
    (should (equal rows (list (list first) (list second))))))

(ert-deftest textui-layout-partition-never-returns-an-empty-row ()
  (should (equal (textui-layout-partition '((:start 30 :minimum 30)) 8 1)
                 '(((:start 30 :minimum 30)))))
  (should-not (textui-layout-partition nil 20 1)))

(ert-deftest textui-layout-allocate-fills-the-row-it-is-given ()
  ;; Allocation assumes its specs already fit: it is the caller's job to
  ;; partition first, so a row it is handed is never re-split.
  (should (equal (textui-layout-allocate
                  '((:start 10 :minimum 8) (:start 10 :minimum 8)) 15 1)
                 '(8 8))))

(ert-deftest textui-layout-grid-columns-falls-with-the-width ()
  (should (= (textui-layout-grid-columns 4 8 40 1) 4))
  (should (= (textui-layout-grid-columns 4 8 25 1) 2))
  (should (= (textui-layout-grid-columns 4 8 10 1) 1))
  (should (= (textui-layout-grid-columns 4 8 0 1) 1)))

(ert-deftest textui-layout-grid-tracks-share-their-remainder-forward ()
  (should (equal (textui-layout-grid-tracks 4 40 1) '(10 9 9 9)))
  (should (equal (textui-layout-grid-tracks 1 10 1) '(10)))
  (should (equal (textui-layout-grid-tracks 3 2 1) '(0 0 0))))

(ert-deftest textui-layout-solve-and-grid-agree-with-their-parts ()
  ;; The end-to-end entries must stay a composition of the public parts, or
  ;; conformance would prove the entries and not what TextUI renders with.
  (let* ((specs '((:start 10 :minimum 4 :grow 1) (:start 10 :minimum 8)))
         (rows (textui-layout-partition specs 15 1))
         (widths (apply #'append
                        (mapcar (lambda (row)
                                  (textui-layout-allocate row 15 1))
                                rows))))
    (should (equal (mapcar (lambda (placement) (plist-get placement :width))
                           (textui-layout-solve specs 15 1))
                   widths)))
  (should (equal (mapcar (lambda (placement) (plist-get placement :width))
                         (textui-layout-grid 4 40 1 4 8))
                 (textui-layout-grid-tracks
                  (textui-layout-grid-columns 4 8 40 1) 40 1))))

(provide 'textui-layout-test)
;;; textui-layout-test.el ends here
