;;; textui-test.el --- Tests for textui -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'textui)

(define-widget 'textui-test-custom-button 'push-button
  "Custom button used to verify direct widget.el compatibility."
  :format "<%[%v%]>")

(define-widget 'textui-test-custom-checkbox 'checkbox
  "Custom checkbox used to verify inherited glyph rendering.")

(define-widget 'textui-test-custom-status 'item
  "Custom item used to verify a package-owned value renderer."
  :format "%v"
  :value-create
  (lambda (widget)
    (insert (format "<%s>" (widget-value widget)))))

(define-widget 'textui-test-custom-field 'editable-field
  "Custom field used to verify inherited editing behavior."
  :format "%v"
  :size 6)

(defun textui-test--spec (kind start minimum &optional grow)
  "Return a test spec with KIND, START, MINIMUM, and optional GROW."
  (list :kind kind :start start :minimum minimum :grow (or grow 0)))

(defun textui-test--trimmed-lines (string)
  "Return STRING split into lines with trailing spaces removed."
  (mapcar (lambda (line) (replace-regexp-in-string " +\\'" "" line))
          (split-string string "\n")))

(ert-deftest textui-row-keeps-natural-widths-without-grow ()
  (let* ((children (list (textui-test--spec :native 10 10)
                         (textui-test--spec :native 5 5)))
         (rows (textui--partition-row children 20 1)))
    (should (= (length rows) 1))
    (should (equal (textui--allocate-row (car rows) 20 1) '(10 5)))))

(ert-deftest textui-row-distributes-grow-proportionally ()
  (let ((row (list (textui-test--spec :native 10 10 1)
                   (textui-test--spec :native 5 5 2))))
    (should (equal (textui--allocate-row row 22 1) '(12 9)))))

(ert-deftest textui-row-shrinks-in-proportion-to-capacity ()
  (let ((row (list (textui-test--spec :flex 30 20)
                   (textui-test--spec :flex 20 10)
                   (textui-test--spec :native 10 10))))
    (should (equal (textui--allocate-row row 49 2) '(22 13 10)))))

(ert-deftest textui-row-wraps-in-source-order-at-minimum-widths ()
  (let* ((a (textui-test--spec :native 10 10))
         (b (textui-test--spec :flex 20 10))
         (c (textui-test--spec :native 8 8))
         (rows (textui--partition-row (list a b c) 25 1)))
    (should (equal rows (list (list a b) (list c))))
    (should (equal (textui--allocate-row (car rows) 25 1) '(10 14)))
    (should (equal (textui--allocate-row (cadr rows) 25 1) '(8)))))

(ert-deftest textui-single-layout-may-go-below-its-minimum ()
  (let ((layout (textui-test--spec :flex 20 15))
        (native (textui-test--spec :native 20 20)))
    (should (equal (textui--allocate-row (list layout) 8 1) '(8)))
    (should (equal (textui--allocate-row (list native) 8 1) '(20)))))

(ert-deftest textui-flex-layout-shrinks-then-wraps-with-window-width ()
  (let ((frame
         '((:type :flex :direction :row :gap 1
            :children
            ((:type :flex :direction :column
              :layout (:width 12 :min-width 8)
              :children ((:type item :format "%v" :value "Alpha")))
             (:type :flex :direction :column
              :layout (:width 12 :min-width 8)
              :children ((:type item :format "%v" :value "Beta"))))))))
    (should (= (length (textui-test--trimmed-lines
                        (textui--render-frame frame 25)))
               1))
    (should (= (length (textui-test--trimmed-lines
                        (textui--render-frame frame 20)))
               1))
    (should (equal (textui-test--trimmed-lines
                    (textui--render-frame frame 16))
                   '("Alpha" "Beta")))))

(ert-deftest textui-nested-three-column-layout-matrix ()
  (let ((frame
         '((:type :flex :direction :row :gap 1
            :children
            ((:type :flex :direction :column :gap 0
              :layout (:width 10 :min-width 6 :grow 1)
              :children
              ((:type item :format "%v" :value "A1")
               (:type item :format "%v" :value "A2")))
             (:type :flex :direction :column :gap 0
              :layout (:width 10 :min-width 6 :grow 1)
              :children
              ((:type item :format "%v" :value "B1")
               (:type item :format "%v" :value "B2")))
             (:type :flex :direction :column :gap 0
              :layout (:width 10 :min-width 6 :grow 1)
              :children
              ((:type item :format "%v" :value "C1")
               (:type item :format "%v" :value "C2"))))))))
    (should (= (length (split-string (textui--render-frame frame 32) "\n"))
               2))
    (let ((lines (textui-test--trimmed-lines
                  (textui--render-frame frame 13))))
      (should (= (length lines) 4))
      (should (string-match-p "A1.*B1" (nth 0 lines)))
      (should (equal (nth 2 lines) "C1")))
    (should
     (equal (textui-test--trimmed-lines (textui--render-frame frame 6))
            '("A1" "A2" "B1" "B2" "C1" "C2")))))

(ert-deftest textui-layout-width-replaces-its-natural-width ()
  (let* ((frame
          '((:type :flex :direction :row
             :children
             ((:type :flex :direction :row
               :layout (:width 8)
               :children
               ((:type item :format "%v" :value "Alpha")
                (:type item :format "%v" :value "Beta")))))))
         (root (car (textui--prepare-frame frame)))
         (child (car (plist-get root :children))))
    (should (> (plist-get child :natural) 8))
    (should (= (plist-get child :start) 8))
    (should (= (plist-get child :minimum) 8))))

(ert-deftest textui-flex-border-and-padding-use-border-box-width ()
  (let* ((frame
          '((:type :flex :direction :column :padding 1 :border t
             :children ((:type item :format "%v" :value "Hello")))))
         (lines (split-string (textui--render-frame frame 12) "\n")))
    (should (= (length lines) 5))
    (dolist (line lines)
      (should (= (string-width line) 12)))
    (should (equal (car lines) "┌──────────┐"))
    (should (string-match-p "│ Hello    │" (nth 2 lines)))
    (should (equal (car (last lines)) "└──────────┘"))))

(ert-deftest textui-column-gap-counts-blank-lines ()
  (let ((frame
         '((:type :flex :direction :column :gap 1
            :children
            ((:type item :format "%v" :value "One")
             (:type item :format "%v" :value "Two"))))))
    (should (equal (textui-test--trimmed-lines
                    (textui--render-frame frame 8))
                   '("One" "" "Two")))))

(ert-deftest textui-grid-reduces-equal-columns-with-width ()
  (let ((frame
         '((:type :grid :columns 3 :min-column-width 6 :gap 1
            :children
            ((:type item :format "%v" :value "A")
             (:type item :format "%v" :value "B")
             (:type item :format "%v" :value "C")
             (:type item :format "%v" :value "D")
             (:type item :format "%v" :value "E"))))))
    (let ((lines (split-string (textui--render-frame frame 20) "\n")))
      (should (= (length lines) 3))
      (should (= (string-match "B" (nth 0 lines)) 7))
      (should (= (string-match "C" (nth 0 lines)) 14))
      (should (= (string-match "E" (nth 2 lines)) 7))
      (should (= (string-width (nth 2 lines)) 20)))
    (let ((lines (split-string (textui--render-frame frame 13) "\n")))
      (should (= (length lines) 5))
      (should (= (string-match "B" (nth 0 lines)) 7))
      (should (= (string-match "D" (nth 2 lines)) 7))
      (should (string-prefix-p "E" (nth 4 lines))))
    (should (= (length (split-string (textui--render-frame frame 6) "\n"))
               9))))

(ert-deftest textui-grid-shares-track-widths-across-rows ()
  (let* ((frame
          '((:type :grid :columns 3 :min-column-width 4 :gap 1
             :children
             ((:type item :format "%v" :value "A")
              (:type item :format "%v" :value "B")
              (:type item :format "%v" :value "C")
              (:type item :format "%v" :value "LONGWORD")
              (:type item :format "%v" :value "E")
              (:type item :format "%v" :value "F")))))
         (lines (split-string (textui--render-frame frame 20) "\n")))
    (should (= (string-match "B" (nth 0 lines))
               (string-match "E" (nth 2 lines))))
    (should (= (string-match "C" (nth 0 lines))
               (string-match "F" (nth 2 lines))))))

(ert-deftest textui-grid-uses-the-tallest-cell-as-row-height ()
  (let* ((frame
          '((:type :grid :columns 2 :min-column-width 10 :gap 1
             :children
             ((:type :flex :direction :column :gap 0
               :children
               ((:type item :format "%v" :value "A1")
                (:type item :format "%v" :value "A2")))
              (:type item :format "%v" :value "B")
              (:type item :format "%v" :value "C")
              (:type item :format "%v" :value "D")))))
         (lines (split-string (textui--render-frame frame 21) "\n")))
    (should (= (length lines) 4))
    (should (= (string-match "B" (nth 0 lines)) 11))
    (should (string-prefix-p "A2" (nth 1 lines)))
    (should (string-match-p "\\` *\\'" (nth 2 lines)))
    (should (= (string-match "D" (nth 3 lines)) 11))))

(ert-deftest textui-grid-validates-options-and-keeps-border-box-width ()
  (dolist (frame
           '(((:type :grid :min-column-width 5 :children nil))
             ((:type :grid :columns 0 :min-column-width 5 :children nil))
             ((:type :grid :columns 2 :min-column-width 0 :children nil))))
    (should-error (textui--render-frame frame 20)))
  (let* ((frame
          '((:type :grid :columns 2 :min-column-width 5 :gap 1
             :padding 1 :border t
             :children
             ((:type item :format "%v" :value "A")
              (:type item :format "%v" :value "B")))))
         (lines (split-string (textui--render-frame frame 15) "\n")))
    (should (= (length lines) 5))
    (dolist (line lines)
      (should (= (string-width line) 15)))
    (should (equal (car lines) "┌─────────────┐"))
    (should (equal (car (last lines)) "└─────────────┘"))))

(ert-deftest textui-expander-runs-once-per-frame ()
  (let ((calls 0)
        (old textui--expanders))
    (unwind-protect
        (progn
          (textui-register-expander
           'sample-label
           (lambda (element)
             (setq calls (1+ calls))
             (list (list :type 'item :format "%v"
                         :value (plist-get element :value)))))
          (should (string-match-p
                   "Expanded"
                   (textui--render-frame
                    '((:type sample-label :value "Expanded")) 20)))
          (should (= calls 1)))
      (setq textui--expanders old))))

(ert-deftest textui-expander-cycle-signals-an-error ()
  (let ((old textui--expanders))
    (unwind-protect
        (progn
          (textui-register-expander 'sample-loop (lambda (element) (list element)))
          (should-error
           (textui--render-frame '((:type sample-loop)) 20)))
      (setq textui--expanders old))))

(ert-deftest textui-custom-expander-can-place-native-controls ()
  (let ((old textui--expanders))
    (unwind-protect
        (progn
          (textui-register-expander
           'textui-test-labeled-control
           (lambda (element)
             (list
              (list :type :flex :direction :row :gap 1
                    :children
                    (list
                     (list :type 'item :format "%v"
                           :value (plist-get element :label))
                     (plist-get element :control))))))
          (should
           (equal
            (car
             (textui-test--trimmed-lines
              (substring-no-properties
               (textui--render-frame
                '((:type textui-test-labeled-control
                   :label "Enabled:"
                   :control (:type checkbox :value t)))
                20))))
            "Enabled: [X]")))
      (setq textui--expanders old))))

(ert-deftest textui-native-widgets-must-be-single-line ()
  (should-error
   (textui--render-frame
    '((:type item :format "%v" :value "one\ntwo")) 20)))

(ert-deftest textui-text-leaf-reflows-at-its-assigned-width ()
  (let ((frame
         '((:type :text :value "alpha beta gamma"
            :layout (:width 16 :min-width 5 :grow 1)))))
    (should (equal (textui--render-frame frame 16)
                   "alpha beta gamma"))
    (should (equal (textui--render-frame frame 10)
                   "alpha beta\ngamma"))))

(ert-deftest textui-text-pixel-width-supports-emacs-30-arity ()
  (let ((emacs-version "30.1")
        (face-remapping-alist nil))
    (cl-letf (((symbol-function 'string-pixel-width)
               (lambda (string) (length string))))
      (should (= (textui--text-pixel-width 7) 7)))))

(ert-deftest textui-text-breaks-account-for-every-literal-space ()
  (require 'textui-kp-core)
  (let* ((string "a  b")
         (limit (textui-kp-core--pixel-width "a b"))
         (ranges (textui-kp-core-break-lines string limit)))
    (dolist (range ranges)
      (should
       (<= (textui-kp-core--pixel-width
            (substring string (car range) (cdr range)))
           limit)))))

(ert-deftest textui-text-leaf-justifies-every-line-to-its-pixel-width ()
  (require 'textui-kp-core)
  (let* ((value "alpha beta gamma delta epsilon zeta eta theta")
         (pixel-width (textui--text-pixel-width 14))
         (lines (textui--wrap-text value 14)))
    (should (> (length lines) 1))
    (dolist (line (butlast lines))
      (when (get-text-property 0 'textui--pixel-justified line)
        (should (= (textui-kp-core--pixel-width line) pixel-width))))
    (should
     (seq-some
      (lambda (line)
        (text-property-not-all 0 (length line) 'display nil line))
      lines))))

(ert-deftest textui-text-leaf-uses-global-knuth-plass-breaks ()
  (require 'textui-kp-core)
  (let* ((value "TextUI gives Knuth–Plass the card's inner pixel width, then stretches display-only spacing without changing the Flex allocation.")
         (lines (textui-kp-core-justify-lines value value 27)))
    (should
     (equal (mapcar (lambda (line)
                      (replace-regexp-in-string
                       "\u200B" "" (substring-no-properties line)))
                    lines)
            '("TextUI gives Knuth–Plass the"
              "card's inner pixel width,"
              "then stretches display-only"
              "spacing without changing the"
              "Flex allocation.")))
    (dolist (line (butlast lines))
      (should (= (textui-kp-core--pixel-width line) 27)))
    (should-not
     (seq-some (lambda (line)
                 (text-property-not-all
                  0 (length line) 'textui--synthetic-spacing nil line))
               lines))))

(ert-deftest textui-text-leaf-falls-back-before-kp-overflows ()
  (require 'textui-kp-core)
  (let* ((value "TextUI gives Knuth–Plass the card's inner pixel width, then stretches display-only spacing without changing the Flex allocation.")
         (lines (textui-kp-core-justify-lines value value 13)))
    (dolist (line lines)
      (should (<= (textui-kp-core--pixel-width line) 13)))
    (should (member "stretches" (mapcar #'substring-no-properties lines)))
    (should (member "display-only"
                    (mapcar #'substring-no-properties lines)))))

(ert-deftest textui-text-leaf-does-not-measure-identifier-breaks-as-spaces ()
  (require 'textui-kp-core)
  (should
   (equal (mapcar #'substring-no-properties
                  (textui-kp-core-justify-lines
                   "TextUI alpha beta" "TextUI alpha beta" 17))
          '("TextUI alpha beta"))))

(ert-deftest textui-pixel-justified-text-keeps-its-layout-box-width ()
  (require 'textui-kp-core)
  (let* ((value "TextUI gives Knuth–Plass the card's inner pixel width, then stretches display-only spacing without changing the Flex allocation.")
         (frame
          `((:type :flex :direction :column :padding 1 :border t
             :children ((:type :text :value ,value)))))
         (lines (split-string (textui--render-frame frame 59) "\n")))
    (dolist (line lines)
      (should (= (textui-kp-core--pixel-width line) 59)))))

(ert-deftest textui-text-leaf-passes-inner-content-width-to-justification ()
  (require 'textui-kp-core)
  (let ((expected (textui--text-pixel-width 17))
        received)
    (cl-letf (((symbol-function 'textui-kp-core-justify-lines)
               (lambda (_source attributed pixel-width)
                 (setq received pixel-width)
                 (list attributed))))
      (textui--render-frame
       '((:type :flex :direction :column :padding 1 :border t
          :children
          ((:type :text :value "alpha beta gamma delta"))))
       21))
    (should (= received expected))))

(ert-deftest textui-text-leaf-composes-inside-grid ()
  (let* ((frame
          '((:type :grid :columns 2 :min-column-width 10 :gap 1
             :children
             ((:type :text :value "alpha beta gamma")
              (:type item :format "%v" :value "R")))))
         (lines (textui-test--trimmed-lines
                 (textui--render-frame frame 21))))
    (should (= (length lines) 2))
    (should (equal (car lines) "alpha beta R"))
    (should (equal (cadr lines) "gamma"))))

(ert-deftest textui-text-leaf-validates-its-public-shape ()
  (should-error (textui--render-frame '((:type :text :value 42)) 20))
  (should-error
   (textui--render-frame
    '((:type :text :value "text" :unknown t)) 20)))

(ert-deftest textui-image-leaf-validates-its-public-shape ()
  (dolist (frame
           '(((:type :image :file 42 :rows 2))
             ((:type :image :file "image.png" :rows 0))
             ((:type :image :file "image.png" :rows 2 :alt 42))
             ((:type :image :file "image.png" :rows 2 :unknown t))))
    (should-error (textui--render-frame frame 20))))

(ert-deftest textui-image-leaf-falls-back-to-a-fixed-height-block ()
  (let* ((frame
          '((:type :grid :columns 2 :min-column-width 10 :gap 1
             :children
             ((:type :image :file "image.png" :rows 3 :alt "preview")
              (:type item :format "%v" :value "R")))))
         (lines (textui-test--trimmed-lines
                 (textui--render-frame frame 21))))
    (should (equal lines '("preview    R" "" "")))))

(ert-deftest textui-image-leaf-slices-a-native-image-across-text-rows ()
  (cl-letf (((symbol-function 'display-graphic-p)
             (lambda (&optional _display) t))
            ((symbol-function 'file-readable-p)
             (lambda (_file) t))
            ((symbol-function 'frame-char-width)
             (lambda (&optional _frame) 10))
            ((symbol-function 'frame-char-height)
             (lambda (&optional _frame) 20))
            ((symbol-function 'create-image)
             (lambda (file &optional _type _data-p &rest properties)
               (cons 'image (append (list :file file) properties))))
            ((symbol-function 'image-size)
             (lambda (&rest _arguments) '(100 . 40))))
    (let* ((rendered
            (textui--render-frame
             '((:type :image :file "image.png" :rows 4 :alt "preview"))
             10))
           (lines (split-string rendered "\n"))
           (first-slice (get-text-property 0 'display (nth 1 lines)))
           (second-slice (get-text-property 0 'display (nth 2 lines))))
      (should (= (length lines) 4))
      (should-not (get-text-property 0 'display (nth 0 lines)))
      (should (equal (substring-no-properties (nth 1 lines) 0 7)
                     "preview"))
      (should (equal (car first-slice) '(slice 0.0 0.0 1.0 0.5)))
      (should (equal (car second-slice) '(slice 0.0 0.5 1.0 0.5)))
      (should-not (get-text-property 0 'display (nth 3 lines))))))

(ert-deftest textui-image-leaf-falls-back-when-file-is-unreadable ()
  (cl-letf (((symbol-function 'display-graphic-p)
             (lambda (&optional _display) t))
            ((symbol-function 'file-readable-p)
             (lambda (_file) nil))
            ((symbol-function 'create-image)
             (lambda (&rest _arguments)
               (error "create-image should not be called"))))
    (should
     (equal
      (substring-no-properties
       (textui--render-frame
        '((:type :image :file "missing.png" :rows 2 :alt "missing")) 10))
      "missing   \n          "))))

(ert-deftest textui-text-leaf-preserves-hard-lines-and-properties ()
  (let ((value (copy-sequence "first line\n\nsecond line")))
    (put-text-property 12 18 'face 'bold value)
    (let ((rendered
           (textui--render-frame
            (list (list :type :text :value value)) 20)))
      (should (equal (substring-no-properties rendered)
                     "first line\n\nsecond line"))
      (should (eq (get-text-property 12 'face rendered) 'bold)))))

(ert-deftest textui-text-leaf-keeps-breakable-lines-within-width ()
  (let* ((value "abcdef ghij 中文测试，继续。")
         (lines (split-string
                 (textui--render-frame
                  (list (list :type :text :value value)) 6)
                 "\n")))
    (dolist (line lines)
      (should (<= (string-width line) 6))
      (should-not (string-match-p "\\`[，。）」』】]" line))
      (should-not (string-match-p "[（「『【]\\'" line)))
    (should (equal (replace-regexp-in-string
                    "[ \n]+" "" (mapconcat #'identity lines ""))
                   "abcdefghij中文测试，继续。"))))

(ert-deftest textui-text-leaf-restores-source-position-after-reflow ()
  (let ((width 24)
        (value "alpha beta gamma delta epsilon")
        (buffer (generate-new-buffer " *textui-text-focus-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--render-function
           (lambda (_width)
             (list (list :type :text :value value))))
          (cl-letf (((symbol-function 'textui--visible-width)
                     (lambda (_buffer) width)))
            (textui-refresh buffer)
            (goto-char (point-min))
            (search-forward "gamma")
            (backward-char 5)
            (let ((source-offset
                   (get-text-property (point) 'textui--text-source-offset)))
              (setq width 12)
              (textui-refresh buffer)
              (should (looking-at "gamma"))
              (should (= (get-text-property
                          (point) 'textui--text-source-offset)
                         source-offset)))))
      (kill-buffer buffer))))

(ert-deftest textui-action-refreshes-once-after-success ()
  (let ((state 0)
        (renders 0)
        (buffer (generate-new-buffer " *textui-action-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30)
          (setq-local
           textui--render-function
           (lambda (_width)
             (setq renders (1+ renders))
             (list (list :type 'push-button
                         :value (number-to-string state)
                         :action (lambda (&rest _)
                                   (setq state (1+ state)))))))
          (textui-refresh buffer)
          (let ((button (cl-find-if
                         (lambda (widget) (eq (car widget) 'push-button))
                         textui--widgets)))
            (widget-apply-action button))
          (should (= state 1))
          (should (= renders 2))
          (should (equal (buffer-string) "[1]")))
      (kill-buffer buffer))))

(ert-deftest textui-update-coalesces-state-and-refresh ()
  (let ((buffer (generate-new-buffer " *textui-state-test*"))
        (renders 0)
        (scheduled-count 0)
        scheduled)
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30
                      textui-state '(:count 0)
                      textui--render-function
                      (lambda (_width)
                        (setq renders (1+ renders))
                        (list (list :type 'item :format "%v"
                                    :value
                                    (number-to-string
                                     (plist-get textui-state :count))))))
          (textui-refresh buffer)
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (_time _repeat function &rest arguments)
                       (setq scheduled-count (1+ scheduled-count)
                             scheduled (cons function arguments))
                       'state-refresh-timer)))
            (textui-update
             buffer
             (lambda (state)
               (plist-put (copy-sequence state) :count 1)))
            (textui-update
             buffer
             (lambda (state)
               (plist-put (copy-sequence state) :count 2)))
            (should (= (plist-get textui-state :count) 2))
            (should (= scheduled-count 1))
            (should (= renders 1))
            (apply (car scheduled) (cdr scheduled))
            (should (= renders 2))
            (should (equal (buffer-string) "2"))))
      (kill-buffer buffer))))

(ert-deftest textui-update-reconciles-named-regions-automatically ()
  (let ((buffer (generate-new-buffer " *textui-auto-region-test*"))
        scheduled)
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--last-width 30
           textui-state '(:count 0 :footer "A")
           textui--render-function
           (lambda (_width)
             `((:type :flex :direction :column :gap 0
                :children
                ((:type :flex :direction :column :gap 0
                  :layout (:refresh-id changing)
                  :children
                  ((:type item :format "%v"
                    :value ,(number-to-string
                             (plist-get textui-state :count)))))
                 (:type :flex :direction :column :gap 0
                  :layout (:refresh-id stable)
                 :children
                  ((:type push-button :value "Stable"
                    :action ignore)))
                 (:type item :format "%v"
                  :value ,(plist-get textui-state :footer)))))))
          (textui-refresh buffer)
          (let ((stable
                 (cl-find-if
                  (lambda (widget)
                    (equal (widget-value widget) "Stable"))
                  textui--widgets)))
            (cl-letf (((symbol-function 'run-at-time)
                       (lambda (_time _repeat function &rest arguments)
                         (setq scheduled (cons function arguments))
                         'auto-region-timer)))
              (textui-update
               buffer
               (lambda (state)
                 (plist-put (copy-sequence state) :count 1)))
              (apply (car scheduled) (cdr scheduled)))
            (should
             (equal (mapcar #'string-trim-right
                            (split-string (buffer-string) "\n"))
                    '("1" "[Stable]" "A")))
            (should
             (eq stable
                 (cl-find-if
                  (lambda (widget)
                    (equal (widget-value widget) "Stable"))
                  textui--widgets)))
            (textui-refresh-region
             buffer 'stable
             (lambda (_width)
               '((:type push-button :value "Stable" :action ignore))))
            (setq stable
                  (cl-find-if
                   (lambda (widget)
                     (equal (widget-value widget) "Stable"))
                   textui--widgets))
            (textui-refresh-region
             buffer 'changing
             (lambda (_width)
               '((:type item :format "%v" :value "manual"))))
            (cl-letf (((symbol-function 'run-at-time)
                       (lambda (_time _repeat function &rest arguments)
                         (setq scheduled (cons function arguments))
                         'auto-region-after-manual-timer)))
              (textui-update
               buffer
               (lambda (state)
                 (plist-put (copy-sequence state) :count 2)))
              (apply (car scheduled) (cdr scheduled)))
            (should
             (equal (mapcar #'string-trim-right
                            (split-string (buffer-string) "\n"))
                    '("2" "[Stable]" "A")))
            (should
             (eq stable
                 (cl-find-if
                  (lambda (widget)
                    (equal (widget-value widget) "Stable"))
                  textui--widgets)))
            (cl-letf (((symbol-function 'run-at-time)
                       (lambda (_time _repeat function &rest arguments)
                         (setq scheduled (cons function arguments))
                         'auto-region-fallback-timer)))
              (textui-update
               buffer
               (lambda (state)
                 (plist-put (copy-sequence state) :footer "B")))
              (apply (car scheduled) (cdr scheduled)))
            (should
             (equal (mapcar #'string-trim-right
                            (split-string (buffer-string) "\n"))
                    '("2" "[Stable]" "B")))
            (should-not
             (eq stable
                 (cl-find-if
                  (lambda (widget)
                    (equal (widget-value widget) "Stable"))
                  textui--widgets)))))
      (kill-buffer buffer))))

(ert-deftest textui-action-respects-state-update-requested-refresh ()
  (let ((buffer (generate-new-buffer " *textui-state-action-test*"))
        (renders 0)
        scheduled)
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30
                      textui-state '(:count 0)
                      textui--render-function
                      (lambda (_width)
                        (setq renders (1+ renders))
                        (list
                         (list
                          :type 'push-button
                          :value (number-to-string
                                  (plist-get textui-state :count))
                          :action
                          (lambda (&rest _)
                            (textui-update
                             buffer
                             (lambda (state)
                               (plist-put
                                (copy-sequence state) :count
                                (1+ (plist-get state :count))))))))))
          (textui-refresh buffer)
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (_time _repeat function &rest arguments)
                       (setq scheduled (cons function arguments))
                       'state-action-timer)))
            (widget-apply-action (car textui--widgets))
            (should (= renders 1))
            (apply (car scheduled) (cdr scheduled))
            (should (= renders 2))
            (should (equal (buffer-string) "[1]"))))
      (kill-buffer buffer))))

(ert-deftest textui-update-keeps-state-when-updater-errors ()
  (let ((buffer (generate-new-buffer " *textui-state-error-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui-state '(:value old))
          (should-error
           (textui-update buffer (lambda (_state) (error "Boom"))))
          (should (equal textui-state '(:value old)))
          (should-error
           (textui-update buffer #'identity :region 'rows))
          (should-not textui--refresh-timer))
      (kill-buffer buffer))))

(ert-deftest textui-set-state-updates-one-plist-value ()
  (let ((buffer (generate-new-buffer " *textui-set-state-test*"))
        scheduled)
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30
                      textui-state '(:count 1 :label "kept")
                      textui--render-function
                      (lambda (_width)
                        `((:type item :format "%v"
                           :value ,(number-to-string
                                    (plist-get textui-state :count))))))
          (textui-refresh buffer)
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (_time _repeat function &rest arguments)
                       (setq scheduled (cons function arguments))
                       'set-state-timer)))
            (textui-set-state buffer :count (lambda (count) (1+ count)))
            (should (equal textui-state '(:count 2 :label "kept")))
            (apply (car scheduled) (cdr scheduled)))
          (should (equal (buffer-string) "2")))
      (kill-buffer buffer))))

(ert-deftest textui-update-reconciles-declared-route-keys-safely ()
  (let ((buffer (generate-new-buffer " *textui-state-route-test*"))
        (renders 0)
        (scheduled-count 0)
        scheduled)
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--last-width 30
           textui-state '(:left "L0" :right "R0" :shell "S0")
           textui--render-function
           (lambda (_width)
             (setq renders (1+ renders))
             (textui-route-state
              'left '(:left)
              (lambda (_width)
                `((:type item :format "%v"
                   :value ,(plist-get textui-state :left)))))
             (textui-route-state
              'right '(:right)
              (lambda (_width)
                `((:type item :format "%v"
                   :value ,(plist-get textui-state :right)))))
             `((:type :flex :direction :column :gap 0
                :children
                ((:type :flex :direction :column :gap 0
                  :layout (:refresh-id left)
                  :children
                  ((:type item :format "%v"
                    :value ,(plist-get textui-state :left))))
                 (:type :flex :direction :column :gap 0
                  :layout (:refresh-id right)
                  :children
                  ((:type item :format "%v"
                    :value ,(plist-get textui-state :right))))
                 (:type item :format "%v"
                  :value ,(plist-get textui-state :shell)))))))
          (textui-refresh buffer)
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (_time _repeat function &rest arguments)
                       (setq scheduled-count (1+ scheduled-count)
                             scheduled (cons function arguments))
                       'state-route-timer)))
            (textui-update
             buffer
             (lambda (state)
               (let ((next (copy-sequence state)))
                 (setq next (plist-put next :left "L1"))
                 (plist-put next :right "R1"))))
            (should (= scheduled-count 1))
            (should textui--refresh-timer)
            (should-not textui--region-refresh-timer)
            (apply (car scheduled) (cdr scheduled))
            (should (= renders 2))
            (should (equal (textui-test--trimmed-lines (buffer-string))
                           '("L1" "R1" "S0")))
            (setq scheduled nil)
            (textui-update buffer #'identity)
            (should textui--refresh-timer)
            (apply (car scheduled) (cdr scheduled))
            (should (= renders 3))
            (setq scheduled nil)
            (textui-set-state buffer :shell "S1")
            (should textui--refresh-timer)
            (apply (car scheduled) (cdr scheduled))
            (should (= renders 4))
            (should (equal (textui-test--trimmed-lines (buffer-string))
                           '("L1" "R1" "S1")))))
      (kill-buffer buffer))))

(ert-deftest textui-routed-state-change-keeps-frame-shell-current ()
  (let ((buffer (generate-new-buffer " *textui-route-shell-test*"))
        scheduled)
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--last-width 30
           textui-state '(:value "old")
           textui--render-function
           (lambda (_width)
             (textui-route-state
              'body '(:value)
              (lambda (_width)
                `((:type item :format "%v"
                   :value ,(plist-get textui-state :value)))))
             `((:type :flex :direction :column :gap 0
                :children
                ((:type :flex :direction :column :gap 0
                  :layout (:refresh-id body)
                  :children
                  ((:type item :format "%v"
                    :value ,(plist-get textui-state :value))))
                 (:type item :format "%v"
                  :value ,(plist-get textui-state :value)))))))
          (textui-refresh buffer)
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (_time _repeat function &rest arguments)
                       (setq scheduled (cons function arguments))
                       'route-shell-timer)))
            (textui-set-state buffer :value "new")
            (apply (car scheduled) (cdr scheduled)))
          (should (equal (textui-test--trimmed-lines (buffer-string))
                         '("new" "new"))))
      (kill-buffer buffer))))

(ert-deftest textui-state-route-must-name-a-rendered-region ()
  (let ((buffer (generate-new-buffer " *textui-invalid-state-route-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30
                      textui-state '(:value "old")
                      textui--render-function
                      (lambda (_width)
                        `((:type item :format "%v"
                           :value ,(plist-get textui-state :value)))))
          (textui-refresh buffer)
          (setq-local
           textui--render-function
           (lambda (_width)
             (textui-route-state 'missing '(:value) #'ignore)
             '((:type item :format "%v" :value "new"))))
          (let ((error-data (should-error (textui-refresh buffer))))
            (should (string-match-p "Unknown state route region"
                                    (error-message-string error-data))))
          (should (equal (buffer-string) "old")))
      (kill-buffer buffer))))

(ert-deftest textui-effect-follows-rendered-dependencies ()
  (let ((buffer (generate-new-buffer " *textui-effect-test*"))
        (dependency 'first)
        (show-effect t)
        events)
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--last-width 30
           textui--render-function
           (lambda (_width)
             (when show-effect
               (let ((value dependency))
                 (textui-effect
                  'worker (list value)
                  (lambda ()
                    (push (list 'start value) events)
                    (lambda () (push (list 'stop value) events))))))
             '((:type item :format "%v" :value "view"))))
          (textui-refresh buffer)
          (should (equal (reverse events) '((start first))))
          (textui-refresh buffer)
          (should (equal (reverse events) '((start first))))
          (setq dependency 'second)
          (textui-refresh buffer)
          (should (equal (reverse events)
                         '((start first) (stop first) (start second))))
          (setq show-effect nil)
          (textui-refresh buffer)
          (should (equal (reverse events)
                         '((start first) (stop first)
                           (start second) (stop second)))))
      (kill-buffer buffer))))

(ert-deftest textui-async-callback-stops-with-its-effect ()
  (let ((buffer (generate-new-buffer " *textui-async-effect-test*"))
        (dependency 'first)
        callbacks
        cleanups
        events)
    (with-current-buffer buffer
      (textui-mode)
      (setq-local
       textui--last-width 30
       textui--render-function
       (lambda (_width)
         (let ((value dependency))
           (textui-effect
            'worker (list value)
            (lambda ()
              (push
               (textui-async-callback
                (lambda (event)
                  (push (list value event (current-buffer)) events)))
               callbacks)
              (lambda () (push value cleanups)))))
         '((:type item :format "%v" :value "view"))))
      (textui-refresh buffer))
    (funcall (car callbacks) 'alive)
    (setq dependency 'second)
    (with-current-buffer buffer
      (textui-refresh buffer))
    (funcall (cadr callbacks) 'stale)
    (funcall (car callbacks) 'alive)
    (kill-buffer buffer)
    (funcall (car callbacks) 'stale)
    (should (equal cleanups '(second first)))
    (should (equal events (list (list 'second 'alive buffer)
                                (list 'first 'alive buffer))))))

(ert-deftest textui-cleanup-runs-once-when-buffer-is-killed ()
  (let ((buffer (generate-new-buffer " *textui-cleanup-test*"))
        (calls 0))
    (with-current-buffer buffer
      (textui-mode)
      (let ((cleanup (lambda () (setq calls (1+ calls)))))
        (textui-register-cleanup buffer cleanup)
        (textui-register-cleanup buffer cleanup)))
    (kill-buffer buffer)
    (should (= calls 1))))

(ert-deftest textui-refresh-region-replaces-only-its-lines ()
  (let ((value "old")
        (renders 0)
        producer-width
        (buffer (generate-new-buffer " *textui-region-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30)
          (setq-local
           textui--render-function
           (lambda (_width)
             (setq renders (1+ renders))
             (list
              `(:type :flex :direction :column :gap 0
                :children
                ((:type push-button :value "Header" :action ignore)
                 (:type :flex :direction :column :gap 0
                  :layout (:refresh-id rows)
                  :children
                  ((:type item :format "%v" :value ,value)))
                 (:type item :format "%v" :value "Footer"))))))
          (textui-refresh buffer)
          (let ((header (car textui--widgets)))
            (goto-char (point-min))
            (search-forward "Footer")
            (backward-char 3)
            (setq value "new")
            (textui-refresh-region
             buffer 'rows
             (lambda (width)
               (setq producer-width width)
               (list `(:type item :format "%v" :value ,value)
                     '(:type item :format "%v" :value "second"))))
            (should (= renders 1))
            (should (= producer-width 30))
            (should (memq header textui--widgets))
            (should (equal (string-trim-right
                            (buffer-substring-no-properties
                             (line-beginning-position) (line-end-position)))
                           "Footer"))
            (should (equal (textui-test--trimmed-lines (buffer-string))
                           '("[Header]" "new" "second" "Footer")))
            (goto-char (point-min))
            (search-forward "second")
            (beginning-of-line)
            (move-to-column 2)
            (textui-refresh-region
             buffer 'rows
             (lambda (_width)
               '((:type item :format "%v" :value "again")
                 (:type item :format "%v" :value "last"))))
            (should (= (current-column) 2))
            (should (equal
                     (string-trim-right
                      (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position)))
                     "last"))
            (let ((before (buffer-string))
                  (generation textui--refresh-generation))
              (should-error
               (textui-refresh-region
                buffer 'rows
                (lambda (_width)
                  '((:type item :format "%v" :value "bad\nwidget")))))
              (should (equal before (buffer-string)))
              (should (= generation textui--refresh-generation)))))
      (kill-buffer buffer))))

(ert-deftest textui-refresh-region-keeps-adjacent-region-boundaries ()
  (let ((buffer (generate-new-buffer " *textui-adjacent-regions-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30)
          (setq-local
           textui--render-function
           (lambda (_width)
             '((:type :flex :direction :column :gap 0
                :children
                ((:type :flex :direction :column :gap 0
                  :layout (:refresh-id first)
                  :children ((:type item :format "%v" :value "one")))
                 (:type :flex :direction :column :gap 0
                  :layout (:refresh-id second)
                  :children ((:type item :format "%v" :value "two")))
                 (:type item :format "%v" :value "footer"))))))
          (textui-refresh buffer)
          (textui-refresh-region
           buffer 'first
           (lambda (_width)
             '((:type item :format "%v" :value "one-a")
               (:type item :format "%v" :value "one-b"))))
          (should (equal (textui-test--trimmed-lines (buffer-string))
                         '("one-a" "one-b" "two" "footer")))
          (should (< (marker-position (nth 3 (assq 'first
                                                   textui--refresh-regions)))
                     (marker-position (nth 3 (assq 'second
                                                   textui--refresh-regions)))))
          (textui-refresh-region
           buffer 'second
           (lambda (_width)
             '((:type item :format "%v" :value "two-a")
               (:type item :format "%v" :value "two-b"))))
          (should (equal (textui-test--trimmed-lines (buffer-string))
                         '("one-a" "one-b" "two-a" "two-b" "footer"))))
      (kill-buffer buffer))))

(ert-deftest textui-equal-length-region-refresh-reuses-rendered-cache ()
  (let ((buffer (generate-new-buffer " *textui-region-cache-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 20
                      textui--render-function
                      (lambda (_width)
                        '((:type :flex :direction :column :gap 0
                           :layout (:refresh-id value)
                           :children
                           ((:type item :format "%v" :value "old"))))))
          (textui-refresh buffer)
          (let ((cached textui--rendered-frame))
            (textui-refresh-region
             buffer 'value
             (lambda (_width)
               '((:type item :format "%v" :value "new"))))
            (should (eq cached textui--rendered-frame))
            (should (string-match-p "new" (buffer-string)))))
      (kill-buffer buffer))))

(ert-deftest textui-request-refresh-region-coalesces-latest-producer ()
  (let ((buffer (generate-new-buffer " *textui-request-region-test*"))
        (calls 0)
        (scheduled-count 0)
        scheduled)
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30)
          (setq-local
           textui--render-function
           (lambda (_width)
             '((:type :flex :direction :column :gap 0
                :layout (:refresh-id rows)
                :children ((:type item :format "%v" :value "initial"))))))
          (textui-refresh buffer)
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (_time _repeat function &rest arguments)
                       (setq scheduled-count (1+ scheduled-count)
                             scheduled (cons function arguments))
                       'request-timer)))
            (setq textui--refreshing t)
            (should
             (eq buffer
                 (textui-request-refresh-region
                  buffer 'rows
                  (lambda (_width)
                    (setq calls (1+ calls))
                    '((:type item :format "%v" :value "stale"))))))
            (textui-request-refresh-region
             buffer 'rows
             (lambda (_width)
               (setq calls (1+ calls))
               '((:type item :format "%v" :value "latest"))))
            (setq textui--refreshing nil)
            (should (= scheduled-count 1))
            (apply (car scheduled) (cdr scheduled))
            (should (= calls 1))
            (should
             (= (marker-position
                 (nth 4 (assq 'rows textui--refresh-regions)))
                (point-max)))
            (should (equal (string-trim-right (buffer-string)) "latest"))
            (textui-request-refresh-region
             buffer 'rows
             (lambda (_width)
               (setq calls (1+ calls))
               '((:type item :format "%v" :value "obsolete"))))
            (setq-local textui--render-function
                        (lambda (_width)
                          '((:type item :format "%v" :value "gone"))))
            (textui-refresh buffer)
            (apply (car scheduled) (cdr scheduled))
            (should (= calls 1))
            (should (equal (string-trim-right (buffer-string)) "gone"))))
      (kill-buffer buffer))
    (should-not
     (textui-request-refresh-region buffer 'rows #'ignore))))

(ert-deftest textui-action-may-refresh-only-its-region ()
  (let ((value 0)
        (renders 0)
        (buffer (generate-new-buffer " *textui-region-action-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30)
          (setq-local
           textui--render-function
           (lambda (_width)
             (setq renders (1+ renders))
             (list
              (list
               :type :flex :direction :column :gap 0
               :children
               (list
                (list
                 :type :flex :direction :column :gap 0
                 :layout '(:refresh-id counter)
                 :children
                 (list
                  (list
                   :type 'push-button
                   :value (number-to-string value)
                   :action
                   (lambda (&rest _)
                     (setq value (1+ value))
                     (textui-refresh-region
                      buffer 'counter
                      (lambda (_width)
                        (list
                         (list :type 'push-button
                               :value (number-to-string value)
                               :action #'ignore)))))))))))))
          (textui-refresh buffer)
          (widget-apply-action (car textui--widgets))
          (should (= value 1))
          (should (= renders 1))
          (should (equal (string-trim-right (buffer-string)) "[1]"))
          (textui-refresh-region
           buffer 'counter
           (lambda (_width)
             '((:type item :format "%v" :value "done"))))
          (should (= renders 1))
          (should (equal (string-trim-right (buffer-string)) "done")))
      (kill-buffer buffer))))

(ert-deftest textui-refresh-region-must-own-complete-lines ()
  (let ((buffer (generate-new-buffer " *textui-inline-region-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (insert "old frame")
          (setq-local textui--last-width 30)
          (setq-local
           textui--render-function
           (lambda (_width)
             '((:type :flex :direction :row :gap 1
                :children
                ((:type :flex :direction :column :gap 0
                  :layout (:refresh-id inline)
                  :children ((:type item :format "%v" :value "left")))
                 (:type item :format "%v" :value "right"))))))
          (let ((condition (should-error (textui-refresh buffer)
                                         :type 'error)))
            (should (string-match-p "complete lines"
                                    (error-message-string condition))))
          (should (equal (buffer-string) "old frame")))
      (kill-buffer buffer))))

(ert-deftest textui-action-error-does-not-refresh ()
  (let ((renders 0)
        (buffer (generate-new-buffer " *textui-action-error-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30)
          (setq-local
           textui--render-function
           (lambda (_width)
             (setq renders (1+ renders))
             (list (list :type 'push-button :value "Fail"
                         :action (lambda (&rest _) (error "Boom"))))))
          (textui-refresh buffer)
          (let ((button (car textui--widgets)))
            (should-error (widget-apply-action button)))
          (should (= renders 1))
          (should (equal (buffer-string) "[Fail]")))
      (kill-buffer buffer))))

(ert-deftest textui-custom-widget-keeps-control-order-and-refreshes ()
  (let ((count 0)
        (renders 0)
        (buffer (generate-new-buffer " *textui-custom-widget-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 40)
          (setq-local
           textui--render-function
           (lambda (_width)
             (setq renders (1+ renders))
             (list
              `(:type :flex :direction :row :gap 1
                :children
                ((:type item :format "%v" :value "L")
                 (:type checkbox :value nil)
                 (:type textui-test-custom-button
                  :value ,(number-to-string count)
                  :action ,(lambda (&rest _)
                             (setq count (1+ count))))
                 (:type editable-field :format "%v" :size 6 :value "Ada")
                 (:type item :format "%v" :value "R"))))))
          (textui-refresh buffer)
          (let* ((ordered
                  (sort (copy-sequence textui--widgets)
                        (lambda (a b)
                          (< (widget-get a :from) (widget-get b :from)))))
                 (custom
                  (cl-find-if
                   (lambda (widget)
                     (eq (car widget) 'textui-test-custom-button))
                   ordered)))
            (should (equal (mapcar #'car ordered)
                           '(item checkbox textui-test-custom-button
                                  editable-field item)))
            (should (equal (car (textui-test--trimmed-lines
                                 (buffer-string)))
                           "L [ ] <[0]> Ada    R"))
            (widget-apply-action custom))
          (should (= count 1))
          (should (= renders 2))
          (should (equal (car (textui-test--trimmed-lines
                               (buffer-string)))
                         "L [ ] <[1]> Ada    R")))
      (kill-buffer buffer))))

(ert-deftest textui-custom-renderer-and-field-display-inside-grid ()
  (let ((buffer (generate-new-buffer " *textui-custom-grid-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--last-width 21
           textui--render-function
           (lambda (_width)
             '((:type :grid :columns 2 :min-column-width 10 :gap 1
                :children
                ((:type textui-test-custom-status :value "ready")
                 (:type textui-test-custom-field :value "Ada"))))))
          (textui-refresh buffer)
          (should
           (equal (mapcar #'car
                          (sort (copy-sequence textui--widgets)
                                (lambda (left right)
                                  (< (widget-get left :from)
                                     (widget-get right :from)))))
                  '(textui-test-custom-status textui-test-custom-field)))
          (should (string-match-p "<ready>.*Ada" (buffer-string)))
          (should (= (length widget-field-list) 1)))
      (kill-buffer buffer))))

(ert-deftest textui-checkbox-notify-updates-state-before-refresh ()
  (let ((enabled nil)
        (renders 0)
        (buffer (generate-new-buffer " *textui-checkbox-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 10)
          (setq-local
           textui--render-function
           (lambda (_width)
             (setq renders (1+ renders))
             (list
              (list :type 'checkbox :value enabled
                    :notify (lambda (widget &rest _)
                              (setq enabled (widget-value widget)))))))
          (textui-refresh buffer)
          (widget-apply-action (car textui--widgets))
          (should enabled)
          (should (= renders 2))
          (should (equal (buffer-string) "[X]")))
      (kill-buffer buffer))))

(ert-deftest textui-checkboxes-keep-widget-glyphs ()
  (let ((buffer (generate-new-buffer " *textui-checkbox-glyph-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 20)
          (setq-local
           textui--render-function
           (lambda (_width)
             '((:type :flex :direction :row :gap 1
                :children
                ((:type checkbox :value nil
                  :on-glyph "checked" :off-glyph "unchecked")
                 (:type textui-test-custom-checkbox :value nil
                  :on-glyph "checked" :off-glyph "unchecked"))))))
          (textui-refresh buffer)
          (should (equal (car (textui-test--trimmed-lines (buffer-string)))
                         "[ ] [ ]"))
          (dolist (widget textui--widgets)
            (should (equal (widget-get widget :on-glyph) "checked"))
            (should (equal (widget-get widget :off-glyph) "unchecked"))))
      (kill-buffer buffer))))

(ert-deftest textui-widget-images-use-text-width-or-fall-back ()
  (with-temp-buffer
    (let ((small-image '(image :type test :width 2))
          (large-image '(image :type test :width 30))
          (fitted-small-image
           '(image :type test :width 2 :max-height (1 . ch)
                   :ascent center)))
      (insert "[ ]x")
      (add-text-properties 1 4
                           (list 'display small-image 'button 'checkbox))
      (add-text-properties 4 5
                           (list 'display large-image 'button 'custom))
      (cl-letf (((symbol-function 'image-size)
                 (lambda (image &rest _)
                   (cons (plist-get (cdr image) :width) 12))))
        (textui--compensate-image-runs 1 5))
      (should (equal (buffer-string) "[ ]x"))
      (should (equal (get-text-property 1 'display) fitted-small-image))
      (should
       (equal (get-text-property 3 'display)
              `(space :width (- (3 . width) ,fitted-small-image))))
      (should (eq (get-text-property 3 'button) 'checkbox))
      (should-not (get-text-property 4 'display))
      (should (eq (get-text-property 4 'button) 'custom)))))

(ert-deftest textui-widget-field-box-does-not-widen-its-layout-line ()
  (let ((buffer (generate-new-buffer " *textui-field-box-test*"))
        (face-attribute-function (symbol-function 'face-attribute)))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 20
                      textui--render-function
                      (lambda (_width)
                        '((:type editable-field :format "%v"
                           :size 8 :value "Ada"))))
          (cl-letf (((symbol-function 'face-attribute)
                     (lambda (face attribute &optional frame inherit)
                       (if (and (eq face 'widget-field)
                                (eq attribute :box))
                           '(:line-width (2 . -1))
                         (funcall face-attribute-function
                                  face attribute frame inherit)))))
            (textui-refresh buffer))
          (let* ((field (car widget-field-list))
                 (overlay (widget-get field :field-overlay)))
            (should
             (equal (overlay-get overlay 'face)
                    '(:inherit widget-field
                      :box (:line-width (-2 . -1)))))))
      (kill-buffer buffer))))

(ert-deftest textui-measurement-error-leaves-old-buffer-untouched ()
  (let ((buffer (generate-new-buffer " *textui-measure-error-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (insert "old frame")
          (setq-local textui--last-width 30)
          (setq-local textui--render-function
                      (lambda (_width)
                        '((:type item :format "%v" :value "bad\nwidget"))))
          (should-error (textui-refresh buffer))
          (should (equal (buffer-string) "old frame")))
      (kill-buffer buffer))))

(ert-deftest textui-reentrant-refresh-is-a-programming-error ()
  (let ((buffer (generate-new-buffer " *textui-reentrant-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30)
          (setq-local textui--render-function
                      (lambda (_width)
                        (textui-refresh buffer)
                        nil))
          (should-error (textui-refresh buffer)))
      (kill-buffer buffer))))

(ert-deftest textui-refresh-deletes-old-editable-widget-overlays ()
  (let ((state "")
        (renders 0)
        (buffer (generate-new-buffer " *textui-field-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 50)
          (setq-local
           textui--render-function
           (lambda (_width)
             (setq renders (1+ renders))
             (list
              `(:type :flex :direction :row :gap 2
                :children
                ((:type item :format "%v" :value "Input:")
                 (:type editable-field :format "%v" :size 12 :value ,state
                  :layout (:focus-id input)
                  :notify ,(lambda (widget &rest _)
                             (setq state (widget-value widget))))
                 (:type item :format "%v" :value "Tail"))))))
          (textui-refresh buffer)
          (let ((field (car widget-field-list)))
            (goto-char (widget-field-start field))
            (insert "hello"))
          (should (= renders 1))
          (textui-refresh buffer)
          (should (equal state "hello"))
          (should (= (length widget-field-list) 1))
          (should-not (get-char-property (point-min) 'field))
          (let ((field (car widget-field-list)))
            (should (= (- (widget-field-end field)
                          (widget-field-start field))
                       12))))
      (kill-buffer buffer))))

(ert-deftest textui-width-hook-refreshes-only-on-a-new-visible-width ()
  (let ((reported-width 30)
        widths
        (buffer (generate-new-buffer " *textui-width-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 30)
          (setq-local textui--render-function
                      (lambda (width)
                        (push width widths)
                        '((:type item :format "%v" :value "frame"))))
          (cl-letf (((symbol-function 'textui--visible-width)
                     (lambda (_buffer) reported-width)))
            (textui--maybe-refresh-for-width)
            (should-not widths)
            (setq reported-width 18)
            (textui--maybe-refresh-for-width)
            (should (equal widths '(18)))
            (should (= textui--last-width 18))))
      (kill-buffer buffer))))

(ert-deftest textui-width-hook-hides-cursor-until-resize-is-idle ()
  (let ((reported-width 30)
        (timer-count 0)
        scheduled
        cancelled
        (buffer (generate-new-buffer " *textui-resize-cursor-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local cursor-type 'box
                      textui--last-width 40
                      textui--render-function (lambda (_width) nil))
          (cl-letf (((symbol-function 'textui--visible-width)
                     (lambda (_buffer) reported-width))
                    ((symbol-function 'textui-refresh)
                     (lambda (_buffer)
                       (setq textui--last-width reported-width)))
                    ((symbol-function 'run-with-timer)
                     (lambda (seconds repeat function &rest arguments)
                       (setq scheduled
                             (list seconds repeat function arguments))
                       (intern (format "timer-%d" (cl-incf timer-count)))))
                    ((symbol-function 'cancel-timer)
                     (lambda (timer) (push timer cancelled))))
            (textui--maybe-refresh-for-width)
            (should-not cursor-type)
            (should (eq textui--cursor-type-before-resize 'box))
            (should (eq textui--resize-cursor-timer 'timer-1))
            (setq reported-width 20)
            (textui--maybe-refresh-for-width)
            (should-not cursor-type)
            (should (eq textui--cursor-type-before-resize 'box))
            (should (equal cancelled '(timer-1)))
            (should (eq textui--resize-cursor-timer 'timer-2))
            (apply (nth 2 scheduled) (nth 3 scheduled))
            (should (eq cursor-type 'box))
            (should-not textui--resize-cursor-timer)))
      (kill-buffer buffer))))

(ert-deftest textui-visible-width-does-not-create-continuation-lines ()
  (let ((buffer (generate-new-buffer " *textui-screen-width-test*")))
    (unwind-protect
        (save-window-excursion
          (let ((window (selected-window)))
            (set-window-buffer window buffer)
            (with-current-buffer buffer
              (textui-mode)
              (setq-local
               textui--render-function
               (lambda (_width)
                 '((:type :flex :direction :column :gap 0
                    :children
                    ((:type item :format "%v" :value "one")
                     (:type item :format "%v" :value "two"))))))
              (textui-refresh buffer)
              (should (= (length (split-string (buffer-string) "\n")) 2))
              (should (= (count-screen-lines
                          (point-min) (point-max) nil window)
                         2)))))
      (kill-buffer buffer))))

(ert-deftest textui-refresh-clears-stale-horizontal-scroll ()
  (let ((buffer (generate-new-buffer " *textui-hscroll-test*")))
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer buffer)
          (textui-mode)
          (setq-local textui--last-width 20)
          (setq-local textui--render-function
                      (lambda (_width)
                        '((:type item :format "%v" :value "short"))))
          (set-window-hscroll (selected-window) 5)
          (textui-refresh buffer)
          (should (= (window-hscroll) 0)))
      (kill-buffer buffer))))

(ert-deftest textui-hidden-refresh-reuses-last-successful-width ()
  (let (widths
        (buffer (generate-new-buffer " *textui-hidden-width-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 27)
          (setq-local textui--render-function
                      (lambda (width)
                        (push width widths)
                        nil))
          (cl-letf (((symbol-function 'textui--visible-width)
                     (lambda (_buffer) nil)))
            (textui-refresh buffer))
          (should (equal widths '(27))))
      (kill-buffer buffer))))

(ert-deftest textui-open-reuses-one-stable-buffer ()
  (let ((name "*textui-open-test*"))
    (unwind-protect
        (save-window-excursion
          (let ((first (textui-open
                        name
                        (lambda (_width)
                          '((:type item :format "%v" :value "first"))))))
            (should (eq first
                        (textui-open
                         name
                         (lambda (_width)
                           '((:type item :format "%v" :value "second"))))))
            (with-current-buffer first
              (should (derived-mode-p 'textui-mode))
              (should (equal (buffer-string) "second")))))
      (when (get-buffer name)
        (kill-buffer name)))))

(ert-deftest textui-open-installs-or-preserves-buffer-state ()
  (let ((name "*textui-open-state-test*")
        (render (lambda (_width)
                  (list (list :type 'item :format "%v"
                              :value (number-to-string
                                      (plist-get textui-state :count)))))))
    (unwind-protect
        (save-window-excursion
          (let ((buffer (textui-open name render '(:count 1))))
            (with-current-buffer buffer
              (should (equal (buffer-string) "1"))
              (setq textui-state '(:count 2)))
            (textui-open name render)
            (with-current-buffer buffer
              (should (equal textui-state '(:count 2)))
              (should (equal (buffer-string) "2")))
            (textui-open name render '(:count 3))
            (with-current-buffer buffer
              (should (equal (buffer-string) "3")))))
      (when (get-buffer name)
        (kill-buffer name)))))

(ert-deftest textui-open-refuses-an-existing-non-textui-buffer ()
  (let* ((name "*textui-open-conflict-test*")
         (buffer (get-buffer-create name)))
    (unwind-protect
        (should-error (textui-open name (lambda (_width) nil)))
      (kill-buffer buffer))))

(ert-deftest textui-focus-restores-after-native-command-finishes ()
  (let ((state "hello")
        (buffer (generate-new-buffer " *textui-focus-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local textui--last-width 50)
          (setq-local
           textui--render-function
           (lambda (_width)
             (list
              `(:type :flex :direction :row :gap 2
                :children
                ((:type editable-field :format "%v" :size 12 :value ,state
                  :layout (:focus-id input)
                  :notify ,(lambda (widget &rest _)
                             (setq state (widget-value widget))))
                 (:type push-button :value "Redraw"
                  :layout (:focus-id redraw)
                  :action ,(lambda (&rest _) nil)))))))
          (textui-refresh buffer)
          (let* ((anchor (assoc 'input textui--focus-anchors))
                 (expected-offset 2))
            (goto-char (+ (nth 1 anchor) expected-offset))
            (textui--remember-focus)
            (let* ((button (cl-find-if
                            (lambda (widget) (eq (car widget) 'push-button))
                            textui--widgets))
                   (this-command 'widget-button-click))
              (goto-char (widget-get button :from))
              (widget-apply-action button))
            ;; This simulates widget-button-click restoring its stale marker.
            (goto-char (point-min))
            (textui--restore-focus-after-command)
            (setq anchor (assoc 'input textui--focus-anchors))
            (should (= (- (point) (nth 1 anchor)) expected-offset))))
      (kill-buffer buffer))))

(ert-deftest textui-refresh-preserves-cursor-window-row ()
  (let ((buffer (generate-new-buffer " *textui-viewport-test*")))
    (unwind-protect
        (save-window-excursion
          (let ((window (selected-window)))
            (set-window-buffer window buffer)
            (with-current-buffer buffer
              (textui-mode)
              (setq-local
               textui--render-function
               (lambda (_width)
                  (list
                  (list :type :flex :direction :column :gap 0
                        :children
                        (cons
                         (list :type 'push-button :value "Refresh"
                               :action (lambda (&rest _) nil))
                         (cl-loop for index from 2 to 40
                                  collect
                                  (list :type 'item :format "%v"
                                        :value
                                        (format "Line %02d" index))))))))
              (textui-refresh buffer)
              (goto-char (point-min))
              (forward-line 23)
              (set-window-start window (point) t)
              (forward-line 5)
              (let ((row (- (line-number-at-pos)
                            (line-number-at-pos (window-start window)))))
                (textui-refresh buffer)
                (should
                 (= (- (line-number-at-pos)
                       (line-number-at-pos (window-start window)))
                    row))
                (goto-char (point-min))
                (forward-line 23)
                (set-window-start window (point) t)
                (forward-line 5)
                (textui--remember-focus)
                (let ((button
                       (cl-find-if
                        (lambda (widget)
                          (eq (car widget) 'push-button))
                        textui--widgets))
                      (this-command 'widget-button-click))
                  (goto-char (widget-get button :from))
                  (widget-apply-action button))
                (goto-char (point-min))
                (textui--restore-focus-after-command)
                (should
                 (= (- (line-number-at-pos)
                       (line-number-at-pos (window-start window)))
                    row))))))
      (kill-buffer buffer))))

(ert-deftest textui-refresh-restores-unkeyed-native-element-after-reflow ()
  (let ((width 25)
        (buffer (generate-new-buffer " *textui-reflow-focus-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--render-function
           (lambda (_width)
             '((:type :flex :direction :row :gap 1
                :children
                ((:type :flex :direction :column :border t
                  :layout (:width 12 :min-width 8)
                  :children ((:type item :format "%v" :value "LEFT")))
                 (:type :flex :direction :column :border t
                  :layout (:width 12 :min-width 8)
                  :children ((:type item :format "%v" :value "RIGHT"))))))))
          (cl-letf (((symbol-function 'textui--visible-width)
                     (lambda (_buffer) width)))
            (textui-refresh buffer)
            (goto-char (point-min))
            (search-forward "RIGHT")
            (backward-char 3)
            (setq width 12)
            (textui-refresh buffer)
            (should (looking-at "GHT"))
            (setq width 25)
            (textui-refresh buffer)
            (should (looking-at "GHT"))))
      (kill-buffer buffer))))

(ert-deftest textui-refresh-restores-space-relative-to-its-layout ()
  (let ((width 25)
        (buffer (generate-new-buffer " *textui-reflow-space-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (textui-mode)
          (setq-local
           textui--render-function
           (lambda (_width)
             '((:type :flex :direction :column :gap 0
                :children
                ((:type :flex :direction :row :gap 1
                  :children
                  ((:type :flex :direction :column :border t
                    :layout (:width 12 :min-width 8)
                    :children ((:type item :format "%v" :value "LEFT")))
                   (:type :flex :direction :column :border t
                    :layout (:width 12 :min-width 8)
                    :children ((:type item :format "%v" :value "RIGHT")))))
                 (:type :flex :direction :column :gap 1 :border t
                  :layout (:width 12 :min-width 8)
                  :children
                  ((:type item :format "%v" :value "HOME")
                   (:type item :format "%v" :value "PROJECTS"))))))))
          (cl-letf (((symbol-function 'textui--visible-width)
                     (lambda (_buffer) width)))
            (textui-refresh buffer)
            (goto-char (point-min))
            (search-forward "HOME")
            (forward-line 1)
            (move-to-column 4)
            (should-not (get-text-property (point) 'textui--location-id))
            (let ((line (line-number-at-pos)))
              (setq width 12)
              (textui-refresh buffer)
              (should (> (line-number-at-pos) line))
              (should (= (current-column) 4))
              (save-excursion
                (forward-line -1)
                (should (search-forward "HOME" (line-end-position) t)))
              (save-excursion
                (forward-line 1)
                (should (search-forward "PROJECTS" (line-end-position) t))))))
      (kill-buffer buffer))))

(ert-deftest textui-mode-handles-repeated-mouse-releases ()
  (should (eq (lookup-key textui-mode-map [double-down-mouse-1]) #'ignore))
  (should (eq (lookup-key textui-mode-map [triple-down-mouse-1]) #'ignore))
  (should (eq (lookup-key textui-mode-map [double-mouse-1])
              #'textui--widget-button-release))
  (should (eq (lookup-key textui-mode-map [triple-mouse-1])
              #'textui--widget-button-release)))

(ert-deftest textui-refresh-dead-buffer-returns-nil ()
  (let ((buffer (generate-new-buffer " *textui-dead-test*")))
    (kill-buffer buffer)
    (should-not (textui-refresh buffer))))

(ert-deftest textui-refresh-rejects-a-non-textui-buffer ()
  (let ((buffer (generate-new-buffer " *textui-wrong-mode-test*")))
    (unwind-protect
        (should-error (textui-refresh buffer))
      (kill-buffer buffer))))

(provide 'textui-test)
;;; textui-test.el ends here
