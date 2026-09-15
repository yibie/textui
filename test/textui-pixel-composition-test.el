;;; textui-pixel-composition-test.el --- Pixel composition tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Regression coverage for pixel-aware row and box composition.  A fake pixel
;; measurer replaces the frame metrics, so the graphical path is exercised in
;; batch:
;;
;;   cell 7px, CJK 17px, ellipsis 9px, space 7px
;;
;; The capture fixture under test/fixtures records the column-based terminal
;; output that must not change.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'textui)

(defconst textui-pixel-test--cell 7
  "Cell width of the fake pixel metrics.")

(defconst textui-pixel-test--rows
  '(" TAG / CONTACT                     26"
    "+ CONTACT / FRIEND                 19"
    "↗ 签字汪炜提供的合同解除书           4"
    "◆ DONE                              4"
    "→ 姑姑"
    "→ 老妈"
    "→ [2025-09-08 Mon 16:19] 很郁闷，其…  2"
    "→ Andreessen Horowitz（a16z）"
    "→ iSouthRain"
    "→ 施宏斌")
  "Unmodified card rows from the alignment probe.")

(defconst textui-pixel-test--fixture
  (expand-file-name "fixtures/terminal-composition.txt"
                    (file-name-directory
                     (or load-file-name buffer-file-name)))
  "Captured column-based output for the composition fixture frame.
The regeneration command is in the fixture paragraphs of
`docs/report-pixel-composition.md'.")

(defun textui-pixel-test--measure (string)
  "Return STRING's fake advance in pixels.
Ordinary characters are one cell, CJK ideographs 17px, and the ellipsis 9px;
display spacers contribute their declared width."
  (let ((width 0)
        (index 0))
    (while (< index (length string))
      (let ((display (get-text-property index 'display string)))
        (if (and (consp display) (eq (car display) 'space))
            (let ((value (plist-get (cdr display) :width)))
              (setq width (+ width (if (consp value) (car value) value))))
          (let ((char (aref string index)))
            (setq width
                  (+ width
                     (cond ((eq char ?…) 9)
                           ((and (>= char #x4E00) (<= char #x9FFF)) 17)
                           (t textui-pixel-test--cell)))))))
      (setq index (1+ index)))
    width))

(defmacro textui-pixel-test--with-metrics (&rest body)
  "Run BODY with the fake pixel metrics installed."
  (declare (indent 0))
  `(let ((textui--pixel-metrics-override
          (cons #'textui-pixel-test--measure textui-pixel-test--cell))
         (textui--pixel-width-cache nil))
     ,@body))

(defun textui-pixel-test--card ()
  "Return the probe's bordered 40-column card element."
  (list :type :flex :direction :column :border t :padding 1 :gap 0
        :layout '(:width 40)
        :children (mapcar (lambda (value)
                            (list :type 'item :format "%v" :value value))
                          textui-pixel-test--rows)))

(defun textui-pixel-test--pair (type)
  "Return two cards side by side in a TYPE container."
  (append
   (list :type type :gap 3 :layout '(:width 100 :min-width 100))
   (when (eq type :grid)
     '(:columns 2 :min-column-width 40))
   (when (eq type :flex)
     '(:direction :row))
   (list :children (list (textui-pixel-test--card)
                         (textui-pixel-test--card)))))

(defun textui-pixel-test--fixture-frame ()
  "Return the frame captured in the terminal composition fixture."
  (list (textui-pixel-test--pair :flex)
        (textui-pixel-test--pair :grid)
        (list :type :text :align 'left
              :value "Mixed 宽度 wrapping keeps its column contract."
              :layout '(:width 40))
        (list :type :grid :columns 3 :min-column-width 8 :gap 1
              :children (mapcar (lambda (value)
                                  (list :type 'item :format "%v" :value value))
                                '("alpha" "中中" "…" "delta" "epsilon" "zeta")))))

(defun textui-pixel-test--border-offsets (line)
  "Return the pixel offsets of LINE's box border characters.
The box-drawing characters in LINE are measured from the line start, so an
offset is the rendered right edge or left edge of the surrounding card."
  (let (offsets
        (index 0))
    (while (< index (length line))
      (when (memq (aref line index)
                  '(#x250c #x2510 #x2502 #x2514 #x2518))
        (push (textui-pixel-test--measure (substring line 0 index)) offsets))
      (setq index (1+ index)))
    (nreverse offsets)))

(defun textui-pixel-test--assert-straight-lines (rendered)
  "Assert every line in RENDERED places its card borders at equal pixels."
  (let* ((lines (split-string rendered "\n"))
         (offsets (mapcar #'textui-pixel-test--border-offsets lines)))
    (should (> (length lines) 10))
    (should (cl-every (lambda (line) (= (length line) 4)) offsets))
    (dotimes (index 4)
      (should
       (= 1 (length
             (delete-dups
              (mapcar (lambda (line) (nth index line)) offsets))))))))

(ert-deftest textui-pixel-composition-flex-pair-has-straight-edges ()
  (textui-pixel-test--with-metrics
    (textui-pixel-test--assert-straight-lines
     (textui--render-frame (list (textui-pixel-test--pair :flex)) 110))))

(ert-deftest textui-pixel-composition-grid-pair-has-straight-edges ()
  (textui-pixel-test--with-metrics
    (textui-pixel-test--assert-straight-lines
     (textui--render-frame (list (textui-pixel-test--pair :grid)) 110))))

(ert-deftest textui-pixel-composition-pads-to-the-exact-pixel-budget ()
  (textui-pixel-test--with-metrics
    ;; Whole spaces fill the budget exactly.
    (should (equal (textui--pixel-pad-right "ab" 4) "ab  "))
    ;; A residual that no space fits becomes one display spacer.
    (let ((padded (textui--pixel-pad-right "中" 3)))
      (should (= (textui-pixel-test--measure padded) 21))
      (should (= (textui--rendered-string-width padded) 3))
      (should (equal (get-text-property 1 'display padded)
                     '(space :width (4)))))
    ;; Content already at or over budget is never clipped or padded.
    (should (equal (textui--pixel-pad-right "中中" 3) "中中"))
    (should (equal (textui--pixel-pad-right "…" 1) "…")))
  ;; Without pixel metrics the primitive is the ordinary column padding.
  (should (equal (textui--pixel-pad-right "ab" 5)
                 (textui--pad-right "ab" 5)))
  (should (equal (textui--pixel-pad-right "中" 3)
                 (textui--pad-right "中" 3))))

(ert-deftest textui-pixel-composition-width-cache-keys-text-properties ()
  (let ((textui--pixel-width-cache nil)
        (calls 0))
    (cl-letf (((symbol-function 'string-pixel-width)
               (lambda (string)
                 (setq calls (1+ calls))
                 (if (eq (get-text-property 0 'face string) 'bold) 40 14))))
      (should (= (textui--string-pixel-width (propertize "ab" 'face 'bold))
                 40))
      (should (= (textui--string-pixel-width "ab") 14))
      ;; Both attributed strings stay cached independently.
      (should (= (textui--string-pixel-width "ab") 14))
      (should (= (textui--string-pixel-width (propertize "ab" 'face 'bold))
                 40))
      (should (= calls 2))
      (should (eq (hash-table-test (cdr textui--pixel-width-cache))
                  'textui--attributed-string))
      (should (= (hash-table-count (cdr textui--pixel-width-cache)) 2)))))

(ert-deftest textui-pixel-composition-terminal-output-is-unchanged ()
  (should (file-readable-p textui-pixel-test--fixture))
  (should
   (equal (concat (substring-no-properties
                   (textui--render-frame (textui-pixel-test--fixture-frame)
                                         110))
                  "\n")
          (with-temp-buffer
            (let ((coding-system-for-read 'utf-8-unix))
              (insert-file-contents textui-pixel-test--fixture))
            (buffer-substring-no-properties (point-min) (point-max))))))

(provide 'textui-pixel-composition-test)
;;; textui-pixel-composition-test.el ends here
