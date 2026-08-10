;;; textui-layout-shape-profile.el --- Nested versus flat layout profile -*- lexical-binding: t; -*-

;;; Code:

(require 'benchmark)
(require 'cl-lib)
(require 'textui-widgets-benchmark)

(defun textui-layout-profile--median (numbers)
  "Return the median of NUMBERS."
  (textui-widgets-benchmark--median numbers))

(defun textui-layout-profile--flat-frame (rows)
  "Return one flat column containing ROWS groups of controls."
  `((:type :flex :direction :column :gap 0
     :children
     ,(cl-loop for row below rows
               append (textui-widgets-benchmark--controls 'attached row)))))

(defun textui-layout-profile--run (name frame samples)
  "Print phase medians for NAME and FRAME over SAMPLES."
  (let (prepare-times layout-times total-times)
    (dotimes (_ samples)
      (garbage-collect)
      (let ((started (float-time)) specs)
        (setq specs (textui--prepare-frame frame))
        (push (* 1000.0 (- (float-time) started)) prepare-times)
        (setq started (float-time))
        (textui--render-specs specs 100)
        (push (* 1000.0 (- (float-time) started)) layout-times))
      (garbage-collect)
      (let ((started (float-time)))
        (textui--render-frame frame 100)
        (push (* 1000.0 (- (float-time) started)) total-times)))
    (princ
     (format "%-7s prepare=%8.3f ms layout=%8.3f ms total=%8.3f ms\n"
             name
             (textui-layout-profile--median prepare-times)
             (textui-layout-profile--median layout-times)
             (textui-layout-profile--median total-times)))))

(textui-layout-profile--run
 'nested (textui-widgets-benchmark--frame 'attached 1000) 11)
(textui-layout-profile--run
 'flat (textui-layout-profile--flat-frame 1000) 11)

;;; textui-layout-shape-profile.el ends here
