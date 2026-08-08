;;; textui-yazi-prototype.el --- Yazi-like UI demo -*- lexical-binding: t; -*-

;; Demonstrates Yazi's three-pane context, responsive collapse, selection,
;; native image preview, and keyboard/mouse navigation in one TextUI buffer.
;; Directory data is deterministic and lives in memory.
;;
;; Run:
;; emacs -Q -L . -l examples/textui-yazi-prototype.el

;;; Code:

(require 'cl-lib)
(require 'textui)

(defgroup textui-yazi-prototype nil
  "Yazi-like TextUI demo."
  :group 'convenience)

(defconst textui-yazi-prototype--buffer-name
  "*TextUI Yazi DEMO*")

(defconst textui-yazi-prototype--image-file
  (expand-file-name
   "textui-yazi-preview.png"
   (file-name-directory (or load-file-name buffer-file-name)))
  "Image used by the Yazi preview experiment.")

(defface textui-yazi-prototype-default-face
  '((t (:background "#0b0f14" :foreground "#c8d3f5")))
  "Default face for the Yazi prototype."
  :group 'textui-yazi-prototype)

(defface textui-yazi-prototype-muted-face
  '((t (:foreground "#64748b")))
  "Muted face for separators and secondary text."
  :group 'textui-yazi-prototype)

(defface textui-yazi-prototype-directory-face
  '((t (:foreground "#7dcfff" :weight bold)))
  "Directory face for the Yazi prototype."
  :group 'textui-yazi-prototype)

(defface textui-yazi-prototype-file-face
  '((t (:foreground "#c8d3f5")))
  "File face for the Yazi prototype."
  :group 'textui-yazi-prototype)

(defface textui-yazi-prototype-selected-face
  '((t (:background "#7dcfff" :foreground "#0b0f14" :weight bold)))
  "Hovered-entry face for the Yazi prototype."
  :group 'textui-yazi-prototype)

(defface textui-yazi-prototype-mode-face
  '((t (:background "#c3e88d" :foreground "#0b0f14" :weight bold)))
  "Mode-pill face for the Yazi prototype."
  :group 'textui-yazi-prototype)

(defface textui-yazi-prototype-accent-face
  '((t (:foreground "#ffc777" :weight bold)))
  "Accent face for the Yazi prototype."
  :group 'textui-yazi-prototype)

(define-widget 'textui-yazi-prototype-row 'push-button
  "Clickable file-manager row used by the Yazi prototype."
  :button-prefix ""
  :button-suffix ""
  :value-create
  (lambda (widget)
    (insert (widget-value widget))))

(defconst textui-yazi-prototype--directories
  '((packages
     :path "~/Documents/emacs/package"
     :parent nil
     :entries
     ((:name "oil" :type dir)
      (:name "org-ai" :type dir)
      (:name "org-contacts" :type dir)
      (:name "org-luhmann" :type dir)
      (:name "org-node" :type dir)
      (:name "org-supertag" :type dir)
      (:name "superchat" :type dir)
      (:name "textui" :type dir :target textui)
      (:name "tui.el" :type dir)
      (:name "widget-music" :type dir)
      (:name "figure16.png" :type file :size "84K")))
    (textui
     :path "~/Documents/emacs/package/textui"
     :parent packages
     :entries
     ((:name "../figure16.png" :type file :size "129K" :image t)
      (:name "docs" :type dir :target docs :size "128B")
      (:name "examples" :type dir :target examples :size "416B")
      (:name "test" :type dir :size "256B")
      (:name "CONTEXT.md" :type file :size "12K"
       :preview ("# TextUI" "" "TextUI provides automatic layout for"
                 "declarative, interactive text interfaces in Emacs."))
      (:name "COPYING" :type file :size "35K"
       :preview ("GNU GENERAL PUBLIC LICENSE" "" "Version 3, 29 June 2007"))
      (:name "README.md" :type file :size "6.0K"
       :preview ("# TextUI" "" "Automatic layout for declarative,"
                 "interactive text interfaces in Emacs."))
      (:name "textui-kp-core.el" :type file :size "23K")
      (:name "textui.el" :type file :size "59K"
       :preview (";;; textui.el --- Declarative text interfaces for Emacs"
                 "" "(require 'cl-lib)" "(require 'subr-x)"
                 "(require 'wid-edit)" ""
                 ";; Layout, widgets, refresh regions, and focus."))))
    (examples
     :path "~/Documents/emacs/package/textui/examples"
     :parent textui
     :entries
     ((:name "textui-responsive-demo.el" :type file :size "3K")
      (:name "textui-grid-gallery.el" :type file :size "7K")
      (:name "textui-k9s-local-refresh-prototype.el" :type file :size "28K")
      (:name "textui-lazygit-prototype.el" :type file :size "25K")
      (:name "textui-yazi-prototype.el" :type file :size "21K")
      (:name "textui-btop-prototype.el" :type file :size "44K")
      (:name "textui-yazi-preview.png" :type file :size "1.1M")))
    (docs
     :path "~/Documents/emacs/package/textui/docs"
     :parent textui
     :entries
     ((:name "adr" :type dir :target adr :size "1.1K")
      (:name "widget-compatibility.md" :type file :size "4.8K"
       :preview ("# Widget compatibility" ""
                 "TextUI presents ordinary widget.el controls"
                 "inside width-aware layouts."))))
    (adr
     :path "~/Documents/emacs/package/textui/docs/adr"
     :parent docs
     :entries
     ((:name "0001-render-functions-not-registered-views.md" :type file :size "1.2K")
      (:name "0012-textui-is-a-layout-engine-not-a-widget-library.md" :type file :size "1.1K")
      (:name "0025-grid-starts-with-equal-responsive-tracks.md" :type file :size "847B")
      (:name "0026-textui-does-not-own-multi-buffer-app-shells.md" :type file :size "5.4K")
      (:name "0027-refresh-regions-replace-whole-line-blocks.md" :type file :size "735B"))))
  "Fake directory tree used by the Yazi prototype.")

(defvar-local textui-yazi-prototype--directory 'textui)
(defvar-local textui-yazi-prototype--cursor 0)
(defvar-local textui-yazi-prototype--selected nil)
(defvar-local textui-yazi-prototype--page-size 20)
(defvar-local textui-yazi-prototype--full-renders 0)
(defvar-local textui-yazi-prototype--region-refreshes 0)
(defvar-local textui-yazi-prototype--face-cookie nil)

(defun textui-yazi-prototype--directory (id)
  "Return directory metadata for ID."
  (cdr (assq id textui-yazi-prototype--directories)))

(defun textui-yazi-prototype--entries (&optional id)
  "Return entries for directory ID or the current directory."
  (plist-get
   (textui-yazi-prototype--directory
    (or id textui-yazi-prototype--directory))
   :entries))

(defun textui-yazi-prototype--current-entry ()
  "Return the hovered entry."
  (nth textui-yazi-prototype--cursor
       (textui-yazi-prototype--entries)))

(defun textui-yazi-prototype--fit (string width)
  "Return STRING shortened to WIDTH cells."
  (truncate-string-to-width string (max 0 width) nil nil "…"))

(defun textui-yazi-prototype--item (value width &optional face)
  "Return a WIDTH-cell item showing VALUE with FACE."
  (let ((display (if (equal value "") " " value)))
    (list :type 'item :format "%v"
          :value (if face (propertize display 'face face) display)
          :layout (list :width width))))

(defun textui-yazi-prototype--visible-height ()
  "Return the smallest live body height for the prototype buffer."
  (let (heights)
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (push (window-body-height window) heights))
    (if heights (apply #'min heights) 22)))

(defun textui-yazi-prototype--sync-page-size ()
  "Fit the middle viewport between the path and status lines."
  (setq textui-yazi-prototype--page-size
        (max 5 (- (textui-yazi-prototype--visible-height) 2))))

(defun textui-yazi-prototype--slice (entries cursor)
  "Return ENTRIES slice and start offset keeping CURSOR visible."
  (let* ((count (length entries))
         (page (min textui-yazi-prototype--page-size count))
         (start (max 0 (min (- count page)
                            (- cursor (/ page 2))))))
    (cons start (cl-subseq entries start (+ start page)))))

(defun textui-yazi-prototype--entry-label (entry selected)
  "Return one compact label for ENTRY, marking SELECTED."
  (format "%s %s %s%s"
          (if selected "*" " ")
          (if (eq (plist-get entry :type) 'dir) "d" "f")
          (plist-get entry :name)
          (if (eq (plist-get entry :type) 'dir) "/" "")))

(defun textui-yazi-prototype--entry-key (entry)
  "Return selection key for ENTRY."
  (cons textui-yazi-prototype--directory (plist-get entry :name)))

(defun textui-yazi-prototype--selected-p (entry)
  "Return non-nil when ENTRY is selected."
  (member (textui-yazi-prototype--entry-key entry)
          textui-yazi-prototype--selected))

(defun textui-yazi-prototype--pane-widths (width)
  "Return visible pane widths for available WIDTH."
  (cond
   ((>= width 72)
    (let* ((usable (- width 2))
           (left (/ usable 8))
           (middle (/ (* usable 4) 8)))
      (list left middle (- usable left middle))))
   ((>= width 48)
    (let* ((usable (1- width))
           (middle (/ (* usable 4) 7)))
      (list 0 middle (- usable middle))))
   (t (list 0 width 0))))

(defun textui-yazi-prototype--parent-rows ()
  "Return parent entries and the row corresponding to current directory."
  (let* ((parent (plist-get
                  (textui-yazi-prototype--directory
                   textui-yazi-prototype--directory)
                  :parent))
         (entries (and parent (textui-yazi-prototype--entries parent)))
         (index (or (cl-position
                     textui-yazi-prototype--directory entries
                     :key (lambda (entry) (plist-get entry :target)))
                    0)))
    (cons index entries)))

(defun textui-yazi-prototype--preview-lines ()
  "Return textual preview lines for the hovered entry."
  (let ((entry (textui-yazi-prototype--current-entry)))
    (cond
     ((null entry) nil)
     ((and (eq (plist-get entry :type) 'dir)
           (plist-get entry :target))
      (mapcar (lambda (child)
                (textui-yazi-prototype--entry-label child nil))
              (textui-yazi-prototype--entries
               (plist-get entry :target))))
     ((plist-get entry :preview))
     (t
      (list (plist-get entry :name) ""
            (format "Size: %s" (or (plist-get entry :size) "—"))
            "Modified: today" "Permissions: -rw-r--r--")))))

(defun textui-yazi-prototype--current-cell (entry index width)
  "Return current-pane cell for ENTRY at INDEX inside WIDTH."
  (if (null entry)
      (textui-yazi-prototype--item "" width)
    (let* ((hovered (= index textui-yazi-prototype--cursor))
           (face (if hovered
                     'textui-yazi-prototype-selected-face
                   (if (eq (plist-get entry :type) 'dir)
                       'textui-yazi-prototype-directory-face
                     'textui-yazi-prototype-file-face)))
           (label (textui-yazi-prototype--fit
                   (textui-yazi-prototype--entry-label
                    entry (textui-yazi-prototype--selected-p entry))
                   width)))
      (list :type 'textui-yazi-prototype-row
            :value label
            :button-face face
            :mouse-face 'highlight
            :layout (append (list :width width)
                            (when hovered '(:focus-id yazi-hover)))
            :action (lambda (&rest _)
                      (setq textui-yazi-prototype--cursor index)
                      (textui-yazi-prototype--refresh))))))

(defun textui-yazi-prototype--screen-elements (width)
  "Return the Yazi-like screen children for WIDTH."
  (textui-yazi-prototype--sync-page-size)
  (let* ((pane-widths (textui-yazi-prototype--pane-widths width))
         (left-width (nth 0 pane-widths))
         (middle-width (nth 1 pane-widths))
         (right-width (nth 2 pane-widths))
         (entry (textui-yazi-prototype--current-entry))
         (current-slice
          (textui-yazi-prototype--slice
           (textui-yazi-prototype--entries)
           textui-yazi-prototype--cursor))
         (current-start (car current-slice))
         (current-rows (cdr current-slice))
         (parent-data (textui-yazi-prototype--parent-rows))
         (parent-slice
          (textui-yazi-prototype--slice
           (cdr parent-data) (car parent-data)))
         (parent-start (car parent-slice))
         (parent-rows (cdr parent-slice))
         (image-preview-p (plist-get entry :image))
         (preview-rows (and (not image-preview-p)
                            (textui-yazi-prototype--preview-lines)))
         parent-cells current-cells preview-cells)
    (dotimes (row textui-yazi-prototype--page-size)
      (let* ((current-index (+ current-start row))
             (current (nth row current-rows))
             (parent (nth row parent-rows))
             (parent-index (+ parent-start row))
             (preview (or (nth row preview-rows) "")))
        (when (> left-width 0)
          (push
           (textui-yazi-prototype--item
            (textui-yazi-prototype--fit
             (if parent
                 (textui-yazi-prototype--entry-label parent nil)
               "")
             left-width)
            left-width
            (if (= parent-index (car parent-data))
                'textui-yazi-prototype-selected-face
              'textui-yazi-prototype-muted-face))
           parent-cells))
        (push (textui-yazi-prototype--current-cell
               current current-index middle-width)
              current-cells)
        (when (and (> right-width 0) (not image-preview-p))
          (push (textui-yazi-prototype--item
                 (textui-yazi-prototype--fit preview right-width)
                 right-width
                 (if (= row 0)
                     'textui-yazi-prototype-directory-face
                   'textui-yazi-prototype-file-face))
                preview-cells))))
    (setq parent-cells (nreverse parent-cells)
          current-cells (nreverse current-cells)
          preview-cells (nreverse preview-cells))
    (let* ((separator-value
            (mapconcat #'identity
                       (make-list textui-yazi-prototype--page-size "│") "\n"))
           (body-children
            (append
             (when (> left-width 0)
               (list
                (list :type :flex :direction :column :gap 0
                      :layout (list :width left-width)
                      :children parent-cells)
                (list :type :text :value separator-value
                      :layout '(:width 1))))
             (list
              (list :type :flex :direction :column :gap 0
                    :layout (list :width middle-width)
                    :children current-cells))
             (when (> right-width 0)
               (list
                (list :type :text :value separator-value
                      :layout '(:width 1))
                (if image-preview-p
                    (list :type :image
                          :file textui-yazi-prototype--image-file
                          :rows textui-yazi-prototype--page-size
                          :alt (plist-get entry :name)
                          :layout (list :width right-width))
                  (list :type :flex :direction :column :gap 0
                        :layout (list :width right-width)
                        :children preview-cells))))))
           (total (length (textui-yazi-prototype--entries)))
           (selected (length textui-yazi-prototype--selected))
           (status
            (concat
             (propertize " NOR " 'face 'textui-yazi-prototype-mode-face)
             (format " %s " (or (plist-get entry :size) "—"))
             (propertize
              (format " %s " (or (plist-get entry :name) "—"))
              'face 'textui-yazi-prototype-accent-face)
             (when (> selected 0)
               (format " %d selected " selected))
             (propertize " drwxr-xr-x "
                         'face 'textui-yazi-prototype-muted-face)
             (format " %d/%d "
                     (if (> total 0) (1+ textui-yazi-prototype--cursor) 0)
                     total))))
      (list
       (textui-yazi-prototype--item
        (textui-yazi-prototype--fit
         (plist-get
          (textui-yazi-prototype--directory
           textui-yazi-prototype--directory)
          :path)
         width)
        width 'textui-yazi-prototype-accent-face)
       (list :type :flex :direction :row :gap 0 :children body-children)
       (textui-yazi-prototype--item
        (textui-yazi-prototype--fit status width) width)))))

(defun textui-yazi-prototype--frame (width)
  "Return the complete Yazi-like frame for WIDTH."
  (setq textui-yazi-prototype--full-renders
        (1+ textui-yazi-prototype--full-renders))
  (list
   (list :type :flex :direction :column :gap 0
         :layout '(:refresh-id yazi-screen)
         :children (textui-yazi-prototype--screen-elements width))))

(defun textui-yazi-prototype--refresh ()
  "Refresh the Yazi screen region."
  (textui-refresh-region
   (current-buffer) 'yazi-screen
   #'textui-yazi-prototype--screen-elements)
  (setq textui-yazi-prototype--region-refreshes
        (1+ textui-yazi-prototype--region-refreshes)))

(defun textui-yazi-prototype-move (amount)
  "Move the hovered entry by AMOUNT rows."
  (let ((maximum (max 0 (1- (length (textui-yazi-prototype--entries))))))
    (setq textui-yazi-prototype--cursor
          (max 0 (min maximum (+ textui-yazi-prototype--cursor amount))))
    (textui-yazi-prototype--refresh)))

(defun textui-yazi-prototype-down ()
  "Move to the next entry."
  (interactive)
  (textui-yazi-prototype-move 1))

(defun textui-yazi-prototype-up ()
  "Move to the previous entry."
  (interactive)
  (textui-yazi-prototype-move -1))

(defun textui-yazi-prototype-enter ()
  "Enter the hovered directory when the prototype contains it."
  (interactive)
  (let ((target (plist-get (textui-yazi-prototype--current-entry) :target)))
    (when target
      (setq textui-yazi-prototype--directory target
            textui-yazi-prototype--cursor 0)
      (textui-yazi-prototype--refresh))))

(defun textui-yazi-prototype-leave ()
  "Move to the parent directory."
  (interactive)
  (let* ((old textui-yazi-prototype--directory)
         (parent (plist-get (textui-yazi-prototype--directory old) :parent)))
    (when parent
      (setq textui-yazi-prototype--directory parent
            textui-yazi-prototype--cursor
            (or (cl-position
                 old (textui-yazi-prototype--entries parent)
                 :key (lambda (entry) (plist-get entry :target)))
                0))
      (textui-yazi-prototype--refresh))))

(defun textui-yazi-prototype-toggle ()
  "Toggle selection of the hovered entry and advance one row."
  (interactive)
  (let* ((entry (textui-yazi-prototype--current-entry))
         (key (and entry (textui-yazi-prototype--entry-key entry))))
    (when key
      (if (member key textui-yazi-prototype--selected)
          (setq textui-yazi-prototype--selected
                (delete key textui-yazi-prototype--selected))
        (push key textui-yazi-prototype--selected))
      (setq textui-yazi-prototype--cursor
            (min (1- (length (textui-yazi-prototype--entries)))
                 (1+ textui-yazi-prototype--cursor)))
      (textui-yazi-prototype--refresh))))

(defun textui-yazi-prototype-home ()
  "Move to the first entry."
  (interactive)
  (setq textui-yazi-prototype--cursor 0)
  (textui-yazi-prototype--refresh))

(defun textui-yazi-prototype-end ()
  "Move to the final entry."
  (interactive)
  (setq textui-yazi-prototype--cursor
        (max 0 (1- (length (textui-yazi-prototype--entries)))))
  (textui-yazi-prototype--refresh))

(defun textui-yazi-prototype--maybe-refresh-for-height ()
  "Refresh locally when a height-only resize changes page size."
  (when (and (derived-mode-p 'textui-mode)
             (not textui--refreshing)
             (assq 'yazi-screen textui--refresh-regions))
    (let ((old textui-yazi-prototype--page-size))
      (textui-yazi-prototype--sync-page-size)
      (when (/= old textui-yazi-prototype--page-size)
        (textui-yazi-prototype--refresh)))))

(defun textui-yazi-prototype--install-keys ()
  "Install Yazi-like navigation keys."
  (let ((map (copy-keymap (current-local-map))))
    (dolist (key '("j" "\C-n" [down] [wheel-down] [mouse-5]))
      (define-key map key #'textui-yazi-prototype-down))
    (dolist (key '("k" "\C-p" [up] [wheel-up] [mouse-4]))
      (define-key map key #'textui-yazi-prototype-up))
    (dolist (key '("l" [right] [return]))
      (define-key map key #'textui-yazi-prototype-enter))
    (dolist (key '("h" [left]))
      (define-key map key #'textui-yazi-prototype-leave))
    (define-key map " " #'textui-yazi-prototype-toggle)
    (define-key map "g" #'textui-yazi-prototype-home)
    (define-key map "G" #'textui-yazi-prototype-end)
    (define-key map "q" #'quit-window)
    (use-local-map map)))

(defun textui-yazi-prototype-open ()
  "Open the in-memory Yazi-like TextUI prototype."
  (interactive)
  (let ((buffer (get-buffer-create textui-yazi-prototype--buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'textui-mode)
        (textui-mode))
      (setq-local textui-yazi-prototype--directory 'textui
                  textui-yazi-prototype--cursor 0
                  textui-yazi-prototype--selected nil
                  textui-yazi-prototype--full-renders 0
                  textui-yazi-prototype--region-refreshes 0))
    (textui-open textui-yazi-prototype--buffer-name
                 #'textui-yazi-prototype--frame)
    (with-current-buffer buffer
      (setq-local truncate-lines t
                  line-spacing nil
                  cursor-type nil
                  mode-line-format nil)
      (unless textui-yazi-prototype--face-cookie
        (setq textui-yazi-prototype--face-cookie
              (face-remap-add-relative
               'default 'textui-yazi-prototype-default-face)))
      (textui-yazi-prototype--install-keys)
      (add-hook 'window-configuration-change-hook
                #'textui-yazi-prototype--maybe-refresh-for-height nil t))
    buffer))

(unless noninteractive
  (set-frame-size (selected-frame) 140 34)
  (textui-yazi-prototype-open)
  (set-frame-name "TextUI — Yazi UI/UX demo"))

(provide 'textui-yazi-prototype)

;;; textui-yazi-prototype.el ends here
