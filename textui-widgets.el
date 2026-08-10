;;; textui-widgets.el --- Semantic widget.el controls for TextUI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 chenyibin
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Package-Requires: ((emacs "29.1") (textui "0.3.0"))
;; Keywords: convenience, widgets

;;; Commentary:

;; This optional library provides reusable implementations of TextUI's
;; `:textui-measure' and `:textui-attach' widget type properties.  Existing
;; package widgets may opt into the fast path by adding the matching functions
;; to their ordinary `define-widget' definitions.  The three `textui-*' widget
;; types below are convenience presets, not a separate control system.

;;; Code:

(require 'textui)

(defface textui-button-face
  '((t (:inherit widget-button)))
  "Default TextUI button face."
  :group 'widgets)

(defface textui-button-primary-face
  '((t (:inherit success :weight bold)))
  "Primary TextUI button face."
  :group 'widgets)

(defface textui-button-danger-face
  '((t (:inherit error :weight bold)))
  "Danger TextUI button face."
  :group 'widgets)

(defface textui-button-muted-face
  '((t (:inherit shadow)))
  "Muted TextUI button face."
  :group 'widgets)

(defface textui-checkbox-face
  '((t (:inherit widget-button)))
  "Text-only TextUI checkbox face."
  :group 'widgets)

(defface textui-field-face
  '((t (:inherit widget-field)))
  "TextUI editable field face."
  :group 'widgets)

(defun textui-widgets-measure-button (widget)
  "Return WIDGET's padded, single-line button presentation.
The result must equal WIDGET's actual presentation outside TextUI."
  (let ((label (or (widget-get widget :tag)
                   (widget-get widget :value)
                   "")))
    (concat "[ " (format "%s" label) " ]")))

(defun textui-widgets--button-value-create (widget)
  "Insert the rendered value for button WIDGET."
  (insert (textui-widgets-measure-button widget)))

(defun textui-widgets--button-face-get (widget)
  "Return the semantic face selected by button WIDGET."
  (pcase (widget-get widget :variant)
    ('primary 'textui-button-primary-face)
    ('danger 'textui-button-danger-face)
    ('muted 'textui-button-muted-face)
    (_ 'textui-button-face)))

(defun textui-widgets-measure-checkbox (widget)
  "Return WIDGET's text-only checkbox presentation as a string.
The result uses WIDGET's `:on' or `:off' property."
  (widget-get widget (if (widget-get widget :value) :on :off)))

(defun textui-widgets-attach-button (widget from to)
  "Attach button WIDGET to existing TextUI text from FROM to TO.
The text must equal the result of WIDGET's `:textui-measure' function."
  (widget-put widget :from (copy-marker from t))
  (widget-put widget :to (copy-marker to nil))
  (widget-put widget :delete #'widget-leave-text)
  (widget-put widget :textui-attached t)
  (widget-specify-button widget from to))

(defun textui-widgets--checkbox-value-set (widget value)
  "Set checkbox WIDGET to VALUE, preserving attached TextUI text."
  (if (not (widget-get widget :textui-attached))
      (widget-default-value-set widget value)
    (let* ((from-marker (widget-get widget :from))
           (to-marker (widget-get widget :to))
           (from (marker-position from-marker))
           (to (marker-position to-marker))
           (overlay (widget-get widget :button-overlay))
           (inhibit-read-only t)
           (inhibit-modification-hooks t))
      (when overlay
        (delete-overlay overlay))
      (widget-put widget :value value)
      (let ((text (textui-widgets-measure-checkbox widget)))
        (save-excursion
          (delete-region from to)
          (goto-char from)
          (insert text))
        (set-marker from-marker from)
        (set-marker to-marker (+ from (length text))))
      (widget-specify-button widget from-marker to-marker))))

(defun textui-widgets-attach-checkbox (widget from to)
  "Attach checkbox WIDGET to existing TextUI text from FROM to TO.
Install the value setter needed to update attached text in place."
  (widget-put widget :value-set #'textui-widgets--checkbox-value-set)
  (textui-widgets-attach-button widget from to))

(defun textui-widgets-measure-field (widget)
  "Return WIDGET's fixed-width editable-field presentation as a string.
WIDGET must have a string `:value' and a positive integer `:size'."
  (let ((value (widget-get widget :value))
        (size (widget-get widget :size)))
    (unless (stringp value)
      (error "TextUI field value must be a string: %S" value))
    (unless (and (integerp size) (> size 0))
      (error "TextUI field size must be a positive integer: %S" size))
    (concat value (make-string (max 0 (- size (length value))) ?\s))))

(defun textui-widgets--delete-attached-field (widget)
  "Detach an attached field WIDGET without deleting its text."
  (setq widget-field-list (delq widget widget-field-list)
        widget-field-new (delq widget widget-field-new))
  (widget-leave-text widget))

(defun textui-widgets-attach-field (widget from to)
  "Attach editable field WIDGET to existing TextUI text from FROM to TO.
Register WIDGET with widget.el's ordinary editable-field machinery."
  (let ((from-marker (copy-marker from t))
        (to-marker (copy-marker to nil)))
    (widget-put widget :from from-marker)
    (widget-put widget :to to-marker)
    (widget-put widget :delete #'textui-widgets--delete-attached-field)
    (widget-specify-field widget from to)
    (push widget widget-field-list)))

(define-widget 'textui-button 'push-button
  "A padded text button implemented by widget.el."
  :format "%[%v%]"
  :value-create #'textui-widgets--button-value-create
  :button-face-get #'textui-widgets--button-face-get
  :textui-measure #'textui-widgets-measure-button
  :textui-attach #'textui-widgets-attach-button)

(define-widget 'textui-checkbox 'checkbox
  "A text-only checkbox implemented by widget.el."
  :format "%[%v%]"
  :on "[x]"
  :off "[ ]"
  :on-glyph nil
  :off-glyph nil
  :button-face 'textui-checkbox-face
  :value-set #'textui-widgets--checkbox-value-set
  :textui-measure #'textui-widgets-measure-checkbox
  :textui-attach #'textui-widgets-attach-checkbox)

(define-widget 'textui-field 'editable-field
  "A fixed-width editable field implemented by widget.el."
  :format "%v"
  :size 16
  :value-face 'textui-field-face
  :textui-measure #'textui-widgets-measure-field
  :textui-attach #'textui-widgets-attach-field)

(provide 'textui-widgets)
;;; textui-widgets.el ends here
