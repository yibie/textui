;;; textui-widget-region-benchmark.el --- Attached region refresh benchmark -*- lexical-binding: t; -*-

;;; Code:

(require 'benchmark)
(require 'cl-lib)
(require 'textui-widgets-benchmark)

(defun textui-region-benchmark--row (kind row)
  "Return one ROW containing controls of KIND."
  `(:type :flex :direction :row :gap 2
    :children ,(textui-widgets-benchmark--controls kind row)))

(defun textui-region-benchmark--frame (kind rows target)
  "Return ROWS groups of KIND with TARGET marked for region refresh."
  `((:type :flex :direction :column :gap 0
     :children
     ,(cl-loop for row below rows
               collect
               (if (= row target)
                   `(:type :flex :direction :column :gap 0
                     :layout (:refresh-id target)
                     :children (,(textui-region-benchmark--row kind row)))
                 (textui-region-benchmark--row kind row))))))

(defun textui-region-benchmark--run (kind rows target samples)
  "Print region refresh median for KIND at TARGET over SAMPLES."
  (let* ((frame (textui-region-benchmark--frame kind rows target))
         (buffer (generate-new-buffer " *textui-region-benchmark*"))
         (version 0)
         times)
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 100
                      textui--render-function (lambda (_width) frame))
          (textui-refresh buffer)
          (dotimes (_ samples)
            (setq version (1+ version))
            (garbage-collect)
            (let ((started (float-time)))
              (textui-refresh-region
               buffer 'target
               (lambda (_width)
                 (list (textui-region-benchmark--row
                        kind (+ target (% version 2))))))
              (push (* 1000.0 (- (float-time) started)) times)))
          (princ
           (format "region %-9s row=%-4d total=%d changed=3 median=%7.3f ms\n"
                   kind target (* rows 3)
                   (textui-widgets-benchmark--median times))))
      (kill-buffer buffer))))

(unless (bound-and-true-p textui-region-benchmark-skip-run)
  (dolist (kind '(semantic attached))
    (dolist (target '(0 500 999))
      (textui-region-benchmark--run kind 1000 target 31))))

(provide 'textui-widget-region-benchmark)
;;; textui-widget-region-benchmark.el ends here
