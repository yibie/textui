;;; textui-kp-core.el --- Minimal Knuth-Plass core for TextUI -*- lexical-binding: t; -*-

;; Adapted from emacs-kp commit e823d89a4a5097dce0316ba66c83cf44e98f3aa8.
;; Upstream: https://github.com/Kinneyzhang/emacs-kp
;; Copyright (C) 2024-2026 Kinney Zhang
;; Copyright (C) 2026 chenyibin
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; The fixed subset TextUI needs: pixel measurement, Latin/CJK boxing,
;; common kinsoku rules, the one-dimensional Knuth-Plass optimizer, and
;; display-only glue allocation for justified lines.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defconst textui-kp-core--no-line-start
  (append ".,;:!?)]}%’”»›…·" nil))
(defconst textui-kp-core--no-line-end
  (append "([{‘“«‹" nil))
(defconst textui-kp-core--no-break-joiners
  '(#x00A0 #x202F #x2007 #x2060 #xFEFF))

(defun textui-kp-core--pixel-width (string)
  "Return STRING's pixel width in the current display context."
  (if (null face-remapping-alist)
      (string-pixel-width string)
    (let ((remap face-remapping-alist))
      (with-current-buffer (get-buffer-create " *textui-kp-width*" t)
        (setq-local face-remapping-alist remap
                    line-prefix nil
                    wrap-prefix nil)
        (erase-buffer)
        (insert string)
        (prog1 (car (buffer-text-pixel-size nil nil t))
          (erase-buffer))))))

(defun textui-kp-core--font-family (string)
  "Return the font family used to display STRING."
  (if-let* ((font (and (display-multi-font-p)
                       (ignore-errors (font-at 0 nil string)))))
      (format "%s" (font-get font :family))
    (let ((family (face-attribute 'default :family)))
      (if (stringp family) family (format "%s" family)))))

(defun textui-kp-core--word-space-width (string)
  "Return the pixel width of STRING's Latin word space."
  (let* ((position (string-match "[A-Za-zÀ-ÖØ-öø-ÿĀ-ɏḀ-ỿ]" string))
         (sample (if position (substring string position (1+ position)) " "))
         (family (textui-kp-core--font-family sample)))
    (max 1 (textui-kp-core--pixel-width
            (propertize " " 'face `(:family ,family))))))

(defun textui-kp-core--measure-boxes (boxes)
  "Return BOXES' widths, measuring equal attributed strings once."
  (let ((seen (make-hash-table :test 'equal))
        (widths (make-vector (length boxes) 0))
        (index 0))
    (while (< index (length boxes))
      (let* ((box (aref boxes index))
             (key (cons (substring-no-properties box)
                        (object-intervals box)))
             (cached (gethash key seen 'missing))
             (width (if (eq cached 'missing)
                        (puthash key (textui-kp-core--pixel-width box) seen)
                      cached)))
        (aset widths index width)
        (setq index (1+ index))))
    widths))

(defun textui-kp-core--cjk-punctuation-p (string)
  "Return non-nil when STRING starts with full-width CJK punctuation."
  (let ((char (aref string 0)))
    (and (not (or (<= #xFF10 char #xFF19)
                  (<= #xFF21 char #xFF3A)
                  (<= #xFF41 char #xFF5A)))
         (or (eq (char-syntax char) ?.)
             (<= #x3000 char #x303F)
             (<= #xFF00 char #xFF60)))))

(defun textui-kp-core--opening-punctuation-p (string)
  "Return non-nil when STRING ends with opening punctuation."
  (memq (get-char-code-property (aref string (1- (length string)))
                                'general-category)
        '(Ps Pi)))

(defun textui-kp-core--zero-width-attaching-p (char)
  "Return non-nil when zero-width CHAR attaches to preceding text."
  (or (memq (get-char-code-property char 'general-category) '(Mn Mc Me))
      (memq char '(#x200C #x200D #x034F #x2060 #xFEFF))
      (<= #xFE00 char #xFE0F)))

(defun textui-kp-core--flush (parts boxes)
  "Join reversed PARTS and push the result onto BOXES."
  (if parts (cons (apply #'concat (nreverse parts)) boxes) boxes))

(defun textui-kp-core--flush-spaces (parts boxes previous next)
  "Push reversed space PARTS according to PREVIOUS and NEXT box widths."
  (if (null parts)
      boxes
    (let ((spaces (apply #'concat (nreverse parts))))
      (cond
       ((or (null boxes) (= previous 2) (= next 2))
        (cons spaces boxes))
       ((> (length spaces) 1)
        (cons spaces boxes))
       (t boxes)))))

(defun textui-kp-core--split-boxes (string)
  "Split STRING into Latin-word, CJK-character, and literal-space boxes."
  (if (string-blank-p string)
      (vector string)
    (with-temp-buffer
      (insert string)
      (goto-char (point-min))
      (let ((state (char-width (aref string 0)))
            (previous 1)
            latin cjk spaces boxes)
        (while (not (eobp))
          (let* ((part (buffer-substring (point) (1+ (point))))
                 (char (aref part 0))
                 (width (string-width part)))
            (cond
             ((and (= width 0) (not (string-blank-p part))
                   (textui-kp-core--zero-width-attaching-p char))
              (cond
               (latin (push part latin))
               (cjk (push part cjk))
               (spaces (push part spaces))
               (boxes
                (if (= previous 2)
                    (setq cjk (list part (pop boxes)) state 2)
                  (setq latin (list part (pop boxes)) state 1)))
               (t (setq latin (list part) state 1))))
             ((or (string-blank-p part) (= width 0))
              (when cjk (setq boxes (textui-kp-core--flush cjk boxes)
                                   previous 2
                                   cjk nil))
              (when latin (setq boxes (textui-kp-core--flush latin boxes)
                                     previous 1
                                     latin nil))
              (push part spaces))
             (t
              (setq boxes (textui-kp-core--flush-spaces
                           spaces boxes previous width)
                    spaces nil)
              (if (= width 1)
                  (if (= state 1)
                      (push part latin)
                    (setq boxes (textui-kp-core--flush cjk boxes)
                          cjk nil
                          latin (list part)
                          state 1))
                (if (= state 1)
                    (setq boxes (textui-kp-core--flush latin boxes)
                          latin nil
                          cjk (list part)
                          state 2)
                  (setq boxes (textui-kp-core--flush cjk boxes)
                        cjk (list part)))))))
          (forward-char 1))
        (setq boxes (textui-kp-core--flush cjk boxes)
              boxes (textui-kp-core--flush latin boxes)
              boxes (textui-kp-core--flush spaces boxes))
        (vconcat (nreverse boxes))))))

(defun textui-kp-core--identifier-char-p (char)
  "Return non-nil when CHAR is an ASCII identifier character."
  (or (<= ?A char ?Z) (<= ?a char ?z) (<= ?0 char ?9)))

(defun textui-kp-core--identifier-separator-end (token index)
  "Return the end of TOKEN's identifier separator at INDEX."
  (pcase (aref token index)
    ((or ?_ ?.) (1+ index))
    (?: (and (< (1+ index) (length token))
             (= (aref token (1+ index)) ?:) (+ index 2)))
    (?- (and (< (1+ index) (length token))
             (= (aref token (1+ index)) ?>) (+ index 2)))))

(defun textui-kp-core--identifier-breaks (token)
  "Return camelCase and digit boundary indexes in TOKEN."
  (let ((index 1)
        breaks)
    (when (and (> (length token) 1)
               (or (<= ?A (aref token 0) ?Z)
                   (<= ?a (aref token 0) ?z))
               (textui-kp-core--identifier-char-p
                (aref token (1- (length token)))))
      (let ((valid t))
        (while (and valid (< index (length token)))
          (let ((previous (aref token (1- index)))
                (current (aref token index)))
            (cond
             ((textui-kp-core--identifier-char-p current)
              (when (or (and (<= ?a previous ?z) (<= ?A current ?Z))
                        (and (or (<= ?A previous ?Z) (<= ?a previous ?z))
                             (<= ?0 current ?9)))
                (push index breaks))
              (setq index (1+ index)))
             ((let ((end (textui-kp-core--identifier-separator-end
                          token index)))
                (if (and end (< end (length token))
                         (textui-kp-core--identifier-char-p previous)
                         (textui-kp-core--identifier-char-p (aref token end)))
                    (setq breaks (cons end breaks)
                          index end)
                  (setq valid nil)))))))
        (and valid breaks (nreverse breaks))))))

(defun textui-kp-core--token-breaks (token)
  "Return fixed legal break indexes inside TOKEN."
  (if (or (string-match-p "://" token)
          (string-match-p "[/\\\\]" token))
      (let ((index 0)
            breaks)
        (while (< index (length token))
          (when (memq (aref token index) '(?/ ?\\))
            (push (1+ index) breaks))
          (setq index (1+ index)))
        (nreverse breaks))
    (textui-kp-core--identifier-breaks token)))

(defun textui-kp-core--split-tokens (string boxes)
  "Split whitespace-delimited identifier, URL, and path BOXES."
  (let ((source-position 0)
        result)
    (dolist (box (append boxes nil) (vconcat (nreverse result)))
      (let ((length (length box)))
        (while (not (eq t (compare-strings
                           string source-position (+ source-position length)
                           box 0 length)))
          (setq source-position (1+ source-position)))
        (let* ((source-end (+ source-position length))
               (isolated
                (and (or (= source-position 0)
                         (string-blank-p
                          (substring string (1- source-position)
                                     source-position)))
                     (or (= source-end (length string))
                         (string-blank-p
                          (substring string source-end (1+ source-end))))))
               (start 0)
               (breaks (and isolated (textui-kp-core--token-breaks box))))
        (dolist (end breaks)
          (push (substring box start end) result)
          (setq start end))
        (when (< start (length box))
            (push (substring box start) result))
          (setq source-position source-end))))))

(defvar textui-kp-core--type-table (make-char-table 'textui-kp-core-type))

(defun textui-kp-core--char-type (string)
  "Return STRING's cached typographic character class."
  (let ((char (aref string 0)))
    (or (aref textui-kp-core--type-table char)
        (aset textui-kp-core--type-table char
              (cond
               ((or (string-blank-p string) (= (string-width string) 0))
                'space)
               ((member string '("“" "”")) 'cjk)
               ((= (string-width string) 1) 'latin)
               ((textui-kp-core--opening-punctuation-p string) 'cjk-open)
               ((textui-kp-core--cjk-punctuation-p string) 'cjk-close)
               (t 'cjk))))))

(defun textui-kp-core--edge-char (box from-end)
  "Return BOX's first visible char, or last when FROM-END is non-nil."
  (let* ((length (length box))
         (index (if from-end (1- length) 0))
         (step (if from-end -1 1)))
    (while (and (<= 0 index) (< index length)
                (= (char-width (aref box index)) 0))
      (setq index (+ index step)))
    (substring box index (1+ index))))

(defun textui-kp-core--box-type (box)
  "Return BOX's (START-TYPE . END-TYPE)."
  (if (or (string-blank-p box) (= (string-width box) 0))
      '(space . space)
    (cons (textui-kp-core--char-type (textui-kp-core--edge-char box nil))
          (textui-kp-core--char-type (textui-kp-core--edge-char box t)))))

(defun textui-kp-core--glue-type (previous current)
  "Return the glue type between PREVIOUS and CURRENT box types."
  (let ((before (cdr previous))
        (after (car current)))
    (cond
     ((null before) 'nws)
     ((or (eq before 'space) (eq after 'space)
          (eq before 'cjk-open) (eq after 'cjk-close)) 'nws)
     ((and (eq before 'latin) (eq after 'latin)) 'lws)
     ((and (eq before 'cjk) (eq after 'cjk)) 'cws)
     ((or (and (eq before 'cjk) (eq after 'latin))
          (and (eq before 'latin) (eq after 'cjk))) 'mws)
     ((or (eq before 'cjk-close) (eq after 'cjk-open)) 'cws)
     (t 'nws))))

(defun textui-kp-core--pure-set-p (box chars)
  "Return non-nil when every character in BOX belongs to CHARS."
  (seq-every-p (lambda (char) (memq char chars)) box))

(defun textui-kp-core--break-forbidden-p (boxes types position)
  "Return non-nil when BOXES may not break at POSITION."
  (let* ((previous (aref boxes (1- position)))
         (current (aref boxes position))
         (previous-type (aref types (1- position)))
         (current-type (aref types position)))
    (or (eq (cdr previous-type) 'cjk-open)
        (eq (car current-type) 'cjk-close)
        (textui-kp-core--pure-set-p previous textui-kp-core--no-line-end)
        (textui-kp-core--pure-set-p current textui-kp-core--no-line-start)
        (memq (aref previous (1- (length previous)))
              textui-kp-core--no-break-joiners)
        (memq (aref current 0) textui-kp-core--no-break-joiners))))

(defun textui-kp-core--box-offsets (string boxes)
  "Locate BOXES in STRING and return their source ranges."
  (let ((offsets (make-vector (length boxes) nil))
        (position 0)
        (index 0))
    (while (< index (length boxes))
      (let* ((box (aref boxes index))
             (length (length box)))
        (while (not (eq t (compare-strings
                           string position (+ position length)
                           box 0 length)))
          (setq position (1+ position)))
        (aset offsets index (cons position (+ position length)))
        (setq position (+ position length)
              index (1+ index))))
    offsets))

(defun textui-kp-core--badness (adjustment flexibility)
  "Return Knuth-Plass badness for ADJUSTMENT and FLEXIBILITY."
  (cond
   ((= adjustment 0) 0)
   ((<= flexibility 0) 10000)
   (t (min 10000 (* 100 (expt (abs (/ (float adjustment) flexibility)) 3))))))

(defun textui-kp-core--fitness (adjustment flexibility)
  "Return the Knuth-Plass fitness class for a line."
  (if (<= flexibility 0)
      1
    (let ((ratio (/ (float adjustment) flexibility)))
      (cond ((< ratio -0.5) 0)
            ((< ratio 0.5) 1)
            ((< ratio 1.0) 2)
            (t 3)))))

(defun textui-kp-core--demerits (badness previous current)
  "Return line demerits from BADNESS, PREVIOUS, and CURRENT fitness."
  (+ (expt (+ 10 badness) 2)
     (if (> (abs (- previous current)) 1) 100 0)))

(defun textui-kp-core--line-width
    (prefix glue-ideals lead-spaces trail-spaces start end)
  "Return the visible natural width of boxes START through END."
  (let ((raw (- (aref prefix end) (aref prefix start)
                (aref glue-ideals start))))
    (- raw (min raw (+ (aref lead-spaces start)
                       (aref trail-spaces end))))))

(defun textui-kp-core--trace (backpointers end)
  "Return break positions ending at END through BACKPOINTERS."
  (let ((breaks (list end)))
    (while (> end 0)
      (setq end (aref backpointers end))
      (when (> end 0) (push end breaks)))
    breaks))

(defun textui-kp-core--optimize
    (prefix glue-ideals lead-spaces trail-spaces breaks-ok line-width
            extra-stretch emergency-stretch)
  "Run the fixed one-dimensional Knuth-Plass dynamic program."
  (let* ((n (1- (length prefix)))
         (emergency (> emergency-stretch 0))
         (backpointers (make-vector (1+ n) nil))
         (costs (make-vector (1+ n) nil))
         (fitnesses (make-vector (1+ n) 1))
         (artificial (and emergency (make-vector (1+ n) nil)))
         (surviving (and emergency (make-bool-vector (1+ n) nil))))
    (aset costs 0 0.0)
    (dotimes (start n)
      (when (and emergency
                 (null (aref costs start))
                 (not (aref surviving start))
                 (aref artificial start))
        (pcase-let ((`(,cost . ,previous) (aref artificial start)))
          (aset costs start cost)
          (aset backpointers start previous)
          (aset fitnesses start 0)))
      (when (aref costs start)
        (let ((end (1+ start)))
          (catch 'overfull
            (while (<= end n)
              (if (not (or (= end n) (aref breaks-ok end)))
                  (setq end (1+ end))
                (let* ((last (= end n))
                       (single (= end (1+ start)))
                       (ideal (textui-kp-core--line-width
                               prefix glue-ideals lead-spaces trail-spaces
                               start end))
                       (adjustment (- line-width ideal))
                       (flexibility (+ extra-stretch emergency-stretch)))
                  (cond
                   ((or (< adjustment 0) (and last (< adjustment 0)))
                    (when emergency
                      (let ((candidate (aref artificial end))
                            (cost (aref costs start)))
                        (when (or (null candidate) (< cost (car candidate)))
                          (aset artificial end (cons cost start)))))
                    (throw 'overfull nil))
                   ((or (<= adjustment flexibility) last)
                    (when emergency (aset surviving end t))
                    (let* ((current-fitness
                            (if last 1
                              (if single
                                  (if emergency
                                      (textui-kp-core--fitness
                                       adjustment emergency-stretch)
                                    1)
                                (textui-kp-core--fitness
                                 adjustment flexibility))))
                           (line-cost
                            (cond
                             (single
                              (textui-kp-core--demerits
                               (textui-kp-core--badness
                                adjustment
                                (if emergency emergency-stretch 1))
                               (aref fitnesses start) current-fitness))
                             (last
                              (let ((ratio (/ (float ideal) line-width)))
                                (expt (+ 10 (if (< ratio 0.5)
                                               (* 50 (- 1.0 ratio))
                                             0))
                                      2)))
                             (t
                              (textui-kp-core--demerits
                               (textui-kp-core--badness
                                adjustment flexibility)
                               (aref fitnesses start) current-fitness))))
                           (total (+ (aref costs start) line-cost)))
                      (when (or (null (aref costs end))
                                (< total (aref costs end)))
                        (aset costs end total)
                        (aset backpointers end start)
                        (aset fitnesses end current-fitness))))
                   (emergency (aset surviving end t)))
                  (setq end (1+ end)))))))))
    (when (and emergency (null (aref costs n))
               (not (aref surviving n)) (aref artificial n))
      (aset costs n (car (aref artificial n)))
      (aset backpointers n (cdr (aref artificial n))))
    (and (aref costs n) (textui-kp-core--trace backpointers n))))

(defun textui-kp-core-break-lines (string line-pixel)
  "Return optimal source ranges for STRING at LINE-PIXEL."
  (if (string-empty-p string)
      (list (cons 0 0))
    (let* ((boxes (textui-kp-core--split-tokens
                   string (textui-kp-core--split-boxes string)))
           (n (length boxes))
           (types (vconcat (mapcar #'textui-kp-core--box-type boxes)))
           (glue-types (make-vector n 'nws))
           (word-space (textui-kp-core--word-space-width string))
           (mixed-space (max 0 (1- word-space)))
           (widths (textui-kp-core--measure-boxes boxes))
           (glue-ideals (make-vector n 0))
           (prefix (make-vector (1+ n) 0))
           (lead-spaces (make-vector (1+ n) 0))
           (trail-spaces (make-vector (1+ n) 0))
           (breaks-ok (make-bool-vector (1+ n) t))
           (offsets (textui-kp-core--box-offsets string boxes)))
      (dotimes (index n)
        (aset glue-types index
              (textui-kp-core--glue-type
               (and (> index 0) (aref types (1- index)))
               (aref types index))))
      (cl-loop for position from 1 below n
               when (textui-kp-core--break-forbidden-p
                     boxes types position)
               do (aset breaks-ok position nil)
               and do (aset glue-types position 'nws))
      (dotimes (index n)
        (let* ((type (aref glue-types index))
               (glue (cond ((eq type 'lws) word-space)
                           ((eq type 'mws) mixed-space)
                           (t 0)))
               (box-width (aref widths index)))
          (aset glue-ideals index glue)
          (aset prefix (1+ index)
                (+ (aref prefix index) box-width glue))
          (aset trail-spaces (1+ index)
                (if (eq (car (aref types index)) 'space)
                    (+ (aref trail-spaces index) box-width)
                  0))))
      (cl-loop for index downfrom (1- n) to 0
               do (aset lead-spaces index
                        (if (eq (car (aref types index)) 'space)
                            (+ (aref widths index)
                               (aref lead-spaces (1+ index)))
                          0)))
      (aset lead-spaces 0 0)
      (let* ((extra (* 8 word-space))
             (strict (textui-kp-core--optimize
                      prefix glue-ideals lead-spaces trail-spaces breaks-ok
                      line-pixel extra 0))
             (breaks
              (or strict
                  (textui-kp-core--optimize
                   prefix glue-ideals lead-spaces trail-spaces breaks-ok
                   line-pixel extra
                   (* 3 (max 1 (textui-kp-core--pixel-width "M"))))))
             (start 0)
             (line-index 0)
             ranges)
        (dolist (end breaks)
          (let ((kept-start start)
                (kept-end end))
            (when (> line-index 0)
              (while (and (< kept-start kept-end)
                          (eq (car (aref types kept-start)) 'space))
                (setq kept-start (1+ kept-start))))
            (while (and (< kept-start kept-end)
                        (eq (car (aref types (1- kept-end))) 'space))
              (setq kept-end (1- kept-end)))
            (when (< kept-start kept-end)
              (push (cons (car (aref offsets kept-start))
                          (cdr (aref offsets (1- kept-end))))
                    ranges))
            (setq start end
                  line-index (1+ line-index))))
        (or (nreverse ranges) (list (cons 0 (length string))))))))

(defun textui-kp-core--glue-ideal-pixel (type word-space mixed-space)
  "Return TYPE's ideal width for WORD-SPACE and MIXED-SPACE."
  (pcase type
    ('lws word-space)
    ('mws mixed-space)
    (_ 0)))

(defun textui-kp-core--line-gaps (boxes types offsets)
  "Return adjustable gaps between BOXES at OFFSETS and TYPES."
  (let ((index 1)
        gaps)
    (while (< index (length boxes))
      (let* ((type (textui-kp-core--glue-type
                    (aref types (1- index)) (aref types index)))
             (start (cdr (aref offsets (1- index))))
             (end (car (aref offsets index))))
        (unless (textui-kp-core--break-forbidden-p boxes types index)
          (when (and (memq type '(lws mws cws))
                     (or (< start end) (memq type '(mws cws))))
            (push (vector type start end end) gaps))))
      (setq index (1+ index)))
    (vconcat (nreverse gaps))))

(defun textui-kp-core--add-glue-pixels
    (gaps pixels type remaining limit)
  "Add REMAINING pixels to TYPE entries in PIXELS, capped by LIMIT.
Return the pixels not assigned.  A nil LIMIT assigns all remaining pixels."
  (let (indexes)
    (dotimes (index (length gaps))
      (when (eq (aref (aref gaps index) 0) type)
        (push index indexes)))
    (setq indexes (nreverse indexes))
    (if (or (null indexes) (<= remaining 0))
        remaining
      (let* ((count (length indexes))
             (used (if limit
                       (min remaining (* count limit))
                     remaining))
             (share (/ used count))
             (extra (% used count))
             (position 0))
        (dolist (index indexes)
          (aset pixels index
                (+ (aref pixels index) share
                   (if (< position extra) 1 0)))
          (setq position (1+ position)))
        (- remaining used)))))

(defun textui-kp-core--pixel-space (pixels)
  "Return one display-only space occupying PIXELS pixels."
  (propertize "\u200B"
              'display `(space :width (,pixels))
              'textui--synthetic-spacing t))

(defun textui-kp-core--apply-gap (line gap pixels)
  "Return attributed LINE with PIXELS applied to GAP."
  (let ((start (aref gap 1))
        (end (aref gap 2))
        (anchor (aref gap 3)))
    (if (< start end)
        (progn
          (put-text-property start (1+ start) 'display
                             `(space :width (,pixels)) line)
          (when (< (1+ start) end)
            (put-text-property (1+ start) end 'display
                               '(space :width (0)) line)))
      (when (> pixels 0)
        (setq line
              (concat (substring line 0 anchor)
                      (textui-kp-core--pixel-space pixels)
                      (substring line anchor)))))
    line))

(defun textui-kp-core--justify-line (line line-pixel last-line)
  "Pixel-justify attributed LINE to LINE-PIXEL.
LAST-LINE keeps its natural ragged-right spacing."
  (if (or last-line (string-blank-p line))
      line
    (let* ((boxes (textui-kp-core--split-tokens
                   line (textui-kp-core--split-boxes line)))
           (types (vconcat (mapcar #'textui-kp-core--box-type boxes)))
           (offsets (textui-kp-core--box-offsets line boxes))
           (widths (textui-kp-core--measure-boxes boxes))
           (word-space (textui-kp-core--word-space-width line))
           (mixed-space (max 0 (1- word-space)))
           (gaps (textui-kp-core--line-gaps boxes types offsets))
           (pixels (make-vector (length gaps) 0))
           (box-pixels (apply #'+ (append widths nil)))
           (ideal-pixels 0))
      (dotimes (index (length gaps))
        (let ((ideal (textui-kp-core--glue-ideal-pixel
                      (aref (aref gaps index) 0)
                      word-space mixed-space)))
          (aset pixels index ideal)
          (setq ideal-pixels (+ ideal-pixels ideal))))
      (if (= (length gaps) 0)
          line
        (let ((remaining (max 0 (- line-pixel box-pixels ideal-pixels))))
          (setq remaining
                (textui-kp-core--add-glue-pixels
                 gaps pixels 'lws remaining
                 (max 1 (round (* word-space 0.5)))))
          (setq remaining
                (textui-kp-core--add-glue-pixels
                 gaps pixels 'mws remaining
                 (max 0 (round (* mixed-space 0.5)))))
          (setq remaining
                (textui-kp-core--add-glue-pixels
                 gaps pixels 'cws remaining nil))
          (let ((index (1- (length gaps))))
            (while (>= index 0)
              (setq line
                    (textui-kp-core--apply-gap
                     line (aref gaps index) (aref pixels index)))
              (setq index (1- index))))
          (when (> remaining 0)
            (setq line (concat line
                               (textui-kp-core--pixel-space remaining))))
          (put-text-property 0 (length line)
                             'textui--pixel-justified t line)
          line)))))

(defun textui-kp-core-justify-lines (source attributed line-pixel)
  "Break SOURCE and pixel-justify matching ATTRIBUTED text to LINE-PIXEL."
  (let* ((ranges (textui-kp-core-break-lines source line-pixel))
         (last-index (1- (length ranges)))
         (index 0)
         lines)
    (dolist (range ranges (nreverse lines))
      (push (textui-kp-core--justify-line
             (substring attributed (car range) (cdr range))
             line-pixel (= index last-index))
            lines)
      (setq index (1+ index)))))

(provide 'textui-kp-core)

;;; textui-kp-core.el ends here
