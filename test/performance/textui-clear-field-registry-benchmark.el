;;; textui-clear-field-registry-benchmark.el --- Registry clear experiment -*- lexical-binding: t; -*-

;;; Code:

(require 'textui-widgets-benchmark)

(let ((commit (symbol-function 'textui--commit-full-frame)))
  (unwind-protect
      (progn
        (fset 'textui--commit-full-frame
              (lambda (&rest arguments)
                (setq widget-field-list nil
                      widget-field-new nil)
                (apply commit arguments)))
        (textui-widgets-benchmark 1000 11))
    (fset 'textui--commit-full-frame commit)))

;;; textui-clear-field-registry-benchmark.el ends here
