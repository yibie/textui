;;; textui-btop-prototype.el --- Live btop UI demo -*- lexical-binding: t; -*-

;; A practical btop-like live monitor with independently refreshed graphs,
;; a selectable process table, and responsive panel rearrangement.  Metrics
;; and processes come from read-only local macOS system commands.
;;
;; Run:
;; emacs -Q -L . -l examples/textui-btop-prototype.el

;;; Code:

(require 'cl-lib)
(require 'textui)

(defgroup textui-btop-prototype nil
  "Live btop-like TextUI demo."
  :group 'convenience)

(defconst textui-btop-prototype--buffer-name "*TextUI btop DEMO*")
(defconst textui-btop-prototype--interval 1.0)

(defconst textui-btop-prototype--sample-command
  '("/bin/sh" "-c"
    "/bin/ps -axo pid=,pcpu=,rss=,user=,state=,etime=,comm=; printf '\n__TEXTUI_VM__\n'; /usr/bin/vm_stat; printf '\n__TEXTUI_NET__\n'; /usr/sbin/netstat -ibn; printf '\n__TEXTUI_SYSTEM__\n'; /usr/sbin/sysctl -n hw.memsize; /usr/sbin/sysctl -n machdep.cpu.brand_string")
  "Read-only macOS commands used by the live prototype sampler.")

(defface textui-btop-prototype-default-face
  '((t (:background "#070a0f" :foreground "#c8d3f5")))
  "Default prototype face."
  :group 'textui-btop-prototype)

(defface textui-btop-prototype-border-face
  '((t (:foreground "#4d8f87")))
  "Panel border face."
  :group 'textui-btop-prototype)

(defface textui-btop-prototype-cpu-face
  '((t (:foreground "#9ece6a" :weight bold)))
  "CPU graph face."
  :group 'textui-btop-prototype)

(defface textui-btop-prototype-cpu-warm-face
  '((t (:foreground "#e0af68" :weight bold)))
  "Medium CPU graph face."
  :group 'textui-btop-prototype)

(defface textui-btop-prototype-cpu-hot-face
  '((t (:foreground "#f7768e" :weight bold)))
  "High CPU graph face."
  :group 'textui-btop-prototype)

(defface textui-btop-prototype-memory-face
  '((t (:foreground "#ff5d8f" :weight bold)))
  "Memory graph face."
  :group 'textui-btop-prototype)

(defface textui-btop-prototype-disk-face
  '((t (:foreground "#ffc777" :weight bold)))
  "Disk graph face."
  :group 'textui-btop-prototype)

(defface textui-btop-prototype-net-face
  '((t (:foreground "#65d1ff" :weight bold)))
  "Network graph face."
  :group 'textui-btop-prototype)

(defface textui-btop-prototype-upload-face
  '((t (:foreground "#c099ff" :weight bold)))
  "Upload graph face."
  :group 'textui-btop-prototype)

(defface textui-btop-prototype-process-face
  '((t (:foreground "#ffc777" :weight bold)))
  "Process table face."
  :group 'textui-btop-prototype)

(defface textui-btop-prototype-muted-face
  '((t (:foreground "#7f8ea3")))
  "Secondary text face."
  :group 'textui-btop-prototype)

(defface textui-btop-prototype-selected-face
  '((t (:background "#365f9d" :foreground "#ffffff" :weight bold)))
  "Selected process face."
  :group 'textui-btop-prototype)

(define-widget 'textui-btop-prototype-row 'push-button
  "Clickable process row used by the btop prototype."
  :button-prefix ""
  :button-suffix ""
  :value-create
  (lambda (widget)
    (insert (widget-value widget))))

(defvar-local textui-btop-prototype--tick 0)
(defvar-local textui-btop-prototype--cpu-history nil)
(defvar-local textui-btop-prototype--download-history nil)
(defvar-local textui-btop-prototype--upload-history nil)
(defvar-local textui-btop-prototype--processes nil)
(defvar-local textui-btop-prototype--cpu-value 0.0)
(defvar-local textui-btop-prototype--cpu-model "sampling…")
(defvar-local textui-btop-prototype--load-average '(0.0 0.0 0.0))
(defvar-local textui-btop-prototype--memory-total 0)
(defvar-local textui-btop-prototype--memory-used 0)
(defvar-local textui-btop-prototype--memory-free 0)
(defvar-local textui-btop-prototype--memory-cached 0)
(defvar-local textui-btop-prototype--disk-total 0)
(defvar-local textui-btop-prototype--disk-used 0)
(defvar-local textui-btop-prototype--disk-free 0)
(defvar-local textui-btop-prototype--download-rate 0.0)
(defvar-local textui-btop-prototype--upload-rate 0.0)
(defvar-local textui-btop-prototype--download-total 0)
(defvar-local textui-btop-prototype--upload-total 0)
(defvar-local textui-btop-prototype--network-sample nil)
(defvar-local textui-btop-prototype--sample-process nil)
(defvar-local textui-btop-prototype--sample-buffer nil)
(defvar-local textui-btop-prototype--sample-started 0.0)
(defvar-local textui-btop-prototype--last-sample-ms 0.0)
(defvar-local textui-btop-prototype--timer nil)
(defvar-local textui-btop-prototype--last-height nil)
(defvar-local textui-btop-prototype--face-cookie nil)

(defconst textui-btop-prototype--initial-state
  '(:boxes (cpu mem net proc)
    :process-index 0 :sort-index 0 :reversed nil
    :filter "" :paused nil :details t))

(defun textui-btop-prototype--state (key)
  "Return KEY from the current buffer's `textui-state'."
  (plist-get textui-state key))

(defun textui-btop-prototype--state-with (state &rest changes)
  "Return a copy of STATE with alternating key/value CHANGES."
  (let ((next (copy-sequence state)))
    (while changes
      (setq next (plist-put next (pop changes) (pop changes))))
    next))

(defun textui-btop-prototype--fit (string width)
  "Truncate and pad STRING to exactly WIDTH display cells."
  (let* ((width (max 0 width))
         (value (truncate-string-to-width string width nil nil "…")))
    (concat value (make-string (max 0 (- width (string-width value))) ?\s))))

(defun textui-btop-prototype--item (value width &optional face)
  "Return a fixed WIDTH native item showing VALUE with FACE."
  (list :type 'item :format "%v"
        :value (if face (propertize value 'face face) value)
        :layout (list :width width)))

(defun textui-btop-prototype--title-line (width key title right face)
  "Return btop-style top border using KEY, TITLE, RIGHT, and FACE."
  (let* ((inside (max 0 (- width 2)))
         (left (format "─%s%s" (if key (format "%s" key) "") title))
         (right (if (string-empty-p right) "" (format "%s─" right)))
         (room (max 0 (- inside (string-width right))))
         (left (truncate-string-to-width left room nil nil "…"))
         (line (concat "╭" left
                       (make-string (max 0 (- room (string-width left))) ?─)
                       right "╮")))
    (propertize line 'face face)))

(defun textui-btop-prototype--bottom-line (width suffix face)
  "Return WIDTH bottom border ending in SUFFIX with FACE."
  (let* ((inside (max 0 (- width 2)))
         (suffix (if (string-empty-p suffix) "" (format "%s─" suffix)))
         (suffix (truncate-string-to-width suffix inside))
         (line (concat "╰" (make-string (- inside (string-width suffix)) ?─)
                       suffix "╯")))
    (propertize line 'face face)))

(defun textui-btop-prototype--inside-line (width value)
  "Return VALUE inside a WIDTH vertical frame."
  (concat (propertize "│" 'face 'textui-btop-prototype-border-face)
          (textui-btop-prototype--fit value (max 0 (- width 2)))
          (propertize "│" 'face 'textui-btop-prototype-border-face)))

(defun textui-btop-prototype--separator-line (width label face)
  "Return a framed horizontal separator containing LABEL."
  (let* ((inside (max 0 (- width 2)))
         (label (truncate-string-to-width (format "─%s" label) inside))
         (line (concat "├" label
                       (make-string (- inside (string-width label)) ?─) "┤")))
    (propertize line 'face face)))

(defun textui-btop-prototype--box-visible-p (box)
  "Return non-nil when BOX is visible."
  (memq box (textui-btop-prototype--state :boxes)))

(defun textui-btop-prototype--append-sample (history value)
  "Append VALUE to HISTORY and retain its newest 240 values."
  (let ((next (append history (list value))))
    (if (> (length next) 240) (cdr next) next)))

(defun textui-btop-prototype--parse-processes (text)
  "Update live process and CPU state from ps TEXT."
  (let ((cpu-total 0.0)
        rows)
    (dolist (line (split-string text "\n" t))
      (when (string-match
             "^[[:space:]]*\\([0-9]+\\)[[:space:]]+\\([0-9.]+\\)[[:space:]]+\\([0-9]+\\)[[:space:]]+\\([^[:space:]]+\\)[[:space:]]+\\([^[:space:]]+\\)[[:space:]]+\\([^[:space:]]+\\)[[:space:]]+\\(.+\\)$"
             line)
        (let* ((pid (string-to-number (match-string 1 line)))
               (cpu (string-to-number (match-string 2 line)))
               (command (string-trim (match-string 7 line)))
               (name (file-name-nondirectory command)))
          (setq cpu-total (+ cpu-total cpu))
          (push (list :pid pid :cpu cpu
                      :mem (round (/ (string-to-number
                                      (match-string 3 line))
                                     1024.0))
                      :user (match-string 4 line)
                      :state (match-string 5 line)
                      :etime (match-string 6 line)
                      :command command
                      :name (if (string-empty-p name) command name))
                rows))))
    (setq textui-btop-prototype--processes (nreverse rows)
          textui-btop-prototype--cpu-value
          (min 100.0 (/ cpu-total (max 1 (num-processors)))))))

(defun textui-btop-prototype--vm-pages (text label)
  "Return page count for LABEL in vm_stat TEXT."
  (if (string-match
       (format "^%s:[[:space:]]+\\([0-9]+\\)\\."
               (regexp-quote label))
       text)
      (string-to-number (match-string 1 text))
    0))

(defun textui-btop-prototype--parse-memory (text)
  "Update memory state from vm_stat TEXT."
  (when (string-match "page size of \\([0-9]+\\) bytes" text)
    (let* ((page-size (string-to-number (match-string 1 text)))
           (free-pages
            (+ (textui-btop-prototype--vm-pages text "Pages free")
               (textui-btop-prototype--vm-pages text "Pages inactive")
               (textui-btop-prototype--vm-pages text "Pages speculative")))
           (free (* page-size free-pages)))
      (setq textui-btop-prototype--memory-free
            (min textui-btop-prototype--memory-total free)
            textui-btop-prototype--memory-used
            (max 0 (- textui-btop-prototype--memory-total
                      textui-btop-prototype--memory-free))
            textui-btop-prototype--memory-cached
            (* page-size
               (textui-btop-prototype--vm-pages
                text "File-backed pages"))))))

(defun textui-btop-prototype--parse-network (text)
  "Update live en0 rates and totals from netstat TEXT."
  (let ((line
         (cl-find-if
          (lambda (candidate)
            (and (string-prefix-p "en0 " candidate)
                 (string-match-p "<Link#" candidate)))
          (split-string text "\n" t))))
    (when line
      (let* ((fields (split-string line "[[:space:]]+" t))
             (download (string-to-number (or (nth 6 fields) "0")))
             (upload (string-to-number (or (nth 9 fields) "0")))
             (now (float-time))
             (previous textui-btop-prototype--network-sample)
             (elapsed (and previous (- now (plist-get previous :time)))))
        (when (and elapsed (> elapsed 0))
          (setq textui-btop-prototype--download-rate
                (max 0.0 (/ (- download (plist-get previous :download))
                            elapsed))
                textui-btop-prototype--upload-rate
                (max 0.0 (/ (- upload (plist-get previous :upload))
                            elapsed))))
        (setq textui-btop-prototype--download-total download
              textui-btop-prototype--upload-total upload
              textui-btop-prototype--network-sample
              (list :time now :download download :upload upload))))))

(defun textui-btop-prototype--parse-system (text)
  "Update total memory and CPU model from sysctl TEXT."
  (let ((lines (split-string text "\n" t)))
    (setq textui-btop-prototype--memory-total
          (string-to-number (or (nth 0 lines) "0"))
          textui-btop-prototype--cpu-model
          (or (nth 1 lines) "unknown CPU"))))

(defun textui-btop-prototype--update-disk ()
  "Update disk totals using Emacs' native filesystem query."
  (let ((info (file-system-info "/")))
    (setq textui-btop-prototype--disk-total (or (nth 0 info) 0)
          textui-btop-prototype--disk-free (or (nth 1 info) 0)
          textui-btop-prototype--disk-used
          (max 0 (- textui-btop-prototype--disk-total
                    textui-btop-prototype--disk-free)))))

(defun textui-btop-prototype--record-sample (ps vm net system)
  "Record one real sample from PS, VM, NET, and SYSTEM output."
  (textui-btop-prototype--parse-system system)
  (textui-btop-prototype--parse-processes ps)
  (textui-btop-prototype--parse-memory vm)
  (textui-btop-prototype--parse-network net)
  (textui-btop-prototype--update-disk)
  (setq textui-btop-prototype--load-average (load-average t)
        textui-btop-prototype--tick (1+ textui-btop-prototype--tick)
        textui-btop-prototype--cpu-history
        (textui-btop-prototype--append-sample
         textui-btop-prototype--cpu-history
         textui-btop-prototype--cpu-value)
        textui-btop-prototype--download-history
        (textui-btop-prototype--append-sample
         textui-btop-prototype--download-history
         textui-btop-prototype--download-rate)
        textui-btop-prototype--upload-history
        (textui-btop-prototype--append-sample
         textui-btop-prototype--upload-history
         textui-btop-prototype--upload-rate)))

(defun textui-btop-prototype--sample-finished (process _event)
  "Consume asynchronous sampler PROCESS output."
  (when (memq (process-status process) '(exit signal))
    (let* ((target (process-get process 'textui-buffer))
           (output (process-buffer process))
           (status (process-exit-status process))
           (text (and (buffer-live-p output)
                      (with-current-buffer output (buffer-string)))))
      (when (buffer-live-p output)
        (kill-buffer output))
      (when (buffer-live-p target)
        (with-current-buffer target
          (setq textui-btop-prototype--sample-process nil
                textui-btop-prototype--sample-buffer nil)
          (if (/= status 0)
              (error "btop sampler exited with status %d" status)
            (unless (textui-btop-prototype--state :paused)
              (let* ((vm-marker "\n__TEXTUI_VM__\n")
                     (net-marker "\n__TEXTUI_NET__\n")
                     (system-marker "\n__TEXTUI_SYSTEM__\n")
                     (vm-start (string-match (regexp-quote vm-marker) text))
                     (net-start (and vm-start
                                     (string-match
                                      (regexp-quote net-marker) text
                                      (+ vm-start (length vm-marker)))))
                     (system-start
                      (and net-start
                           (string-match
                            (regexp-quote system-marker) text
                            (+ net-start (length net-marker))))))
                (unless (and vm-start net-start system-start)
                  (error "btop sampler returned incomplete output"))
                (textui-btop-prototype--record-sample
                 (substring text 0 vm-start)
                 (substring text (+ vm-start (length vm-marker)) net-start)
                 (substring text (+ net-start (length net-marker)) system-start)
                 (substring text (+ system-start (length system-marker))))
                (setq textui-btop-prototype--last-sample-ms
                      (* 1000.0
                         (- (float-time)
                            textui-btop-prototype--sample-started)))
                (when (get-buffer-window target t)
                  (when (assq 'btop-cpu textui--refresh-regions)
                    (textui-request-refresh-region
                     target 'btop-cpu
                     #'textui-btop-prototype--cpu-elements))
                  (textui-request-refresh-region
                   target 'btop-lower
                   #'textui-btop-prototype--lower-elements))))))))))

(defun textui-btop-prototype--start-sample ()
  "Start one non-blocking real system sample."
  (unless (or (textui-btop-prototype--state :paused)
              (process-live-p textui-btop-prototype--sample-process))
    (let* ((output (generate-new-buffer " *textui-btop-sample*"))
           (process
            (make-process
             :name "textui-btop-sample"
             :buffer output
             :command textui-btop-prototype--sample-command
             :coding 'utf-8-unix
             :noquery t
             :connection-type 'pipe
             :sentinel #'textui-btop-prototype--sample-finished)))
      (process-put process 'textui-buffer (current-buffer))
      (setq textui-btop-prototype--sample-buffer output
            textui-btop-prototype--sample-process process
            textui-btop-prototype--sample-started (float-time)))))

(defun textui-btop-prototype--last (values)
  "Return final value in VALUES or zero."
  (or (car (last values)) 0))

(defun textui-btop-prototype--graph-lines
    (values width height face &optional maximum)
  "Render VALUES as a fractional WIDTH by HEIGHT graph using FACE.
FACE may be a top-to-bottom vector of faces.  MAXIMUM defaults to 100."
  (let* ((width (max 1 width))
         (height (max 1 height))
         (maximum (max 1.0 (or maximum 100.0)))
         (visible (last values (min width (length values))))
         (visible (append (make-list (- width (length visible)) 0) visible)))
    (cl-loop
     for row below height
     collect
     (let ((row-face
            (if (vectorp face)
                (aref face (min (1- (length face))
                                (/ (* row (length face)) height)))
              face))
           chars)
       (dolist (value visible)
         (let* ((filled (round (* (max 0.0 (min maximum value))
                                  height 8.0 (/ 1.0 maximum))))
                (level (max 0 (min 8 (- filled (* (- height row 1) 8))))))
           (push (aref " ▁▂▃▄▅▆▇█" level) chars)))
       (propertize (concat (nreverse chars)) 'face row-face)))))

(defun textui-btop-prototype--bar (value width face)
  "Return a VALUE-percent bar of WIDTH with FACE."
  (let* ((width (max 1 width))
         (filled (min width (round (* width (/ value 100.0))))))
    (concat (propertize (make-string filled ?█) 'face face)
            (propertize (make-string (- width filled) ?░)
                        'face 'textui-btop-prototype-muted-face))))

(defun textui-btop-prototype--percent (part total)
  "Return PART as a percentage of TOTAL."
  (if (> total 0) (min 100.0 (* 100.0 (/ (float part) total))) 0.0))

(defun textui-btop-prototype--cpu-panel (width height)
  "Return the live CPU panel at WIDTH by HEIGHT."
  (let* ((inside (max 1 (- width 2)))
         (slots (max 1 (- height 2)))
         (stats-width (if (>= width 90) (min 31 (/ width 4)) 20))
         (graph-width (max 8 (- inside stats-width 1)))
         (cpu (textui-btop-prototype--last
               textui-btop-prototype--cpu-history))
         (graphs (textui-btop-prototype--graph-lines
                  textui-btop-prototype--cpu-history graph-width slots
                  [textui-btop-prototype-cpu-hot-face
                   textui-btop-prototype-cpu-warm-face
                   textui-btop-prototype-cpu-face]))
         (top-processes
          (sort (copy-sequence textui-btop-prototype--processes)
                (lambda (left right)
                  (> (plist-get left :cpu) (plist-get right :cpu)))))
         children)
    (push (textui-btop-prototype--item
           (textui-btop-prototype--title-line
            width "1" "cpu" "1000ms +" 'textui-btop-prototype-cpu-face)
           width)
          children)
    (dotimes (row slots)
      (let* ((graph (nth row graphs))
             (process (and (>= row 2) (nth (- row 2) top-processes)))
             (stats
              (cond
               ((= row 0)
                (format " %s  %d cores"
                        textui-btop-prototype--cpu-model (num-processors)))
               ((= row 1) (format " CPU  %5.1f%%" cpu))
               ((= row (1- slots))
                (format " Load AVG: %.2f %.2f %.2f"
                        (or (nth 0 textui-btop-prototype--load-average) 0.0)
                        (or (nth 1 textui-btop-prototype--load-average) 0.0)
                        (or (nth 2 textui-btop-prototype--load-average) 0.0)))
               (process
                (format " %-16s %5.1f%%"
                        (plist-get process :name)
                        (plist-get process :cpu)))
               (t "")))
             (line (concat graph " "
                           (textui-btop-prototype--fit stats stats-width))))
        (push (textui-btop-prototype--item
               (textui-btop-prototype--inside-line width line) width)
              children)))
    (push (textui-btop-prototype--item
           (textui-btop-prototype--bottom-line
            width (format "sample %d: %.0fms"
                          textui-btop-prototype--tick
                          textui-btop-prototype--last-sample-ms)
            'textui-btop-prototype-border-face)
           width)
          children)
    (list :type :flex :direction :column :gap 0
          :layout (list :width width :min-width width)
          :children (nreverse children))))

(defun textui-btop-prototype--simple-panel
    (width height key title right lines face)
  "Return framed LINES at WIDTH by HEIGHT with btop-style metadata."
  (let ((slots (max 0 (- height 2)))
        children)
    (push (textui-btop-prototype--item
           (textui-btop-prototype--title-line width key title right face) width)
          children)
    (dotimes (row slots)
      (push (textui-btop-prototype--item
             (textui-btop-prototype--inside-line
              width (or (nth row lines) ""))
             width)
            children))
    (push (textui-btop-prototype--item
           (textui-btop-prototype--bottom-line width "" face) width)
          children)
    (list :type :flex :direction :column :gap 0
          :layout (list :width width :min-width width)
          :children (nreverse children))))

(defun textui-btop-prototype--memory-lines (width)
  "Return memory data lines fitted for WIDTH."
  (let* ((bar-width (max 5 (- width 13)))
         (used (textui-btop-prototype--percent
                textui-btop-prototype--memory-used
                textui-btop-prototype--memory-total))
         (free (textui-btop-prototype--percent
                textui-btop-prototype--memory-free
                textui-btop-prototype--memory-total)))
    (list (format " Total:          %s"
                  (file-size-human-readable
                   textui-btop-prototype--memory-total))
          (format " Used:           %s"
                  (file-size-human-readable
                   textui-btop-prototype--memory-used))
          (concat " " (textui-btop-prototype--bar
                       used bar-width 'textui-btop-prototype-memory-face)
                  (format " %.0f%%" used))
          (format " Available:      %s"
                  (file-size-human-readable
                   textui-btop-prototype--memory-free))
          (concat " " (textui-btop-prototype--bar
                       free bar-width 'textui-btop-prototype-disk-face)
                  (format " %.0f%%" free))
          (format " Cached:         %s"
                  (file-size-human-readable
                   textui-btop-prototype--memory-cached))
          (format " Free:           %s"
                  (file-size-human-readable
                   textui-btop-prototype--memory-free)))))

(defun textui-btop-prototype--disk-lines (width)
  "Return disk data lines fitted for WIDTH."
  (let* ((bar-width (max 5 (- width 15)))
         (used (textui-btop-prototype--percent
                textui-btop-prototype--disk-used
                textui-btop-prototype--disk-total)))
    (list (format " /                 %s"
                  (file-size-human-readable
                   textui-btop-prototype--disk-total))
          (concat " " (textui-btop-prototype--bar
                       used bar-width 'textui-btop-prototype-memory-face)
                  (format " %.0f%%" used))
          (format " Used:             %s"
                  (file-size-human-readable
                   textui-btop-prototype--disk-used))
          (format " Free:             %s"
                  (file-size-human-readable
                   textui-btop-prototype--disk-free))
          " Filesystem:       apfs"
          " Source:           file-system-info"
          "")))

(defun textui-btop-prototype--memory-group (width height)
  "Return memory and disk boxes inside WIDTH by HEIGHT."
  (if (>= width 62)
      (let* ((memory-width (/ width 2))
             (disk-width (- width memory-width)))
        (list :type :flex :direction :row :gap 0
              :layout (list :width width :min-width width)
              :children
              (list
               (textui-btop-prototype--simple-panel
                memory-width height "2" "mem" ""
                (textui-btop-prototype--memory-lines memory-width)
                'textui-btop-prototype-memory-face)
               (textui-btop-prototype--simple-panel
                disk-width height nil "disks" "io"
                (textui-btop-prototype--disk-lines disk-width)
                'textui-btop-prototype-disk-face))))
    (textui-btop-prototype--simple-panel
     width height "2" "mem + disks" ""
     (append (cl-subseq (textui-btop-prototype--memory-lines width) 0 4)
             (cl-subseq (textui-btop-prototype--disk-lines width) 0 3))
     'textui-btop-prototype-memory-face)))

(defun textui-btop-prototype--network-lines (width height)
  "Return HEIGHT lines for the live network graph at WIDTH."
  (let* ((inside (max 1 (- width 2)))
         (stats-width (if (>= width 48) 22 14))
         (graph-width (max 5 (- inside stats-width 1)))
         (half (max 1 (/ height 2)))
         (down-graph (textui-btop-prototype--graph-lines
                      textui-btop-prototype--download-history
                      graph-width half 'textui-btop-prototype-net-face
                      (if textui-btop-prototype--download-history
                          (apply #'max
                                 textui-btop-prototype--download-history)
                        1.0)))
         (up-graph (textui-btop-prototype--graph-lines
                    textui-btop-prototype--upload-history
                    graph-width (- height half)
                    'textui-btop-prototype-upload-face
                    (if textui-btop-prototype--upload-history
                        (apply #'max
                               textui-btop-prototype--upload-history)
                      1.0)))
         (graphs (append down-graph up-graph)))
    (cl-loop
     for row below height
     collect
     (let ((stats
            (cond
             ((= row 0) "▼ download")
              ((= row 1)
              (format "▼ %s/s"
                      (file-size-human-readable
                       textui-btop-prototype--download-rate)))
             ((= row (1- half))
              (format "▼ Total: %s"
                      (file-size-human-readable
                       textui-btop-prototype--download-total)))
             ((= row half) "▲ upload")
             ((= row (1+ half))
              (format "▲ %s/s"
                      (file-size-human-readable
                       textui-btop-prototype--upload-rate)))
             ((= row (1- height))
              (format "▲ Total: %s"
                      (file-size-human-readable
                       textui-btop-prototype--upload-total)))
             (t ""))))
       (concat (nth row graphs) " "
               (textui-btop-prototype--fit stats stats-width))))))

(defun textui-btop-prototype--network-panel (width height)
  "Return live network panel at WIDTH by HEIGHT."
  (textui-btop-prototype--simple-panel
   width height "3" "net" "en0"
   (textui-btop-prototype--network-lines width (max 0 (- height 2)))
   'textui-btop-prototype-net-face))

(defun textui-btop-prototype--process-cpu (process)
  "Return real sampled CPU percentage for PROCESS."
  (or (plist-get process :cpu) 0.0))

(defun textui-btop-prototype--ordered-processes ()
  "Return filtered and sorted sampled processes."
  (let* ((filter (textui-btop-prototype--state :filter))
         (filtered
          (if (string-empty-p filter)
              (copy-sequence textui-btop-prototype--processes)
            (cl-remove-if-not
             (lambda (process)
               (string-match-p
                (regexp-quote filter)
                (downcase (plist-get process :name))))
             textui-btop-prototype--processes)))
         (key (aref [cpu memory pid]
                    (textui-btop-prototype--state :sort-index)))
         (sorted
          (sort filtered
                (lambda (left right)
                  (> (pcase key
                       ('cpu (textui-btop-prototype--process-cpu left))
                       ('memory (plist-get left :mem))
                       (_ (plist-get left :pid)))
                     (pcase key
                       ('cpu (textui-btop-prototype--process-cpu right))
                       ('memory (plist-get right :mem))
                       (_ (plist-get right :pid))))))))
    (if (textui-btop-prototype--state :reversed)
        (nreverse sorted)
      sorted)))

(defun textui-btop-prototype--current-process ()
  "Return currently selected process."
  (let ((processes (textui-btop-prototype--ordered-processes)))
    (nth (min (textui-btop-prototype--state :process-index)
              (max 0 (1- (length processes))))
         processes)))

(defun textui-btop-prototype--process-header (width)
  "Return process table header fitted to WIDTH."
  (if (>= width 72)
      (textui-btop-prototype--fit
       "   PID Program            Command                      State User       MemB  Cpu%" width)
    (textui-btop-prototype--fit "   PID Program                 MemB  Cpu%" width)))

(defun textui-btop-prototype--process-label (process width)
  "Return one responsive PROCESS row for WIDTH."
  (let ((cpu (textui-btop-prototype--process-cpu process)))
    (if (>= width 72)
        (format "%6d %-18s %-28s %-5s %-9s %5d %5.1f"
                (plist-get process :pid)
                (plist-get process :name)
                (plist-get process :command)
                (plist-get process :state)
                (plist-get process :user)
                (plist-get process :mem)
                (float cpu))
      (format "%6d %-23s %5d %5.1f"
              (plist-get process :pid)
              (plist-get process :name)
              (plist-get process :mem)
              (float cpu)))))

(defun textui-btop-prototype--process-row
    (process index width selected)
  "Return clickable PROCESS at INDEX in WIDTH."
  (let ((value (textui-btop-prototype--inside-line
                width (textui-btop-prototype--process-label
                       process (max 1 (- width 2))))))
    (list :type 'textui-btop-prototype-row
          :value value
          :button-face (if selected
                           'textui-btop-prototype-selected-face
                         'textui-btop-prototype-default-face)
          :mouse-face 'highlight
          :layout (append (list :width width)
                          (when selected '(:focus-id btop-process)))
          :action
          (lambda (&rest _)
            (textui-btop-prototype--update-lower
             (lambda (state)
               (textui-btop-prototype--state-with
                state :process-index index)))))))

(defun textui-btop-prototype--process-panel (width height)
  "Return process details and table at WIDTH by HEIGHT."
  (let* ((processes (textui-btop-prototype--ordered-processes))
         (maximum (max 0 (1- (length processes))))
         (selected (min (textui-btop-prototype--state :process-index)
                        maximum))
         (process (nth selected processes))
         (detail-height
          (if (and (textui-btop-prototype--state :details) process) 6 0))
         (fixed (+ 3 detail-height))
         (slots (max 1 (- height fixed)))
         (start (max 0 (min (- (length processes)
                               (min slots (length processes)))
                            (- selected (/ slots 2)))))
         (visible (cl-subseq processes start
                             (min (length processes) (+ start slots))))
         (sort (aref [cpu memory pid]
                     (textui-btop-prototype--state :sort-index)))
         (attributes (and process
                          (process-attributes (plist-get process :pid))))
         (threads (or (alist-get 'thcount attributes) 0))
         children)
    (push (textui-btop-prototype--item
           (textui-btop-prototype--title-line
            width "4" "proc"
            (format "%s%s%s"
                    sort
                    (if (textui-btop-prototype--state :reversed)
                        " reverse" "")
                    (if (textui-btop-prototype--state :paused)
                        " paused" ""))
            'textui-btop-prototype-process-face)
           width)
          children)
    (when (and (textui-btop-prototype--state :details) process)
      (dolist
          (line
           (list
            (format " Status: %-8s    Elapsed: %s"
                    (plist-get process :state)
                    (plist-get process :etime))
            (format " PID: %-8d User: %-10s Threads: %d"
                    (plist-get process :pid) (plist-get process :user)
                    threads)
            (format " CPU: %.1f%%      Memory: %d MiB"
                    (float (textui-btop-prototype--process-cpu process))
                    (plist-get process :mem))
            ""
            (format " %s" (plist-get process :command))))
        (push (textui-btop-prototype--item
               (textui-btop-prototype--inside-line width line) width)
              children))
      (push (textui-btop-prototype--item
             (textui-btop-prototype--separator-line
              width "proc  filter  per-core  reverse  tree"
              'textui-btop-prototype-process-face)
             width)
            children))
    (push (textui-btop-prototype--item
           (textui-btop-prototype--inside-line
            width (textui-btop-prototype--process-header (max 1 (- width 2))))
           width 'textui-btop-prototype-process-face)
          children)
    (let ((index start))
      (dolist (row visible)
        (push (textui-btop-prototype--process-row
               row index width (= index selected))
              children)
        (setq index (1+ index))))
    (dotimes (_ (- slots (length visible)))
      (push (textui-btop-prototype--item
             (textui-btop-prototype--inside-line width "") width)
            children))
    (push (textui-btop-prototype--item
           (textui-btop-prototype--bottom-line
            width (format "%d/%d" (if process (1+ selected) 0)
                          (length processes))
            'textui-btop-prototype-process-face)
           width)
          children)
    (list :type :flex :direction :column :gap 0
          :layout (list :width width :min-width width)
          :children (nreverse children))))

(defun textui-btop-prototype--visible-height ()
  "Return the smallest live body height for the prototype buffer."
  (let (heights)
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (push (window-body-height window) heights))
    (if heights (apply #'min heights) 42)))

(defun textui-btop-prototype--body-height ()
  "Return visible rows available above the one-line footer."
  (max 12 (1- (textui-btop-prototype--visible-height))))

(defun textui-btop-prototype--cpu-height ()
  "Return responsive CPU box height."
  (if (textui-btop-prototype--box-visible-p 'cpu)
      (max 8 (min 14 (/ (textui-btop-prototype--body-height) 3)))
    0))

(defun textui-btop-prototype--lower-height ()
  "Return rows available to the lower boxes."
  (max 8 (- (textui-btop-prototype--body-height)
            (textui-btop-prototype--cpu-height))))

(defun textui-btop-prototype--left-column (width height)
  "Return visible memory/network boxes at WIDTH by HEIGHT."
  (let ((mem (textui-btop-prototype--box-visible-p 'mem))
        (net (textui-btop-prototype--box-visible-p 'net)))
    (cond
     ((and mem net)
      (let ((top (/ height 2)))
        (list :type :flex :direction :column :gap 0
              :layout (list :width width :min-width width)
              :children
              (list (textui-btop-prototype--memory-group width top)
                    (textui-btop-prototype--network-panel
                     width (- height top))))))
     (mem (textui-btop-prototype--memory-group width height))
     (net (textui-btop-prototype--network-panel width height))
     (t nil))))

(defun textui-btop-prototype--lower-layout (width height)
  "Return responsive lower btop layout at WIDTH by HEIGHT."
  (let ((left-visible
         (or (textui-btop-prototype--box-visible-p 'mem)
             (textui-btop-prototype--box-visible-p 'net)))
        (proc-visible (textui-btop-prototype--box-visible-p 'proc)))
    (cond
     ((and (>= width 108) left-visible proc-visible)
      (let* ((left (max 46 (/ (* width 45) 100)))
             (right (- width left)))
        (list :type :flex :direction :row :gap 0
              :layout (list :width width :min-width width)
              :children
              (list (textui-btop-prototype--left-column left height)
                    (textui-btop-prototype--process-panel right height)))))
     ((and left-visible proc-visible)
      (let* ((mem (textui-btop-prototype--box-visible-p 'mem))
             (net (textui-btop-prototype--box-visible-p 'net))
             (left-count (+ (if mem 1 0) (if net 1 0)))
             (small (max 6 (/ height (+ left-count 2))))
             (used (* small left-count))
             children)
        (when mem
          (push (textui-btop-prototype--memory-group width small) children))
        (when net
          (push (textui-btop-prototype--network-panel width small) children))
        (push (textui-btop-prototype--process-panel
               width (max 6 (- height used)))
              children)
        (list :type :flex :direction :column :gap 0
              :layout (list :width width :min-width width)
              :children (nreverse children))))
     (left-visible (textui-btop-prototype--left-column width height))
     (proc-visible (textui-btop-prototype--process-panel width height))
     (t
      (textui-btop-prototype--simple-panel
       width height nil "btop" ""
       '(" No boxes visible. Press 1, 2, 3, or 4.")
       'textui-btop-prototype-muted-face)))))

(defun textui-btop-prototype--cpu-elements (width)
  "Return children for the high-frequency CPU refresh region."
  (list (textui-btop-prototype--cpu-panel
         width (textui-btop-prototype--cpu-height))))

(defun textui-btop-prototype--lower-elements (width)
  "Return children for the slower lower refresh region."
  (list (textui-btop-prototype--lower-layout
         width (textui-btop-prototype--lower-height))
        (textui-btop-prototype--footer width)))

(defun textui-btop-prototype--footer (width)
  "Return one responsive interaction footer for WIDTH."
  (textui-btop-prototype--item
   (textui-btop-prototype--fit
    (format "↑↓ select  Enter details  ←→ sort  / filter  r reverse  p %s  1-4 boxes  q quit"
            (if (textui-btop-prototype--state :paused) "resume" "pause"))
    width)
   width 'textui-btop-prototype-muted-face))

(defun textui-btop-prototype--frame (width)
  "Return complete btop-like frame for WIDTH."
  (setq textui-btop-prototype--last-height
        (textui-btop-prototype--visible-height))
  (let (children)
    (when (textui-btop-prototype--box-visible-p 'cpu)
      (push
       (list :type :flex :direction :column :gap 0
             :layout '(:refresh-id btop-cpu)
             :children (textui-btop-prototype--cpu-elements width))
       children))
    (push
     (list :type :flex :direction :column :gap 0
           :layout '(:refresh-id btop-lower)
           :children (textui-btop-prototype--lower-elements width))
     children)
    (list (list :type :flex :direction :column :gap 0
                :children (nreverse children)))))

(defun textui-btop-prototype--refresh-cpu ()
  "Refresh only the CPU region immediately."
  (when (assq 'btop-cpu textui--refresh-regions)
    (textui-refresh-region
     (current-buffer) 'btop-cpu #'textui-btop-prototype--cpu-elements)))

(defun textui-btop-prototype--update-lower (updater)
  "Apply state UPDATER; TextUI reconciles the changed named region."
  (textui-update (current-buffer) updater))

(defun textui-btop-prototype--tick-buffer (buffer)
  "Start a real asynchronous sample for prototype BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (textui-btop-prototype--start-sample))))

(defun textui-btop-prototype-move (amount)
  "Move process selection by AMOUNT."
  (interactive "p")
  (let ((maximum (max 0 (1- (length
                             (textui-btop-prototype--ordered-processes))))))
    (textui-btop-prototype--update-lower
     (lambda (state)
       (textui-btop-prototype--state-with
        state :process-index
        (max 0 (min maximum
                    (+ (min maximum (plist-get state :process-index))
                       amount))))))))

(defun textui-btop-prototype-down ()
  "Select the next process."
  (interactive)
  (textui-btop-prototype-move 1))

(defun textui-btop-prototype-up ()
  "Select the previous process."
  (interactive)
  (textui-btop-prototype-move -1))

(defun textui-btop-prototype-toggle-details ()
  "Toggle selected process details."
  (interactive)
  (textui-btop-prototype--update-lower
   (lambda (state)
     (textui-btop-prototype--state-with
      state :details (not (plist-get state :details))))))

(defun textui-btop-prototype-toggle-pause ()
  "Pause or resume real metric sampling."
  (interactive)
  (textui-btop-prototype--update-lower
   (lambda (state)
     (textui-btop-prototype--state-with
      state :paused (not (plist-get state :paused)))))
  (unless (textui-btop-prototype--state :paused)
    (textui-btop-prototype--start-sample)))

(defun textui-btop-prototype-cycle-sort (amount)
  "Cycle process sorting by AMOUNT."
  (interactive "p")
  (textui-btop-prototype--update-lower
   (lambda (state)
     (textui-btop-prototype--state-with
      state
      :sort-index (mod (+ (plist-get state :sort-index) amount) 3)
      :process-index 0))))

(defun textui-btop-prototype-toggle-reverse ()
  "Reverse the process ordering."
  (interactive)
  (textui-btop-prototype--update-lower
   (lambda (state)
     (textui-btop-prototype--state-with
      state
      :reversed (not (plist-get state :reversed))
      :process-index 0))))

(defun textui-btop-prototype-toggle-filter ()
  "Toggle a visible prototype process filter."
  (interactive)
  (textui-btop-prototype--update-lower
   (lambda (state)
     (textui-btop-prototype--state-with
      state
      :filter (if (string-empty-p (plist-get state :filter)) "emacs" "")
      :process-index 0))))

(defun textui-btop-prototype-toggle-box (box)
  "Toggle BOX and rebuild the responsive region structure."
  (textui-update
   (current-buffer)
   (lambda (state)
     (let ((boxes (plist-get state :boxes)))
       (textui-btop-prototype--state-with
        state :boxes
        (if (memq box boxes)
            (cl-remove box boxes)
          (cons box boxes)))))))

(defun textui-btop-prototype--maybe-refresh-for-height ()
  "Rebuild when a height-only resize changes panel allocation."
  (when (and (derived-mode-p 'textui-mode)
             (not textui--refreshing)
             textui--render-function)
    (let ((height (textui-btop-prototype--visible-height)))
      (when (and textui-btop-prototype--last-height
                 (/= height textui-btop-prototype--last-height))
        (textui-refresh (current-buffer))))))

(defun textui-btop-prototype--stop-timer ()
  "Stop this buffer's prototype timer and pending sampler."
  (when (timerp textui-btop-prototype--timer)
    (cancel-timer textui-btop-prototype--timer)
    (setq textui-btop-prototype--timer nil))
  (when (process-live-p textui-btop-prototype--sample-process)
    (process-put textui-btop-prototype--sample-process 'textui-buffer nil)
    (delete-process textui-btop-prototype--sample-process))
  (when (buffer-live-p textui-btop-prototype--sample-buffer)
    (kill-buffer textui-btop-prototype--sample-buffer))
  (setq textui-btop-prototype--sample-process nil
        textui-btop-prototype--sample-buffer nil))

(defun textui-btop-prototype--ensure-supported-system ()
  "Reject systems unsupported by the prototype's sampler commands."
  (unless (eq system-type 'darwin)
    (user-error "The btop prototype currently supports macOS only")))

(defun textui-btop-prototype-quit ()
  "Stop live sampling and kill the current prototype buffer."
  (interactive)
  (textui-btop-prototype--stop-timer)
  (kill-buffer (current-buffer)))

(defun textui-btop-prototype--install-keys ()
  "Install btop-like local keys."
  (let ((map (copy-keymap (current-local-map))))
    (dolist (key '("j" "\C-n" [down] [wheel-down] [mouse-5]))
      (define-key map key #'textui-btop-prototype-down))
    (dolist (key '("k" "\C-p" [up] [wheel-up] [mouse-4]))
      (define-key map key #'textui-btop-prototype-up))
    (define-key map (kbd "RET") #'textui-btop-prototype-toggle-details)
    (define-key map "p" #'textui-btop-prototype-toggle-pause)
    (define-key map [left]
                (lambda () (interactive)
                  (textui-btop-prototype-cycle-sort -1)))
    (define-key map [right]
                (lambda () (interactive)
                  (textui-btop-prototype-cycle-sort 1)))
    (define-key map "r" #'textui-btop-prototype-toggle-reverse)
    (define-key map "/" #'textui-btop-prototype-toggle-filter)
    (define-key map "1"
                (lambda () (interactive)
                  (textui-btop-prototype-toggle-box 'cpu)))
    (define-key map "2"
                (lambda () (interactive)
                  (textui-btop-prototype-toggle-box 'mem)))
    (define-key map "3"
                (lambda () (interactive)
                  (textui-btop-prototype-toggle-box 'net)))
    (define-key map "4"
                (lambda () (interactive)
                  (textui-btop-prototype-toggle-box 'proc)))
    (define-key map "q" #'textui-btop-prototype-quit)
    (use-local-map map)))

(defun textui-btop-prototype-open ()
  "Open the one-buffer btop-like prototype with live local data."
  (interactive)
  (textui-btop-prototype--ensure-supported-system)
  (let ((buffer (get-buffer-create textui-btop-prototype--buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'textui-mode)
        (textui-mode))
      (textui-btop-prototype--stop-timer)
      (setq-local textui-btop-prototype--tick 0
                  textui-btop-prototype--last-height nil
                  textui-btop-prototype--processes nil
                  textui-btop-prototype--cpu-value 0.0
                  textui-btop-prototype--cpu-model "sampling…"
                  textui-btop-prototype--load-average '(0.0 0.0 0.0)
                  textui-btop-prototype--memory-total 0
                  textui-btop-prototype--memory-used 0
                  textui-btop-prototype--memory-free 0
                  textui-btop-prototype--memory-cached 0
                  textui-btop-prototype--disk-total 0
                  textui-btop-prototype--disk-used 0
                  textui-btop-prototype--disk-free 0
                  textui-btop-prototype--download-rate 0.0
                  textui-btop-prototype--upload-rate 0.0
                  textui-btop-prototype--download-total 0
                  textui-btop-prototype--upload-total 0
                  textui-btop-prototype--network-sample nil
                  textui-btop-prototype--last-sample-ms 0.0
                  textui-btop-prototype--cpu-history nil
                  textui-btop-prototype--download-history nil
                  textui-btop-prototype--upload-history nil))
    (textui-open textui-btop-prototype--buffer-name
                 #'textui-btop-prototype--frame
                 (copy-tree textui-btop-prototype--initial-state))
    (let ((window (get-buffer-window buffer t)))
      (when window
        (delete-other-windows window)
        (select-window window)))
    (with-current-buffer buffer
      (setq-local truncate-lines t
                  line-spacing nil
                  cursor-type nil
                  mode-line-format nil)
      (unless textui-btop-prototype--face-cookie
        (setq textui-btop-prototype--face-cookie
              (face-remap-add-relative
               'default 'textui-btop-prototype-default-face)))
      (textui-btop-prototype--install-keys)
      (add-hook 'window-configuration-change-hook
                #'textui-btop-prototype--maybe-refresh-for-height nil t)
      (textui-register-cleanup
       buffer #'textui-btop-prototype--stop-timer)
      (setq textui-btop-prototype--timer
            (run-at-time textui-btop-prototype--interval
                         textui-btop-prototype--interval
                         #'textui-btop-prototype--tick-buffer buffer))
      (textui-btop-prototype--start-sample))
    buffer))

(unless noninteractive
  (set-frame-size (selected-frame) 150 44)
  (textui-btop-prototype-open)
  (set-frame-name "TextUI — btop live demo"))

(provide 'textui-btop-prototype)

;;; textui-btop-prototype.el ends here
