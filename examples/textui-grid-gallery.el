;;; textui-grid-gallery.el --- Responsive grid and widget gallery -*- lexical-binding: t; -*-

;;; Commentary:
;; Demonstrates TextUI's equal-track responsive `:grid' element with native
;; widget.el controls, package-owned widget types, and uneven cell heights.
;; Run: Emacs -Q -L . -l examples/textui-grid-gallery.el

;;; Code:

(require 'textui)

(defface textui-grid-gallery-field-face
  '((t :inherit widget-field :box nil :extend nil))
  "Field face used by the grid gallery."
  :group 'widget-faces)

(define-widget 'textui-grid-gallery-status 'item
  "Custom item with its own value renderer."
  :format "%v"
  :value-create
  (lambda (widget)
    (insert (format "<%s>" (widget-value widget)))))

(define-widget 'textui-grid-gallery-button 'push-button
  "Custom push button with a distinct text format."
  :format "{%[%v%]}")

(define-widget 'textui-grid-gallery-field 'editable-field
  "Custom single-line editable field."
  :format "%v"
  :size 10
  :value-face 'textui-grid-gallery-field-face)

(defvar textui-grid-gallery-count 0)
(defvar textui-grid-gallery-toggle t)
(defvar textui-grid-gallery-checkbox nil)
(defvar textui-grid-gallery-radio nil)
(defvar textui-grid-gallery-visible t)
(defvar textui-grid-gallery-name "Ada")
(defvar textui-grid-gallery-number 42)
(defvar textui-grid-gallery-color "red")
(defvar textui-grid-gallery-last "none")

(defconst textui-grid-gallery--maximum-columns 3)
(defconst textui-grid-gallery--minimum-cell-width 26)
(defconst textui-grid-gallery--gap 1)

(defun textui-grid-gallery--item (value)
  "Return a one-line item displaying VALUE."
  (list :type 'item :format "%v" :value (format "%s" value)))

(defun textui-grid-gallery--card (title children)
  "Return a gallery card named TITLE containing CHILDREN."
  (list :type :flex :direction :column :gap 1 :padding 1 :border t
        :layout (list :width textui-grid-gallery--minimum-cell-width
                      :min-width textui-grid-gallery--minimum-cell-width
                      :grow 1)
        :children (cons (textui-grid-gallery--item title) children)))

(defun textui-grid-gallery--grid (cells)
  "Arrange CELLS with the accepted equal-track grid rules."
  (list :type :grid
        :columns textui-grid-gallery--maximum-columns
        :min-column-width textui-grid-gallery--minimum-cell-width
        :gap textui-grid-gallery--gap
        :children cells))

(defun textui-grid-gallery--native-card ()
  "Return a card containing native one-line controls."
  (textui-grid-gallery--card
   "Native controls"
   (list
    (list :type 'link :tag "Link" :value "link"
          :layout (list :focus-id 'native-link)
          :action (lambda (&rest _)
                    (setq textui-grid-gallery-last "link")))
    (list :type 'toggle :format "%[%v%]"
          :value textui-grid-gallery-toggle :on "ON" :off "OFF"
          :layout (list :focus-id 'native-toggle)
          :notify (lambda (widget &rest _)
                    (setq textui-grid-gallery-toggle
                          (widget-value widget))))
    (list :type 'checkbox :value textui-grid-gallery-checkbox
          :layout (list :focus-id 'native-checkbox)
          :notify (lambda (widget &rest _)
                    (setq textui-grid-gallery-checkbox
                          (widget-value widget))))
    (list :type 'radio-button :value textui-grid-gallery-radio
          :layout (list :focus-id 'native-radio)
          :notify (lambda (widget &rest _)
                    (setq textui-grid-gallery-radio
                          (widget-value widget))))
    (list :type 'visibility :value textui-grid-gallery-visible
          :layout (list :focus-id 'native-visibility)
          :notify (lambda (widget &rest _)
                    (setq textui-grid-gallery-visible
                          (widget-value widget)))))))

(defun textui-grid-gallery--field-card ()
  "Return a card containing native editable controls."
  (textui-grid-gallery--card
   "Native fields"
   (list
    (list :type 'string :format "%v" :size 10
          :value textui-grid-gallery-name
          :value-face 'textui-grid-gallery-field-face
          :layout (list :focus-id 'native-string)
          :notify (lambda (widget &rest _)
                    (setq textui-grid-gallery-name
                          (widget-value widget))))
    (list :type 'integer :format "%v" :size 10
          :value textui-grid-gallery-number
          :value-face 'textui-grid-gallery-field-face
          :layout (list :focus-id 'native-integer)
          :notify (lambda (widget &rest _)
                    (setq textui-grid-gallery-number
                          (widget-value widget))))
    (list :type 'color :format "%v" :size 10
          :value textui-grid-gallery-color
          :value-face 'textui-grid-gallery-field-face
          :layout (list :focus-id 'native-color)
          :notify (lambda (widget &rest _)
                    (setq textui-grid-gallery-color
                          (widget-value widget)))))))

(defun textui-grid-gallery--custom-card ()
  "Return a card containing custom widget.el types."
  (textui-grid-gallery--card
   "Custom widgets"
   (list
    (list :type 'textui-grid-gallery-status
          :value (format "count %d" textui-grid-gallery-count))
    (list :type 'textui-grid-gallery-button :value "Increment"
          :layout (list :focus-id 'custom-button)
          :action (lambda (&rest _)
                    (setq textui-grid-gallery-count
                          (1+ textui-grid-gallery-count))))
    (list :type 'textui-grid-gallery-field
          :value textui-grid-gallery-name
          :layout (list :focus-id 'custom-field)
          :notify (lambda (widget &rest _)
                    (setq textui-grid-gallery-name
                          (widget-value widget)))))))

(defun textui-grid-gallery--uneven-cards ()
  "Return deliberately uneven cards for row-height testing."
  (list
   (textui-grid-gallery--card
    "Short" (list (textui-grid-gallery--item "one line")))
   (textui-grid-gallery--card
    "Tall"
    (list (textui-grid-gallery--item "line one")
          (textui-grid-gallery--item "line two")
          (textui-grid-gallery--item "line three")
          (textui-grid-gallery--item "line four")))
   (textui-grid-gallery--card
    "State"
    (list (textui-grid-gallery--item
           (format "Last: %s" textui-grid-gallery-last))))))

(defun textui-grid-gallery--frame (width)
  "Return the grid gallery frame for WIDTH."
  (list
   (list
    :type :flex :direction :column :gap 1
    :children
    (list
     (textui-grid-gallery--item
      (format "GRID GALLERY — width %d" width))
     (textui-grid-gallery--item
      "Resize | click | edit | q")
     (textui-grid-gallery--grid
      (append
       (list (textui-grid-gallery--native-card)
             (textui-grid-gallery--field-card)
             (textui-grid-gallery--custom-card))
       (textui-grid-gallery--uneven-cards)))))))

(defun textui-grid-gallery-open ()
  "Open the responsive grid and widget gallery."
  (interactive)
  (textui-open "*TextUI Grid Gallery*" #'textui-grid-gallery--frame))

(unless noninteractive
  (textui-grid-gallery-open)
  (set-frame-name "TextUI — grid gallery"))

(provide 'textui-grid-gallery)
;;; textui-grid-gallery.el ends here
