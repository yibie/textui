;;; textui-lazygit-prototype.el --- Lazygit UI demo -*- lexical-binding: t; -*-

;; Demonstrates Lazygit's stacked context panels, linked diff view, panel focus,
;; dynamic footer, and normal/half/full-screen modes in one TextUI buffer.
;; Repository data is deterministic and lives in memory.
;;
;; Run:
;; emacs -Q -L . -l examples/textui-lazygit-prototype.el

;;; Code:

(require 'cl-lib)
(require 'textui)

(defgroup textui-lazygit-prototype nil
  "Lazygit-like TextUI demo."
  :group 'convenience)

(defconst textui-lazygit-prototype--buffer-name
  "*TextUI Lazygit DEMO*")

(defface textui-lazygit-prototype-default-face
  '((t (:background "#101418" :foreground "#d8dee9")))
  "Default prototype face."
  :group 'textui-lazygit-prototype)

(defface textui-lazygit-prototype-border-face
  '((t (:foreground "#6b7785")))
  "Inactive border face."
  :group 'textui-lazygit-prototype)

(defface textui-lazygit-prototype-active-face
  '((t (:foreground "#5eead4" :weight bold)))
  "Active panel face."
  :group 'textui-lazygit-prototype)

(defface textui-lazygit-prototype-selected-face
  '((t (:background "#5eead4" :foreground "#101418" :weight bold)))
  "Selected row face."
  :group 'textui-lazygit-prototype)

(defface textui-lazygit-prototype-muted-face
  '((t (:foreground "#7f8c98")))
  "Secondary text face."
  :group 'textui-lazygit-prototype)

(defface textui-lazygit-prototype-green-face
  '((t (:foreground "#a6e3a1")))
  "Added and healthy state face."
  :group 'textui-lazygit-prototype)

(defface textui-lazygit-prototype-red-face
  '((t (:foreground "#f38ba8")))
  "Removed and warning state face."
  :group 'textui-lazygit-prototype)

(defface textui-lazygit-prototype-yellow-face
  '((t (:foreground "#f9e2af" :weight bold)))
  "Changed state face."
  :group 'textui-lazygit-prototype)

(defface textui-lazygit-prototype-blue-face
  '((t (:foreground "#89b4fa" :weight bold)))
  "Diff header face."
  :group 'textui-lazygit-prototype)

(define-widget 'textui-lazygit-prototype-row 'push-button
  "Clickable list row used by the Lazygit prototype."
  :button-prefix ""
  :button-suffix ""
  :value-create
  (lambda (widget)
    (insert (widget-value widget))))

(defconst textui-lazygit-prototype--files
  '("textui.el"
    "examples/textui-yazi-prototype.el"
    "examples/textui-lazygit-prototype.el"
    "docs/adr/0028-prototype-driven-capability-extraction.md"
    "README.md"
    "test/textui-test.el"))

(defconst textui-lazygit-prototype--branches
  '("main ✓" "prototype/lazygit-ui" "feature/image-preview"
    "fix/refresh-focus" "docs/prototype-findings" "dev"))

(defconst textui-lazygit-prototype--commits
  '("d8d01efd  fix: preserve cursor in refresh regions"
    "713ae790  feat: add native image leaf"
    "aa3fb261  docs: record prototype-driven extraction"
    "59788190  fix: align bordered widget rows"
    "1b0fcf4a  test: cover responsive grid placement"
    "64c30bd0  refactor: keep layout engine widget-agnostic"
    "ba0ceb09  feat: add local refresh regions"
    "fc512226  chore: require Emacs 29.1"))

(defconst textui-lazygit-prototype--stash
  '("stash@{0}  WIP: denser TUI theme"))

(defvar-local textui-lazygit-prototype--active-panel 2)
(defvar-local textui-lazygit-prototype--cursors [0 0 0 0 0 0])
(defvar-local textui-lazygit-prototype--staged nil)
(defvar-local textui-lazygit-prototype--screen-mode 'normal)
(defvar-local textui-lazygit-prototype--diff-offset 0)
(defvar-local textui-lazygit-prototype--help-visible nil)
(defvar-local textui-lazygit-prototype--refresh-count 0)
(defvar-local textui-lazygit-prototype--last-height nil)
(defvar-local textui-lazygit-prototype--face-cookie nil)

(defun textui-lazygit-prototype--fit (string width)
  "Truncate and pad STRING to exactly WIDTH display cells."
  (let* ((width (max 0 width))
         (value (truncate-string-to-width string width nil nil "…")))
    (concat value (make-string (max 0 (- width (string-width value))) ?\s))))

(defun textui-lazygit-prototype--item (value width &optional face)
  "Return a fixed WIDTH native item showing VALUE with FACE."
  (list :type 'item :format "%v"
        :value (if face (propertize value 'face face) value)
        :layout (list :width width)))

(defun textui-lazygit-prototype--title-line (width id title active)
  "Return a Lazygit-style top border for WIDTH, ID, and TITLE."
  (let* ((inside (max 0 (- width 2)))
         (label (truncate-string-to-width
                 (if (equal id "")
                     (format "─%s" title)
                   (format "─[%s]─%s" id title))
                 inside nil nil "…"))
         (line (concat "╭" label
                       (make-string (- inside (string-width label)) ?─) "╮")))
    (propertize line 'face
                (if active
                    'textui-lazygit-prototype-active-face
                  'textui-lazygit-prototype-border-face))))

(defun textui-lazygit-prototype--bottom-line (width counter active)
  "Return a WIDTH bottom border ending in COUNTER."
  (let* ((inside (max 0 (- width 2)))
         (suffix (if counter (format "%s─" counter) ""))
         (suffix (truncate-string-to-width suffix inside))
         (line (concat "╰" (make-string (- inside (string-width suffix)) ?─)
                       suffix "╯")))
    (propertize line 'face
                (if active
                    'textui-lazygit-prototype-active-face
                  'textui-lazygit-prototype-border-face))))

(defun textui-lazygit-prototype--inside-line (width value)
  "Return VALUE inside a WIDTH vertical frame."
  (concat (propertize "│" 'face 'textui-lazygit-prototype-border-face)
          (textui-lazygit-prototype--fit value (max 0 (- width 2)))
          (propertize "│" 'face 'textui-lazygit-prototype-border-face)))

(defun textui-lazygit-prototype--panel-title (id)
  "Return title for panel ID."
  (aref ["Unstaged changes" "Status" "Files - Worktrees - Submodules"
         "Local branches - Remotes - Tags" "Commits - Reflog" "Stash"] id))

(defun textui-lazygit-prototype--panel-rows (id)
  "Return fake data rows for panel ID."
  (pcase id
    (1 '("✓ textui → main"))
    (2 textui-lazygit-prototype--files)
    (3 textui-lazygit-prototype--branches)
    (4 textui-lazygit-prototype--commits)
    (5 textui-lazygit-prototype--stash)
    (_ nil)))

(defun textui-lazygit-prototype--row-label (id row)
  "Return Lazygit-like label for ROW in panel ID."
  (pcase id
    (1 row)
    (2 (let ((staged (member row textui-lazygit-prototype--staged)))
         (format "%s %s"
                 (if staged "M" " M") row)))
    (3 (concat (if (string-prefix-p "main" row) "* " "  ") row))
    (4 row)
    (5 row)
    (_ row)))

(defun textui-lazygit-prototype--row-face (id row)
  "Return semantic face for ROW in panel ID."
  (cond
   ((and (= id 2) (member row textui-lazygit-prototype--staged))
    'textui-lazygit-prototype-green-face)
   ((= id 2) 'textui-lazygit-prototype-yellow-face)
   ((and (= id 3) (string-prefix-p "main" row))
    'textui-lazygit-prototype-green-face)
   (t 'textui-lazygit-prototype-default-face)))

(defun textui-lazygit-prototype--row-element
    (id row index width selected)
  "Return one clickable ROW at INDEX for panel ID and WIDTH."
  (let ((value (textui-lazygit-prototype--inside-line
                width (concat " " (textui-lazygit-prototype--row-label id row)))))
    (list :type 'textui-lazygit-prototype-row
          :value value
          :button-face (if selected
                           'textui-lazygit-prototype-selected-face
                         (textui-lazygit-prototype--row-face id row))
          :mouse-face 'highlight
          :layout (append (list :width width)
                          (when selected '(:focus-id lazygit-selection)))
          :action
          (lambda (&rest _)
            (setq textui-lazygit-prototype--active-panel id
                  textui-lazygit-prototype--diff-offset 0)
            (aset textui-lazygit-prototype--cursors id index)
            (textui-lazygit-prototype--refresh)))))

(defun textui-lazygit-prototype--list-panel (id width height)
  "Return list panel ID inside WIDTH by HEIGHT."
  (let* ((rows (textui-lazygit-prototype--panel-rows id))
         (active (= id textui-lazygit-prototype--active-panel))
         (cursor (min (max 0 (aref textui-lazygit-prototype--cursors id))
                      (max 0 (1- (length rows)))))
         (slots (max 0 (- height 2)))
         (start (max 0 (min (- (length rows) (min slots (length rows)))
                            (- cursor (/ slots 2)))))
         (visible (cl-subseq rows start (min (length rows) (+ start slots))))
         (index start)
         children)
    (push (textui-lazygit-prototype--item
           (textui-lazygit-prototype--title-line
            width id (textui-lazygit-prototype--panel-title id) active)
           width)
          children)
    (dolist (row visible)
      (push (textui-lazygit-prototype--row-element
             id row index width (and active (= index cursor)))
            children)
      (setq index (1+ index)))
    (dotimes (_ (- slots (length visible)))
      (push (textui-lazygit-prototype--item
             (textui-lazygit-prototype--inside-line width "") width)
            children))
    (push (textui-lazygit-prototype--item
           (textui-lazygit-prototype--bottom-line
            width
            (format "%d of %d"
                    (if rows (1+ cursor) 0) (length rows))
            active)
           width)
          children)
    (list :type :flex :direction :column :gap 0
          :layout (list :width width :min-width width)
          :children (nreverse children))))

(defun textui-lazygit-prototype--selected-row (id)
  "Return the selected fake row in panel ID."
  (let ((rows (textui-lazygit-prototype--panel-rows id)))
    (nth (min (aref textui-lazygit-prototype--cursors id)
              (max 0 (1- (length rows))))
         rows)))

(defun textui-lazygit-prototype--diff-lines ()
  "Return main-view lines linked to the active list selection."
  (if textui-lazygit-prototype--help-visible
      '("Keybindings" ""
        "j/k                 next/previous item"
        "h/l or Tab         previous/next panel"
        "0..5               focus panel"
        "Space              stage/unstage selected file"
        "Enter              focus main view"
        "+/_                 next/previous screen mode"
        "R                   fake refresh"
        "?                   close keybindings"
        "q                   quit")
    (pcase textui-lazygit-prototype--active-panel
      (1 '("Repository status" ""
           "On branch main" "Your branch is up to date with 'origin/main'."
           "" "Changes not staged for commit:  4"
           "Changes to be committed:           2"
           "Untracked files:                   1"))
      (2 (let* ((file (or (textui-lazygit-prototype--selected-row 2)
                          "textui.el"))
                (staged (member file textui-lazygit-prototype--staged)))
           (list
            (format "diff --git a/%s b/%s" file file)
            "index 4ac1031..aa0ce42 100644"
            (format "--- a/%s" file)
            (format "+++ b/%s" file)
            "@@ -136,8 +136,12 @@"
            " (defun textui-refresh-region (buffer id producer)"
            "-  \"Replace one rendered block.\""
            "+  \"Replace refresh region ID in BUFFER.\""
            "+  ;; Preserve semantic focus while row positions move."
            "   (with-current-buffer buffer"
            "-    (erase-buffer)"
            "+    (delete-region from to)"
            "+    (insert replacement-text))"
            ""
            (if staged
                "This file is staged in the prototype."
              "Press Space to stage this file."))))
      (3 (let ((branch (textui-lazygit-prototype--selected-row 3)))
           (list (format "Branch: %s" branch) ""
                 "* d8d01efd preserve cursor in refresh regions"
                 "* 713ae790 add native image leaf"
                 "* aa3fb261 record prototype-driven extraction"
                 "| * 59788190 align bordered widget rows"
                 "|/" "* 1b0fcf4a cover responsive grid placement")))
      (4 (let ((commit (textui-lazygit-prototype--selected-row 4)))
           (list commit "Author: TextUI contributors" "Date: today" ""
                 "    Keep one-buffer applications visually coherent."
                 ""
                 " 3 files changed, 82 insertions(+), 14 deletions(-)"
                 "+ local refresh keeps the app shell stable"
                 "- full redraw on every navigation event")))
      (5 '("stash@{0}: WIP: denser TUI theme" ""
           " examples/textui-k9s-local-refresh-prototype.el | 24 +++++++++++++-------"
           " 1 file changed, 16 insertions(+), 8 deletions(-)"))
      (_ '("Main view" ""
           "Select a side panel with 1..5."
           "The main view follows the selected row without opening another buffer.")))))

(defun textui-lazygit-prototype--diff-face (line)
  "Return syntax face for diff LINE."
  (cond
   ((string-prefix-p "diff --git" line)
    'textui-lazygit-prototype-blue-face)
   ((string-prefix-p "@@" line)
    'textui-lazygit-prototype-active-face)
   ((and (string-prefix-p "+" line)
         (not (string-prefix-p "+++" line)))
    'textui-lazygit-prototype-green-face)
   ((and (string-prefix-p "-" line)
         (not (string-prefix-p "---" line)))
    'textui-lazygit-prototype-red-face)
   ((or (string-prefix-p "index " line)
        (string-prefix-p "Author:" line)
        (string-prefix-p "Date:" line))
    'textui-lazygit-prototype-muted-face)
   (t 'textui-lazygit-prototype-default-face)))

(defun textui-lazygit-prototype--text-panel
    (id title lines width height active)
  "Return framed text LINES in panel ID, TITLE, WIDTH, and HEIGHT."
  (let* ((slots (max 0 (- height 2)))
         (maximum (max 0 (- (length lines) slots)))
         (start (min maximum textui-lazygit-prototype--diff-offset))
         (visible (cl-subseq lines start (min (length lines) (+ start slots))))
         children)
    (push (textui-lazygit-prototype--item
           (textui-lazygit-prototype--title-line width id title active) width)
          children)
    (dolist (line visible)
      (push (textui-lazygit-prototype--item
             (textui-lazygit-prototype--inside-line
              width (concat " " line))
             width (textui-lazygit-prototype--diff-face line))
            children))
    (dotimes (_ (- slots (length visible)))
      (push (textui-lazygit-prototype--item
             (textui-lazygit-prototype--inside-line width "") width)
            children))
    (push (textui-lazygit-prototype--item
           (textui-lazygit-prototype--bottom-line
            width
            (when (> (length lines) slots)
              (format "%d of %d" (1+ start) (length lines)))
            active)
           width)
          children)
    (list :type :flex :direction :column :gap 0
          :layout (list :width width :min-width width)
          :children (nreverse children))))

(defun textui-lazygit-prototype--command-log (width height)
  "Return fake command log at WIDTH by HEIGHT."
  (textui-lazygit-prototype--text-panel
   "" "Command log"
   (list "You can hide/focus this panel by pressing '@'"
         ""
         (format "Local UI refresh #%d; no Git command was run."
                 textui-lazygit-prototype--refresh-count)
         "Tip: inspect the diff before asking somebody to review it.")
   width height nil))

(defun textui-lazygit-prototype--main-column (width height)
  "Return linked main view and command log at WIDTH by HEIGHT."
  (let* ((log-height (min 7 (max 3 (/ height 4))))
         (main-height (max 3 (- height log-height)))
         (main-title (if textui-lazygit-prototype--help-visible
                         "Keybindings"
                       (textui-lazygit-prototype--panel-title 0))))
    (list :type :flex :direction :column :gap 0
          :layout (list :width width :min-width width)
          :children
          (list
           (textui-lazygit-prototype--text-panel
            0 main-title (textui-lazygit-prototype--diff-lines)
            width main-height (= textui-lazygit-prototype--active-panel 0))
           (textui-lazygit-prototype--command-log width log-height)))))

(defun textui-lazygit-prototype--normal-panel-heights (height)
  "Split HEIGHT among Lazygit's five stacked side panels."
  (let* ((content (max 5 (- height 10)))
         (remaining (max 3 (- content 2)))
         (files (max 1 (/ remaining 4)))
         (branches (max 1 (/ remaining 3)))
         (commits (max 1 (- remaining files branches))))
    (list 3 (+ files 2) (+ branches 2) (+ commits 2) 3)))

(defun textui-lazygit-prototype--side-column (width height &optional one-panel)
  "Return stacked side panels at WIDTH by HEIGHT.
When ONE-PANEL is non-nil, expand only the active panel."
  (if one-panel
      (textui-lazygit-prototype--list-panel
       (max 1 textui-lazygit-prototype--active-panel) width height)
    (let ((heights (textui-lazygit-prototype--normal-panel-heights height))
          children)
      (dotimes (index 5)
        (push (textui-lazygit-prototype--list-panel
               (1+ index) width (nth index heights))
              children))
      (list :type :flex :direction :column :gap 0
            :layout (list :width width :min-width width)
            :children (nreverse children)))))

(defun textui-lazygit-prototype--visible-height ()
  "Return the smallest live body height for the prototype buffer."
  (let (heights)
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (push (window-body-height window) heights))
    (if heights (apply #'min heights) 40)))

(defun textui-lazygit-prototype--effective-mode (width height)
  "Return screen mode after responsive WIDTH and HEIGHT collapse."
  (cond
   ((or (< width 72) (< height 16)) 'full)
   ((and (eq textui-lazygit-prototype--screen-mode 'normal)
         (or (< width 110) (< height 26)))
    'half)
   (t textui-lazygit-prototype--screen-mode)))

(defun textui-lazygit-prototype--footer (width mode)
  "Return dynamic Lazygit footer for WIDTH and effective MODE."
  (let* ((context
          (pcase textui-lazygit-prototype--active-panel
            (2 "Stage: <space> | Enter: view diff")
            (0 "Scroll diff: j/k | Panels: h/l")
            (_ "Select: j/k | Main view: <enter>")))
         (value
          (format "%s | Screen: %s (+/_) | Keybindings: ? | q quit    0.63.0"
                  context mode)))
    (textui-lazygit-prototype--item
     (textui-lazygit-prototype--fit value width) width
     'textui-lazygit-prototype-muted-face)))

(defun textui-lazygit-prototype--screen-elements (width)
  "Return the responsive Lazygit-like screen children for WIDTH."
  (let* ((height (max 8 (1- (textui-lazygit-prototype--visible-height))))
         (mode (textui-lazygit-prototype--effective-mode width height))
         body)
    (setq textui-lazygit-prototype--last-height height)
    (setq body
          (pcase mode
            ('normal
             (let* ((left (max 34 (/ width 3)))
                    (left (min left (- width 40)))
                    (right (- width left)))
               (list :type :flex :direction :row :gap 0
                     :children
                     (list
                      (textui-lazygit-prototype--side-column left height)
                      (textui-lazygit-prototype--main-column right height)))))
            ('half
             (if (= textui-lazygit-prototype--active-panel 0)
                 (textui-lazygit-prototype--main-column width height)
               (let* ((left (/ width 2))
                      (right (- width left)))
                 (list :type :flex :direction :row :gap 0
                       :children
                       (list
                        (textui-lazygit-prototype--side-column left height t)
                        (textui-lazygit-prototype--main-column right height))))))
            (_
             (if (= textui-lazygit-prototype--active-panel 0)
                 (textui-lazygit-prototype--text-panel
                  0 (textui-lazygit-prototype--panel-title 0)
                  (textui-lazygit-prototype--diff-lines) width height t)
               (textui-lazygit-prototype--side-column width height t)))))
    (list body (textui-lazygit-prototype--footer width mode))))

(defun textui-lazygit-prototype--frame (width)
  "Return complete Lazygit-like frame for WIDTH."
  (list
   (list :type :flex :direction :column :gap 0
         :layout '(:refresh-id lazygit-screen)
         :children (textui-lazygit-prototype--screen-elements width))))

(defun textui-lazygit-prototype--refresh ()
  "Refresh only the single-buffer application screen."
  (interactive)
  (setq textui-lazygit-prototype--refresh-count
        (1+ textui-lazygit-prototype--refresh-count))
  (textui-refresh-region
   (current-buffer) 'lazygit-screen
   #'textui-lazygit-prototype--screen-elements))

(defun textui-lazygit-prototype-move (amount)
  "Move AMOUNT rows in the active panel."
  (interactive "p")
  (if (= textui-lazygit-prototype--active-panel 0)
      (let* ((lines (textui-lazygit-prototype--diff-lines))
             (maximum (max 0 (1- (length lines)))))
        (setq textui-lazygit-prototype--diff-offset
              (max 0 (min maximum
                          (+ textui-lazygit-prototype--diff-offset amount)))))
    (let* ((id textui-lazygit-prototype--active-panel)
           (maximum (max 0 (1- (length
                                (textui-lazygit-prototype--panel-rows id))))))
      (aset textui-lazygit-prototype--cursors id
            (max 0 (min maximum
                        (+ (aref textui-lazygit-prototype--cursors id)
                           amount))))
      (setq textui-lazygit-prototype--diff-offset 0)))
  (textui-lazygit-prototype--refresh))

(defun textui-lazygit-prototype-down ()
  "Move to the next row."
  (interactive)
  (textui-lazygit-prototype-move 1))

(defun textui-lazygit-prototype-up ()
  "Move to the previous row."
  (interactive)
  (textui-lazygit-prototype-move -1))

(defun textui-lazygit-prototype-focus-panel (id)
  "Focus panel ID and refresh its linked main view."
  (setq textui-lazygit-prototype--active-panel (max 0 (min 5 id))
        textui-lazygit-prototype--diff-offset 0)
  (textui-lazygit-prototype--refresh))

(defun textui-lazygit-prototype-next-panel (amount)
  "Move panel focus by AMOUNT."
  (interactive "p")
  (textui-lazygit-prototype-focus-panel
   (mod (+ textui-lazygit-prototype--active-panel amount) 6)))

(defun textui-lazygit-prototype-stage ()
  "Toggle staged state of the selected fake file."
  (interactive)
  (when (= textui-lazygit-prototype--active-panel 2)
    (let ((file (textui-lazygit-prototype--selected-row 2)))
      (if (member file textui-lazygit-prototype--staged)
          (setq textui-lazygit-prototype--staged
                (delete file textui-lazygit-prototype--staged))
        (push file textui-lazygit-prototype--staged))
      (textui-lazygit-prototype--refresh))))

(defun textui-lazygit-prototype-main ()
  "Focus the linked main view."
  (interactive)
  (textui-lazygit-prototype-focus-panel 0))

(defun textui-lazygit-prototype-screen-mode (amount)
  "Move screen mode by AMOUNT through normal, half, and full."
  (interactive "p")
  (let* ((modes [normal half full])
         (current (or (cl-position textui-lazygit-prototype--screen-mode modes)
                      0)))
    (setq textui-lazygit-prototype--screen-mode
          (aref modes (max 0 (min 2 (+ current amount)))))
    (textui-lazygit-prototype--refresh)))

(defun textui-lazygit-prototype-toggle-help ()
  "Toggle the keybinding view."
  (interactive)
  (setq textui-lazygit-prototype--help-visible
        (not textui-lazygit-prototype--help-visible)
        textui-lazygit-prototype--active-panel 0
        textui-lazygit-prototype--diff-offset 0)
  (textui-lazygit-prototype--refresh))

(defun textui-lazygit-prototype--maybe-refresh-for-height ()
  "Refresh locally when a height-only resize changes visible rows."
  (when (and (derived-mode-p 'textui-mode)
             (assq 'lazygit-screen textui--refresh-regions)
             (not textui--refreshing))
    (let ((height (max 8 (1- (textui-lazygit-prototype--visible-height)))))
      (when (/= height textui-lazygit-prototype--last-height)
        (textui-lazygit-prototype--refresh)))))

(defun textui-lazygit-prototype--install-keys ()
  "Install Lazygit-like local keys."
  (let ((map (copy-keymap (current-local-map))))
    (dolist (key '("j" "\C-n" [down] [wheel-down] [mouse-5]))
      (define-key map key #'textui-lazygit-prototype-down))
    (dolist (key '("k" "\C-p" [up] [wheel-up] [mouse-4]))
      (define-key map key #'textui-lazygit-prototype-up))
    (dolist (key '("l" "\t"))
      (define-key map key
                  (lambda () (interactive)
                    (textui-lazygit-prototype-next-panel 1))))
    (define-key map "h"
                (lambda () (interactive)
                  (textui-lazygit-prototype-next-panel -1)))
    (dotimes (id 6)
      (define-key map (number-to-string id)
                  (let ((panel id))
                    (lambda () (interactive)
                      (textui-lazygit-prototype-focus-panel panel)))))
    (define-key map " " #'textui-lazygit-prototype-stage)
    (define-key map (kbd "RET") #'textui-lazygit-prototype-main)
    (define-key map "+"
                (lambda () (interactive)
                  (textui-lazygit-prototype-screen-mode 1)))
    (define-key map "_"
                (lambda () (interactive)
                  (textui-lazygit-prototype-screen-mode -1)))
    (define-key map "?" #'textui-lazygit-prototype-toggle-help)
    (define-key map "R" #'textui-lazygit-prototype--refresh)
    (define-key map "q" #'quit-window)
    (use-local-map map)))

(defun textui-lazygit-prototype-open ()
  "Open the one-buffer, in-memory Lazygit-like prototype."
  (interactive)
  (let ((buffer (get-buffer-create textui-lazygit-prototype--buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'textui-mode)
        (textui-mode))
      (setq-local textui-lazygit-prototype--active-panel 2
                  textui-lazygit-prototype--cursors (vector 0 0 0 0 0 0)
                  textui-lazygit-prototype--staged nil
                  textui-lazygit-prototype--screen-mode 'normal
                  textui-lazygit-prototype--diff-offset 0
                  textui-lazygit-prototype--help-visible nil
                  textui-lazygit-prototype--refresh-count 0
                  textui-lazygit-prototype--last-height nil))
    (textui-open textui-lazygit-prototype--buffer-name
                 #'textui-lazygit-prototype--frame)
    (let ((window (get-buffer-window buffer t)))
      (when window
        (delete-other-windows window)
        (select-window window)))
    (with-current-buffer buffer
      (setq-local truncate-lines t
                  line-spacing nil
                  cursor-type nil
                  mode-line-format nil)
      (unless textui-lazygit-prototype--face-cookie
        (setq textui-lazygit-prototype--face-cookie
              (face-remap-add-relative
               'default 'textui-lazygit-prototype-default-face)))
      (textui-lazygit-prototype--install-keys)
      (add-hook 'window-configuration-change-hook
                #'textui-lazygit-prototype--maybe-refresh-for-height nil t))
    buffer))

(unless noninteractive
  (set-frame-size (selected-frame) 150 42)
  (textui-lazygit-prototype-open)
  (set-frame-name "TextUI — Lazygit UI/UX demo"))

(provide 'textui-lazygit-prototype)

;;; textui-lazygit-prototype.el ends here
