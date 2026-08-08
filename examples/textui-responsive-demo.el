;;; textui-responsive-demo.el --- Responsive TextUI demo -*- lexical-binding: t; -*-

;;; Commentary:
;; Run this file and resize the frame to exercise responsive flex layout.

;;; Code:

(require 'textui)

(defvar textui-responsive-demo-count 0)
(defvar textui-responsive-demo-name "Ada")

(defun textui-responsive-demo--card (title children)
  "Return one responsive card named TITLE containing CHILDREN."
  `(:type :flex :direction :column :gap 0 :padding 1 :border t
    :layout (:width 22 :min-width 16 :grow 1)
    :children
    ((:type item :format "%v" :value ,title)
     ,@children)))

(defun textui-responsive-demo--frame (width)
  "Return the demo frame for available WIDTH."
  (list
   `(:type :flex :direction :row :gap 1
     :children
     (,(textui-responsive-demo--card
        "Counter"
        `((:type item :format "%v"
           :value ,(format "Value: %d" textui-responsive-demo-count))
          (:type push-button :value "Increment"
           :layout (:focus-id increment)
           :action ,(lambda (&rest _)
                      (setq textui-responsive-demo-count
                            (1+ textui-responsive-demo-count))))))
      ,(textui-responsive-demo--card
        "Editor"
        `((:type editable-field :format "%v" :size 12
           :value ,textui-responsive-demo-name
           :layout (:focus-id name)
           :notify ,(lambda (widget &rest _)
                      (setq textui-responsive-demo-name
                            (widget-value widget))))
          (:type push-button :value "Apply"
           :layout (:focus-id apply)
           :action ,(lambda (&rest _) nil))))
      ,(textui-responsive-demo--card
        "Layout"
        `((:type item :format "%v" :value ,(format "Width: %d" width))
          (:type item :format "%v" :value "Resize frame")))
      ,(textui-responsive-demo--card
        "Pixel-justified text"
        '((:type :text
           :value "TextUI gives Knuth–Plass the card's inner pixel width, then stretches display-only spacing without changing the Flex allocation.")))))))

(let ((buffer (textui-open "*TextUI Responsive Demo*"
                           #'textui-responsive-demo--frame)))
  (unless noninteractive
    (with-current-buffer buffer
      (goto-char (point-min))
      (widget-forward 1))
    (set-frame-name "TextUI — responsive flex demo")))

(provide 'textui-responsive-demo)
;;; textui-responsive-demo.el ends here
