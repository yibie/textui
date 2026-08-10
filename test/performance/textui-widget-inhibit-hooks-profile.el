;;; textui-widget-inhibit-hooks-profile.el --- Modification hook experiment -*- lexical-binding: t; -*-

;;; Code:

(require 'textui-widgets-benchmark)

(let ((commit (symbol-function 'textui--commit-full-frame))
      (profile-file
       (expand-file-name
        "textui-widget-phase-profile.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  (unwind-protect
      (progn
        (fset 'textui--commit-full-frame
              (lambda (&rest arguments)
                (let ((inhibit-modification-hooks t))
                  (apply commit arguments))))
        (load profile-file nil t))
    (fset 'textui--commit-full-frame commit)))

;;; textui-widget-inhibit-hooks-profile.el ends here
