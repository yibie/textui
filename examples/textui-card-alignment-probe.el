;;; textui-card-alignment-probe.el --- Card edge experiment -*- lexical-binding: t; -*-

;;; Commentary:
;; Load this file, then M-x textui-card-alignment-probe.
;; Batch: emacs -Q --batch -l examples/textui-card-alignment-probe.el
;;   --eval '(textui-card-alignment-probe-report)'
;; Sample whitespace is deliberately preserved, including overfull rows.
;; Re-run the command after changing fonts or the window configuration.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(eval-and-compile
  (add-to-list 'load-path
               (expand-file-name
                ".." (file-name-directory
                      (or load-file-name
                          (bound-and-true-p byte-compile-current-file)
                          buffer-file-name)))))
(require 'textui)

(defface textui-card-alignment-probe-fill
  '((t :background "#334455" :extend nil))
  "Background of the sample's fill row."
  :group 'textui)

(defconst textui-card-alignment-probe--rows
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
  "Unmodified sample strings, including the supplied spaces.")

(defvar-local textui-card-alignment-probe--overflows nil)

(defun textui-card-alignment-probe--item (value)
  "Make an unadorned item displaying VALUE."
  (list :type 'item :format "%v" :value value))

(defun textui-card-alignment-probe--block (value)
  "Return an attached, precomposed multiline block containing VALUE."
  (list :type 'item :value value
        :textui-layout (lambda (widget _width) (widget-value widget))
        :textui-attach
        (lambda (widget from to)
          (widget-put widget :from (copy-marker from))
          (widget-put widget :to (copy-marker to t))
          (widget-put widget :delete
                      (lambda (w)
                        (delete-region (widget-get w :from) (widget-get w :to))
                        (set-marker (widget-get w :from) nil)
                        (set-marker (widget-get w :to) nil))))))

(defun textui-card-alignment-probe--sample ()
  "Return a fresh sample with a background on its first row."
  (cons (propertize (car textui-card-alignment-probe--rows)
                    'face 'textui-card-alignment-probe-fill)
        (cdr textui-card-alignment-probe--rows)))

(defun textui-card-alignment-probe--stock ()
  "Return the stock 40-column card."
  (list :type :flex :direction :column :border t :padding 1 :gap 0
        :layout '(:width 40)
        :children (mapcar #'textui-card-alignment-probe--item
                          (textui-card-alignment-probe--sample))))

(defun textui-card-alignment-probe--pixels (string)
  "Measure STRING in pixels, or columns in a terminal."
  (if (display-graphic-p) (string-pixel-width string) (string-width string)))

(defun textui-card-alignment-probe--spacer (prefix column technique)
  "Pad after PREFIX to COLUMN using TECHNIQUE B or C.
Never discard content on overflow.  Record the negative budget instead."
  (let* ((cell (if (display-graphic-p) (frame-char-width) 1))
         (remaining (- (* column cell)
                       (textui-card-alignment-probe--pixels prefix))))
    (when (< remaining 0)
      (push (format "%s target=%d deficit=%d%s"
                    technique column (- remaining)
                    (if (display-graphic-p) "px" "col"))
            textui-card-alignment-probe--overflows))
    (if (eq technique 'B)
        ;; Keep useful underlying column widths for terminal diagnostics.
        (propertize (make-string (max 1 (- column (string-width prefix))) ?\s)
                    'display `(space :align-to ,column))
      (let* ((space (max 1 (textui-card-alignment-probe--pixels " ")))
             (budget (max 0 remaining))
             (whole (/ budget space))
             (rest (% budget space)))
        (concat (make-string whole ?\s)
                (when (> rest 0)
                  (propertize " " 'display `(space :width (,rest)))))))))

(defun textui-card-alignment-probe--pair-line (body kind technique)
  "Compose BODY in two cards of KIND with TECHNIQUE.
KIND is top, bottom, or body.  All coordinates are line-absolute."
  (let ((line "")
        (left (pcase kind ('top #x250c) ('bottom #x2514) (_ #x2502)))
        (right (pcase kind ('top #x2510) ('bottom #x2518) (_ #x2502))))
    (dotimes (card 2)
      (let ((origin (* card 43)))
        (when (> card 0)
          (setq line (concat line
                             (textui-card-alignment-probe--spacer
                              line origin technique))))
        (setq line (concat line (char-to-string left)))
        (if (memq kind '(top bottom))
            (setq line (concat line (make-string 38 #x2500)))
          (setq line (concat line
                             (textui-card-alignment-probe--spacer
                              line (+ origin 2) technique)
                             body)))
        (let ((padding (textui-card-alignment-probe--spacer
                        line (+ origin 39) technique)))
          (when (and (> (length body) 0) (get-text-property 0 'face body))
            (put-text-property 0 (length padding) 'face
                               'textui-card-alignment-probe-fill padding))
          (setq line (concat line padding (char-to-string right))))))
    line))

(defun textui-card-alignment-probe--composed (technique)
  "Return precomposed item lines for TECHNIQUE without a layout wrapper."
  (mapcar #'textui-card-alignment-probe--item
          (append
           (list (textui-card-alignment-probe--pair-line "" 'top technique)
                 (textui-card-alignment-probe--pair-line "" 'body technique))
           (mapcar (lambda (row)
                     (textui-card-alignment-probe--pair-line row 'body technique))
                   (textui-card-alignment-probe--sample))
           (list (textui-card-alignment-probe--pair-line "" 'body technique)
                 (textui-card-alignment-probe--pair-line "" 'bottom technique)))))

(defun textui-card-alignment-probe--frame (_width)
  "Return the probe frame; require a wide window for the stock pair."
  (setq textui-card-alignment-probe--overflows nil)
  (cl-mapcan (lambda (element) (list element (textui-card-alignment-probe--block "\n")))
   (append
   (list (textui-card-alignment-probe--item "A. Stock")
         (list :type :flex :direction :row :gap 0
               :children
               (list (list :type :flex :direction :row :gap 3
                           :layout '(:width 100 :min-width 100)
                           :children
                           (list (textui-card-alignment-probe--stock)
                                 (textui-card-alignment-probe--stock)))))
         (textui-card-alignment-probe--item "B. Align-to"))
   (list (textui-card-alignment-probe--block
          (concat (mapconcat (lambda (item) (plist-get item :value))
                             (textui-card-alignment-probe--composed 'B) "\n")
                  "\n")))
   (list (textui-card-alignment-probe--item "C. Pixel-padded"))
   (list (textui-card-alignment-probe--block
          (concat (mapconcat (lambda (item) (plist-get item :value))
                             (textui-card-alignment-probe--composed 'C) "\n")
                  "\n"))))))

(defun textui-card-alignment-probe--x (window start position)
  "Measure live WINDOW x at POSITION on the line beginning at START."
  (if (display-graphic-p)
      (car (window-text-pixel-size window start position 100000))
    (string-width (buffer-substring start position))))

(defun textui-card-alignment-probe--measure (window)
  "Measure materialized card rows in WINDOW and insert diagnostics."
  (let ((inhibit-read-only t)
        (graphic (display-graphic-p))
        (unit (if (display-graphic-p) "px" "col"))
        sections)
    (goto-char (point-min))
    (while (re-search-forward "^\\([ABC]\\)\\. " nil t)
      (let ((variant (match-string 1)) (row 0) records
            (xs (vector nil nil)))
        (forward-line 1)
        (while (memq (char-after) '(#x250c #x2502 #x2514))
          (let ((start (line-beginning-position))
                (end (line-end-position)) edges)
            (while (re-search-forward "[\u250c\u2510\u2502\u2514\u2518]" end t)
              (push (1- (point)) edges))
            (setq edges (nreverse edges))
            (unless (= (length edges) 4)
              (error "Expected two cards, got %d borders" (length edges)))
            (cl-incf row)
            (dotimes (card 2)
              (let* ((left (nth (* 2 card) edges))
                     (right (nth (1+ (* 2 card)) edges))
                     (x (textui-card-alignment-probe--x window start right))
                     (lx (textui-card-alignment-probe--x window start left))
                     (string (buffer-substring left (1+ right))))
                (when (= row 3)
                  (put-text-property (1+ left) right 'face
                                     'textui-card-alignment-probe-fill))
                (push x (aref xs card))
                (push (format "  line=%02d card=%d spw=%d left-x=%d right-x=%d %s"
                              row (1+ card)
                              (textui-card-alignment-probe--pixels string) lx x unit)
                      records))))
          (forward-line 1))
        (let* ((d1 (- (apply #'max (aref xs 0)) (apply #'min (aref xs 0))))
               (d2 (- (apply #'max (aref xs 1)) (apply #'min (aref xs 1))))
               (deviation (max d1 d2))
               (status (if (<= deviation (if graphic 1 0)) "PASS" "FAIL")))
          (push (cons (copy-marker (point))
                      (concat (mapconcat #'identity (nreverse records) "\n")
                              (format "\n%s %s%s max-deviation=%d%s (card1=%d card2=%d)\n\n"
                                      variant status (if graphic "" " COLUMN-ONLY")
                                      deviation unit d1 d2)))
                sections))))
    ;; Insert bottom-up, after all live measurements have been collected.
    (dolist (section sections)
      (goto-char (car section))
      (insert (cdr section))
      (set-marker (car section) nil))
    (goto-char (point-min))
    (let* ((arrow (save-excursion (search-forward "\u2197") (1- (point))))
           (font (and graphic (font-at arrow window))))
      (insert (format "Card alignment probe | Emacs %s | graphic=%S\n" emacs-version graphic)
              (format "frame-char-width=%d; target=40 cells; gap=3 cells\n" (frame-char-width))
              (mapconcat (lambda (s)
                           (format "%S=%d" s (textui-card-alignment-probe--pixels s)))
                         '("\u4e2d\u4e2d" "ab" "\u2192" "\u2197" "\u2026") "; ")
              (format " (%s); arrow-font-family=%S\n" unit
                      (and font (font-get font :family)))
              (format "Sample row columns=%S; content budget=36.\n"
                      (mapcar #'string-width textui-card-alignment-probe--rows))
              "Stock may expand beyond 40; B/C preserve content on overflow.\n"
              "spw measures the inclusive substring in isolation; right-x is live line-relative.\n"
              (if graphic "PASS means right-edge spread <=1px, not absence of overflow.\n\n"
                "COLUMN-ONLY: display spacers ignored; pixel checks need a GUI.\n\n")))
    (goto-char (point-max))
    (insert "Padding budget deficits (content is never clipped):\n"
            (mapconcat #'identity
                       (nreverse textui-card-alignment-probe--overflows) "\n") "\n")
    (goto-char (point-min))))

;;;###autoload
(defun textui-card-alignment-probe ()
  "Open and measure the three card variants in a TextUI buffer.
Use one window and widen the frame to at least 110 columns for the pair.
Measurements are a snapshot; run again after changing fonts."
  (interactive)
  (when (< (frame-width) 110)
    (set-frame-width (selected-frame) 110))
  (delete-other-windows)
  (let ((buffer (textui-open "*TextUI Card Alignment Probe*"
                             #'textui-card-alignment-probe--frame)))
    (select-window (get-buffer-window buffer))
    (with-current-buffer buffer
      (setq-local truncate-lines t)
      ;; The report is a snapshot, not a reconciled TextUI subtree.
      (remove-hook 'window-configuration-change-hook #'textui--maybe-refresh-for-width t)
      (redisplay t)
      (textui-card-alignment-probe--measure (selected-window)))
    buffer))

(defun textui-card-alignment-probe-report ()
  "Run the probe, print its report, and return the report string."
  (interactive)
  (let ((report (with-current-buffer (textui-card-alignment-probe)
                  (buffer-substring-no-properties (point-min) (point-max)))))
    (when noninteractive (princ report))
    report))

(provide 'textui-card-alignment-probe)
;;; textui-card-alignment-probe.el ends here
