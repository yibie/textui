# Prototypes extract proven layout primitives

TextUI reproduces demanding interfaces such as dashboards, k9s-like tables,
and Yazi-like file managers to discover missing framework capabilities under
real layout and interaction pressure. These prototypes are capability probes,
not promises to add an application-specific component catalogue.

The Yazi prototype exposed one general gap: a file preview must occupy a
rectangular part of a character grid, while an ordinary Emacs image glyph sits
on one logical line and makes that entire line taller. Converting the image to
colored block characters preserved the grid but unnecessarily discarded Emacs'
native image display.

When a prototype demonstrates a general need and validates its behavior, TextUI
extracts the smallest reusable primitive into the framework and changes the
prototype to consume that primitive. The prototype keeps application policy;
TextUI owns the difficult mapping between declarative content and layout.

The first extraction under this rule is the `:image` rendering leaf:

```elisp
(:type :image :file "/path/to/image.png" :rows 12 :alt "image.png"
 :layout (:width 40 :min-width 12 :grow 1))
```

`:file` names an image format supported by Emacs. `:rows` is a positive number
of text rows chosen by the caller, and `:alt` is optional alternative text.
TextUI fits the image within its allocated width and row count, preserves its
aspect ratio, centers it, and divides the native display into horizontal slices
whose pixel heights match ordinary text rows. The slices therefore remain one
continuous image without changing sibling line heights. Non-graphical Emacs
presents the alternative text in a block with the same row count.

This does not make TextUI a widget library or a height-allocation engine.
`:image` is a rendering primitive, like width-aware `:text`, because every
caller would otherwise have to repeat the same display-property and geometry
logic. The caller still decides how many rows are available. Native images
inside widget.el controls retain their separate one-line compatibility rule.

Future prototypes do not automatically enlarge TextUI. A finding moves into the
framework only after the reproduced interface proves that the capability is
general, the experiment validates its behavior, and one small interface can
hide complexity that would otherwise be repeated by callers.
