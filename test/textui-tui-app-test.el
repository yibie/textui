;;; textui-tui-app-test.el --- Retained TUI demo checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'textui-btop-prototype)
(require 'textui-k9s-local-refresh-prototype)
(require 'textui-lazygit-prototype)
(require 'textui-yazi-prototype)

(ert-deftest textui-yazi-prototype-ships-its-preview-image ()
  (let ((examples-directory
         (file-name-directory (locate-library "textui-yazi-prototype"))))
    (should (file-readable-p textui-yazi-prototype--image-file))
    (should (file-in-directory-p textui-yazi-prototype--image-file
                                 examples-directory))))

(ert-deftest textui-lazygit-prototype-refresh-key-is-a-command ()
  (should (commandp #'textui-lazygit-prototype--refresh)))

(ert-deftest textui-btop-prototype-rejects-unsupported-systems ()
  (let ((system-type 'gnu/linux))
    (should-error (textui-btop-prototype--ensure-supported-system)
                  :type 'user-error)))

(ert-deftest textui-btop-prototype-quit-kills-buffer-and-cleans-up ()
  (let ((buffer (generate-new-buffer " *textui-btop-quit-test*"))
        stopped)
    (with-current-buffer buffer
      (add-hook 'kill-buffer-hook
                (lambda () (setq stopped t)) nil t)
      (textui-btop-prototype-quit))
    (should-not (buffer-live-p buffer))
    (should stopped)))

(ert-deftest textui-btop-prototype-parses-real-system-output ()
  (with-temp-buffer
    (textui-btop-prototype--parse-system "17179869184\nApple M4\n")
    (textui-btop-prototype--parse-processes
     " 42 12.5 2048 ada R 01:23 /usr/bin/demo\n")
    (textui-btop-prototype--parse-memory
     "Mach Virtual Memory Statistics: (page size of 4096 bytes)\nPages free: 10.\nPages inactive: 20.\nPages speculative: 5.\nFile-backed pages: 8.\n")
    (textui-btop-prototype--parse-network
     "en0 1500 <Link#6> aa:bb 10 0 1024 20 0 2048 0\n")
    (should (equal textui-btop-prototype--cpu-model "Apple M4"))
    (should (= (plist-get (car textui-btop-prototype--processes) :pid) 42))
    (should (= (plist-get (car textui-btop-prototype--processes) :cpu) 12.5))
    (should (= textui-btop-prototype--memory-free (* 35 4096)))
    (should (= textui-btop-prototype--download-total 1024))
    (should (= textui-btop-prototype--upload-total 2048))
    (should
     (equal (mapcar #'substring-no-properties
                    (textui-btop-prototype--graph-lines
                     '(0 25 100) 3 1 'default))
            '(" ▂█")))))

(ert-deftest textui-btop-prototype-renders-from-buffer-state ()
  (with-temp-buffer
    (textui-mode)
    (setq-local textui-state
                (copy-tree textui-btop-prototype--initial-state))
    (let ((rendered
           (textui--render-frame
            (textui-btop-prototype--frame 100) 100)))
      (should (string-match-p "cpu" rendered))
      (should (string-match-p "proc" rendered)))))

(ert-deftest textui-k9s-demo-renders-one-buffer-with-bounded-viewport ()
  (let ((textui-tui-app-scope 'all)
        (textui-tui-app-selected nil))
    (with-temp-buffer
      (textui-mode)
      (setq-local
       textui-k9s-local-refresh-prototype--data
       (textui-k9s-local-refresh-prototype--make-data 100)
       textui-k9s-local-refresh-prototype--visible-rows nil
       textui-k9s-local-refresh-prototype--visible-scope nil
       textui-k9s-local-refresh-prototype--page-size 4
       textui-k9s-local-refresh-prototype--state '(:offset 0)
       textui-k9s-local-refresh-prototype--full-render-count 0)
      (let* ((rendered
              (textui--render-frame
               (textui-k9s-local-refresh-prototype--frame 150) 150))
             (lines (split-string rendered "\n")))
        (should (string-match-p
                 (regexp-quote "Pods(all)[100]") rendered))
        (should (= (length lines) 15))
        (should (= textui-k9s-local-refresh-prototype--full-render-count 1))
        (dolist (line lines)
          (should (<= (string-width line) 150)))))))

(ert-deftest textui-k9s-demo-reducer-jumps-without-walking-data ()
  (let ((state '(:offset 0)))
    (should
     (equal
      (textui-k9s-local-refresh-prototype--reduce
       state :end 10000 12)
      '(:offset 9988)))
    (should
     (equal
      (textui-k9s-local-refresh-prototype--reduce
       '(:offset 9988) '(:scroll 1) 10000 12)
      '(:offset 9988)))
    (should
     (equal
      (textui-k9s-local-refresh-prototype--reduce
       state '(:scroll -1) 10000 12)
      '(:offset 0)))))

(ert-deftest textui-k9s-demo-derives-viewport-height ()
  (should (= (textui-k9s-local-refresh-prototype--page-size-for-height
              35 17)
             17))
  (should (= (textui-k9s-local-refresh-prototype--page-size-for-height
              10 20)
             1)))

(provide 'textui-tui-app-test)

;;; textui-tui-app-test.el ends here
