# Interface elements are property lists

Each public DSL element is an ordinary property list with a required `:type`.
TextUI v1 will not add element constructor functions, a macro language, or a
second tree syntax: plists are already proven by the source implementation and
remain easy to generate with ordinary Lisp. This accepts a little visible
verbosity to avoid another evaluation and extension mechanism.
