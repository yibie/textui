# Custom elements expand to DSL

TextUI permits package authors to register custom element types, but their
element expanders are pure functions from one custom element plist to one or more
interface elements. Expanders cannot insert or erase text, create widgets or
overlays, inspect internal buffer state, or request refresh. This gives packages
reusable domain vocabulary without exposing TextUI's presentation bookkeeping or
weakening uniform refresh and validation.

Custom types are registered process-wide and must use their defining package's
symbol prefix, while TextUI reserves keyword types for its built-ins. Interfaces
do not carry private registries or extension environments.

Type resolution has one fixed order: a keyword selects a TextUI layout element;
a non-keyword symbol with an explicitly registered expander is expanded; any
other non-keyword symbol is passed to widget.el as a widget type; a type resolved
by neither system signals an error. An explicit expander therefore takes
precedence if its symbol also happens to name a widget.el type.

Registering the same custom type again replaces its previous expander, matching
normal Emacs re-evaluation and package-reload workflows. Package prefixes, not a
replacement flag or ownership subsystem, prevent legitimate packages from
colliding.

The sole public registration entry point is
`(textui-register-expander TYPE FUNCTION)`. It requires a function, returns
TYPE, and replaces any previous function for that type. V1 adds no definition
macro, local registry, replacement flag, or separate unregister function.

An expander always returns a proper list of zero or more interface-element
plists; even one result is wrapped in a list, and `nil` means no output. This
avoids guessing whether a Lisp list is one plist or a list of plists. Returned
custom elements are expanded recursively under the same contract.

Recursive expansion tracks custom types along the current ancestor path and
signals an error with that path if a type repeats. Sibling uses of the same type
remain valid. TextUI does not impose an arbitrary maximum depth; expanders that
own recursive data traverse it themselves and return non-cyclic DSL.

TextUI calls an expander with the complete original element plist as its only
argument and does not propagate common properties into the result. The expander
must place values such as `:layout (:focus-id ...)` on the appropriate returned
element itself; it receives no width, buffer, window, context, or registry object.
