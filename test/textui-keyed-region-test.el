;;; textui-keyed-region-test.el --- Tests for keyed TextUI regions -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'textui-keyed-region)

(defun textui-keyed-region-test--entries (&rest values)
  "Return keyed text entries for VALUES."
  (mapcar (lambda (value)
            (list value (list :type :text :value value :wrap 'greedy)))
          values))

(defun textui-keyed-region-test--lines (buffer)
  "Return trimmed non-empty lines from BUFFER."
  (with-current-buffer buffer
    (seq-filter
     (lambda (line) (not (string-empty-p line)))
     (mapcar #'string-trim-right (split-string (buffer-string) "\n")))))

(ert-deftest textui-keyed-region-renders-only-new-sliding-window-items ()
  (let ((buffer (generate-new-buffer " *textui-keyed-slide*"))
        (rendered 0))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 24
                      textui--render-function
                      (lambda (_width)
                        '((:type :flex :direction :column :gap 0
                           :layout (:refresh-id rows)
                           :children
                           ((:type :text :value "seed" :wrap greedy))))))
          (textui-refresh buffer)
          (let ((original (symbol-function
                           'textui-keyed-region--render-item)))
            (cl-letf (((symbol-function 'textui-keyed-region--render-item)
                       (lambda (element width)
                         (setq rendered (1+ rendered))
                         (funcall original element width))))
              (textui-reconcile-keyed-region
               buffer 'rows
               (lambda (_width)
                 (textui-keyed-region-test--entries "0" "1" "2" "3")))
              (should (= rendered 4))
              (setq rendered 0)
              (textui-reconcile-keyed-region
               buffer 'rows
               (lambda (_width)
                 (textui-keyed-region-test--entries "2" "3" "4" "5")))
              (should (= rendered 2))))
          (should (equal (textui-keyed-region-test--lines buffer)
                         '("2" "3" "4" "5"))))
      (kill-buffer buffer))))

(ert-deftest textui-keyed-region-preserves-unchanged-widgets-and-gap ()
  (let ((buffer (generate-new-buffer " *textui-keyed-widget*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 24
                      textui--render-function
                      (lambda (_width)
                        '((:type :flex :direction :column :gap 1
                           :layout (:refresh-id rows)
                           :children
                           ((:type item :format "%v" :value "seed"))))))
          (textui-refresh buffer)
          (textui-reconcile-keyed-region
           buffer 'rows
           (lambda (_width)
             '((a (:type push-button :value "A" :action ignore))
               (b (:type push-button :value "B" :action ignore)))))
          (let ((widget-a (car textui--widgets)))
            (textui-reconcile-keyed-region
             buffer 'rows
             (lambda (_width)
               '((b (:type push-button :value "B" :action ignore))
                 (c (:type push-button :value "C" :action ignore)))))
            (should-not (memq widget-a textui--widgets))
            (should (= (length textui--widgets) 2)))
          (should (equal (textui-keyed-region-test--lines buffer)
                         '("[B]" "[C]")))
          (goto-char (point-min))
          (search-forward "[B]")
          (should (= (forward-line 1) 0))
          (should (looking-at-p "[[:space:]]*$")))
      (kill-buffer buffer))))

(ert-deftest textui-keyed-region-rejects-duplicates-before-changing-buffer ()
  (let ((buffer (generate-new-buffer " *textui-keyed-invalid*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 24
                      textui--render-function
                      (lambda (_width)
                        '((:type :flex :direction :column :gap 0
                           :layout (:refresh-id rows)
                           :children
                           ((:type item :format "%v" :value "old"))))))
          (textui-refresh buffer)
          (let ((before (buffer-string)))
            (should-error
             (textui-reconcile-keyed-region
              buffer 'rows
              (lambda (_width)
                '((same (:type item :format "%v" :value "one"))
                  (same (:type item :format "%v" :value "two"))))))
            (should (equal before (buffer-string)))))
      (kill-buffer buffer))))

(ert-deftest textui-keyed-region-empty-window-remains-a-complete-line ()
  (let ((buffer (generate-new-buffer " *textui-keyed-empty*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 24
                      textui--render-function
                      (lambda (_width)
                        '((:type :flex :direction :column :gap 0
                           :layout (:refresh-id rows)
                           :children
                           ((:type item :format "%v" :value "old"))))))
          (textui-refresh buffer)
          (textui-reconcile-keyed-region buffer 'rows (lambda (_width) nil))
          (should (= (line-number-at-pos (point-max)) 1))
          (should (string-blank-p (buffer-string)))
          (textui-reconcile-keyed-region
           buffer 'rows
           (lambda (_width)
             (textui-keyed-region-test--entries "new")))
          (should (equal (textui-keyed-region-test--lines buffer) '("new"))))
      (kill-buffer buffer))))

(ert-deftest textui-keyed-region-rejects-nested-refresh-regions ()
  (let ((buffer (generate-new-buffer " *textui-keyed-nested*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 24
                      textui--render-function
                      (lambda (_width)
                        '((:type :flex :direction :column :gap 0
                           :layout (:refresh-id rows)
                           :children
                           ((:type item :format "%v" :value "old"))))))
          (textui-refresh buffer)
          (let ((before (buffer-string)))
            (should-error
             (textui-reconcile-keyed-region
              buffer 'rows
              (lambda (_width)
                '((nested
                   (:type :flex :direction :column :gap 0
                    :layout (:refresh-id child)
                    :children
                    ((:type item :format "%v" :value "bad"))))))))
            (should (equal before (buffer-string)))))
      (kill-buffer buffer))))

(ert-deftest textui-keyed-region-invalidates-after-a-full-refresh ()
  (let ((buffer (generate-new-buffer " *textui-keyed-invalidate*"))
        (rendered 0))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 24
                      textui--render-function
                      (lambda (_width)
                        '((:type :flex :direction :column :gap 0
                           :layout (:refresh-id rows)
                           :children
                           ((:type item :format "%v" :value "frame"))))))
          (textui-refresh buffer)
          (textui-reconcile-keyed-region
           buffer 'rows
           (lambda (_width)
             (textui-keyed-region-test--entries "a" "b")))
          (textui-refresh buffer)
          (let ((original (symbol-function
                           'textui-keyed-region--render-item)))
            (cl-letf (((symbol-function 'textui-keyed-region--render-item)
                       (lambda (element width)
                         (setq rendered (1+ rendered))
                         (funcall original element width))))
              (textui-reconcile-keyed-region
               buffer 'rows
               (lambda (_width)
                 (textui-keyed-region-test--entries "a" "b")))
              (should (= rendered 2)))))
      (kill-buffer buffer))))

(provide 'textui-keyed-region-test)
;;; textui-keyed-region-test.el ends here
