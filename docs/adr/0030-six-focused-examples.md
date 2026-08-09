# TextUI keeps six focused examples

The statement that TextUI does not own application lifecycle is superseded by
[ADR 0031](0031-textui-owns-buffer-runtime-lifecycle.md).

The published example set has two direct layout demonstrations and four
recognizable TUI stress tests:

- `textui-responsive-demo.el` demonstrates Flex, native controls, responsive
  wrapping, and pixel-justified `:text` inside a content box.
- `textui-grid-gallery.el` demonstrates equal responsive Grid tracks, uneven
  row heights, and native and package-owned widgets.
- The retained K9s, Lazygit, Yazi, and btop demos test demanding application
  layouts, bounded refresh, focus, navigation, image preview, and live data.

Earlier counter, layout-gallery, layout-stress, wrapped-text, widget-combination,
and three-buffer K9s experiments no longer remain as separate entry points.
Their unique behavior is either present in the two layout demos or locked down
by core and compatibility tests.  Keeping duplicate runnable examples made it
harder to tell which programs represented current architecture.

The one-buffer K9s demo owns the small amount of visual vocabulary it needs and
does not depend on the rejected three-buffer shell.  The btop demo is the most
practical example: on macOS it reads live local state through read-only system
commands and exercises independently refreshed regions.  It is still an
example: its commands and parsers remain application-owned, while TextUI owns
the sampler effect's lifetime under ADR 0031.
