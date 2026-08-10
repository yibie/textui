;;; textui-widgets.el --- Semantic widget.el controls for TextUI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 chenyibin
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Package-Requires: ((emacs "29.1") (textui "0.2.0"))
;; Keywords: convenience, widgets

;;; Commentary:

;; This experimental optional library keeps control behavior in widget.el and
;; adds three predictable, text-only controls for TextUI layouts.

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

(defun textui-widgets--button-text (widget)
  "Return the rendered text for button WIDGET."
  (let ((label (or (widget-get widget :tag)
                   (widget-get widget :value)
                   "")))
    (concat "[ " (substitute-command-keys (format "%s" label)) " ]")))

(defun textui-widgets--button-value-create (widget)
  "Insert the rendered value for button WIDGET."
  (insert (textui-widgets--button-text widget)))

(defun textui-widgets--button-face-get (widget)
  "Return the semantic face selected by button WIDGET."
  (pcase (widget-get widget :variant)
    ('primary 'textui-button-primary-face)
    ('danger 'textui-button-danger-face)
    ('muted 'textui-button-muted-face)
    (_ 'textui-button-face)))

(defun textui-widgets--checkbox-text (widget)
  "Return the text-only presentation for checkbox WIDGET."
  (substitute-command-keys
   (widget-get widget (if (widget-get widget :value) :on :off))))

(defun textui-widgets--field-text (widget)
  "Return the fixed-width presentation for editable field WIDGET."
  (let ((value (widget-get widget :value))
        (size (widget-get widget :size)))
    (unless (stringp value)
      (error "TextUI field value must be a string: %S" value))
    (unless (and (integerp size) (> size 0))
      (error "TextUI field size must be a positive integer: %S" size))
    (concat value (make-string (max 0 (- size (length value))) ?\s))))

(define-widget 'textui-button 'push-button
  "A padded text button implemented by widget.el."
  :format "%[%v%]"
  :value-create #'textui-widgets--button-value-create
  :button-face-get #'textui-widgets--button-face-get
  :textui-measure #'textui-widgets--button-text)

(define-widget 'textui-checkbox 'checkbox
  "A text-only checkbox implemented by widget.el."
  :format "%[%v%]"
  :on "[x]"
  :off "[ ]"
  :on-glyph nil
  :off-glyph nil
  :button-face 'textui-checkbox-face
  :textui-measure #'textui-widgets--checkbox-text)

(define-widget 'textui-field 'editable-field
  "A fixed-width editable field implemented by widget.el."
  :format "%v"
  :size 16
  :value-face 'textui-field-face
  :textui-measure #'textui-widgets--field-text)

(provide 'textui-widgets)
;;; textui-widgets.el ends here
