# One complex dashboard gates 0.1

TextUI 0.1 is not gated by the number of toy examples or by migrating every
`org-supertag` view. Its single end-to-end product proof is the existing complex
`org-supertag` dashboard demo running well through TextUI.

The migrated dashboard must exercise the real layout and interaction path:
nested responsive layout at wide and narrow widths, native buttons and editable
fields, automatic action refresh, stable field state and focus, repeated mouse
clicks, and correct borders and spacing. The inline counter and focused Flex
demo remain API smoke tests; they do not replace this proof. The later
consolidation of runnable examples is recorded in
[ADR 0030](0030-six-focused-examples.md).

Other `org-supertag` views may be migrated incrementally after 0.1. Their
migration is not allowed to enlarge TextUI's initial public surface before the
dashboard exposes a concrete missing capability.
