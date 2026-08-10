;;; textui-widget-phase-profile.el --- TextUI phase profiler -*- lexical-binding: t; -*-

;;; Code:

(require 'benchmark)
(require 'cl-lib)
(require 'textui-widgets-benchmark)

(defvar textui-profile--times nil)
(defvar textui-profile--advices nil)

(defun textui-profile--install (symbol)
  "Time calls to SYMBOL until its installed advice is removed."
  (let ((phase symbol)
        advice)
    (setq advice
          (lambda (function &rest arguments)
            (let ((started (float-time)) result)
              (unwind-protect
                  (setq result (apply function arguments))
                (puthash phase
                         (+ (gethash phase textui-profile--times 0.0)
                            (- (float-time) started))
                         textui-profile--times))
              result)))
    (push (cons symbol advice) textui-profile--advices)
    (advice-add symbol :around advice)))

(defun textui-profile--median (numbers)
  "Return the median of NUMBERS."
  (textui-widgets-benchmark--median numbers))

(defun textui-profile--frame (kind count)
  "Return a flat frame with COUNT controls of KIND."
  (let ((element
         (pcase kind
           ('button '(:type textui-button :value "Save"))
           ('checkbox '(:type textui-checkbox :value t))
           ('field '(:type textui-field :size 16 :value "Ada"))
           (_ (error "Unknown kind: %S" kind)))))
    `((:type :flex :direction :column :gap 0
       :children ,(cl-loop repeat count collect (copy-tree element))))))

(defun textui-profile--buffer (frame)
  "Return a hidden TextUI buffer rendering FRAME at width 100."
  (let ((buffer (generate-new-buffer " *textui-phase-profile*")))
    (with-current-buffer buffer
      (textui-mode)
      (setq-local textui--last-width 100
                  textui--render-function (lambda (_width) frame)))
    buffer))

(defun textui-profile--one (frame repeat)
  "Time one FRAME refresh, warming it first when REPEAT is non-nil."
  (let ((buffer (textui-profile--buffer frame))
        total phases)
    (unwind-protect
        (progn
          (when repeat
            (with-current-buffer buffer (textui-refresh buffer)))
          (setq textui-profile--times (make-hash-table :test #'eq))
          (garbage-collect)
          (let ((started (float-time)))
            (with-current-buffer buffer (textui-refresh buffer))
            (setq total (- (float-time) started)))
          (maphash (lambda (key value) (push (cons key value) phases))
                   textui-profile--times)
          (cons total phases))
      (kill-buffer buffer))))

(defun textui-profile--phase (result phase)
  "Return PHASE milliseconds recorded in RESULT."
  (* 1000.0 (or (cdr (assq phase (cdr result))) 0.0)))

(defun textui-profile--report (kind count repeat samples)
  "Print phase medians for KIND and COUNT over SAMPLES."
  (let (totals renders prepares layouts commits materializes setups)
    (dotimes (_ samples)
      (let ((result (textui-profile--one
                     (textui-profile--frame kind count) repeat)))
        (push (* 1000.0 (car result)) totals)
        (push (textui-profile--phase result 'textui--render-current-frame)
              renders)
        (push (textui-profile--phase result 'textui--prepare-frame) prepares)
        (push (textui-profile--phase result 'textui--render-specs) layouts)
        (push (textui-profile--phase result 'textui--commit-full-frame) commits)
        (push (textui-profile--phase
               result 'textui--materialize-placeholders)
              materializes)
        (push (textui-profile--phase result 'widget-setup) setups)))
    (princ
     (format "%s %-8s n=%-4d total=%8.2f render=%8.2f prepare=%8.2f layout=%8.2f commit=%8.2f materialize=%8.2f setup=%8.2f\n"
             (if repeat "repeat" "first ") kind count
             (textui-profile--median totals)
             (textui-profile--median renders)
             (textui-profile--median prepares)
             (textui-profile--median layouts)
             (textui-profile--median commits)
             (textui-profile--median materializes)
             (textui-profile--median setups)))))

(defun textui-profile--delete (kind count samples)
  "Print deletion median for KIND and COUNT over SAMPLES."
  (let (times)
    (dotimes (_ samples)
      (let* ((frame (textui-profile--frame kind count))
             (buffer (textui-profile--buffer frame)))
        (unwind-protect
            (with-current-buffer buffer
              (textui-refresh buffer)
              (garbage-collect)
              (let ((started (float-time)))
                (mapc #'widget-delete textui--widgets)
                (push (* 1000.0 (- (float-time) started)) times))
              (setq textui--widgets nil))
          (kill-buffer buffer))))
    (princ (format "delete %-8s n=%-4d %8.2f ms\n"
                   kind count (textui-profile--median times)))))

(dolist (symbol '(textui--render-current-frame
                  textui--prepare-frame
                  textui--render-specs
                  textui--commit-full-frame
                  textui--materialize-placeholders
                  widget-setup))
  (textui-profile--install symbol))

(unwind-protect
    (progn
      (dolist (kind '(button checkbox field))
        (textui-profile--report kind 1000 nil 5)
        (textui-profile--report kind 1000 t 5)
        (textui-profile--delete kind 1000 5))
      (dolist (count '(250 500 1000 2000))
        (textui-profile--report 'field count nil 3)
        (textui-profile--report 'field count t 3)))
  (dolist (entry textui-profile--advices)
    (advice-remove (car entry) (cdr entry))))

(provide 'textui-widget-phase-profile)
;;; textui-widget-phase-profile.el ends here
