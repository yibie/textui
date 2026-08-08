# Minimum Emacs version is 29.1

TextUI v1 declares `Package-Requires: ((emacs "29.1"))`. This matches
`org-supertag`'s existing floor and lets TextUI use modern Emacs display and
text-property APIs without compatibility branches for older releases.

Before release, Emacs 29.1 must successfully byte-compile the package and pass
the core automated and interactive smoke tests.
