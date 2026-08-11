;;; textui-btop-reconcile-benchmark.el --- Automatic/manual btop cost -*- lexical-binding: t; -*-

;;; Commentary:
;; Compare automatic frame reconciliation with the explicit region fast path.
;; Run from the repository root:
;; emacs -Q --batch -L . -L examples -L test/performance \
;;   -l test/performance/textui-btop-reconcile-benchmark.el

;;; Code:

(require 'cl-lib)
(require 'textui-btop-prototype)

(defun textui-btop-reconcile-benchmark--median (numbers)
  "Return the median of NUMBERS."
  (nth (/ (length numbers) 2) (sort (copy-sequence numbers) #'<)))

(defun textui-btop-reconcile-benchmark--percentile (numbers percentile)
  "Return PERCENTILE from NUMBERS using the nearest-rank method."
  (let* ((values (sort (copy-sequence numbers) #'<))
         (index (ceiling (* percentile (length values)))))
    (nth (max 0 (1- index)) values)))

(defun textui-btop-reconcile-benchmark--processes (count)
  "Return COUNT deterministic process rows."
  (cl-loop for index from 1 to count
           collect
           (list :pid (+ 1000 index)
                 :cpu (float (mod (* index 7) 61))
                 :mem (+ 20 (mod (* index 13) 700))
                 :user (if (cl-evenp index) "ada" "root")
                 :state (if (cl-evenp index) "S" "R")
                 :etime (format "00:%02d" index)
                 :command (format "/usr/bin/process-%02d" index)
                 :name (format "process-%02d" index))))

(defun textui-btop-reconcile-benchmark--buffer (width height rows)
  "Return a btop fixture buffer at WIDTH, HEIGHT, and ROWS."
  (let ((buffer (generate-new-buffer " *textui-btop-reconcile-benchmark*")))
    (with-current-buffer buffer
      (textui-mode)
      (setq-local textui-state
                  (plist-put (copy-tree textui-btop-prototype--initial-state)
                             :paused t)
                  textui-btop-prototype--processes
                  (textui-btop-reconcile-benchmark--processes rows)
                  textui-btop-prototype--cpu-history '(5 10 18 30 42 55 49 41)
                  textui-btop-prototype--download-history
                  '(100 400 200 900 1200 800 700 1100)
                  textui-btop-prototype--upload-history
                  '(80 150 100 300 550 400 350 500)
                  textui-btop-prototype--cpu-value 41.0
                  textui-btop-prototype--memory-total 137438953472
                  textui-btop-prototype--memory-used 58411555226
                  textui-btop-prototype--memory-free 79027398246
                  textui-btop-prototype--disk-total 1000000000000
                  textui-btop-prototype--disk-used 630000000000
                  textui-btop-prototype--disk-free 370000000000
                  textui-btop-prototype--download-total 240000000000
                  textui-btop-prototype--upload-total 39000000000
                  textui--last-width width
                  textui--render-function #'textui-btop-prototype--frame)
      (cl-letf (((symbol-function 'textui-btop-prototype--visible-height)
                 (lambda () height)))
        (textui-refresh buffer)))
    buffer))

(defun textui-btop-reconcile-benchmark--flush (buffer height)
  "Finish BUFFER's queued update at HEIGHT."
  (with-current-buffer buffer
    (cl-letf (((symbol-function 'textui-btop-prototype--visible-height)
               (lambda () height)))
      (when (timerp textui--region-refresh-timer)
        (cancel-timer textui--region-refresh-timer)
        (textui--run-requested-region-refreshes buffer))
      (when (timerp textui--refresh-timer)
        (cancel-timer textui--refresh-timer)
        (textui--run-requested-refresh buffer)))))

(defun textui-btop-reconcile-benchmark--run
    (mode width height rows samples)
  "Print SAMPLE MODE update times for WIDTH, HEIGHT, and ROWS."
  (let ((buffer
         (textui-btop-reconcile-benchmark--buffer width height rows))
        (index 0)
        times)
    (unwind-protect
        (dotimes (_ samples)
          (setq index (- 1 index))
          (garbage-collect)
          (let ((started (float-time)))
            (with-current-buffer buffer
              (let ((updater
                     (lambda (state)
                       (plist-put (copy-sequence state)
                                  :process-index index))))
                (pcase mode
                  ('automatic (textui-update buffer updater))
                  ('manual
                   (textui-update
                    buffer updater
                    :region 'btop-lower
                    :producer #'textui-btop-prototype--lower-elements))
                  (_ (error "Unknown reconciliation mode: %S" mode)))))
            (textui-btop-reconcile-benchmark--flush buffer height)
            (push (* 1000.0 (- (float-time) started)) times)))
      (kill-buffer buffer))
    (princ
     (format "btop mode=%s width=%d height=%d rows=%d samples=%d median=%.3fms p95=%.3fms\n"
             mode width height rows samples
             (textui-btop-reconcile-benchmark--median times)
             (textui-btop-reconcile-benchmark--percentile times 0.95)))))

(dolist (mode '(automatic manual))
  (dolist (rows '(0 50 1000))
    (dolist (width '(80 120 150))
      (textui-btop-reconcile-benchmark--run mode width 42 rows 31))))

(provide 'textui-btop-reconcile-benchmark)
;;; textui-btop-reconcile-benchmark.el ends here
