;;; textui-keyed-region.el --- Incremental keyed TextUI regions -*- lexical-binding: t; -*-

;; Copyright (C) 2026 chenyibin
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; Reconcile a bounded, complete-line column region from stable keyed items.
;; This module deliberately does not add identity to TextUI's general element
;; tree: keys exist only for the direct children of one named refresh region.

;;; Code:

(require 'cl-lib)
(require 'textui)

(defvar-local textui-keyed-region--states nil
  "Installed keyed-region states in the current TextUI buffer.")

(defun textui-keyed-region--entry-p (entry)
  "Return non-nil when ENTRY has the public (KEY ELEMENT) shape."
  (and (consp entry)
       (consp (cdr entry))
       (null (cddr entry))
       (car entry)
       (textui--plist-p (cadr entry))))

(defun textui-keyed-region--validate-entries (entries)
  "Validate and return keyed ENTRIES."
  (unless (textui--proper-list-p entries)
    (error "Keyed region producer must return a proper list: %S" entries))
  (let ((keys (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (unless (textui-keyed-region--entry-p entry)
        (error "Keyed region entry must be (KEY ELEMENT): %S" entry))
      (when (gethash (car entry) keys)
        (error "Duplicate keyed region key: %S" (car entry)))
      (puthash (car entry) t keys)))
  entries)

(defun textui-keyed-region--validate-container (element)
  "Validate keyed refresh-region container ELEMENT."
  (unless (and (eq (plist-get element :type) :flex)
               (eq (plist-get element :direction) :column))
    (error "Keyed region must be a column flex container"))
  (when (or (plist-get element :border)
            (> (or (plist-get element :padding) 0) 0))
    (error "Keyed region container cannot have border or padding"))
  (let ((gap (if (textui--plist-member-p element :gap)
                 (plist-get element :gap)
               1)))
    (unless (and (integerp gap) (>= gap 0))
      (error "Keyed region gap must be a non-negative integer: %S" gap))
    gap))

(defun textui-keyed-region--render-item (element width)
  "Render one keyed ELEMENT at region WIDTH."
  (let* ((textui--collect-refresh-regions t)
         (textui--rendered-regions nil)
         (rendered
         (textui--render-specs
          (textui--prepare-frame
           (list (list :type :flex :direction :column :gap 0
                       :children (list element))) t)
          width)))
    (when textui--rendered-regions
      (error "Keyed region entries cannot contain refresh regions"))
    rendered))

(defun textui-keyed-region--same-entry-p (left right)
  "Return non-nil when stored LEFT and public RIGHT are reusable."
  (and (equal (nth 0 left) (nth 0 right))
       (equal-including-properties (nth 1 left) (nth 1 right))))

(defun textui-keyed-region--lcs-pairs (old desired)
  "Return reusable index pairs for OLD and DESIRED keyed entries."
  (let* ((old-items (vconcat old))
         (new-items (vconcat desired))
         (old-count (length old-items))
         (new-count (length new-items))
         (table (make-vector (1+ old-count) nil)))
    (dotimes (row (1+ old-count))
      (aset table row (make-vector (1+ new-count) 0)))
    (dotimes (old-index old-count)
      (dotimes (new-index new-count)
        (aset (aref table (1+ old-index)) (1+ new-index)
              (if (textui-keyed-region--same-entry-p
                   (aref old-items old-index) (aref new-items new-index))
                  (1+ (aref (aref table old-index) new-index))
                (max (aref (aref table old-index) (1+ new-index))
                     (aref (aref table (1+ old-index)) new-index))))))
    (let ((old-index old-count)
          (new-index new-count)
          pairs)
      (while (and (> old-index 0) (> new-index 0))
        (cond
         ((textui-keyed-region--same-entry-p
           (aref old-items (1- old-index))
           (aref new-items (1- new-index)))
          (push (cons (1- old-index) (1- new-index)) pairs)
          (setq old-index (1- old-index)
                new-index (1- new-index)))
         ((>= (aref (aref table (1- old-index)) new-index)
              (aref (aref table old-index) (1- new-index)))
          (setq old-index (1- old-index)))
         (t
          (setq new-index (1- new-index)))))
      pairs)))

(defun textui-keyed-region--separator (gap width)
  "Return the separator for GAP blank lines padded to WIDTH."
  (concat "\n"
          (mapconcat (lambda (_index) (make-string width ?\s))
                     (number-sequence 1 gap) "\n")
          (and (> gap 0) "\n")))

(defun textui-keyed-region--layout (entries gap width trailing-newline)
  "Lay out ENTRIES with GAP at WIDTH and optional TRAILING-NEWLINE.
Return (TEXT STARTS ENDS)."
  (let ((separator (textui-keyed-region--separator gap width))
        (position 0)
        starts ends parts first)
    (setq first t)
    (dolist (entry entries)
      (unless first
        (push separator parts)
        (setq position (+ position (length separator))))
      (setq first nil)
      (push position starts)
      (let ((template (nth 2 entry)))
        (push template parts)
        (setq position (+ position (length template))))
      (push position ends))
    (when (null entries)
      (push (make-string width ?\s) parts))
    (when trailing-newline
      (push "\n" parts))
    (list (apply #'concat (nreverse parts))
          (vconcat (nreverse starts))
          (vconcat (nreverse ends)))))

(defun textui-keyed-region--render-desired (desired old pairs width)
  "Render DESIRED at WIDTH, reusing OLD according to PAIRS."
  (let ((reuse (make-hash-table :test #'eql)))
    (dolist (pair pairs)
      (puthash (cdr pair) (nth (car pair) old) reuse))
    (cl-loop for entry in desired
             for index from 0
             for cached = (gethash index reuse)
             collect (or cached
                         (list (car entry) (cadr entry)
                               (textui-keyed-region--render-item
                                (cadr entry) width))))))

(defun textui-keyed-region--splice (from to replacement)
  "Replace FROM..TO with pre-rendered REPLACEMENT."
  (let ((delta (- (length replacement) (- to from)))
        (start (copy-marker from))
        (finish (copy-marker to t))
        end)
    (textui--delete-widgets-in-region from to)
    ;; `widget-delete' removes its displayed text.  Markers keep the original
    ;; splice boundary valid while those deletions change numeric positions.
    (delete-region start finish)
    (goto-char start)
    (insert replacement)
    (setq end (copy-marker (+ (marker-position start)
                              (length replacement))))
    (textui--shift-focus-anchors-after-region from to delta)
    (textui--materialize-placeholders (current-buffer) start end t)
    (set-marker start nil)
    (set-marker finish nil)
    (set-marker end nil)
    delta))

(defun textui-keyed-region--incremental-commit
    (buffer region element pairs old-layout new-layout)
  "Commit ELEMENT in BUFFER by retaining PAIRS inside REGION."
  (let* ((region-from (marker-position (nth 3 region)))
         (region-to (marker-position (nth 4 region)))
         (old-text (nth 0 old-layout))
         (old-starts (nth 1 old-layout))
         (old-ends (nth 2 old-layout))
         (new-text (nth 0 new-layout))
         (new-starts (nth 1 new-layout))
         (new-ends (nth 2 new-layout))
         (snapshot (textui--capture-region-point region-from region-to))
         (point-offset (- (point) region-from))
         (keyed-point
          (cl-loop for pair in pairs
                   for old-index = (car pair)
                   for start = (aref old-starts old-index)
                   for end = (aref old-ends old-index)
                   when (and (<= start point-offset) (< point-offset end))
                   return (cons (cdr pair) (- point-offset start))))
         (other-boundaries
          (delq nil
                (mapcar
                 (lambda (other)
                   (unless (eq other region)
                     (list (nth 3 other) (marker-position (nth 3 other))
                           (nth 4 other) (marker-position (nth 4 other)))))
                 textui--refresh-regions)))
         (old-cursor 0)
         (new-cursor 0)
         gaps)
    (dolist (pair pairs)
      (let ((old-index (car pair))
            (new-index (cdr pair)))
        (push (list old-cursor (aref old-starts old-index)
                    new-cursor (aref new-starts new-index)) gaps)
        (setq old-cursor (aref old-ends old-index)
              new-cursor (aref new-ends new-index))))
    (push (list old-cursor (length old-text)
                new-cursor (length new-text)) gaps)
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (dolist (gap gaps)
        (let ((old-from (+ region-from (nth 0 gap)))
              (old-to (+ region-from (nth 1 gap)))
              (old-fragment (substring old-text (nth 0 gap) (nth 1 gap)))
              (replacement (substring new-text (nth 2 gap) (nth 3 gap))))
          (unless (equal-including-properties old-fragment replacement)
            (textui-keyed-region--splice old-from old-to replacement))))
      (let ((delta (- (length new-text) (length old-text))))
        (when textui--rendered-frame
          (let ((cache-from (- region-from (point-min)))
                (cache-to (- region-to (point-min))))
            (setq textui--rendered-frame
                  (concat (substring textui--rendered-frame 0 cache-from)
                          new-text
                          (substring textui--rendered-frame cache-to)))))
        (set-marker (nth 3 region) region-from buffer)
        (set-marker (nth 4 region) (+ region-from (length new-text)) buffer)
        (dolist (boundary other-boundaries)
          (set-marker (nth 0 boundary)
                      (+ (nth 1 boundary)
                         (if (>= (nth 1 boundary) region-to) delta 0)) buffer)
          (set-marker (nth 2 boundary)
                      (+ (nth 3 boundary)
                         (if (>= (nth 3 boundary) region-to) delta 0)) buffer)))
      (setf (nth 1 region) element
            (nth 5 region) new-text)
      (setq textui--refresh-generation (1+ textui--refresh-generation))
      (if keyed-point
          (let* ((index (car keyed-point))
                 (start (aref new-starts index))
                 (end (aref new-ends index)))
            (goto-char (+ region-from start
                          (min (cdr keyed-point) (- end start)))))
        (textui--restore-region-point
         snapshot (nth 3 region)
         (max 0 (1- (length (split-string
                             (string-remove-suffix "\n" new-text) "\n"))))))
      (force-mode-line-update))))

;;;###autoload
(defun textui-reconcile-keyed-region (buffer id producer)
  "Incrementally reconcile refresh region ID in BUFFER.
PRODUCER receives the region content width and returns ordered, unique
entries of the form (KEY ELEMENT).  Unchanged entries with the same key and
relative order retain their rendered text and widgets.  The named region must
be a complete-line column flex container without padding or a border."
  (if (not (buffer-live-p buffer))
      nil
    (unless (functionp producer)
      (error "Keyed region producer must be a function: %S" producer))
    (with-current-buffer buffer
      (unless (derived-mode-p 'textui-mode)
        (error "Not a TextUI buffer: %S" buffer))
      (when textui--refreshing
        (error "Reentrant TextUI refresh: %S" buffer))
      (let ((region (assq id textui--refresh-regions)))
        (unless region
          (error "Unknown refresh region: %S" id))
        (let* ((textui--refreshing t)
               (element (nth 1 region))
               (gap (textui-keyed-region--validate-container element))
               (width (nth 2 region))
               (from (marker-position (nth 3 region)))
               (to (marker-position (nth 4 region)))
               (trailing-newline (and (> to from) (= (char-before to) ?\n)))
               (desired (textui-keyed-region--validate-entries
                         (funcall producer width)))
               (state (assq id textui-keyed-region--states))
               (old (and state (nth 5 state)))
               (fresh (and state
                           (= (nth 1 state) width)
                           (= (nth 2 state) textui--refresh-generation)
                           (eq (nth 3 state) trailing-newline)
                           (= (nth 4 state) gap)))
               (pairs (and fresh
                           (textui-keyed-region--lcs-pairs old desired)))
               (stored (textui-keyed-region--render-desired
                        desired old pairs width))
               (old-layout (and fresh
                                (textui-keyed-region--layout
                                 old gap width trailing-newline)))
               (new-layout (textui-keyed-region--layout
                            stored gap width trailing-newline))
               (replacement (plist-put (copy-sequence element)
                                       :children (mapcar #'cadr desired))))
          (if (not fresh)
              (textui--replace-refresh-region-template
               buffer region
               (list id replacement width nil nil (car new-layout))
               (car new-layout))
            (textui-keyed-region--incremental-commit
             buffer region replacement pairs old-layout new-layout))
          (let ((next (list id width textui--refresh-generation
                            trailing-newline gap stored)))
            (if state
                (setcdr state (cdr next))
              (push next textui-keyed-region--states))))
      buffer))))

(provide 'textui-keyed-region)
;;; textui-keyed-region.el ends here
