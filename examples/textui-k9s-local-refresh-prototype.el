;;; textui-k9s-local-refresh-prototype.el --- K9s local-refresh demo -*- lexical-binding: t; -*-

;; Demonstrates one coherent K9s-style buffer backed by 10,000 rows.  Scrolling
;; replaces only the visible viewport region, including near the end of data.
;;
;; Run:
;; emacs -Q -L . -L examples -l examples/textui-k9s-local-refresh-prototype.el

;;; Code:

(require 'cl-lib)
(require 'face-remap)
(require 'textui)

;; The retained one-buffer demo owns its visual vocabulary.  It intentionally
;; does not depend on the rejected three-buffer shell experiment.

(defface textui-tui-app-default-face
  '((t :foreground "#f2f2f2" :background "#000000" :extend t))
  "Default face for the K9s demo."
  :group 'widget-faces)

(defface textui-tui-app-border-face
  '((t :foreground "#62d9e8" :background "#000000"))
  "Cyan table border face."
  :group 'widget-faces)

(defface textui-tui-app-header-face
  '((t :foreground "#000000" :background "#62e4e8" :weight bold))
  "High-contrast resource header face."
  :group 'widget-faces)

(defface textui-tui-app-value-face
  '((t :foreground "#ffb000" :background "#000000" :weight bold))
  "Context value and logo face."
  :group 'widget-faces)

(defface textui-tui-app-key-face
  '((t :foreground "#00aeea" :background "#000000" :weight bold))
  "Shortcut key face."
  :group 'widget-faces)

(defface textui-tui-app-scope-face
  '((t :foreground "#ff5de4" :background "#000000" :weight bold))
  "Scope shortcut face."
  :group 'widget-faces)

(defface textui-tui-app-muted-face
  '((t :foreground "#858585" :background "#000000"))
  "Secondary shortcut label face."
  :group 'widget-faces)

(defface textui-tui-app-row-face
  '((t :foreground "#f2f2f2" :background "#000000"))
  "Default resource row face."
  :group 'widget-faces)

(defface textui-tui-app-system-row-face
  '((t :foreground "#a8ff00" :background "#000000"))
  "System resource row face."
  :group 'widget-faces)

(defface textui-tui-app-selected-face
  '((t :foreground "#000000" :background "#62e4e8" :weight bold))
  "Selected resource row face."
  :group 'widget-faces)

(define-widget 'textui-tui-app-row 'push-button
  "Full-width textual resource row."
  :button-prefix ""
  :button-suffix ""
  :value-create
  (lambda (widget)
    (insert (widget-value widget))))

(defvar textui-tui-app--pods nil)
(defvar textui-tui-app-scope 'all)
(defvar textui-tui-app-selected nil)

(defun textui-tui-app--item (value &optional width face)
  "Return a one-line item for VALUE with optional WIDTH and FACE."
  (let ((text (format "%s" value)))
    (when face
      (add-face-text-property 0 (length text) face nil text))
    (append (list :type 'item :format "%v" :value text)
            (when width (list :layout (list :width width))))))

(defun textui-tui-app--fit (value width)
  "Return VALUE truncated or padded to exactly WIDTH cells."
  (let* ((short (truncate-string-to-width value width nil nil ""))
         (missing (- width (string-width short))))
    (concat short (make-string (max 0 missing) ?\s))))

(defun textui-tui-app--context-row (label value)
  "Return a K9s-style context LABEL and VALUE row."
  (list :type :flex :direction :row :gap 0
        :children
        (list (textui-tui-app--item label 14 'textui-tui-app-row-face)
              (textui-tui-app--item value nil 'textui-tui-app-value-face))))

(defun textui-tui-app--shortcut-row (key label)
  "Return a shortcut KEY and LABEL row."
  (list :type :flex :direction :row :gap 0
        :children
        (list (textui-tui-app--item key 10 'textui-tui-app-key-face)
              (textui-tui-app--item label nil 'textui-tui-app-muted-face))))

(defun textui-tui-app--scope-row (key scope)
  "Return an interactive scope row for KEY and SCOPE."
  (list :type :flex :direction :row :gap 0
        :children
        (list
         (textui-tui-app--item key 5 'textui-tui-app-scope-face)
         (list :type 'link
               :tag (if (symbolp scope) (symbol-name scope) scope)
               :value scope
               :button-prefix ""
               :button-suffix ""
               :button-face (if (equal scope textui-tui-app-scope)
                                'textui-tui-app-row-face
                              'textui-tui-app-muted-face)
               :layout (list :focus-id
                             (intern (format "scope-%s" scope)))
               :action (lambda (&rest _)
                         (setq textui-tui-app-scope scope
                               textui-tui-app-selected nil))))))

(defun textui-tui-app--logo ()
  "Return the TextUI logo used in the K9s reference composition."
  (list :type :text
        :value
        (propertize
         (mapconcat
          #'identity
          '("                              "
            "       ╔╦╗╔═╗═╗ ╦╔╦╗╦ ╦╦     "
            "        ║ ║╣ ╔╩╦╝ ║ ║ ║║     "
            "        ╩ ╚═╝╩ ╚═ ╩ ╚═╝╩     "
            "                              "
            "                              "
            "                              ")
          "\n")
         'face 'textui-tui-app-value-face)
        :layout '(:width 30 :min-width 28)))

(defun textui-tui-app--top-area ()
  "Return the responsive K9s information area."
  (list
   :type :flex :direction :row :gap 2
   :children
   (list
    (list :type :flex :direction :column :gap 0
          :layout '(:width 34 :min-width 28)
          :children
          (list
           (textui-tui-app--context-row "Context:" "minikube")
           (textui-tui-app--context-row "Cluster:" "minikube")
           (textui-tui-app--context-row "User:" "minikube")
           (textui-tui-app--context-row "K9s Version:" "0.1.6")
           (textui-tui-app--context-row "K8s Version:" "v1.13.2")
           (textui-tui-app--context-row "CPU:" "10%(-)")
           (textui-tui-app--context-row "MEM:" "20%(+)")))
    (list :type :flex :direction :column :gap 0
          :layout '(:width 20 :min-width 18)
          :children
          (list
           (textui-tui-app--shortcut-row "<?>" "Help")
           (textui-tui-app--shortcut-row "<ctrl-d>" "Delete")
           (textui-tui-app--shortcut-row "<d>" "Describe")
           (textui-tui-app--shortcut-row "<e>" "Edit")
           (textui-tui-app--shortcut-row "<l>" "Logs")
           (textui-tui-app--shortcut-row "<s>" "Shell")
           (textui-tui-app--shortcut-row "<j/k>" "Scroll")))
    (list :type :flex :direction :column :gap 0
          :layout '(:width 18 :min-width 16)
          :children
          (list
           (textui-tui-app--scope-row "<0>" 'all)
           (textui-tui-app--scope-row "<1>" "kube-system")
           (textui-tui-app--scope-row "<2>" "default")))
    (list :type :text :value " "
          :layout '(:width 1 :min-width 1 :grow 1))
    (textui-tui-app--logo))))

(defun textui-tui-app--visible-pods ()
  "Return rows visible in `textui-tui-app-scope'."
  (if (eq textui-tui-app-scope 'all)
      textui-tui-app--pods
    (cl-remove-if-not
     (lambda (row) (string= (car row) textui-tui-app-scope))
     textui-tui-app--pods)))

(defun textui-tui-app--table-text (columns)
  "Format COLUMNS in the reference table's fixed column tracks."
  (apply #'format
         "%-13s%-39s%-7s%-10s%-10s%-8s%-10s%-16s%-16s%-14s%-5s"
         columns))

(defun textui-tui-app--top-border (width title)
  "Return a centered TITLE border of WIDTH cells."
  (let* ((body (max 0 (- width 2)))
         (short (truncate-string-to-width title (max 0 (- body 2))))
         (token (if (string-empty-p short) "" (format " %s " short)))
         (remaining (max 0 (- body (string-width token))))
         (left (/ remaining 2)))
    (concat "┏" (make-string left ?━) token
            (make-string (- remaining left) ?━) "┓")))

(defun textui-tui-app--framed-line (value width face &optional row focus-id)
  "Return VALUE in a WIDTH-cell cyan frame using FACE.
When ROW is non-nil, make the inner line interactive at FOCUS-ID."
  (let* ((inner (max 1 (- width 2)))
         (text (textui-tui-app--fit value inner))
         (middle
          (if row
              (list :type 'textui-tui-app-row
                    :value text
                    :button-face face
                    :layout (list :focus-id focus-id)
                    :action
                    (lambda (&rest _)
                      (setq textui-tui-app-selected
                            (list (nth 0 row) (nth 1 row)))))
            (textui-tui-app--item text inner face))))
    (list :type :flex :direction :row :gap 0
          :children
          (list
           (textui-tui-app--item "┃" 1 'textui-tui-app-border-face)
           middle
           (textui-tui-app--item "┃" 1 'textui-tui-app-border-face)))))

(defun textui-tui-app--row-face (row)
  "Return the semantic face for ROW."
  (cond
   ((equal textui-tui-app-selected (list (nth 0 row) (nth 1 row)))
    'textui-tui-app-selected-face)
   ((string= (car row) "kube-system")
    'textui-tui-app-system-row-face)
   (t 'textui-tui-app-row-face)))

(defun textui-tui-app--header-frame (width)
  "Return the responsive top area and table header for WIDTH."
  (let* ((rows (textui-tui-app--visible-pods))
         (scope (if (symbolp textui-tui-app-scope)
                    (symbol-name textui-tui-app-scope)
                  textui-tui-app-scope))
         (columns (textui-tui-app--table-text
                   '("NAMESPACE" "NAME" "READY" "STATUS" "RESTARTS"
                     "CPU" "MEM" "IP" "NODE" "QOS" "AGE"))))
    (list
     (list
      :type :flex :direction :column :gap 1
      :children
      (list
       (textui-tui-app--top-area)
       (list
        :type :flex :direction :column :gap 0
        :children
        (list
         (textui-tui-app--item
          (textui-tui-app--top-border
           width (format "Pods(%s)[%d]" scope (length rows)))
          width 'textui-tui-app-border-face)
         (textui-tui-app--framed-line
          columns width 'textui-tui-app-header-face))))))))

(defun textui-tui-app--footer-frame (width)
  "Return the table bottom border for WIDTH."
  (list
   (textui-tui-app--item
    (concat "┗" (make-string (max 0 (- width 2)) ?━) "┛")
    width 'textui-tui-app-border-face)))

(defconst textui-k9s-local-refresh-prototype--buffer-name
  "*TextUI K9s Local Refresh DEMO*")
(defconst textui-k9s-local-refresh-prototype--row-count 10000)

(defvar-local textui-k9s-local-refresh-prototype--state nil)
(defvar-local textui-k9s-local-refresh-prototype--page-size 12)
(defvar-local textui-k9s-local-refresh-prototype--data nil)
(defvar-local textui-k9s-local-refresh-prototype--visible-rows nil)
(defvar-local textui-k9s-local-refresh-prototype--visible-scope nil)
(defvar-local textui-k9s-local-refresh-prototype--load-ms 0.0)
(defvar-local textui-k9s-local-refresh-prototype--filter-ms 0.0)
(defvar-local textui-k9s-local-refresh-prototype--patch-count 0)
(defvar-local textui-k9s-local-refresh-prototype--last-patch-ms 0.0)
(defvar-local textui-k9s-local-refresh-prototype--full-render-count 0)
(defvar-local textui-k9s-local-refresh-prototype--last-scope nil)
(defvar-local textui-k9s-local-refresh-prototype--face-cookie nil)

(defun textui-k9s-local-refresh-prototype--make-row (index)
  "Return one deterministic fake pod row for INDEX."
  (let* ((namespaces ["default" "kube-system" "monitoring"
                      "production" "staging"])
         (services ["api" "web" "worker" "metrics" "gateway"
                    "scheduler" "redis" "controller"])
         (namespace (aref namespaces (% index (length namespaces))))
         (service (aref services (% index (length services))))
         (pending (= (% index 97) 0))
         (crashing (= (% index 211) 0)))
    (list
     namespace
     (format "%s-%05d-%04x" service index (% (* index 7919) 65536))
     (if (or pending crashing) "0/1" "1/1")
     (cond (crashing "CrashLoop")
           (pending "Pending")
           (t "Running"))
     (number-to-string (if crashing (1+ (% index 8)) (% index 2)))
     (format "%dm" (1+ (% (* index 7) 950)))
     (format "%dMi" (+ 8 (% (* index 13) 2048)))
     (format "10.%d.%d.%d"
             (% (/ index 65536) 256)
             (% (/ index 256) 256)
             (% index 256))
     (format "node-%02d.internal" (% index 48))
     (if (= (% index 4) 0) "Guaranteed" "Burstable")
     (format "%dh" (1+ (% index 240))))))

(defun textui-k9s-local-refresh-prototype--make-data (count)
  "Return a vector containing COUNT deterministic fake pod rows."
  (let ((rows (make-vector count nil))
        (index 0))
    (while (< index count)
      (aset rows index
            (textui-k9s-local-refresh-prototype--make-row index))
      (setq index (1+ index)))
    rows))

(defun textui-k9s-local-refresh-prototype--current-rows ()
  "Return the cached rows for the current K9s scope."
  (unless (equal textui-k9s-local-refresh-prototype--visible-scope
                 textui-tui-app-scope)
    (let ((started (float-time)))
      (setq textui-k9s-local-refresh-prototype--visible-scope
            textui-tui-app-scope
            textui-k9s-local-refresh-prototype--visible-rows
            (if (eq textui-tui-app-scope 'all)
                textui-k9s-local-refresh-prototype--data
              (vconcat
               (seq-filter
                (lambda (row)
                  (string= (car row) textui-tui-app-scope))
                textui-k9s-local-refresh-prototype--data)))
            textui-k9s-local-refresh-prototype--filter-ms
            (* 1000.0 (- (float-time) started)))))
  textui-k9s-local-refresh-prototype--visible-rows)

(defun textui-k9s-local-refresh-prototype--reduce
    (state action row-count page-size)
  "Return the next viewport STATE after ACTION.
ROW-COUNT and PAGE-SIZE define the legal offset range."
  (let* ((maximum (max 0 (- row-count page-size)))
         (offset (or (plist-get state :offset) 0))
         (next
          (pcase action
            (`(:scroll ,amount) (+ offset amount))
            (:home 0)
            (:end maximum)
            (_ offset))))
    (plist-put (copy-sequence state) :offset
               (max 0 (min maximum next)))))

(defun textui-k9s-local-refresh-prototype--page-size-for-height
    (body-height header-lines)
  "Return rows fitting BODY-HEIGHT below HEADER-LINES and one footer."
  (max 1 (- body-height header-lines 1)))

(defun textui-k9s-local-refresh-prototype--visible-height ()
  "Return the smallest body height displaying the prototype buffer."
  (let (heights)
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (push (window-body-height window) heights))
    (when heights
      (apply #'min heights))))

(defun textui-k9s-local-refresh-prototype--header-line-count (width)
  "Return the responsive header height at WIDTH."
  (let ((textui-tui-app--pods
         textui-k9s-local-refresh-prototype--data))
    (length
     (split-string
      (textui--render-frame
       (textui-tui-app--header-frame width) width)
      "\n"))))

(defun textui-k9s-local-refresh-prototype--sync-page-size (width)
  "Update the viewport row count for the current window and WIDTH."
  (let ((height (textui-k9s-local-refresh-prototype--visible-height)))
    (when height
      (let ((next
             (textui-k9s-local-refresh-prototype--page-size-for-height
              height
              (textui-k9s-local-refresh-prototype--header-line-count
               width))))
        (unless (= next textui-k9s-local-refresh-prototype--page-size)
          (setq textui-k9s-local-refresh-prototype--page-size next
                textui-k9s-local-refresh-prototype--state
                (textui-k9s-local-refresh-prototype--reduce
                 textui-k9s-local-refresh-prototype--state
                 '(:scroll 0)
                 (length
                  (textui-k9s-local-refresh-prototype--current-rows))
                 next)))))))

(defun textui-k9s-local-refresh-prototype--rows ()
  "Return the fixed-height visible row slice."
  (let* ((rows (textui-k9s-local-refresh-prototype--current-rows))
         (maximum
          (max 0 (- (length rows)
                    textui-k9s-local-refresh-prototype--page-size)))
         (start
          (min maximum
               (or (plist-get textui-k9s-local-refresh-prototype--state
                              :offset)
                   0))))
    (append
     (seq-subseq
      rows start
      (min (length rows)
           (+ start textui-k9s-local-refresh-prototype--page-size)))
     nil)))

(defun textui-k9s-local-refresh-prototype--row-elements (width)
  "Return the fixed-height viewport children for WIDTH."
  (let ((rows (textui-k9s-local-refresh-prototype--rows))
        children)
    (dolist (row rows)
      (let* ((line
              (textui-tui-app--framed-line
               (textui-tui-app--table-text row)
               width (textui-tui-app--row-face row) row
               (intern (format "pod-%s-%s" (nth 0 row) (nth 1 row)))))
             (control (cadr (plist-get line :children)))
             (action (plist-get control :action)))
        (plist-put
         control :action
         (lambda (&rest arguments)
           (apply action arguments)
           (textui-k9s-local-refresh-prototype--patch-rows)))
        (push line children)))
    (dotimes (_ (- textui-k9s-local-refresh-prototype--page-size
                   (length rows)))
      (push
       (textui-tui-app--framed-line
        "" width 'textui-tui-app-row-face)
       children))
    (nreverse children)))

(defun textui-k9s-local-refresh-prototype--rows-element (width)
  "Return the locally refreshable viewport element for WIDTH."
  (list :type :flex :direction :column :gap 0
        :layout '(:refresh-id rows)
        :children
        (textui-k9s-local-refresh-prototype--row-elements width)))

(defun textui-k9s-local-refresh-prototype--frame (width)
  "Return the complete single-buffer K9s frame for WIDTH."
  (setq textui-k9s-local-refresh-prototype--full-render-count
        (1+ textui-k9s-local-refresh-prototype--full-render-count))
  (let ((textui-tui-app--pods
         textui-k9s-local-refresh-prototype--data))
    (textui-k9s-local-refresh-prototype--sync-page-size width)
    (list
     (list
      :type :flex :direction :column :gap 0
      :children
      (list
       (car (textui-tui-app--header-frame width))
       (textui-k9s-local-refresh-prototype--rows-element width)
       (car (textui-tui-app--footer-frame width)))))))

(defun textui-k9s-local-refresh-prototype--patch-rows ()
  "Refresh only the row region and record its cost."
  (let* ((started (float-time))
         (buffer (current-buffer)))
    (textui-refresh-region
     buffer 'rows
     #'textui-k9s-local-refresh-prototype--row-elements)
    (setq textui-k9s-local-refresh-prototype--patch-count
          (1+ textui-k9s-local-refresh-prototype--patch-count)
          textui-k9s-local-refresh-prototype--last-patch-ms
          (* 1000.0 (- (float-time) started)))
    (force-mode-line-update)))

(defun textui-k9s-local-refresh-prototype--dispatch (action)
  "Apply viewport ACTION and patch rows when its state changes."
  (let* ((rows (textui-k9s-local-refresh-prototype--current-rows))
         (next
          (textui-k9s-local-refresh-prototype--reduce
           textui-k9s-local-refresh-prototype--state
           action (length rows)
           textui-k9s-local-refresh-prototype--page-size)))
    (unless (equal next textui-k9s-local-refresh-prototype--state)
      (setq textui-k9s-local-refresh-prototype--state next)
      (textui-k9s-local-refresh-prototype--patch-rows))))

(defun textui-k9s-local-refresh-prototype-scroll-down ()
  "Move the local viewport down one row."
  (interactive)
  (textui-k9s-local-refresh-prototype--dispatch '(:scroll 1)))

(defun textui-k9s-local-refresh-prototype-scroll-up ()
  "Move the local viewport up one row."
  (interactive)
  (textui-k9s-local-refresh-prototype--dispatch '(:scroll -1)))

(defun textui-k9s-local-refresh-prototype-page-down ()
  "Move the local viewport down one page."
  (interactive)
  (textui-k9s-local-refresh-prototype--dispatch
   `(:scroll ,textui-k9s-local-refresh-prototype--page-size)))

(defun textui-k9s-local-refresh-prototype-page-up ()
  "Move the local viewport up one page."
  (interactive)
  (textui-k9s-local-refresh-prototype--dispatch
   `(:scroll ,(- textui-k9s-local-refresh-prototype--page-size))))

(defun textui-k9s-local-refresh-prototype--after-full-refresh ()
  "Refresh rows when scope or usable viewport height changed."
  (when (and (derived-mode-p 'textui-mode)
             (equal (buffer-name)
                    textui-k9s-local-refresh-prototype--buffer-name)
             (> (buffer-size) 0))
    (let ((old-page-size textui-k9s-local-refresh-prototype--page-size)
          (scope-changed
           (not (equal textui-k9s-local-refresh-prototype--last-scope
                       textui-tui-app-scope))))
      (when scope-changed
        (setq textui-k9s-local-refresh-prototype--last-scope
              textui-tui-app-scope
              textui-k9s-local-refresh-prototype--state '(:offset 0)))
      (textui-k9s-local-refresh-prototype--sync-page-size
       (textui--available-width (current-buffer)))
      (when (or scope-changed
                (/= old-page-size
                    textui-k9s-local-refresh-prototype--page-size))
        (textui-k9s-local-refresh-prototype--patch-rows)))))

(defun textui-k9s-local-refresh-prototype--install-keys ()
  "Install local viewport commands in the prototype buffer."
  (let ((map (copy-keymap (current-local-map))))
    (dolist (key '("j" "n" "\C-n" [wheel-down] [mouse-5]))
      (define-key map key
                  #'textui-k9s-local-refresh-prototype-scroll-down))
    (dolist (key '("k" "p" "\C-p" [wheel-up] [mouse-4]))
      (define-key map key
                  #'textui-k9s-local-refresh-prototype-scroll-up))
    (define-key map [next]
                #'textui-k9s-local-refresh-prototype-page-down)
    (define-key map [prior]
                #'textui-k9s-local-refresh-prototype-page-up)
    (define-key map (kbd "<home>")
                (lambda ()
                  (interactive)
                  (textui-k9s-local-refresh-prototype--dispatch :home)))
    (define-key map (kbd "<end>")
                (lambda ()
                  (interactive)
                  (textui-k9s-local-refresh-prototype--dispatch :end)))
    (use-local-map map)))

(defun textui-k9s-local-refresh-prototype-open ()
  "Open the single-buffer local-refresh prototype."
  (interactive)
  (let ((buffer
         (get-buffer-create
          textui-k9s-local-refresh-prototype--buffer-name))
        (started (float-time))
        data)
    (setq data
          (textui-k9s-local-refresh-prototype--make-data
           textui-k9s-local-refresh-prototype--row-count))
    (with-current-buffer buffer
      (unless (derived-mode-p 'textui-mode)
        (textui-mode))
      (setq-local textui-k9s-local-refresh-prototype--data data
                  textui-k9s-local-refresh-prototype--page-size 12
                  textui-k9s-local-refresh-prototype--visible-rows nil
                  textui-k9s-local-refresh-prototype--visible-scope nil
                  textui-k9s-local-refresh-prototype--load-ms
                  (* 1000.0 (- (float-time) started))
                  textui-k9s-local-refresh-prototype--filter-ms 0.0
                  textui-k9s-local-refresh-prototype--state '(:offset 0)
                  textui-k9s-local-refresh-prototype--patch-count 0
                  textui-k9s-local-refresh-prototype--last-patch-ms 0.0
                  textui-k9s-local-refresh-prototype--full-render-count 0
                  textui-k9s-local-refresh-prototype--last-scope
                  textui-tui-app-scope))
    (textui-open textui-k9s-local-refresh-prototype--buffer-name
                 #'textui-k9s-local-refresh-prototype--frame)
    (with-current-buffer buffer
      (setq-local line-spacing nil
                  truncate-lines t
                  mode-line-format
                  '("  LOCAL VIEWPORT  "
                    (:eval
                     (format
                      "loaded %d in %.1f ms | scope %d in %.1f ms | viewport %d | offset %d/%d | patch %d: %.3f ms | full %d"
                      (length textui-k9s-local-refresh-prototype--data)
                      textui-k9s-local-refresh-prototype--load-ms
                      (length
                       (textui-k9s-local-refresh-prototype--current-rows))
                      textui-k9s-local-refresh-prototype--filter-ms
                      textui-k9s-local-refresh-prototype--page-size
                      (or (plist-get
                           textui-k9s-local-refresh-prototype--state
                           :offset)
                          0)
                      (max
                       0
                       (- (length
                           (textui-k9s-local-refresh-prototype--current-rows))
                          textui-k9s-local-refresh-prototype--page-size))
                      textui-k9s-local-refresh-prototype--patch-count
                      textui-k9s-local-refresh-prototype--last-patch-ms
                      textui-k9s-local-refresh-prototype--full-render-count))))
      (unless textui-k9s-local-refresh-prototype--face-cookie
        (setq textui-k9s-local-refresh-prototype--face-cookie
              (face-remap-add-relative
               'default 'textui-tui-app-default-face)))
      (textui-k9s-local-refresh-prototype--install-keys)
      (add-hook 'post-command-hook
                #'textui-k9s-local-refresh-prototype--after-full-refresh
                t t)
      (add-hook 'window-configuration-change-hook
                #'textui-k9s-local-refresh-prototype--after-full-refresh
                t t))
    buffer))

(unless noninteractive
  (set-frame-size (selected-frame) 151 27)
  (textui-k9s-local-refresh-prototype-open)
  (set-frame-name "TextUI — K9s 10K adaptive viewport demo"))

(provide 'textui-k9s-local-refresh-prototype)

;;; textui-k9s-local-refresh-prototype.el ends here
