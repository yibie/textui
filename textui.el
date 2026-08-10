;;; textui.el --- Declarative text interfaces for Emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2026 chenyibin
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Author: chenyibin
;; Version: 0.3.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, widgets

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; TextUI lays out text and ordinary widget.el controls in responsive
;; Emacs buffers.
;; Its public surface is intentionally small: `textui-open',
;; `textui-update', `textui-set-state', `textui-route-state', `textui-effect',
;; `textui-async-callback', `textui-refresh', `textui-request-refresh',
;; `textui-refresh-region',
;; `textui-request-refresh-region', `textui-register-cleanup', and
;; `textui-register-expander'.
;; A `:text' leaf wraps and pixel-justifies attributed text at the content
;; width assigned by its flex or grid parent:
;;
;;   (:type :text :value "A long paragraph"
;;    :layout (:width 40 :min-width 16 :grow 1))
;;
;; A `:image' leaf fits a native image into an explicit number of rows:
;;
;;   (:type :image :file "/path/to/image.png" :rows 12 :alt "image")

;;; Code:

(require 'cl-lib)
(require 'image)
(require 'subr-x)
(require 'wid-edit)

(defvar textui--expanders nil
  "Alist mapping custom element types to pure expansion functions.")

(defvar textui--focus-override nil
  "Dynamically bound focus snapshot used by an action-triggered refresh.")

(defvar textui--next-location-id nil
  "Dynamically bound native-element location counter.")

(defvar textui--next-layout-id nil
  "Dynamically bound layout-element location counter.")

(defvar textui--collect-refresh-regions nil
  "Non-nil while rendered refresh regions should be recorded.")

(defvar textui--rendered-regions nil
  "Dynamically collected refresh region metadata.")

(defvar textui--collect-effects nil
  "Non-nil while the render function may declare lifecycle effects.")

(defvar textui--rendered-effects nil
  "Dynamically collected (ID DEPENDENCIES SETUP) effect descriptions.")

(defvar textui--collect-state-routes nil
  "Non-nil while the render function may declare state routes.")

(defvar textui--rendered-state-routes nil
  "Dynamically collected (REGION KEYS PRODUCER) state routes.")

(defvar textui--current-effect-token nil
  "Dynamically bound token of the lifecycle effect being started.")

(declare-function textui-kp-core-justify-lines
                  "textui-kp-core" (source attributed line-pixel))

(defvar-local textui--render-function nil)
(defvar-local textui--last-width nil)
(defvar-local textui--refreshing nil)
(defvar-local textui--widgets nil)
(defvar-local textui--focus-anchors nil)
(defvar-local textui--refresh-regions nil
  "Installed (ID ELEMENT WIDTH FROM TO TEMPLATE) refresh-region records.")
(defvar-local textui--region-refresh-requests nil)
(defvar-local textui--region-refresh-timer nil)
(defvar-local textui--refresh-timer nil)
(defvar-local textui--cleanup-functions nil)
(defvar-local textui--effects nil
  "Active (ID DEPENDENCIES CLEANUP TOKEN) lifecycle effects.")
(defvar-local textui--state-routes nil
  "Active (REGION KEYS PRODUCER) state-to-region routes.")
(defvar-local textui--refresh-generation 0)
(defvar-local textui--rendered-frame nil
  "Last pre-widget rendered frame used for automatic reconciliation.")
(defvar-local textui--focus-before-command nil)
(defvar-local textui--position-before-command nil)
(defvar-local textui--pending-focus nil)
(defvar-local textui--resize-cursor-timer nil)
(defvar-local textui--cursor-type-before-resize nil)

(defvar-local textui-state nil
  "Application state owned by the current TextUI buffer.")

(defun textui--proper-list-p (object)
  "Return non-nil when OBJECT is a finite proper list."
  (let ((slow object)
        (fast object))
    (catch 'done
      (while t
        (cond
         ((null fast) (throw 'done t))
         ((not (consp fast)) (throw 'done nil)))
        (setq fast (cdr fast))
        (cond
         ((null fast) (throw 'done t))
         ((not (consp fast)) (throw 'done nil)))
        (setq fast (cdr fast)
              slow (cdr slow))
        (when (eq slow fast)
          (throw 'done nil))))))

(defun textui--plist-p (object)
  "Return non-nil when OBJECT is a finite property list."
  (and (textui--proper-list-p object)
       (= (% (length object) 2) 0)))

(defun textui--plist-member-p (plist property)
  "Return non-nil when PLIST contains PROPERTY."
  (let ((cursor plist)
        found)
    (while cursor
      (when (eq (car cursor) property)
        (setq found t
              cursor nil))
      (when cursor
        (setq cursor (cddr cursor))))
    found))

(defun textui--validate-layout-options (element native)
  "Validate ELEMENT's parent-facing layout options.
NATIVE is non-nil for a widget.el leaf.  Return the options plist."
  (let ((layout (plist-get element :layout)))
    (unless (or (null layout) (textui--plist-p layout))
      (error "Element :layout must be a property list: %S" layout))
    (let ((cursor layout))
      (while cursor
        (unless (memq (car cursor)
                      '(:width :min-width :grow :focus-id :refresh-id))
          (error "Unknown layout option: %S" (car cursor)))
        (setq cursor (cddr cursor))))
    (dolist (property '(:width :min-width))
      (when (textui--plist-member-p layout property)
        (let ((value (plist-get layout property)))
          (unless (and (integerp value) (> value 0))
            (error "%S must be a positive integer: %S" property value)))))
    (when (textui--plist-member-p layout :grow)
      (let ((grow (plist-get layout :grow)))
        (unless (and (numberp grow) (>= grow 0))
          (error ":grow must be a non-negative number: %S" grow))))
    (when (and native (textui--plist-member-p layout :min-width))
      (error "Native widgets cannot specify :min-width: %S" element))
    (when (textui--plist-member-p layout :refresh-id)
      (let ((id (plist-get layout :refresh-id)))
        (unless (and (symbolp id) id)
          (error ":refresh-id must be a non-nil symbol: %S" id))
        (unless (and (not native)
                     (eq (plist-get element :type) :flex)
                     (eq (plist-get element :direction) :column))
          (error ":refresh-id requires a column :flex element: %S"
                 element))))
    layout))

(defun textui--validate-element (element)
  "Validate the common shape of ELEMENT and return its type."
  (unless (textui--plist-p element)
    (error "Interface element must be a property list: %S" element))
  (unless (textui--plist-member-p element :type)
    (error "Interface element is missing :type: %S" element))
  (let ((type (plist-get element :type)))
    (unless (symbolp type)
      (error "Element :type must be a symbol: %S" type))
    type))

(defun textui--validate-layout-container (element type properties)
  "Validate common layout ELEMENT properties for TYPE.
PROPERTIES lists every accepted property."
  (let ((cursor element))
    (while cursor
      (unless (memq (car cursor) properties)
        (error "Unknown %S property: %S" type (car cursor)))
      (setq cursor (cddr cursor))))
  (dolist (property '(:gap :padding))
    (let ((value (if (textui--plist-member-p element property)
                     (plist-get element property)
                   (if (eq property :gap) 1 0))))
      (unless (and (integerp value) (>= value 0))
        (error "%S must be a non-negative integer: %S" property value))))
  (when (and (textui--plist-member-p element :border)
             (not (memq (plist-get element :border) '(nil t))))
    (error ":border must be nil or t: %S" (plist-get element :border)))
  (let ((children (plist-get element :children)))
    (unless (textui--proper-list-p children)
      (error "%S :children must be a proper list: %S" type children)))
  (textui--validate-layout-options element nil))

(defun textui--validate-flex (element)
  "Validate the TextUI flex ELEMENT."
  (textui--validate-layout-container
   element :flex
   '(:type :direction :gap :padding :border :children :layout))
  (unless (memq (plist-get element :direction) '(:row :column))
    (error ":flex :direction must be :row or :column: %S"
           (plist-get element :direction))))

(defun textui--validate-grid (element)
  "Validate the TextUI grid ELEMENT."
  (textui--validate-layout-container
   element :grid
   '(:type :columns :min-column-width :gap :padding :border
     :children :layout))
  (dolist (property '(:columns :min-column-width))
    (let ((value (plist-get element property)))
      (unless (and (integerp value) (> value 0))
        (error "%S must be a positive integer: %S" property value)))))

(defun textui--validate-text (element)
  "Validate the width-aware TextUI text ELEMENT."
  (let ((cursor element))
    (while cursor
      (unless (memq (car cursor) '(:type :value :layout))
        (error "Unknown :text property: %S" (car cursor)))
      (setq cursor (cddr cursor))))
  (unless (stringp (plist-get element :value))
    (error ":text :value must be a string: %S" (plist-get element :value)))
  (textui--validate-layout-options element nil))

(defun textui--validate-image (element)
  "Validate the row-sliced TextUI image ELEMENT."
  (let ((cursor element))
    (while cursor
      (unless (memq (car cursor) '(:type :file :rows :alt :layout))
        (error "Unknown :image property: %S" (car cursor)))
      (setq cursor (cddr cursor))))
  (unless (and (stringp (plist-get element :file))
               (not (string-empty-p (plist-get element :file))))
    (error ":image :file must be a non-empty string: %S"
           (plist-get element :file)))
  (unless (and (integerp (plist-get element :rows))
               (> (plist-get element :rows) 0))
    (error ":image :rows must be a positive integer: %S"
           (plist-get element :rows)))
  (when (and (textui--plist-member-p element :alt)
             (not (stringp (plist-get element :alt))))
    (error ":image :alt must be a string: %S" (plist-get element :alt)))
  (textui--validate-layout-options element nil))

(defun textui--image-alt (element)
  "Return ELEMENT's alternative image text."
  (or (plist-get element :alt)
      (file-name-nondirectory (plist-get element :file))))

;;;###autoload
(defun textui-register-expander (type function)
  "Register FUNCTION as the pure DSL expander for TYPE.
Re-registering TYPE replaces the previous function.  Return TYPE."
  (unless (and (symbolp type) (not (keywordp type)))
    (error "Expander type must be a non-keyword symbol: %S" type))
  (unless (functionp function)
    (error "Expander must be a function: %S" function))
  (let ((entry (assq type textui--expanders)))
    (if entry
        (setcdr entry function)
      (push (cons type function) textui--expanders)))
  type)

(defun textui--expand-elements (elements ancestors)
  "Expand ELEMENTS recursively, tracking expander ANCESTORS."
  (unless (textui--proper-list-p elements)
    (error "Element sequence must be a proper list: %S" elements))
  (let (result)
    (dolist (element elements (nreverse result))
      (dolist (expanded (textui--expand-element element ancestors))
        (push expanded result)))))

(defun textui--expand-element (element ancestors)
  "Expand ELEMENT recursively, tracking expander ANCESTORS."
  (let* ((type (textui--validate-element element))
         (entry (and (not (keywordp type)) (assq type textui--expanders))))
    (cond
     (entry
      (when (memq type ancestors)
        (error "Element expansion cycle: %S" (reverse (cons type ancestors))))
      (let ((expanded (funcall (cdr entry) element)))
        (unless (textui--proper-list-p expanded)
          (error "Expander %S must return a proper list: %S" type expanded))
        (textui--expand-elements expanded (cons type ancestors))))
     ((keywordp type)
      (unless (memq type '(:flex :grid :text :image))
        (error "Unknown TextUI layout type: %S" type))
      (if (memq type '(:text :image))
          (progn
            (if (eq type :text)
                (textui--validate-text element)
              (textui--validate-image element))
            (list element))
        (if (eq type :flex)
            (textui--validate-flex element)
          (textui--validate-grid element))
        (let ((copy (copy-sequence element)))
          (setq copy
                (plist-put copy :children
                           (textui--expand-elements
                            (plist-get element :children) ancestors)))
          (list copy))))
     (t
      (textui--validate-layout-options element t)
      (list element)))))

(defun textui--widget-args (element)
  "Return ELEMENT properties suitable for `widget-create'."
  (let ((cursor element)
        result)
    (while cursor
      (unless (memq (car cursor) '(:type :layout))
        (setq result (append result (list (car cursor) (cadr cursor)))))
      (setq cursor (cddr cursor)))
    result))

