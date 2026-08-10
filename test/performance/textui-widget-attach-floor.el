;;; textui-widget-attach-floor.el --- Native field attachment floor -*- lexical-binding: t; -*-

;;; Code:

(require 'benchmark)
(require 'cl-lib)
(require 'textui-widgets)

(defun textui-attach-floor--median (numbers)
  "Return the median of NUMBERS."
  (let* ((sorted (sort numbers #'<))
         (middle (/ (length sorted) 2)))
    (nth middle sorted)))

(defun textui-attach-floor--run (count samples)
  "Print attach and delete medians for COUNT fields over SAMPLES."
  (let (attach-times delete-times)
    (dotimes (_ samples)
      (let ((buffer (generate-new-buffer " *textui-attach-floor*"))
            fields)
        (unwind-protect
            (with-current-buffer buffer
              (dotimes (_ count)
                (insert "Ada             \n"))
              (garbage-collect)
              (let ((started (float-time)))
                (dotimes (index count)
                  (let* ((from (+ (point-min) (* index 17)))
                         (to (+ from 16))
                         (widget (widget-convert
                                  'textui-field :size 16 :value "Ada"))
                         (from-marker (copy-marker from t))
                         (to-marker (copy-marker to nil)))
                    (widget-put widget :from from-marker)
                    (widget-put widget :to to-marker)
                    (widget-put widget :delete #'widget-leave-text)
                    (widget-specify-field widget from to)
                    (push widget widget-field-list)
                    (push widget fields)))
                (push (* 1000.0 (- (float-time) started)) attach-times))
              (garbage-collect)
              (let ((started (float-time)))
                (setq widget-field-list nil
                      widget-field-new nil)
                (mapc #'widget-delete fields)
                (push (* 1000.0 (- (float-time) started)) delete-times)))
          (kill-buffer buffer))))
    (princ (format "attach-floor n=%-4d attach=%8.2f ms delete=%8.2f ms\n"
                   count
                   (textui-attach-floor--median attach-times)
                   (textui-attach-floor--median delete-times)))))

(dolist (count '(250 500 1000 2000))
  (textui-attach-floor--run count 5))

;;; textui-widget-attach-floor.el ends here
