;;; textui-widget-cpu-profile.el --- Field-heavy CPU profile -*- lexical-binding: t; -*-

;;; Code:

(require 'profiler)
(require 'textui-widgets-benchmark)

(defun textui-cpu-profile--frame (count)
  "Return a frame containing COUNT attached fields."
  `((:type :flex :direction :column :gap 0
     :children
     ,(cl-loop repeat count
               collect '(:type textui-field :size 16 :value "Ada")))))

(defun textui-cpu-profile--buffer (frame)
  "Return a hidden TextUI buffer rendering FRAME at width 100."
  (let ((buffer (generate-new-buffer " *textui-cpu-profile*")))
    (with-current-buffer buffer
      (textui-mode)
      (setq-local textui--last-width 100
                  textui--render-function (lambda (_width) frame)))
    buffer))

(let* ((frame (textui-cpu-profile--frame 2000))
       (buffer (textui-cpu-profile--buffer frame)))
  (unwind-protect
      (with-current-buffer buffer
        (textui-refresh buffer)
        (profiler-start 'cpu)
        (dotimes (_ 5)
          (textui-refresh buffer))
        (profiler-stop)
        (profiler-report)
        (let ((report
               (cl-find-if
                (lambda (candidate)
                  (string-match-p "[Pp]rofiler.*[Rr]eport"
                                  (buffer-name candidate)))
                (buffer-list))))
          (unless report
            (error "Profiler report buffer was not created: %S"
                   (mapcar #'buffer-name (buffer-list))))
          (with-current-buffer report
            (goto-char (point-min))
            (profiler-report-move-to-entry)
            (profiler-report-expand-entry t)
            (princ (buffer-string)))))
    (when (profiler-running-p)
      (profiler-stop))
    (kill-buffer buffer)))

;;; textui-widget-cpu-profile.el ends here
