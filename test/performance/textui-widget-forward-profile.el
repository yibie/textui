;;; textui-widget-forward-profile.el --- Forward placeholder experiment -*- lexical-binding: t; -*-

;;; Code:

(require 'textui-widgets-benchmark)

(let ((ranges (symbol-function 'textui--placeholder-ranges))
      (profile-file
       (expand-file-name
        "textui-widget-phase-profile.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  (unwind-protect
      (progn
        (fset 'textui--placeholder-ranges
              (lambda (&optional from to)
                (nreverse (funcall ranges from to))))
        (load profile-file nil t))
    (fset 'textui--placeholder-ranges ranges)))

;;; textui-widget-forward-profile.el ends here
