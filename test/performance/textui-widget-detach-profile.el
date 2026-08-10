;;; textui-widget-detach-profile.el --- Detached marker experiment -*- lexical-binding: t; -*-

;;; Code:

(require 'textui-widgets-benchmark)

(let ((delete (symbol-function 'widget-delete))
      (profile-file
       (expand-file-name
        "textui-widget-phase-profile.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  (unwind-protect
      (progn
        (fset 'widget-delete
              (lambda (widget)
                (let ((from (widget-get widget :from))
                      (to (widget-get widget :to)))
                  (prog1 (funcall delete widget)
                    (when (markerp from)
                      (set-marker from nil))
                    (when (markerp to)
                      (set-marker to nil))))))
        (load profile-file nil t))
    (fset 'widget-delete delete)))

;;; textui-widget-detach-profile.el ends here