(defun textui--measure-native (element)
  "Measure native widget ELEMENT and return its placeholder text.
Use its optional `:textui-measure' function without creating it."
  (let* ((widget (apply #'widget-convert (plist-get element :type)
                        (textui--widget-args element)))
         (measure (widget-get widget :textui-measure))
         (location-id
          (when (integerp textui--next-location-id)
            (prog1 textui--next-location-id
              (setq textui--next-location-id
                    (1+ textui--next-location-id)))))
         (text
          (if measure
              (progn
                (unless (functionp measure)
                  (error "Widget :textui-measure is not a function: %S"
                         measure))
                (funcall measure widget))
            (with-temp-buffer
              (let ((start (point)))
                (widget-apply widget :create)
                (buffer-substring-no-properties start (point)))))))
    (unless (stringp text)
      (error "Widget :textui-measure must return a string: %S" text))
    (setq text (copy-sequence text))
    (when (string-match-p "\n" text)
      (error "Native widget must render exactly one line: %S" element))
    (when (= (length text) 0)
      (error "Native widget must render at least one character: %S" element))
    (add-text-properties
     0 (length text)
     (list 'textui--placeholder element
           'textui--location-id location-id)
     text)
    text))

(defun textui--sum (numbers)
  "Return the sum of NUMBERS."
  (let ((sum 0))
    (dolist (number numbers sum)
      (setq sum (+ sum number)))))

(defun textui--make-spec (element)
  "Measure normalized ELEMENT and return its internal layout specification."
  (let* ((type (plist-get element :type))
         (native (not (keywordp type)))
         (layout (textui--validate-layout-options element native))
         (declared (plist-get layout :width))
         (grow (or (plist-get layout :grow) 0)))
    (if native
        (let* ((placeholder (textui--measure-native element))
               (natural (string-width placeholder))
               (start (max natural (or declared 0))))
          (list :kind :native :element element :placeholder placeholder
                :natural natural :start start :minimum natural :grow grow))
      (if (memq type '(:text :image))
          (let* ((value (if (eq type :text)
                            (plist-get element :value)
                          (textui--image-alt element)))
                 (natural
                  (if (string-empty-p value)
                      0
                    (apply #'max
                           (mapcar #'string-width
                                   (split-string value "\n" nil)))))
                 (minimum-option (plist-get layout :min-width))
                 (start (max (or declared natural)
                             (or minimum-option 0)))
                 (minimum (or minimum-option start))
                 (location-id
                  (when (integerp textui--next-layout-id)
                    (prog1 textui--next-layout-id
                      (setq textui--next-layout-id
                            (1+ textui--next-layout-id))))))
            (list :kind type :element element :location-id location-id
                  :natural natural :start start :minimum minimum :grow grow))
        (if (eq type :flex)
            (textui--validate-flex element)
          (textui--validate-grid element))
        (let* ((location-id
              (when (integerp textui--next-layout-id)
                (prog1 textui--next-layout-id
                  (setq textui--next-layout-id (1+ textui--next-layout-id)))))
             (children (mapcar #'textui--make-spec
                               (plist-get element :children)))
             (gap (if (textui--plist-member-p element :gap)
                      (plist-get element :gap)
                    1))
             (padding (or (plist-get element :padding) 0))
             (border (and (plist-get element :border) t))
             (content-natural
              (cond
               ((eq type :grid)
                (let* ((columns (plist-get element :columns))
                       (track-width
                        (max
                         (plist-get element :min-column-width)
                         (if children
                             (apply #'max
                                    (mapcar (lambda (child)
                                              (plist-get child :start))
                                            children))
                           0))))
                  (+ (* columns track-width)
                     (* gap (max 0 (1- columns))))))
               ((eq (plist-get element :direction) :row)
                (+ (textui--sum (mapcar (lambda (child)
                                          (plist-get child :start))
                                        children))
                   (* gap (max 0 (1- (length children))))))
               (t
                (if children
                    (apply #'max (mapcar (lambda (child)
                                          (plist-get child :start))
                                        children))
                  0))))
             (natural (+ content-natural (* 2 padding) (if border 2 0)))
             (minimum-option (plist-get layout :min-width))
             (start (max (or declared natural) (or minimum-option 0)))
             (minimum (or minimum-option start)))
          (list :kind type :element element :children children
                :location-id location-id
                :natural natural :start start :minimum minimum :grow grow))))))

(defun textui--prepare-frame (frame &optional omit-location-ids)
  "Expand and measure FRAME without modifying the real interface buffer."
  (unless (textui--proper-list-p frame)
    (error "Render function must return a proper list: %S" frame))
  (let ((textui--next-location-id (unless omit-location-ids 0))
        (textui--next-layout-id (unless omit-location-ids 0)))
    (mapcar #'textui--make-spec (textui--expand-elements frame nil))))

(defun textui--partition-row (children width gap)
  "Partition CHILDREN into ordered rows fitting WIDTH at minima and GAP."
  (let ((available (max 0 width))
        current
        (current-width 0)
        rows)
    (dolist (child children)
      (let* ((minimum (plist-get child :minimum))
             (joined (+ current-width (if current gap 0) minimum)))
        (if (or (null current) (<= joined available))
            (progn
              (push child current)
              (setq current-width joined))
          (push (nreverse current) rows)
          (setq current (list child)
                current-width minimum))))
    (when current
      (push (nreverse current) rows))
    (nreverse rows)))

(defun textui--proportional-shares (amount weights &optional limits)
  "Split integer AMOUNT in proportion to WEIGHTS.
Optional LIMITS caps each returned share."
  (let* ((count (length weights))
         (total (float (textui--sum weights)))
         (shares (make-list count 0))
         (remaining amount))
    (when (> total 0)
      (let ((index 0))
        (dolist (weight weights)
          (let* ((raw (floor (* amount (/ (float weight) total))))
                 (limit (and limits (nth index limits)))
                 (share (if limit (min raw limit) raw)))
            (setcar (nthcdr index shares) share)
            (setq remaining (- remaining share)
                  index (1+ index)))))
      (while (> remaining 0)
        (let ((index 0)
              progressed)
          (while (and (< index count) (> remaining 0))
            (let ((weight (nth index weights))
                  (limit (and limits (nth index limits)))
                  (share (nth index shares)))
              (when (and (> weight 0) (or (null limit) (< share limit)))
                (setcar (nthcdr index shares) (1+ share))
                (setq remaining (1- remaining)
                      progressed t)))
            (setq index (1+ index)))
          (unless progressed
            (setq remaining 0)))))
    shares))

(defun textui--allocate-row (row width gap)
  "Return allocated widths for ROW inside WIDTH using GAP."
  (let* ((count (length row))
         (available (max 0 (- width (* gap (max 0 (1- count))))))
         (starts (mapcar (lambda (child) (plist-get child :start)) row))
         (minimums (mapcar (lambda (child) (plist-get child :minimum)) row))
         (start-total (textui--sum starts)))
    (cond
     ((null row) nil)
     ((and (= count 1) (> (car minimums) available))
      (if (eq (plist-get (car row) :kind) :native)
          (list (car starts))
        (list available)))
     ((<= start-total available)
      (let* ((extra (- available start-total))
             (weights (mapcar (lambda (child) (plist-get child :grow)) row))
             (shares (textui--proportional-shares extra weights)))
        (cl-mapcar #'+ starts shares)))
     (t
      (let* ((overflow (- start-total available))
             (capacities (cl-mapcar #'- starts minimums))
             (capacity (textui--sum capacities))
             (reductions (textui--proportional-shares
                          (min overflow capacity) capacities capacities)))
        (cl-mapcar #'- starts reductions))))))

(defun textui--rendered-string-width (string)
  "Return STRING's displayed width in TextUI cells."
  (if (and (> (length string) 0)
           (text-property-not-all
            0 (length string) 'textui--pixel-justified nil string))
      (ceiling (/ (float (string-pixel-width string))
                  (max 1 (string-pixel-width " "))))
    (string-width string)))

(defun textui--pad-right (string width)
  "Pad STRING with spaces to at least display WIDTH."
  (let ((missing (- width (textui--rendered-string-width string))))
    (if (> missing 0)
        (concat string (make-string missing ?\s))
      string)))

(defun textui--block-width (lines)
  "Return the widest display width in LINES."
  (if lines
      (apply #'max (mapcar #'textui--rendered-string-width lines))
    0))

;;;; Width-aware text

;; Text wrapping uses the fixed subset of emacs-kp that TextUI needs:
;; pixel measurement, boxing, common kinsoku, and one-dimensional KP.

(defun textui--text-pixel-width (width)
  "Return the pixel measure corresponding to WIDTH text cells."
  (max 1
       (string-pixel-width (make-string (max 1 width) ?\s))))

(defun textui--text-hard-line-ranges (string)
  "Return source ranges in STRING separated by hard newlines."
  (let ((start 0)
        ranges)
    (while (string-match "\n" string start)
      (push (cons start (match-beginning 0)) ranges)
      (setq start (match-end 0)))
    (push (cons start (length string)) ranges)
    (nreverse ranges)))

(defun textui--text-plan-lines (source attributed pixel-width)
  "Break SOURCE and return matching substrings from ATTRIBUTED."
  (if (string-empty-p source)
      (list "")
    (require 'textui-kp-core)
    (textui-kp-core-justify-lines source attributed pixel-width)))

(defun textui--wrap-text (string width)
  "Return STRING wrapped by the vendored EKP core for WIDTH cells."
  (let ((attributed (copy-sequence string))
        (pixel-width (textui--text-pixel-width width))
        lines)
    (dotimes (offset (length attributed))
      (put-text-property offset (1+ offset)
                         'textui--text-source-offset offset attributed))
    (dolist (range (textui--text-hard-line-ranges string) lines)
      (let ((start (car range))
            (end (cdr range)))
        (setq lines
              (append
               lines
               (textui--text-plan-lines
                (substring string start end)
                (substring attributed start end)
                pixel-width)))))))

(defun textui--render-text-spec (spec width)
  "Render width-aware text SPEC into WIDTH."
  (let* ((location-id (plist-get spec :location-id))
         (lines
          (textui--wrap-text
           (plist-get (plist-get spec :element) :value)
           (max 1 width))))
    (dolist (line lines lines)
      (when (> (length line) 0)
        (put-text-property 0 (length line)
                           'textui--text-location-id location-id line)))))

(defun textui--image-fallback-lines (element width)
  "Render ELEMENT's alternative text into a fixed WIDTH block."
  (let* ((width (max 0 width))
         (rows (plist-get element :rows))
         (line
          (if (= width 0)
              ""
            (textui--pad-right
             (truncate-string-to-width
              (textui--image-alt element) width nil nil "…")
             width))))
    (cons line (make-list (1- rows) (make-string width ?\s)))))

(defun textui--render-image-spec (spec width)
  "Render image SPEC as native horizontal slices inside WIDTH."
  (let* ((element (plist-get spec :element))
         (rows (plist-get element :rows))
         (frame (selected-frame))
         lines)
    (if (or (<= width 0)
            (not (display-graphic-p frame))
            (not (file-readable-p (plist-get element :file))))
        (setq lines (textui--image-fallback-lines element width))
      (let* ((cell-width (frame-char-width frame))
             (cell-height (frame-char-height frame))
             (source
              (or (create-image (plist-get element :file) nil nil :scale 1)
                  (error "Cannot create image: %s" (plist-get element :file))))
             (source-size (image-size source t))
             (scale (min 1.0
                         (/ (float (* width cell-width)) (car source-size))
                         (/ (float (* rows cell-height)) (cdr source-size))))
             (fitted-height (max 1 (floor (* (cdr source-size) scale))))
             (image-rows
              (max 1 (min rows (floor fitted-height cell-height))))
             (image-height
              (min fitted-height (* image-rows cell-height)))
             (image-width
              (min (* width cell-width)
                   (max 1 (round (* (car source-size)
                                    (/ (float image-height)
                                       (cdr source-size)))))))
             (image-columns (min width (ceiling image-width cell-width)))
             (left (/ (- width image-columns) 2))
             (top (/ (- rows image-rows) 2))
             (slice-height (/ 1.0 image-rows))
             (image (create-image (plist-get element :file) nil nil :scale 1
                                  :width image-width :height image-height
                                  :ascent 'center)))
        (dotimes (row rows)
          (let ((line (make-string width ?\s)))
            (when (and (>= row top) (< row (+ top image-rows)))
              (let ((slice-row (- row top)))
                (when (= slice-row 0)
                  (store-substring
                   line left
                   (truncate-string-to-width
                    (textui--image-alt element) image-columns nil nil "…")))
                (put-text-property
                 left (+ left image-columns) 'display
                 (list (list 'slice 0.0
                             (* slice-row slice-height)
                             1.0 slice-height)
                       image)
                 line)))
            (push line lines)))
        (setq lines (nreverse lines))))
    (textui--tag-layout-cells lines (plist-get spec :location-id))))

(defun textui--render-native-spec (spec width)
  "Render native SPEC into a one-line block of at least WIDTH."
  (let* ((placeholder (plist-get spec :placeholder))
         (location-id (get-text-property 0 'textui--location-id placeholder))
         (line (textui--pad-right
                placeholder (max width (plist-get spec :natural)))))
    (put-text-property 0 (length line) 'textui--location-id location-id line)
    (list line)))

(defun textui--compose-row-blocks (blocks widths gap)
  "Compose rendered BLOCKS at WIDTHS separated by GAP."
  (let ((height 0)
        lines)
    (dolist (block blocks)
      (setq height (max height (length block))))
    (dotimes (line-index height)
      (let (parts)
        (cl-mapc
         (lambda (block width)
           (push (textui--pad-right (or (nth line-index block) "") width)
                 parts))
         blocks widths)
        (push (mapconcat #'identity (nreverse parts) (make-string gap ?\s))
              lines)))
    (nreverse lines)))

(defun textui--render-row-line-block (row widths gap)
  "Render one allocated ROW using WIDTHS and GAP."
  (let ((blocks (cl-mapcar #'textui--render-spec row widths))
        actual-widths)
    (setq actual-widths
          (cl-mapcar (lambda (block assigned)
                       (max assigned (textui--block-width block)))
                     blocks widths))
    (textui--compose-row-blocks blocks actual-widths gap)))

(defun textui--render-row-content (children width gap)
  "Render row CHILDREN responsively inside WIDTH using GAP."
  (if (null children)
      (list "")
    (let (lines)
      (dolist (row (textui--partition-row children width gap))
        (dolist (line
                 (textui--render-row-line-block
                  row (textui--allocate-row row width gap) gap))
          (push line lines)))
      (nreverse lines))))

(defun textui--render-column-content (children width gap)
  "Render column CHILDREN inside WIDTH with GAP blank lines."
  (if (null children)
      (list "")
    (let (lines first)
      (setq first t)
      (dolist (child children)
        (unless first
          (dotimes (_ gap)
            (push "" lines)))
        (setq first nil)
        (dolist (line
                 (textui--render-spec
                  child
                  (if (eq (plist-get child :kind) :native)
                      (max width (plist-get child :start))
                    width)))
          (push line lines)))
      (nreverse lines))))

(defun textui--grid-column-count (element width)
  "Return responsive column count for grid ELEMENT inside WIDTH."
  (let ((gap (or (plist-get element :gap) 1))
        (minimum (plist-get element :min-column-width)))
    (max 1
         (min (plist-get element :columns)
              (/ (+ width gap) (+ minimum gap))))))

(defun textui--partition-fixed (values count)
  "Partition VALUES into source-order groups of at most COUNT."
  (let (groups)
    (while values
      (let* ((size (min count (length values)))
             (group (cl-subseq values 0 size)))
        (push group groups)
        (setq values (nthcdr size values))))
    (nreverse groups)))

(defun textui--render-grid-content (spec width gap)
  "Render equal-track grid SPEC inside WIDTH using GAP."
  (let ((children (plist-get spec :children)))
    (if (null children)
        (list "")
      (let* ((element (plist-get spec :element))
             (columns (textui--grid-column-count element width))
             (available (max 0 (- width (* gap (1- columns)))))
             (widths (textui--proportional-shares
                      available (make-list columns 1)))
             block-rows
             (actual-widths (copy-sequence widths)))
        (dolist (row (textui--partition-fixed children columns))
          (let ((blocks
                 (cl-mapcar #'textui--render-spec row
                            (cl-subseq widths 0 (length row)))))
            (setq blocks
                  (append blocks
                          (make-list (- columns (length blocks)) (list ""))))
            (dotimes (index columns)
              (setcar (nthcdr index actual-widths)
                      (max (nth index actual-widths)
                           (textui--block-width (nth index blocks)))))
            (push blocks block-rows)))
        (let (lines first)
          (setq first t)
          (dolist (blocks (nreverse block-rows))
            (unless first
              (dotimes (_ gap)
                (push "" lines)))
            (setq first nil)
            (dolist (line
                     (textui--compose-row-blocks
                      blocks actual-widths gap))
              (push line lines)))
          (nreverse lines))))))

(defun textui--tag-layout-cells (lines location-id)
  "Tag layout-owned cells in LINES relative to LOCATION-ID."
  (when location-id
    (let ((row 0))
      (dolist (line lines)
        (let ((index 0)
              (column 0))
          (while (< index (length line))
            (unless (or (get-text-property index 'textui--location-id line)
                        (get-text-property index 'textui--layout-cell line))
              (put-text-property
               index (1+ index) 'textui--layout-cell
               (vector location-id row column) line))
            (setq column (+ column (char-width (aref line index)))
                  index (1+ index))))
        (setq row (1+ row)))))
  lines)

(defun textui--render-layout-box (element content width location-id)
  "Render ELEMENT's CONTENT inside WIDTH and tag LOCATION-ID."
  (let* ((padding (or (plist-get element :padding) 0))
         (border (and (plist-get element :border) t))
         (decoration (+ (* 2 padding) (if border 2 0)))
         (content-width
          (max (max 0 (- width decoration)) (textui--block-width content)))
         (body-width (+ content-width (* 2 padding)))
         (horizontal-padding (make-string padding ?\s))
         (blank-body (make-string body-width ?\s))
         body)
    (dotimes (_ padding)
      (push blank-body body))
    (dolist (line content)
      (push (concat horizontal-padding
                    (textui--pad-right line content-width)
                    horizontal-padding)
            body))
    (dotimes (_ padding)
      (push blank-body body))
    (setq body (nreverse body))
    (textui--tag-layout-cells
     (if border
         (append
          (list (concat "┌" (make-string body-width ?─) "┐"))
          (mapcar (lambda (line) (concat "│" line "│")) body)
          (list (concat "└" (make-string body-width ?─) "┘")))
       body)
     location-id)))

(defun textui--render-flex-spec (spec width)
  "Render flex SPEC inside total border-box WIDTH."
  (let* ((element (plist-get spec :element))
         (padding (or (plist-get element :padding) 0))
         (border (and (plist-get element :border) t))
         (gap (if (textui--plist-member-p element :gap)
                  (plist-get element :gap)
                1))
         (inner-width
          (max 0 (- width (* 2 padding) (if border 2 0))))
         (content
          (if (eq (plist-get element :direction) :row)
              (textui--render-row-content
               (plist-get spec :children) inner-width gap)
            (textui--render-column-content
             (plist-get spec :children) inner-width gap))))
    (textui--render-layout-box
     element content width (plist-get spec :location-id))))

(defun textui--render-grid-spec (spec width)
  "Render grid SPEC inside total border-box WIDTH."
  (let* ((element (plist-get spec :element))
         (padding (or (plist-get element :padding) 0))
         (border (and (plist-get element :border) t))
         (gap (if (textui--plist-member-p element :gap)
                  (plist-get element :gap)
                1))
         (inner-width
          (max 0 (- width (* 2 padding) (if border 2 0))))
         (content (textui--render-grid-content spec inner-width gap)))
    (textui--render-layout-box
     element content width (plist-get spec :location-id))))

(defun textui--render-spec (spec width)
  "Render SPEC inside WIDTH and return a list of attributed lines."
  (let* ((lines
          (pcase (plist-get spec :kind)
            (:native (textui--render-native-spec spec width))
            (:text (textui--render-text-spec spec width))
            (:image (textui--render-image-spec spec width))
            (:flex (textui--render-flex-spec spec width))
            (:grid (textui--render-grid-spec spec width))))
         (element (plist-get spec :element))
         (id (plist-get (plist-get element :layout) :refresh-id)))
    (when id
      (when textui--collect-refresh-regions
        (when (assq id textui--rendered-regions)
          (error "Duplicate refresh ID: %S" id))
        (push (list id element width) textui--rendered-regions))
      (dolist (line lines)
        (when (> (length line) 0)
          (put-text-property 0 (length line) 'textui--refresh-id id line))))
    lines))

(defun textui--render-specs (specs width)
  "Render top-level SPECS at available WIDTH without implicit separators."
  (let (parts)
    (dolist (spec specs)
      (push (mapconcat
             #'identity
             (textui--render-spec
              spec
              (if (eq (plist-get spec :kind) :native)
                  (plist-get spec :start)
                width))
             "\n")
            parts))
    (apply #'concat (nreverse parts))))

(defun textui--render-frame (frame width)
  "Expand, measure, and render FRAME for available WIDTH."
  (unless (and (integerp width) (>= width 0))
    (error "Available width must be a non-negative integer: %S" width))
  (textui--render-specs (textui--prepare-frame frame) width))

(defun textui--refresh-region-span (rendered id)
  "Return ID's complete-line span in RENDERED."
  (let* ((length (length rendered))
         (start (text-property-any
                 0 length 'textui--refresh-id id rendered)))
    (unless start
      (error "Refresh region %S rendered no complete lines" id))
    (unless (or (= start 0) (= (aref rendered (1- start)) ?\n))
      (error "Refresh region %S must occupy complete lines" id))
    (let ((position start)
          end)
      (while (not end)
        (let ((line-end (or (string-match "\n" rendered position) length)))
          (when (or (= position line-end)
                    (text-property-not-all
                     position line-end 'textui--refresh-id id rendered))
            (error "Refresh region %S must occupy complete lines" id))
          (let ((next (if (< line-end length) (1+ line-end) length)))
            (if (and (< next length)
                     (eq (get-text-property
                          next 'textui--refresh-id rendered)
                         id))
                (setq position next)
              (setq end next)))))
      (when (text-property-any
             end length 'textui--refresh-id id rendered)
        (error "Refresh region %S must be one continuous block" id))
      (cons start end))))

(defun textui--collect-refresh-region-spans (rendered)
  "Return collected refresh metadata with spans in RENDERED."
  (let (result)
    (dolist (region textui--rendered-regions result)
      (let ((span (textui--refresh-region-span rendered (car region))))
        (push (append region (list (car span) (cdr span))) result)))))

(defun textui--clear-refresh-regions ()
  "Detach all refresh-region markers in the current buffer."
  (dolist (region textui--refresh-regions)
    (set-marker (nth 3 region) nil)
    (set-marker (nth 4 region) nil))
  (setq textui--refresh-regions nil))

(defun textui--install-refresh-regions (regions rendered)
  "Install REGIONS and their templates from RENDERED in the current buffer."
  (textui--clear-refresh-regions)
  (dolist (region regions)
    (let ((from (copy-marker (+ (point-min) (nth 3 region))))
          (to (copy-marker (+ (point-min) (nth 4 region)))))
      (push (list (nth 0 region) (nth 1 region) (nth 2 region) from to
                  (substring rendered (nth 3 region) (nth 4 region)))
            textui--refresh-regions)))
  (setq textui--refresh-regions (nreverse textui--refresh-regions)))

(defun textui--placeholder-ranges (&optional from to)
  "Return deferred widget ranges between FROM and TO in reverse order."
  (let ((position (or from (point-min)))
        (limit (or to (point-max)))
        ranges)
    (while (< position limit)
      (let* ((element (get-text-property position 'textui--placeholder))
             (end (or (next-single-property-change
                       position 'textui--placeholder nil limit)
                      limit)))
        (when element
          (push (list position end element
                      (get-text-property position 'textui--location-id))
                ranges))
        (setq position end)))
    ranges))

(defun textui--focus-id (element)
  "Return ELEMENT's optional focus ID."
  (plist-get (plist-get element :layout) :focus-id))

(defun textui--compensate-image-runs (from to)
  "Keep image runs between FROM and TO within one text cell line."
  (let ((position from)
        (inhibit-read-only t))
    (while (< position to)
      (let* ((display (get-text-property position 'display))
             (end (or (next-single-property-change
                       position 'display nil to)
                      to)))
        (when (and (consp display) (eq (car display) 'image))
          (let* ((fitted-display
                  (cons 'image
                        (plist-put
                         (plist-put (copy-tree (cdr display))
                                    :max-height '(1 . ch))
                         :ascent 'center)))
                 (text (buffer-substring-no-properties position end))
                 (cells (string-width text))
                 (image-width (car (image-size fitted-display t)))
                 (text-width (string-pixel-width text)))
            (put-text-property position end 'display fitted-display)
            (if (and (> cells 1) (<= image-width text-width))
                (put-text-property
                 (1- end) end 'display
                 `(space :width (- (,cells . width) ,fitted-display)))
              (remove-text-properties position end '(display nil)))))
        (setq position end)))))

