;;; textui-widgets-test.el --- Tests for semantic TextUI widgets -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'textui-widgets)

(defvar textui-widgets-test--creates 0)

(define-widget 'textui-widgets-test-counted-item 'item
  "Widget used to distinguish measurement from creation."
  :format "%v"
  :value-create
  (lambda (_widget)
    (setq textui-widgets-test--creates
          (1+ textui-widgets-test--creates))
    (insert "fast"))
  :textui-measure (lambda (_widget) "fast"))

(define-widget 'textui-widgets-test-generic-item
  'textui-widgets-test-counted-item
  "The same widget without intrinsic measurement."
  :textui-measure nil)

(defun textui-widgets-test--actual-text (element)
  "Create ELEMENT with widget.el and return its plain text."
  (with-temp-buffer
    (apply #'widget-create (plist-get element :type)
           (textui--widget-args element))
    (buffer-substring-no-properties (point-min) (point-max))))

(ert-deftest textui-intrinsic-widget-measurement-skips-creation ()
  (let ((textui-widgets-test--creates 0)
        (textui--next-location-id 0))
    (should
     (equal (substring-no-properties
             (textui--measure-native
              '(:type textui-widgets-test-counted-item)))
            "fast"))
    (should (= textui-widgets-test--creates 0))))

(ert-deftest textui-generic-widget-measurement-still-creates-widget ()
  (let ((textui-widgets-test--creates 0)
        (textui--next-location-id 0))
    (textui--measure-native '(:type textui-widgets-test-generic-item))
    (should (= textui-widgets-test--creates 1))))

(ert-deftest textui-semantic-widget-measurements-match-widget-output ()
  (dolist (element
           '((:type textui-button :value "Save")
             (:type textui-button :value "Delete" :variant danger)
             (:type textui-checkbox :value t)
             (:type textui-checkbox :value nil)
             (:type textui-field :size 8 :value "Ada")))
    (let ((textui--next-location-id 0))
      (should
       (equal (substring-no-properties (textui--measure-native element))
              (textui-widgets-test--actual-text element))))))

(ert-deftest textui-semantic-widgets-retain-widget-el-behavior ()
  (with-temp-buffer
    (let ((checkbox (widget-create 'textui-checkbox :value nil)))
      (widget-setup)
      (widget-apply checkbox :action)
      (should (widget-value checkbox))))
  (with-temp-buffer
    (let ((field (widget-create 'textui-field :size 8 :value "Ada")))
      (widget-setup)
      (should (equal (widget-value field) "Ada")))))

(provide 'textui-widgets-test)
;;; textui-widgets-test.el ends here
