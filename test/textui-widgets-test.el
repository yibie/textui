;;; textui-widgets-test.el --- Tests for semantic TextUI widgets -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'textui-widgets)

(defvar textui-widgets-test--creates 0)
(defvar textui-widgets-test--attaches 0)

(defun textui-widgets-test--attach-item (widget from to)
  "Attach WIDGET to existing text between FROM and TO."
  (setq textui-widgets-test--attaches
        (1+ textui-widgets-test--attaches))
  (widget-put widget :from (copy-marker from t))
  (widget-put widget :to (copy-marker to nil))
  (widget-put widget :delete #'widget-leave-text))

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

(define-widget 'textui-widgets-test-attached-item
  'textui-widgets-test-counted-item
  "Widget attached to the already rendered placeholder text."
  :textui-attach #'textui-widgets-test--attach-item)

(define-widget 'textui-widgets-test-field-button 'push-button
  "Existing package widget opting into TextUI's fast path with fields."
  :format "%[%v%]"
  :value-create
  (lambda (widget)
    (setq textui-widgets-test--creates
          (1+ textui-widgets-test--creates))
    (insert (format "[ %s ]" (widget-value widget))))
  :textui-measure #'textui-widgets-measure-button
  :textui-attach #'textui-widgets-attach-button)

(define-widget 'textui-widgets-test-field-checkbox 'checkbox
  "Existing checkbox opting into TextUI's fast path with fields."
  :format "%[%v%]"
  :on "[x]"
  :off "[ ]"
  :on-glyph nil
  :off-glyph nil
  :value-create
  (lambda (widget)
    (setq textui-widgets-test--creates
          (1+ textui-widgets-test--creates))
    (insert (widget-get widget (if (widget-value widget) :on :off))))
  :textui-measure #'textui-widgets-measure-checkbox
  :textui-attach #'textui-widgets-attach-checkbox)

(define-widget 'textui-widgets-test-field-input 'editable-field
  "Existing field opting into TextUI's fast path with fields."
  :format "%v"
  :size 8
  :value-create
  (lambda (widget)
    (setq textui-widgets-test--creates
          (1+ textui-widgets-test--creates))
    (widget-field-value-create widget))
  :textui-measure #'textui-widgets-measure-field
  :textui-attach #'textui-widgets-attach-field)

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

(ert-deftest textui-intrinsic-widget-measurement-skips-temporary-buffer ()
  (let ((temporary-buffers 0)
        (original (symbol-function 'generate-new-buffer))
        (textui--next-location-id 0))
    (cl-letf (((symbol-function 'generate-new-buffer)
               (lambda (&rest arguments)
                 (setq temporary-buffers (1+ temporary-buffers))
                 (apply original arguments))))
      (textui--measure-native '(:type textui-widgets-test-counted-item)))
    (should (= temporary-buffers 0))))

(ert-deftest textui-generic-widget-measurement-still-creates-widget ()
  (let ((textui-widgets-test--creates 0)
        (textui--next-location-id 0))
    (textui--measure-native '(:type textui-widgets-test-generic-item))
    (should (= textui-widgets-test--creates 1))))

(ert-deftest textui-attached-widget-reuses-placeholder-text ()
  (let ((textui-widgets-test--creates 0)
        (textui-widgets-test--attaches 0)
        (buffer (generate-new-buffer " *textui-attached-widget-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 20
                      textui--render-function
                      (lambda (_width)
                        '((:type textui-widgets-test-attached-item))))
          (textui-refresh buffer)
          (should (= textui-widgets-test--creates 0))
          (should (= textui-widgets-test--attaches 1))
          (should (equal (buffer-string) "fast"))
          (should (= (length textui--widgets) 1)))
      (kill-buffer buffer))))

(ert-deftest textui-custom-widget-fields-enable-button-fast-path ()
  (let ((textui-widgets-test--creates 0)
        (activations 0)
        (buffer (generate-new-buffer " *textui-field-button-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--last-width 20
           textui--render-function
           (lambda (_width)
             `((:type textui-widgets-test-field-button
                :value "Save"
                :action ,(lambda (&rest _)
                           (setq activations (1+ activations)))))))
          (textui-refresh buffer)
          (should (equal (buffer-string) "[ Save ]"))
          (should (= textui-widgets-test--creates 0))
          (widget-apply (car textui--widgets) :action)
          (should (= activations 1))
          (should (= textui-widgets-test--creates 0)))
      (kill-buffer buffer))))

(ert-deftest textui-custom-widget-fields-enable-checkbox-fast-path ()
  (let ((textui-widgets-test--creates 0)
        (checked nil)
        (buffer (generate-new-buffer " *textui-field-checkbox-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--last-width 20
           textui--render-function
           (lambda (_width)
             `((:type textui-widgets-test-field-checkbox
                :value ,checked
                :notify ,(lambda (widget &rest _)
                           (setq checked (widget-value widget)))))))
          (textui-refresh buffer)
          (should (equal (buffer-string) "[ ]"))
          (should (= textui-widgets-test--creates 0))
          (widget-apply (car textui--widgets) :action)
          (should checked)
          (should (equal (buffer-string) "[x]"))
          (should (= textui-widgets-test--creates 0)))
      (kill-buffer buffer))))

(ert-deftest textui-custom-widget-fields-enable-field-fast-path ()
  (let ((textui-widgets-test--creates 0)
        (buffer (generate-new-buffer " *textui-field-input-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--last-width 20
           textui--render-function
           (lambda (_width)
             '((:type textui-widgets-test-field-input
                :size 8 :value "Ada"))))
          (textui-refresh buffer)
          (should (equal (buffer-string) "Ada     "))
          (should (= textui-widgets-test--creates 0))
          (should (= (length widget-field-list) 1))
          (should (equal (widget-value (car textui--widgets)) "Ada")))
      (kill-buffer buffer))))

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

(ert-deftest textui-attached-field-retains-editing-across-full-refreshes ()
  (let ((buffer (generate-new-buffer " *textui-attached-field-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 20
                      textui--render-function
                      (lambda (_width)
                        '((:type textui-field :size 8 :value "Ada"))))
          (textui-refresh buffer)
          (should (= (length textui--widgets) 1))
          (should (= (length widget-field-list) 1))
          (should (equal (widget-value (car textui--widgets)) "Ada"))
          (widget-value-set (car textui--widgets) "Eve")
          (should (equal (widget-value (car textui--widgets)) "Eve"))
          (textui-refresh buffer)
          (should (= (length textui--widgets) 1))
          (should (= (length widget-field-list) 1))
          (should (equal (widget-value (car textui--widgets)) "Ada")))
      (kill-buffer buffer))))

(ert-deftest textui-full-commit-does-not-run-user-modification-hooks ()
  (let ((buffer (generate-new-buffer " *textui-commit-hooks-test*"))
        (changes 0))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 20
                      textui--render-function
                      (lambda (_width)
                        '((:type textui-field :size 8 :value "Ada"))))
          (textui-refresh buffer)
          (add-hook 'before-change-functions
                    (lambda (&rest _) (setq changes (1+ changes))) nil t)
          (textui-refresh buffer)
          (should (= changes 0))
          (goto-char (widget-get (car textui--widgets) :from))
          (delete-char 1)
          (should (= changes 1)))
      (kill-buffer buffer))))

(ert-deftest textui-semantic-buttons-attach-and-checkbox-still-toggles ()
  (let ((buffer (generate-new-buffer " *textui-attached-buttons-test*"))
        (checked nil))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--last-width 40
           textui--render-function
           (lambda (_width)
             `((:type :flex :direction :row :gap 1
                :children
                ((:type textui-button :value "Save" :action ignore)
                 (:type textui-checkbox :value ,checked
                  :notify ,(lambda (widget &rest _)
                             (setq checked (widget-value widget)))))))))
          (textui-refresh buffer)
          (should
           (cl-every (lambda (widget)
                       (eq (widget-get widget :delete) #'widget-leave-text))
                     textui--widgets))
          (let ((checkbox
                 (cl-find 'textui-checkbox textui--widgets
                          :key #'car)))
            (widget-apply checkbox :action)
            (should checked)
            (should (string-match-p "\[x\]" (buffer-string)))
            (should (= (length textui--widgets) 2))))
      (kill-buffer buffer))))

(ert-deftest textui-region-commit-does-not-run-user-modification-hooks ()
  (let ((buffer (generate-new-buffer " *textui-region-hooks-test*"))
        (changes 0))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--last-width 20
           textui--render-function
           (lambda (_width)
             '((:type :flex :direction :column :gap 0
                :layout (:refresh-id field)
                :children
                ((:type textui-field :size 8 :value "Ada"))))))
          (textui-refresh buffer)
          (add-hook 'before-change-functions
                    (lambda (&rest _) (setq changes (1+ changes))) nil t)
          (textui-refresh-region
           buffer 'field
           (lambda (_width)
             '((:type textui-field :size 8 :value "Eve"))))
          (should (= changes 0))
          (goto-char (widget-get (car textui--widgets) :from))
          (delete-char 1)
          (should (= changes 1)))
      (kill-buffer buffer))))

(provide 'textui-widgets-test)
;;; textui-widgets-test.el ends here
