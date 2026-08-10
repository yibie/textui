;;; textui-widget-cpu-profile-mixed.el --- Mixed attached CPU profile -*- lexical-binding: t; -*-

;;; Code:

(require 'profiler)
(require 'textui-widgets-benchmark)

(let* ((frame (textui-widgets-benchmark--frame 'attached 1000))
       (buffer (generate-new-buffer " *textui-mixed-cpu-profile*")))
  (unwind-protect
      (with-current-buffer buffer
        (textui-mode)
        (setq-local textui--last-width 100
                    textui--render-function (lambda (_width) frame))
        (textui-refresh buffer)
        (profiler-start 'cpu)
        (dotimes (_ 10)
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
            (error "Profiler report buffer was not created"))
          (with-current-buffer report
            (goto-char (point-min))
            (profiler-report-move-to-entry)
            (profiler-report-expand-entry t)
            (princ (buffer-string)))))
    (when (profiler-running-p)
      (profiler-stop))
    (kill-buffer buffer)))

;;; textui-widget-cpu-profile-mixed.el ends here
