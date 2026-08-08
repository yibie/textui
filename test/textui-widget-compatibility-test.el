;;; textui-widget-compatibility-test.el --- Native widget display tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'textui)

(defun textui-widget-compatibility-test--cases ()
  "Return representative one-line widget.el elements and fallback widths."
  (list
   (cons '(:type item :format "%v" :value "Item") 4)
   (cons '(:type push-button :value "Push") 6)
   (cons `(:type link :tag "Link" :value "target" :action ,#'ignore) 6)
   (cons '(:type editable-field :format "%v" :size 8 :value "abc") 8)
   (cons '(:type toggle :format "%[%v%]" :value t :on "ON" :off "OFF") 2)
   (cons '(:type checkbox :value t) 3)
   (cons `(:type radio-button :value nil :notify ,#'ignore) 3)
   (cons '(:type visibility :value t) 4)
   (cons '(:type choice-item :format "%[%t%]" :tag "Choice" :value choice) 6)
   (cons '(:type const :format "%v" :value 42) 2)
   (cons '(:type string :format "%v" :size 8 :value "abc") 8)
   (cons '(:type regexp :format "%v" :size 8 :value "a+") 8)
   (cons '(:type file :format "%v" :size 10 :value "/tmp/a") 10)
   (cons '(:type directory :format "%v" :size 10 :value "/tmp/") 10)
   (cons '(:type symbol :format "%v" :size 8 :value alpha) 8)
   (cons '(:type integer :format "%v" :size 6 :value 42) 6)
   (cons '(:type natnum :format "%v" :size 6 :value 7) 6)
   (cons '(:type number :format "%v" :size 6 :value 3.5) 6)
   (cons '(:type float :format "%v" :size 6 :value 1.5) 6)
   (cons '(:type character :format "%v" :value 65) 1)
   (cons '(:type color :format "%v" :size 8 :value "red") 20)))

(ert-deftest textui-native-widget-fallback-width-matrix ()
  (let ((textui--next-location-id 0))
    (dolist (case (textui-widget-compatibility-test--cases))
      (let ((text (textui--measure-native (car case))))
        (should-not (string-match-p "\n" text))
        (should (= (string-width text) (cdr case)))))))

(ert-deftest textui-native-widget-matrix-materializes-in-one-buffer ()
  (let ((cases (textui-widget-compatibility-test--cases))
        (buffer (generate-new-buffer " *textui-widget-matrix-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 40
                      textui--render-function
                      (lambda (_width)
                        (list
                         (list :type :flex :direction :column :gap 0
                               :children (mapcar #'car cases)))))
          (textui-refresh buffer)
          (should (= (length textui--widgets) (length cases)))
          (should
           (equal
            (mapcar #'car
                    (sort (copy-sequence textui--widgets)
                          (lambda (left right)
                            (< (widget-get left :from)
                               (widget-get right :from)))))
            (mapcar (lambda (case) (plist-get (car case) :type)) cases))))
      (kill-buffer buffer))))

(provide 'textui-widget-compatibility-test)
;;; textui-widget-compatibility-test.el ends here
