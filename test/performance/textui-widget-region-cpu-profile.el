;;; textui-widget-region-cpu-profile.el --- Region refresh CPU profile -*- lexical-binding: t; -*-

;;; Code:

(require 'profiler)

(declare-function textui-region-benchmark--frame
                  "textui-widget-region-benchmark" (kind rows target))
(declare-function textui-region-benchmark--row
                  "textui-widget-region-benchmark" (kind row))

(defvar textui-region-benchmark-skip-run t)

(load
 (expand-file-name
  "textui-widget-region-benchmark.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil t)

(let* ((kind 'attached)
       (rows 1000)
       (target 500)
       (frame (textui-region-benchmark--frame kind rows target))
       (buffer (generate-new-buffer " *textui-region-cpu-profile*"))
       (version 0))
  (unwind-protect
      (with-current-buffer buffer
        (textui-mode)
        (setq-local textui--last-width 100
                    textui--render-function (lambda (_width) frame))
        (textui-refresh buffer)
        (profiler-start 'cpu)
        (dotimes (_ 50)
          (setq version (1+ version))
          (textui-refresh-region
           buffer 'target
           (lambda (_width)
             (list (textui-region-benchmark--row
                    kind (+ target (% version 2)))))))
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

;;; textui-widget-region-cpu-profile.el ends here
