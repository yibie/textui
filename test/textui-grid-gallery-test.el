;;; textui-grid-gallery-test.el --- Tests for the grid gallery -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'textui-grid-gallery)

(ert-deftest textui-grid-gallery-responsive-column-matrix ()
  (dolist (case '((82 . 3) (60 . 2) (32 . 1)))
    (let* ((width (car case))
           (expected (cdr case))
           (lines
            (split-string
             (textui--render-frame (textui-grid-gallery--frame width) width)
             "\n"))
           (cards-per-row
            (apply #'max
                   (mapcar (lambda (line) (cl-count ?┌ line)) lines))))
      (should (= cards-per-row expected))
      (dolist (line lines)
        (should (<= (string-width line) width))))))

(ert-deftest textui-grid-gallery-materializes-native-and-custom-widgets ()
  (let ((textui-grid-gallery-count 0)
        (width 82)
        (buffer (generate-new-buffer " *textui-grid-gallery-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--render-function #'textui-grid-gallery--frame)
          (cl-letf (((symbol-function 'textui--visible-width)
                     (lambda (_buffer) width)))
            (textui-refresh buffer)
            (let ((types (mapcar #'car textui--widgets)))
              (dolist (type '(link toggle checkbox radio-button visibility
                              string integer color
                              textui-grid-gallery-status
                              textui-grid-gallery-button
                              textui-grid-gallery-field))
                (should (memq type types))))
            (let ((button
                   (cl-find-if
                    (lambda (widget)
                      (eq (car widget) 'textui-grid-gallery-button))
                    textui--widgets)))
              (widget-apply-action button)
              (should (= textui-grid-gallery-count 1))
              (should (string-match-p "<count 1>" (buffer-string))))))
      (kill-buffer buffer))))

(provide 'textui-grid-gallery-test)
;;; textui-grid-gallery-test.el ends here
