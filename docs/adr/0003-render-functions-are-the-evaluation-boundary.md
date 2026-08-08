# Render functions are the evaluation boundary

TextUI evaluates the caller's render function and explicit event callbacks only.
All other element properties must already contain their final values; TextUI will
not automatically call function-valued content, width, or children properties.
The extracted implementation therefore drops `org-supertag`'s context-based
property resolver and its literal-property allowlist, keeping function values
unambiguous and dynamic composition in ordinary Lisp.
