;;; textui-widgets-experiment.el --- Semantic widget.el gallery -*- lexical-binding: t; -*-

;;; Commentary:
;; Run: emacs -Q -L . -l examples/textui-widgets-experiment.el

;;; Code:

(require 'textui-widgets)

(defvar textui-widgets-experiment-count 0)
(defvar textui-widgets-experiment-enabled t)
(defvar textui-widgets-experiment-name "Ada")

(defun textui-widgets-experiment--text (value)
  "Return an item displaying VALUE."
  (list :type 'item :format "%v" :value value))

(defun textui-widgets-experiment--frame (width)
  "Return the semantic widget gallery for WIDTH."
  `((:type :flex :direction :column :gap 1
     :children
     ((:type item :format "%v"
       :value ,(format "TEXTUI WIDGETS — width %d" width))
      (:type :flex :direction :row :gap 1
       :children
       ((:type textui-button :value "Save" :variant primary
         :action ,(lambda (&rest _)
                    (setq textui-widgets-experiment-count
                          (1+ textui-widgets-experiment-count))))
        (:type textui-button :value "Delete" :variant danger
         :action ,(lambda (&rest _)
                    (setq textui-widgets-experiment-count 0)))
        (:type textui-button :value "Later" :variant muted
         :action ignore)))
      (:type :flex :direction :row :gap 1
       :children
       ((:type textui-checkbox
         :value ,textui-widgets-experiment-enabled
         :notify ,(lambda (widget &rest _)
                    (setq textui-widgets-experiment-enabled
                          (widget-value widget))))
        (:type item :format "%v" :value "Live updates")))
      (:type :flex :direction :row :gap 1
       :children
       ((:type item :format "%v" :value "Name:")
        (:type textui-field :size 20
         :value ,textui-widgets-experiment-name
         :notify ,(lambda (widget &rest _)
                    (setq textui-widgets-experiment-name
                          (widget-value widget))))))
      (:type item :format "%v"
       :value ,(format "Save clicks: %d" textui-widgets-experiment-count))))))

(defun textui-widgets-experiment-open ()
  "Open the semantic widget experiment."
  (interactive)
  (textui-open "*TextUI Widgets Experiment*"
               #'textui-widgets-experiment--frame))

(unless noninteractive
  (textui-widgets-experiment-open)
  (set-frame-name "TextUI — semantic widgets"))

(provide 'textui-widgets-experiment)
;;; textui-widgets-experiment.el ends here