(defun textui--inset-widget-field-box (widget)
  "Keep WIDGET's field face box inside its allocated character width."
  (let* ((overlay (widget-get widget :field-overlay))
         (face (and (overlayp overlay) (overlay-get overlay 'face)))
         (box (and (facep face) (face-attribute face :box nil t)))
         (line-width (and (listp box) (plist-get box :line-width)))
         inset-width)
    (cond
     ((and (integerp line-width) (> line-width 0))
      (setq inset-width (- line-width)))
     ((and (consp line-width)
           (integerp (car line-width))
           (> (car line-width) 0))
      (setq inset-width (cons (- (car line-width)) (cdr line-width)))))
    (when inset-width
      (overlay-put
       overlay 'face
       (list :inherit face :box
             (plist-put (copy-tree box) :line-width inset-width))))))

(defun textui--materialize-placeholders (buffer &optional from to append)
  "Replace placeholders for BUFFER between FROM and TO.
Keep existing widget and focus records when APPEND is non-nil."
  (unless append
    (setq textui--widgets nil
          textui--focus-anchors nil))
  (dolist (range (textui--placeholder-ranges from to))
    (let* ((from (nth 0 range))
           (to (nth 1 range))
           (element (nth 2 range))
           (location-id (nth 3 range))
           (expected-width
            (string-width (buffer-substring-no-properties from to))))
      (remove-text-properties from to '(textui--placeholder nil))
      (let* ((widget (apply #'widget-convert (plist-get element :type)
                            (textui--widget-args element)))
             (original-action (widget-get widget :action))
             (attach (widget-get widget :textui-attach)))
        (when original-action
          (unless (functionp original-action)
            (error "Widget :action is not a function: %S" original-action))
          (let ((target-buffer buffer)
                (action original-action))
            (widget-put
             widget :action
             (lambda (active-widget &optional event)
               (let* ((generation
                       (and (buffer-live-p target-buffer)
                            (buffer-local-value
                             'textui--refresh-generation target-buffer)))
                      (result (funcall action active-widget event)))
                 (when (and (buffer-live-p target-buffer)
                            (= generation
                               (buffer-local-value
                                'textui--refresh-generation target-buffer))
                            (not (buffer-local-value
                                  'textui--refresh-timer target-buffer))
                            (not (buffer-local-value
                                  'textui--region-refresh-requests
                                  target-buffer)))
                   (let ((textui--focus-override
                          (and this-command
                               (list textui--focus-before-command
                                     textui--position-before-command))))
                    (textui--reconcile target-buffer)))
                 result)))))
        (if attach
            (progn
              (unless (functionp attach)
                (error "Widget :textui-attach is not a function: %S" attach))
              (funcall attach widget from to)
              (let ((widget-from (widget-get widget :from))
                    (widget-to (widget-get widget :to)))
                (unless (and (markerp widget-from)
                             (markerp widget-to)
                             (eq (marker-buffer widget-from) buffer)
                             (eq (marker-buffer widget-to) buffer)
                             (= widget-from from)
                             (= widget-to to))
                  (error "Widget :textui-attach returned invalid bounds: %S"
                         element))
                (goto-char widget-to)))
          (delete-region from to)
          (goto-char from)
          (widget-apply widget :create))
        (let ((actual-end (point)))
          (put-text-property from actual-end
                             'textui--location-id location-id)
          (textui--compensate-image-runs
           (widget-get widget :from) (widget-get widget :to))
          (push widget textui--widgets)
          (let ((actual (buffer-substring-no-properties from actual-end)))
            (when (or (string-match-p "\n" actual)
                      (/= expected-width (string-width actual)))
              (error "Measured and real widget output differs: %S" element)))
          (let ((focus-id (textui--focus-id element)))
            (when focus-id
              (when (assoc focus-id textui--focus-anchors)
                (error "Duplicate focus ID: %S" focus-id))
              (push (list focus-id from actual-end)
                    textui--focus-anchors)))))))
  (widget-setup)
  (dolist (widget textui--widgets)
    (textui--inset-widget-field-box widget)))

(defun textui--capture-text-focus ()
  "Return point's semantic source position inside a width-aware text leaf."
  (let* ((position (point))
         (probe
          (cond
           ((get-text-property position 'textui--text-location-id) position)
           ((and (> position (point-min))
                 (get-text-property
                  (1- position) 'textui--text-location-id))
            (1- position))))
         (location-id
          (and probe
               (get-text-property probe 'textui--text-location-id)))
         (source-offset
          (and probe
               (get-text-property probe 'textui--text-source-offset))))
    (when (and location-id (integerp source-offset))
      (vector 'text location-id source-offset))))

(defun textui--capture-focus ()
  "Return point's semantic native or layout location."
  (let ((position (point))
        result)
    (dolist (anchor textui--focus-anchors result)
      (when (and (<= (nth 1 anchor) position)
                 (<= position (nth 2 anchor)))
        (setq result (cons (car anchor) (- position (nth 1 anchor))))))
    (or result
        (textui--capture-text-focus)
        (let* ((probe (if (get-text-property position 'textui--location-id)
                          position
                        (and (> position (point-min)) (1- position))))
               (location-id
                (and probe
                     (get-text-property probe 'textui--location-id))))
          (when location-id
            (let ((start
                   (or (previous-single-property-change
                        (1+ probe) 'textui--location-id nil (point-min))
                       (point-min))))
              (vector location-id (- position start)))))
        (or (get-text-property position 'textui--layout-cell)
            (and (> position (point-min))
                 (get-text-property (1- position) 'textui--layout-cell))))))

(defun textui--capture-position ()
  "Return point's one-based line and display column."
  (cons (line-number-at-pos) (current-column)))

(defun textui--capture-window-views (buffer focus position)
  "Capture semantic points and cursor rows for windows showing BUFFER.
FOCUS and POSITION describe point in the selected window."
  (let (views)
    (dolist (window (get-buffer-window-list buffer nil t) (nreverse views))
      (when (window-live-p window)
        (if (eq window (selected-window))
            (push (list window focus position
                        (max 0 (- (car position)
                                  (line-number-at-pos
                                   (window-start window)))))
                  views)
          (save-excursion
            (goto-char (window-point window))
            (let ((window-focus (textui--capture-focus))
                  (window-position (textui--capture-position)))
              (push (list window window-focus window-position
                          (max 0 (- (car window-position)
                                    (line-number-at-pos
                                     (window-start window)))))
                    views))))))))

(defun textui--remember-focus ()
  "Remember point and its focus anchor before an input command."
  (setq textui--focus-before-command (textui--capture-focus)
        textui--position-before-command (textui--capture-position)))

(defun textui--restore-position (position)
  "Restore one-based line and display column POSITION."
  (goto-char (point-min))
  (forward-line (1- (car position)))
  (move-to-column (cdr position)))

(defun textui--restore-layout-cell (cell)
  "Restore point to the closest cell belonging to layout CELL."
  (let ((position (point-min))
        best
        best-row-distance
        best-column-distance)
    (while (< position (point-max))
      (let ((candidate (get-text-property position 'textui--layout-cell)))
        (when (and (vectorp candidate)
                   (= (length candidate) 3)
                   (equal (aref candidate 0) (aref cell 0)))
          (let ((row-distance
                 (abs (- (aref candidate 1) (aref cell 1))))
                (column-distance
                 (abs (- (aref candidate 2) (aref cell 2)))))
            (when (or (null best)
                      (< row-distance best-row-distance)
                      (and (= row-distance best-row-distance)
                           (< column-distance best-column-distance)))
              (setq best position
                    best-row-distance row-distance
                    best-column-distance column-distance)))))
      (setq position (1+ position)))
    (when best
      (goto-char best)
      t)))

(defun textui--restore-text-focus (focus)
  "Restore point to the source position described by text FOCUS."
  (let ((location-id (aref focus 1))
        (source-offset (aref focus 2))
        (position (point-min))
        best
        best-distance)
    (catch 'found
      (while (< position (point-max))
        (when (equal (get-text-property
                      position 'textui--text-location-id)
                     location-id)
          (let ((candidate
                 (get-text-property position 'textui--text-source-offset)))
            (when (integerp candidate)
              (let ((distance (abs (- candidate source-offset))))
                (when (= distance 0)
                  (goto-char position)
                  (throw 'found t))
                (when (or (null best) (< distance best-distance))
                  (setq best position best-distance distance))))))
        (setq position (1+ position)))
      (when best
        (goto-char best)
        t))))

(defun textui--restore-focus (focus position)
  "Restore FOCUS, falling back to line and column POSITION."
  (let ((anchor (and (consp focus)
                     (assoc (car focus) textui--focus-anchors))))
    (cond
     (anchor
     (goto-char (+ (nth 1 anchor)
                    (min (cdr focus) (- (nth 2 anchor) (nth 1 anchor))))))
     ((and (vectorp focus) (= (length focus) 3)
           (eq (aref focus 0) 'text))
      (unless (textui--restore-text-focus focus)
        (textui--restore-position position)))
     ((and (vectorp focus) (= (length focus) 3))
      (unless (textui--restore-layout-cell focus)
        (textui--restore-position position)))
     ((vectorp focus)
      (let ((start (text-property-any
                    (point-min) (point-max) 'textui--location-id
                    (aref focus 0))))
        (if start
            (let ((end (or (next-single-property-change
                            start 'textui--location-id nil (point-max))
                           (point-max))))
              (goto-char (+ start (min (aref focus 1) (- end start)))))
          (textui--restore-position position))))
     (t
     (textui--restore-position position)))))

(defun textui--restore-window-views (views)
  "Restore semantic window points and cursor rows from VIEWS."
  (dolist (view views)
    (let ((window (nth 0 view)))
      (when (and (window-live-p window)
                 (eq (window-buffer window) (current-buffer)))
        (save-excursion
          (textui--restore-focus (nth 1 view) (nth 2 view))
          (set-window-point window (point))
          (forward-line
           (- (min (nth 3 view)
                   (max 0 (1- (window-body-height window))))))
          (set-window-start window (line-beginning-position)))))))

(defun textui--restore-focus-after-command ()
  "Apply a focus restoration deferred until the native command returned."
  (when textui--pending-focus
    (let ((focus (nth 0 textui--pending-focus))
          (position (nth 1 textui--pending-focus))
          (views (nth 2 textui--pending-focus)))
      (setq textui--pending-focus nil)
      (textui--restore-focus focus position)
      (textui--restore-window-views views))))

(defun textui--widget-button-release (event)
  "Apply the widget action under repeated mouse release EVENT."
  (interactive "e")
  (let* ((event-position (event-end event))
         (window (posn-window event-position))
         (position (posn-point event-position))
         (button (and (windowp window)
                      (integer-or-marker-p position)
                      (get-char-property position 'button
                                         (window-buffer window)))))
    (when button
      (with-selected-window window
        (goto-char position)
        (widget-apply-action button event)))))

(defvar textui-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map
                       (make-composed-keymap widget-keymap special-mode-map))
    (dolist (event '([double-down-mouse-1] [triple-down-mouse-1]
                     [double-down-mouse-2] [triple-down-mouse-2]))
      (define-key map event #'ignore))
    (dolist (event '([double-mouse-1] [triple-mouse-1]
                     [double-mouse-2] [triple-mouse-2]))
      (define-key map event #'textui--widget-button-release))
    map)
  "Keymap for `textui-mode'.")

;;;###autoload
(defun textui-route-state (region keys producer)
  "Route changes to plist state KEYS directly to refresh REGION.
Call this from a TextUI render function.  PRODUCER follows the
`textui-refresh-region' contract and must read the current `textui-state'.
Every key must affect only the declared region or regions; undeclared keys
fall back to complete frame reconciliation."
  (unless textui--collect-state-routes
    (error "textui-route-state must be called by a TextUI render function"))
  (unless (symbolp region)
    (error "State route region must be a symbol: %S" region))
  (unless (and (textui--proper-list-p keys)
               keys
               (cl-every #'symbolp keys))
    (error "State route keys must be a non-empty symbol list: %S" keys))
  (unless (functionp producer)
    (error "State route producer must be a function: %S" producer))
  (when (assq region textui--rendered-state-routes)
    (error "Duplicate state route region: %S" region))
  (push (list region (delete-dups (copy-sequence keys)) producer)
        textui--rendered-state-routes)
  nil)

;;;###autoload
(defun textui-effect (id dependencies setup)
  "Keep one buffer lifecycle effect ID synchronized with DEPENDENCIES.
Call this from a TextUI render function.  SETUP runs after the rendered frame
is committed and may return a zero-argument cleanup function.  TextUI runs the
cleanup before changed dependencies restart the effect, when a later render
omits ID, or when the buffer is killed."
  (unless textui--collect-effects
    (error "textui-effect must be called by a TextUI render function"))
  (unless id
    (error "Effect ID must be non-nil"))
  (unless (functionp setup)
    (error "Effect setup must be a function: %S" setup))
  (when (assoc id textui--rendered-effects)
    (error "Duplicate effect ID: %S" id))
  (push (list id (copy-tree dependencies) setup) textui--rendered-effects)
  nil)

(defun textui--effect-active-p (token)
  "Return non-nil when TOKEN identifies an active current-buffer effect."
  (cl-some (lambda (effect) (eq (nth 3 effect) token)) textui--effects))

;;;###autoload
(defun textui-async-callback (function)
  "Return a lifecycle-bound asynchronous wrapper around FUNCTION.
Create the wrapper inside a `textui-effect' SETUP function.  It restores the
owning TextUI buffer before calling FUNCTION and ignores calls after that
effect has stopped or the buffer has been killed."
  (unless (functionp function)
    (error "Async callback must wrap a function: %S" function))
  (unless textui--current-effect-token
    (error "textui-async-callback must be created by an effect setup"))
  (let ((buffer (current-buffer))
        (token textui--current-effect-token))
    (lambda (&rest arguments)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when (textui--effect-active-p token)
            (apply function arguments)))))))

(defun textui--start-effect (description)
  "Start effect DESCRIPTION and return its active record."
  (let* ((token (list 'textui-effect-token))
         (record (list (nth 0 description) (nth 1 description) nil token)))
    (push record textui--effects)
    (condition-case error-data
        (let ((textui--current-effect-token token))
          (let ((cleanup (funcall (nth 2 description))))
            (unless (or (null cleanup) (functionp cleanup))
              (error "Effect cleanup must be a function or nil: %S" cleanup))
            (setf (nth 2 record) cleanup)
            record))
      (error
       (setq textui--effects (delq record textui--effects))
       (signal (car error-data) (cdr error-data))))))

(defun textui--commit-effects (descriptions)
  "Reconcile active effects with rendered DESCRIPTIONS."
  (let (stopped retained)
    (dolist (effect textui--effects)
      (let ((next (assoc (car effect) descriptions)))
        (if (and next (equal (nth 1 effect) (nth 1 next)))
            (push effect retained)
          (push effect stopped))))
    (setq textui--effects (nreverse retained))
    (dolist (effect stopped)
      (when (functionp (nth 2 effect))
        (funcall (nth 2 effect))))
    (dolist (description descriptions)
      (unless (assoc (car description) textui--effects)
        (textui--start-effect description)))
    (setq textui--effects
          (mapcar (lambda (description)
                    (assoc (car description) textui--effects))
                  descriptions))))

(defun textui--dispose ()
  "Cancel internal work and run cleanup functions for the current buffer."
  (dolist (timer (list textui--refresh-timer
                       textui--region-refresh-timer
                       textui--resize-cursor-timer))
    (when (timerp timer)
      (cancel-timer timer)))
  (setq textui--refresh-timer nil
        textui--region-refresh-timer nil
        textui--region-refresh-requests nil
        textui--resize-cursor-timer nil)
  (let ((cleanups (append (delq nil (mapcar (lambda (effect)
                                              (nth 2 effect))
                                            textui--effects))
                          textui--cleanup-functions))
        first-error)
    (setq textui--effects nil
          textui--state-routes nil
          textui--cleanup-functions nil)
    (dolist (cleanup cleanups)
      (condition-case error-data
          (funcall cleanup)
        (error
         (unless first-error
           (setq first-error error-data)))))
    (when first-error
      (signal (car first-error) (cdr first-error)))))

;;;###autoload
(defun textui-register-cleanup (buffer function)
  "Run FUNCTION once when live TextUI BUFFER is killed.
Registering the same function object more than once has no effect."
  (if (not (buffer-live-p buffer))
      nil
    (unless (functionp function)
      (error "Cleanup must be a function: %S" function))
    (with-current-buffer buffer
      (unless (derived-mode-p 'textui-mode)
        (error "Not a TextUI buffer: %S" buffer))
      (unless (memq function textui--cleanup-functions)
        (push function textui--cleanup-functions))
      function)))

(define-derived-mode textui-mode special-mode "TextUI"
  "Major mode for TextUI-managed widget buffers."
  (setq buffer-read-only nil)
  (add-hook 'pre-command-hook #'textui--remember-focus nil t)
  (add-hook 'post-command-hook #'textui--restore-focus-after-command nil t)
  (add-hook 'window-configuration-change-hook
            #'textui--maybe-refresh-for-width nil t)
  (add-hook 'kill-buffer-hook #'textui--dispose nil t))

(defun textui--visible-width (buffer)
  "Return BUFFER's narrowest usable live window width, or nil."
  (let ((windows (get-buffer-window-list buffer nil t))
        widths)
    (dolist (window windows)
      (when (window-live-p window)
        (push (max 0 (1- (window-body-width window))) widths)))
    (when widths
      (apply #'min widths))))

(defun textui--available-width (buffer)
  "Return BUFFER's visible width or its last successful hidden width."
  (or (textui--visible-width buffer)
      textui--last-width
      (error "TextUI buffer has no available width: %S" buffer)))

(defun textui--restore-cursor-after-resize (buffer)
  "Restore BUFFER's cursor after window resizing becomes idle."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq cursor-type textui--cursor-type-before-resize
            textui--cursor-type-before-resize nil
            textui--resize-cursor-timer nil))))

(defun textui--hide-cursor-during-resize ()
  "Hide the current buffer's cursor until window resizing becomes idle."
  (unless textui--resize-cursor-timer
    (setq textui--cursor-type-before-resize cursor-type))
  (when textui--resize-cursor-timer
    (cancel-timer textui--resize-cursor-timer))
  (setq cursor-type nil
        textui--resize-cursor-timer
        (run-with-timer 0.1 nil #'textui--restore-cursor-after-resize
                        (current-buffer))))

(defun textui--maybe-refresh-for-width ()
  "Refresh current TextUI buffer when its visible width changed."
  (when (and (derived-mode-p 'textui-mode)
             textui--render-function
             (not textui--refreshing))
    (let ((width (textui--visible-width (current-buffer))))
      (when (and width (not (equal width textui--last-width)))
        (textui--hide-cursor-during-resize)
        (textui-refresh (current-buffer))))))

(defun textui--delete-widgets-in-region (from to)
  "Delete widgets beginning between FROM and TO."
  (let (deleted kept)
    (dolist (widget textui--widgets)
      (let ((start (widget-get widget :from)))
        (if (and (markerp start)
                 (marker-position start)
                 (<= from start)
                 (< start to))
            (push widget deleted)
          (push widget kept))))
    (setq textui--widgets (nreverse kept))
    (dolist (widget
             (sort deleted
                   (lambda (left right)
                     (> (widget-get left :from) (widget-get right :from)))))
      (widget-delete widget))))

(defun textui--shift-focus-anchors-after-region (from to delta)
  "Remove anchors in FROM..TO and shift later anchors by DELTA."
  (let (kept)
    (dolist (anchor textui--focus-anchors)
      (cond
       ((<= (nth 2 anchor) from)
        (push anchor kept))
       ((>= (nth 1 anchor) to)
        (push (list (nth 0 anchor)
                    (+ (nth 1 anchor) delta)
                    (+ (nth 2 anchor) delta))
              kept))))
    (setq textui--focus-anchors (nreverse kept))))

(defun textui--capture-region-point (from to)
  "Capture point relative to refresh region FROM..TO."
  (if (and (<= from (point)) (< (point) to))
      (list :row (- (line-number-at-pos)
                    (line-number-at-pos from))
            :column (current-column)
            :focus (let ((focus (textui--capture-focus)))
                     (and (consp focus) focus)))
    (list :marker (copy-marker (point) t))))

(defun textui--restore-region-point (snapshot from max-row)
  "Restore point from SNAPSHOT at region FROM, clamped to MAX-ROW."
  (let ((marker (plist-get snapshot :marker))
        (focus (plist-get snapshot :focus)))
    (cond
     (marker
      (goto-char marker)
      (set-marker marker nil))
     ((and focus (assoc (car focus) textui--focus-anchors))
      (let ((anchor (assoc (car focus) textui--focus-anchors)))
        (goto-char (+ (nth 1 anchor)
                      (min (cdr focus)
                           (- (nth 2 anchor) (nth 1 anchor)))))))
     (t
      (goto-char from)
      (forward-line (min (plist-get snapshot :row) max-row))
      (move-to-column (plist-get snapshot :column))))))

(defun textui--render-current-frame (buffer)
  "Return BUFFER's current (WIDTH RENDERED REGIONS EFFECTS ROUTES) frame data."
  (let ((width (textui--available-width buffer))
        (textui--collect-refresh-regions t)
        (textui--rendered-regions nil)
        (textui--collect-effects t)
        (textui--rendered-effects nil)
        (textui--collect-state-routes t)
        (textui--rendered-state-routes nil))
    (let* ((frame (funcall textui--render-function width))
           (specs (textui--prepare-frame frame))
           (rendered (textui--render-specs specs width))
           (regions (textui--collect-refresh-region-spans rendered))
           (routes (nreverse textui--rendered-state-routes)))
      (dolist (route routes)
        (unless (assq (car route) regions)
          (error "Unknown state route region: %S" (car route))))
      (list width rendered regions (nreverse textui--rendered-effects)
            routes))))

(defun textui--commit-full-frame (buffer width rendered regions)
  "Commit a complete BUFFER frame described by WIDTH, RENDERED, and REGIONS."
  (let* ((focus (if textui--focus-override
                    (nth 0 textui--focus-override)
                  (textui--capture-focus)))
         (position (if textui--focus-override
                       (nth 1 textui--focus-override)
                     (textui--capture-position)))
         (views (textui--capture-window-views buffer focus position))
         (inhibit-read-only t)
         (inhibit-modification-hooks t))
    (mapc #'widget-delete textui--widgets)
    (setq textui--widgets nil)
    (erase-buffer)
    (insert rendered)
    (goto-char (point-min))
    (textui--materialize-placeholders buffer)
    (textui--install-refresh-regions regions rendered)
    (setq textui--rendered-frame rendered
          textui--last-width width
          textui--refresh-generation (1+ textui--refresh-generation))
    (if textui--focus-override
        (setq textui--pending-focus (list focus position views))
      (textui--restore-focus focus position)
      (textui--restore-window-views views))
    (dolist (window (get-buffer-window-list buffer nil t))
      (set-window-hscroll window 0))))

(defun textui--installed-refresh-region-spans ()
  "Return installed refresh regions with numeric cached-frame spans."
  (let (spans valid)
    (setq valid t)
    (dolist (region textui--refresh-regions)
      (let ((from (marker-position (nth 3 region)))
            (to (marker-position (nth 4 region))))
        (if (and from to)
            (push (list (nth 0 region) (nth 1 region) (nth 2 region)
                        (- from (point-min)) (- to (point-min)))
                  spans)
          (setq valid nil))))
    (and valid (nreverse spans))))

(defun textui--refresh-region-shell (rendered regions)
  "Return RENDERED with every complete-line REGION replaced by its ID."
  (let ((cursor 0)
        parts)
    (dolist (region regions)
      (push (substring rendered cursor (nth 3 region)) parts)
      (push (car region) parts)
      (setq cursor (nth 4 region)))
    (push (substring rendered cursor) parts)
    (nreverse parts)))

(defun textui--reconcile-region-pairs (width rendered regions)
  "Return installed/new region pairs safe to patch, or nil for full refresh."
  (let ((installed-spans (textui--installed-refresh-region-spans)))
    (when (and textui--rendered-frame
               (= width textui--last-width)
               textui--refresh-regions
               (= (length textui--rendered-frame)
                  (- (point-max) (point-min)))
               (= (length textui--refresh-regions) (length regions))
               (cl-every #'eq (mapcar #'car textui--refresh-regions)
                         (mapcar #'car regions))
               (equal-including-properties
                (textui--refresh-region-shell
                 textui--rendered-frame installed-spans)
                (textui--refresh-region-shell rendered regions)))
      (cl-mapcar #'cons textui--refresh-regions regions))))

(defun textui--replace-rendered-cache (from to replacement)
  "Replace cached frame text from buffer positions FROM to TO with REPLACEMENT."
  (when textui--rendered-frame
    (let ((start (- from (point-min)))
          (end (- to (point-min))))
      (unless (= (- end start) (length replacement))
        (setq textui--rendered-frame
              (concat (substring textui--rendered-frame 0 start)
                      replacement
                      (substring textui--rendered-frame end)))))))

(defun textui--refresh-region-templates-equal-p (left right)
  "Return non-nil when LEFT and RIGHT differ only by generated location IDs."
  (when (= (length left) (length right))
    (let ((a (copy-sequence left))
          (b (copy-sequence right)))
      (remove-list-of-text-properties
       0 (length a) '(textui--location-id) a)
      (remove-list-of-text-properties
       0 (length b) '(textui--location-id) b)
      (equal-including-properties a b))))

(defun textui--replace-refresh-region-template
    (buffer region new-region replacement-text)
  "Replace installed REGION in BUFFER from NEW-REGION and REPLACEMENT-TEXT."
  (let* ((from-marker (nth 3 region))
         (to-marker (nth 4 region))
         (from (marker-position from-marker))
         (to (marker-position to-marker))
         (other-boundaries
          (delq
           nil
           (mapcar
            (lambda (other)
              (unless (eq other region)
                (list (nth 3 other) (marker-position (nth 3 other))
                      (nth 4 other) (marker-position (nth 4 other)))))
            textui--refresh-regions)))
         (snapshot (textui--capture-region-point from to))
         (delta (- (length replacement-text) (- to from)))
         (content (string-remove-suffix "\n" replacement-text))
         (max-row (max 0 (1- (length (split-string content "\n")))))
         (inhibit-read-only t)
         (inhibit-modification-hooks t))
    (textui--replace-rendered-cache from to replacement-text)
    (textui--delete-widgets-in-region from to)
    (delete-region from-marker to-marker)
    (goto-char from-marker)
    (insert replacement-text)
    (set-marker from-marker from buffer)
    (set-marker to-marker (+ from (length replacement-text)) buffer)
    (textui--shift-focus-anchors-after-region from to delta)
    (setf (nth 1 region) (nth 1 new-region)
          (nth 2 region) (nth 2 new-region)
          (nth 5 region) replacement-text)
    (goto-char from-marker)
    (textui--materialize-placeholders buffer from-marker to-marker t)
    (set-marker from-marker from buffer)
    (set-marker to-marker (+ from (length replacement-text)) buffer)
    (dolist (boundary other-boundaries)
      (set-marker (nth 0 boundary)
                  (+ (nth 1 boundary)
                     (if (>= (nth 1 boundary) to) delta 0))
                  buffer)
      (set-marker (nth 2 boundary)
                  (+ (nth 3 boundary)
                     (if (>= (nth 3 boundary) to) delta 0))
                  buffer))
    (setq textui--refresh-generation (1+ textui--refresh-generation))
    (textui--restore-region-point snapshot from-marker max-row)
    (force-mode-line-update)))

(defun textui--reconcile (buffer)
  "Render BUFFER and patch changed named regions when its frame shell is stable."
  (if (not (buffer-live-p buffer))
      nil
    (with-current-buffer buffer
      (unless (derived-mode-p 'textui-mode)
        (error "Not a TextUI buffer: %S" buffer))
      (when textui--refreshing
        (error "Reentrant TextUI refresh: %S" buffer))
      (let* ((textui--refreshing t)
             (frame (textui--render-current-frame buffer))
             (width (nth 0 frame))
             (rendered (nth 1 frame))
             (regions (nth 2 frame))
             (pairs (textui--reconcile-region-pairs width rendered regions)))
        (if (not pairs)
            (textui--commit-full-frame buffer width rendered regions)
          (dolist (pair pairs)
            (let* ((installed (car pair))
                   (new (cdr pair))
                   (template (substring rendered (nth 3 new) (nth 4 new))))
              (if (textui--refresh-region-templates-equal-p
                   (nth 5 installed) template)
                  (setf (nth 1 installed) (nth 1 new)
                        (nth 2 installed) (nth 2 new)
                        (nth 5 installed) template)
                (textui--replace-refresh-region-template
                 buffer installed new template))))
          (setq textui--rendered-frame rendered
                textui--last-width width))
        (setq textui--state-routes (nth 4 frame))
        (textui--commit-effects (nth 3 frame))
        buffer))))

(defun textui--run-requested-region-refreshes (buffer)
  "Run the latest queued region refreshes for live BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq textui--region-refresh-timer nil)
      (let ((requests (nreverse textui--region-refresh-requests)))
        (setq textui--region-refresh-requests nil)
        (dolist (request requests)
          (when (assq (car request) textui--refresh-regions)
            (textui-refresh-region buffer (car request) (cdr request))))))))

(defun textui--run-requested-refresh (buffer)
  "Run a queued reconciled refresh for live BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when textui--refresh-timer
        (setq textui--refresh-timer nil)
        (textui--reconcile buffer)))))

;;;###autoload
(defun textui-request-refresh (buffer)
  "Request one asynchronous reconciled refresh of live TextUI BUFFER.
Repeated pending requests are combined.  Changed named regions are patched;
structural or width changes fall back to a complete rebuild."
  (if (not (buffer-live-p buffer))
      nil
    (with-current-buffer buffer
      (unless (derived-mode-p 'textui-mode)
        (error "Not a TextUI buffer: %S" buffer))
      (when (timerp textui--region-refresh-timer)
        (cancel-timer textui--region-refresh-timer))
      (setq textui--region-refresh-timer nil
            textui--region-refresh-requests nil)
      (unless textui--refresh-timer
        (setq textui--refresh-timer
              (run-at-time 0 nil #'textui--run-requested-refresh buffer)))
      buffer)))

;;;###autoload
(defun textui-request-refresh-region (buffer id producer)
  "Request an asynchronous refresh of region ID in BUFFER.
PRODUCER has the same contract as in `textui-refresh-region'.  Repeated
pending requests for the same BUFFER and ID keep only the latest PRODUCER."
  (if (not (buffer-live-p buffer))
      nil
    (unless (functionp producer)
      (error "Region producer must be a function: %S" producer))
    (with-current-buffer buffer
      (unless (derived-mode-p 'textui-mode)
        (error "Not a TextUI buffer: %S" buffer))
      (let ((region (assq id textui--refresh-regions)))
        (unless region
          (error "Unknown refresh region: %S" id))
        (unless textui--refresh-timer
          (let ((request (assq id textui--region-refresh-requests)))
            (if request
                (setcdr request producer)
              (push (cons id producer) textui--region-refresh-requests))
            (unless textui--region-refresh-timer
              (setq textui--region-refresh-timer
                    (run-at-time 0 nil
                                 #'textui--run-requested-region-refreshes
                                 buffer))))))
      buffer)))

(defun textui--changed-plist-keys (before after)
  "Return top-level keys whose values differ between BEFORE and AFTER."
  (let (keys changed)
    (dolist (plist (list before after))
      (let ((cursor plist))
        (while cursor
          (cl-pushnew (car cursor) keys :test #'eq)
          (setq cursor (cddr cursor)))))
    (dolist (key (nreverse keys))
      (unless (and (eq (textui--plist-member-p before key)
                       (textui--plist-member-p after key))
                   (equal (plist-get before key) (plist-get after key)))
        (push key changed)))
    (nreverse changed)))

(defun textui--state-routes-for-keys (keys)
  "Return all active state routes covering KEYS, or nil if any is uncovered."
  (when (cl-every
         (lambda (key)
           (cl-some (lambda (route) (memq key (nth 1 route)))
                    textui--state-routes))
         keys)
    (cl-remove-if-not
     (lambda (route)
       (cl-some (lambda (key) (memq key (nth 1 route))) keys))
     textui--state-routes)))

(defun textui--request-state-routes (buffer keys)
  "Request BUFFER state routes covering changed KEYS and return non-nil.
Return nil without requesting anything when any key is not covered."
  (let ((routes (textui--state-routes-for-keys keys)))
    (when routes
      (dolist (route routes)
        (textui-request-refresh-region buffer (nth 0 route) (nth 2 route)))
      t)))

;;;###autoload
(cl-defun textui-update (buffer updater &key region producer)
  "Update live TextUI BUFFER state with UPDATER and request a refresh.
UPDATER receives `textui-state' and returns its replacement.  Without REGION,
changed plist keys use declared state routes when all are covered, otherwise
TextUI reconciles the complete frame.  With REGION, PRODUCER refreshes that
existing region directly."
  (if (not (buffer-live-p buffer))
      nil
    (unless (functionp updater)
      (error "State updater must be a function: %S" updater))
    (when (and producer (not region))
      (error "A region producer requires :region"))
    (when (and region (not (functionp producer)))
      (error "Region producer must be a function: %S" producer))
    (with-current-buffer buffer
      (unless (derived-mode-p 'textui-mode)
        (error "Not a TextUI buffer: %S" buffer))
      (when (and region (not (assq region textui--refresh-regions)))
        (error "Unknown refresh region: %S" region))
      (if region
          (progn
            (setq textui-state (funcall updater textui-state))
            (textui-request-refresh-region buffer region producer))
        (let* ((before-is-plist (textui--plist-p textui-state))
               (before (and before-is-plist (copy-sequence textui-state)))
               (next (funcall updater textui-state)))
          (setq textui-state next)
          (if (and before-is-plist (textui--plist-p next))
              (let ((keys (textui--changed-plist-keys before next)))
                (unless (and keys
                             (textui--request-state-routes buffer keys))
                  (textui-request-refresh buffer)))
            (textui-request-refresh buffer))))
      buffer)))

;;;###autoload
(defun textui-set-state (buffer key value)
  "Set plist KEY in live TextUI BUFFER state and request one refresh.
When VALUE is a function, call it with KEY's current value and store its
return value.  Use `textui-update' when state is not a property list or when a
bounded region refresh is required."
  (textui-update
   buffer
   (lambda (state)
     (unless (textui--plist-p state)
       (error "textui-set-state requires plist state: %S" state))
     (let ((next (if (functionp value)
                     (funcall value (plist-get state key))
                   value)))
       (plist-put (copy-sequence state) key next)))))

;;;###autoload
(defun textui-refresh-region (buffer id producer)
  "Replace refresh region ID in BUFFER using children from PRODUCER.
PRODUCER receives the region's current content width and returns a proper
list of children for the existing column flex container."
  (if (not (buffer-live-p buffer))
      nil
    (unless (functionp producer)
      (error "Region producer must be a function: %S" producer))
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
               (width (nth 2 region))
               (from-marker (nth 3 region))
               (to-marker (nth 4 region))
               (from (marker-position from-marker))
               (to (marker-position to-marker))
               (padding (or (plist-get element :padding) 0))
               (content-width
                (max 0 (- width (* 2 padding)
                          (if (plist-get element :border) 2 0))))
               (children (funcall producer content-width)))
          (unless (textui--proper-list-p children)
            (error "Region producer must return a proper list: %S" children))
          (let* ((replacement (plist-put (copy-sequence element)
                                         :children children))
                 (textui--collect-refresh-regions t)
                 (textui--rendered-regions nil)
                 ;; ponytail: local elements omit source-order IDs; mutable
                 ;; controls use :focus-id until regional ID namespaces exist.
                 (specs (textui--prepare-frame (list replacement) t))
                 (rendered (textui--render-specs specs width))
                 (regions (textui--collect-refresh-region-spans rendered)))
            (unless (and (= (length regions) 1)
                         (eq (caar regions) id))
              (error "Refresh region %S cannot contain another refresh region"
                     id))
            (let* ((trailing-newline
                    (and (> to from) (= (char-before to) ?\n)))
                   (replacement-text
                    (if trailing-newline (concat rendered "\n") rendered)))
              (textui--replace-refresh-region-template
               buffer region (car regions) replacement-text))))
      buffer))))

;;;###autoload
(defun textui-refresh (buffer)
  "Synchronously rebuild live TextUI BUFFER.
Return nil for a dead buffer and BUFFER after a successful refresh."
  (if (not (buffer-live-p buffer))
      nil
    (with-current-buffer buffer
      (unless (derived-mode-p 'textui-mode)
        (error "Not a TextUI buffer: %S" buffer))
      (when textui--refreshing
        (error "Reentrant TextUI refresh: %S" buffer))
      (dolist (timer (list textui--refresh-timer
                           textui--region-refresh-timer))
        (when (timerp timer)
          (cancel-timer timer)))
      (setq textui--refresh-timer nil
            textui--region-refresh-timer nil
            textui--region-refresh-requests nil)
      (let* ((textui--refreshing t)
             (frame (textui--render-current-frame buffer)))
        (textui--commit-full-frame
         buffer (nth 0 frame) (nth 1 frame) (nth 2 frame))
        (setq textui--state-routes (nth 4 frame))
        (textui--commit-effects (nth 3 frame)))
      buffer)))

;;;###autoload
(cl-defun textui-open (name render-function
                            &optional (initial-state nil state-supplied-p))
  "Display stable buffer NAME backed by RENDER-FUNCTION and return it.
When INITIAL-STATE is supplied, install it before the first refresh."
  (unless (stringp name)
    (error "TextUI buffer name must be a string: %S" name))
  (unless (functionp render-function)
    (error "TextUI render function must be a function: %S" render-function))
  (let ((existing (get-buffer name)))
    (when (and existing
               (with-current-buffer existing
                 (not (derived-mode-p 'textui-mode))))
      (error "A non-TextUI buffer already uses name %S" name))
    (let ((buffer (or existing (get-buffer-create name))))
      (with-current-buffer buffer
        (unless (derived-mode-p 'textui-mode)
          (textui-mode))
        (setq-local textui--render-function render-function)
        (when state-supplied-p
          (setq-local textui-state initial-state)))
      (unless (display-buffer buffer)
        (error "Could not display TextUI buffer %S" name))
      (textui-refresh buffer)
      buffer)))

(provide 'textui)
;;; textui.el ends here
