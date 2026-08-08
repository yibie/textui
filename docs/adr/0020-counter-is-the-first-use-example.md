# Counter is the first-use example

The first public example opens one real interactive buffer, presents ordinary
widget.el text and a push button in a flex row, mutates one Lisp variable from
the button's native `:action`, and relies on TextUI's automatic refresh:

```elisp
(require 'textui)
(defvar my-clicks 0)

(textui-open
 "*Clicks*"
 (lambda (_width)
   (list
    `(:type :flex :direction :row :gap 2
      :children
      ((:type item :format "%v" :value "Clicks:")
       (:type push-button :value ,(number-to-string my-clicks)
        :action ,(lambda (&rest _)
                   (setq my-clicks (1+ my-clicks)))))))))
```

It is deliberately small but exercises the complete public path: render
function, proper-list frame, TextUI layout, direct widget.el controls, ordinary
Lisp state, native action, and one automatic redraw. It was run in a clean
`emacs -q` GUI and rapid repeated mouse clicks were verified after handling
Emacs's double- and triple-click release events.
