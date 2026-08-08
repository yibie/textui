# org-supertag retains the legacy view boundary

`org-supertag` has real views, tests, and documentation built on
`supertag-view-register`, `supertag-view-open`, `supertag-view-refresh`, and old
element types such as `:section`, `:text`, `:card`, and `:table`. Those APIs and
types remain owned by `org-supertag`; TextUI does not learn them.

During migration, an `org-supertag` render path rewrites one complete old frame
into TextUI `:flex` layouts and native widget.el elements before calling TextUI.
This preserves current callers while keeping TextUI's public vocabulary generic.
Individual views can later be rewritten directly without requiring a flag day.

After TextUI's API and behavior are stable, the projects may provide a
repository skill that helps agents perform this mechanical migration and run
the relevant tests. The skill is a development aid, not a TextUI dependency,
runtime translation mechanism, or reason to preserve unstable TextUI APIs.
