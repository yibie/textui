;;; textui-widgets-benchmark.el --- Widget measurement benchmark -*- lexical-binding: t; -*-

;;; Code:

(require 'benchmark)
(require 'cl-lib)
(require 'textui-widgets)

(define-widget 'textui-widgets-benchmark-button 'textui-button
  "TextUI button measured through ordinary widget creation."
  :textui-measure nil
  :textui-attach nil)

(define-widget 'textui-widgets-benchmark-checkbox 'textui-checkbox
  "TextUI checkbox measured through ordinary widget creation."
  :textui-measure nil
  :textui-attach nil)

(define-widget 'textui-widgets-benchmark-field 'textui-field
  "TextUI field measured through ordinary widget creation."
  :textui-measure nil
  :textui-attach nil)

(define-widget 'textui-widgets-benchmark-measured-field 'textui-field
  "TextUI field with intrinsic measurement but ordinary creation."
  :textui-attach nil)

(define-widget 'textui-widgets-benchmark-measured-button 'textui-button
  "TextUI button with intrinsic measurement but ordinary creation."
  :textui-attach nil)

(define-widget 'textui-widgets-benchmark-measured-checkbox 'textui-checkbox
  "TextUI checkbox with intrinsic measurement but ordinary creation."
  :textui-attach nil)

(defun textui-widgets-benchmark--controls (kind row)
  "Return three comparable controls of KIND for ROW."
  (let ((label (format "Save %03d" row))
        (value (format "name-%03d" row)))
    (pcase kind
      ('native
       `((:type push-button :value ,(concat " " label " "))
         (:type checkbox :value ,(zerop (% row 2))
          :on "[x]" :off "[ ]" :on-glyph nil :off-glyph nil)
         (:type editable-field :format "%v" :size 16 :value ,value)))
      ('semantic
       `((:type textui-widgets-benchmark-button :value ,label)
         (:type textui-widgets-benchmark-checkbox
          :value ,(zerop (% row 2)))
         (:type textui-widgets-benchmark-field :size 16 :value ,value)))
      ('intrinsic
       `((:type textui-widgets-benchmark-measured-button :value ,label)
         (:type textui-widgets-benchmark-measured-checkbox
          :value ,(zerop (% row 2)))
         (:type textui-widgets-benchmark-measured-field
          :size 16 :value ,value)))
      ('attached
       `((:type textui-button :value ,label)
         (:type textui-checkbox :value ,(zerop (% row 2)))
         (:type textui-field :size 16 :value ,value)))
      (_ (error "Unknown benchmark kind: %S" kind)))))

(defun textui-widgets-benchmark--frame (kind rows)
  "Return a TextUI frame containing ROWS groups of KIND controls."
  `((:type :flex :direction :column :gap 0
     :children
     ,(cl-loop for row below rows
               collect
               `(:type :flex :direction :row :gap 2
                 :children
                 ,(textui-widgets-benchmark--controls kind row))))))

(defun textui-widgets-benchmark--median (numbers)
  "Return the median of NUMBERS."
  (let* ((sorted (sort (copy-sequence numbers) #'<))
         (length (length sorted))
         (middle (/ length 2)))
    (if (= (% length 2) 1)
        (nth middle sorted)
      (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2.0))))

(defun textui-widgets-benchmark--run-kind (kind rows samples)
  "Benchmark render and full refresh of KIND with ROWS for SAMPLES."
  (let ((buffer (generate-new-buffer
                 (format " *textui-widgets-%s-benchmark*" kind)))
        (frame (textui-widgets-benchmark--frame kind rows))
        render-times
        refresh-times)
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 100
                      textui--render-function
                      (lambda (_width) frame))
          (textui-refresh buffer)
          (dotimes (_ samples)
            (garbage-collect)
            (push (* 1000.0
                     (car (benchmark-run
                            1 (textui--render-frame frame 100))))
                  render-times)
            (garbage-collect)
            (push (* 1000.0
                     (car (benchmark-run 1 (textui-refresh buffer))))
                  refresh-times))
          (list (textui-widgets-benchmark--median render-times)
                (textui-widgets-benchmark--median refresh-times)))
      (kill-buffer buffer))))

;;;###autoload
(defun textui-widgets-benchmark (&optional rows samples)
  "Print full-refresh medians for ROWS groups over SAMPLES runs."
  (interactive)
  (let ((rows (or rows 100))
        (samples (or samples 7)))
    (princ (format "TextUI widgets: %d controls, median of %d runs\n"
                   (* rows 3) samples))
    (princ "kind       render+layout  full refresh\n")
    (dolist (kind '(native semantic intrinsic attached))
      (let ((result
             (textui-widgets-benchmark--run-kind kind rows samples)))
        (princ
         (format "%-10s %10.3f ms %10.3f ms\n"
                 kind (nth 0 result) (nth 1 result)))))))

(provide 'textui-widgets-benchmark)
;;; textui-widgets-benchmark.el ends here
