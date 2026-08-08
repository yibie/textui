# TextUI

TextUI provides automatic layout for declarative, interactive text interfaces
in Emacs buffers. It complements Emacs widgets rather than replacing them with
a component library.

TextUI v1 supports Emacs 29.1 and newer. Older releases are outside the tested
compatibility contract even where the underlying widget.el APIs happen to exist.

TextUI 0.1 has one end-to-end product proof: the existing complex
`org-supertag` dashboard demo must run well through TextUI, including responsive
layout and real interaction. Releasing 0.1 does not require migrating every
other `org-supertag` view or accumulating several smaller demos.

## Language

**Text interface**:
An interactive Emacs buffer whose contents are derived from ordinary Lisp state.
It is not a persistent registered object. A package may arrange several TextUI
buffers with ordinary Emacs windows, but TextUI does not combine them into one
interface or own their shared lifecycle.
_Avoid_: View, component instance

**TextUI mode**:
The thin major mode installed by `textui-open`. It derives from `special-mode`,
keeps the buffer writable for native editable fields, and composes widget.el's
standard keymap ahead of `special-mode-map`. TextUI adds no separate focus
navigation commands. For repeated mouse clicks, it ignores double- and
triple-press events and activates the native widget on the matching release;
this avoids widget.el waiting through and consuming later clicks.
_Avoid_: Application-specific major mode, custom navigation system

**Interface frame**:
The complete declarative description of a text interface at one moment in time:
a proper list of zero or more interface elements. Top-level elements are
presented in order without implicit spacing, line breaks, or layout. A refresh
replaces the previous frame.
_Avoid_: Component tree, virtual DOM

**Layout engine**:
The part of TextUI that measures and arranges interface elements within the
available width. It is the package's primary capability.
_Avoid_: Widget library, component library

**Flex layout**:
A one-direction layout that arranges children in a row or column and adapts them
to the available width. One `:flex` element selects `:row` or `:column` with its
`:direction` property. V1 allocates width only; a column stacks content without
allocating window height.
_Avoid_: Grid layout

**Grid layout**:
A two-direction layout that fills equal-width columns in source order, shares
the same track starts across rows, and reduces its column count when the declared
minimum column width no longer fits. Each row takes the height of its tallest
cell; tracks do not span rows or columns.
_Avoid_: Wrapped flex rows, CSS Grid

**Layout element**:
A TextUI-owned element whose keyword `:type` describes how children are measured
and arranged. TextUI v1 owns `:flex` and `:grid`. A layout element may present a
multi-line block made from rendering leaves and single-line native widgets.
_Avoid_: Control, component

**Rendering leaf**:
A TextUI-owned keyword element that turns content into a width-aware block but
has no children or interaction behavior. TextUI owns `:text` because wrapping
at an allocated width is layout work, and `:image` because fitting a native
image into a character grid requires layout geometry. Rendering leaves are not
an application component catalogue.
_Avoid_: Widget, control, component

**Image leaf**:
A `:image` rendering leaf naming one `:file`, a positive caller-chosen `:rows`
count, and optional `:alt` text. In graphical Emacs, TextUI fits the native image
inside its allocated width and row count, centers it, and presents it as one
horizontal slice per text row so no logical line becomes taller than its
siblings. Non-graphical Emacs presents the alternative text in a block with the
same number of rows. The caller owns the row count; TextUI does not allocate
window height.
_Avoid_: Image widget, image component, height layout

**Deferred widget placeholder**:
A single-line string carrying a TextUI text property with the original native
widget element. TextUI measures a temporary widget, lays out its plain placeholder
text, inserts the completed layout into the real buffer, and replaces placeholder
ranges from last to first with real widgets. The placeholder is positioning data,
not component identity or persistent state.
_Avoid_: Widget adapter, layout marker, reconciliation key

**Layout options**:
An element's `:layout` plist, which tells its parent how to size it and restore
focus without mixing TextUI metadata into control properties.
_Avoid_: Top-level layout properties

**Natural width**:
The width an element's presented content needs before a flex layout gives it
extra space or makes it smaller. TextUI normally discovers it by presenting the
element in a temporary buffer and measuring its widest line. It is the default
starting width unless an element's layout options supply numeric `:width`.
_Avoid_: Equal share

**Measurement pass**:
The temporary presentation of an already computed and expanded interface frame,
used only to discover natural widths before layout. A refresh calls the render
function and element expanders once, then uses the same resulting frame for both
measurement and real presentation. The two presentations may each call
`widget-create`, so a widget's creation code must tolerate running twice. TextUI
may skip natural-width measurement for a layout element whose layout options
supply numeric `:width`, but native widgets are always measured because they
cannot be forced narrower than their content. TextUI does not track or
individually delete measurement widgets; Emacs discards the temporary buffer,
and any measurement error is re-signaled directly.
_Avoid_: Widget adapter, guessed width

**Grow weight**:
A non-negative `:grow` number in layout options that controls an element's share
of space left after natural widths and gaps. Its default is zero.
_Avoid_: Fixed percentage

**Minimum width**:
The smallest width a TextUI layout element may take while remaining on its
current flex row. If the row still does not fit after shrinkable layout children
reach their minima, later children wrap to the next row. A native widget is
atomic and always has its measured natural width as its minimum.
_Avoid_: Minimum window size

**Minimum column width**:
The smallest equal track width a grid uses when deciding how many columns fit.
The grid reduces its column count before crossing this value; a one-column grid
may still receive less space when the Emacs window itself is narrower.
_Avoid_: Cell minimum width, minimum window size

**Allocated width**:
The total visible width a parent gives an element, including its content,
horizontal padding, and borders.
_Avoid_: Content width

**Interface element**:
A plain property list within an interface frame. Its required `:type` property
selects how TextUI presents it. A keyword names a TextUI layout element or
rendering leaf; another symbol uses its explicitly registered element expander
when present and otherwise names a widget.el type. An unresolved type is an
error.
_Avoid_: Node, component, widget config

**Element expander**:
A globally registered pure function that replaces one package-prefixed custom
interface element with a proper list of zero or more interface elements. It
cannot modify a buffer directly. Explicit expander registration takes precedence
when the same symbol also names a widget.el type. Packages register one with
`textui-register-expander`; registering the same type again replaces it.
_Avoid_: Custom renderer, component

**Native widget**:
An Emacs `widget.el` control presented inside a TextUI-managed buffer.
TextUI passes its type and properties directly to `widget-create`; `widget.el`
owns its behavior while TextUI owns the surrounding layout and refresh. TextUI
treats the presented widget as one atomic leaf: it can measure, pad, or move the
whole widget to a later row, but cannot shorten or crop it. Static single-line
labels may use an appropriate widget.el type such as `item`; reflowing prose
uses the TextUI-owned `:text` rendering leaf. A native widget's starting width
is the larger of its measured natural width and any numeric layout `:width`. In
v1 it must present exactly one logical line;
measurement rejects embedded newlines before the real buffer is changed. Its
real presentation must match the measured placeholder width or TextUI signals an
error immediately. TextUI tracks widgets created in the real buffer only so it
can call `widget-delete` on them before the next `erase-buffer`; otherwise stale
editable-field overlays can expand across the replacement frame. This tracking
does not give widgets persistent identity.
_Avoid_: TextUI component, TextUI leaf element

**Render function**:
A caller-supplied function of one available-width argument that returns a
complete interface frame. Like an element expander, it always returns a proper
list, even for one element; `nil` is an empty frame. It is the only place where
ordinary element values are computed, and TextUI calls it once per refresh.
_Avoid_: Property binding, template resolver

**Available width**:
One column less than the smallest body width among live windows currently
displaying a text interface's buffer, or the last successfully used width while
it is hidden. Emacs visually continues a logical line that occupies the complete
`window-body-width`, so TextUI reserves the final column rather than producing
an empty continuation line. A shared buffer therefore has one conservative
layout.
_Avoid_: Current window width, selected window width

**Event handler**:
A callback resolved as a native widget's effective `:action`, whether supplied
by the element or inherited from its widget.el type. TextUI preserves widget.el's
input behavior and triggers one refresh only when the outer action returns
normally. A custom element may expose another event name, but its expander must
translate that name to `:action`. Native `:notify` callbacks are not wrapped and
never cause an implicit refresh. An editable field uses `:notify` to copy its
current `widget-value` into ordinary Lisp state; it calls `textui-refresh`
explicitly only when other presented content must immediately reflect that
state.
_Avoid_: State transaction

**Focus anchor**:
An optional `:focus-id` value in layout options that identifies where point
should return after a full refresh. TextUI records the anchor and intra-element
offset before an input command starts. When that command refreshes the buffer,
the final point restoration runs after the native command finishes so
widget.el's own saved marker cannot overwrite it. The ID is unique within one
frame and has no rendering lifecycle. Native leaves without a matching explicit
anchor use an internal source-order location carried from their measured
placeholder to the real widget as a text property. This preserves point through
responsive reflow while the expanded frame order remains stable; explicit IDs
remain the stable choice across insertion, removal, or reordering. Point on
layout-owned borders, gaps, or padding uses the innermost layout element's
internal source-order location and relative row and display column. Only a
position without native or layout identity falls back to its previous one-based
line and display column. Each live window also restores its semantic window
point and the cursor's vertical row relative to `window-start`.
_Avoid_: Component key, marker

**Full refresh**:
Replacement of the complete interface frame after evaluating its render
function again. It is the normal response to width or frame-wide state changes.
_Avoid_: Reconciliation, diff

**Refresh region**:
A frame-unique, continuous block of complete lines owned by one column flex
element. Its children may be replaced without rebuilding the surrounding frame.
_Avoid_: Component subtree, arbitrary text range

**Region refresh**:
Replacement of one refresh region's children at its current allocated width.
It does not evaluate the interface render function or recreate widgets outside
the region.
_Avoid_: Local refresh, cell diff, database refresh

**Requested region refresh**:
Asynchronous, coalesced region refresh for timers, process sentinels, and other
external callbacks. One pending request is retained per buffer and refresh ID;
the latest producer wins. TextUI owns scheduling the redraw but not obtaining
the data or managing the external source's lifecycle.
_Avoid_: Subscription, effect, live query

**Legacy view translation**:
An `org-supertag`-owned migration step that rewrites one complete old view frame
into TextUI layout elements and native widget.el elements before TextUI sees it.
The old view registry and types remain outside TextUI. After TextUI is stable, a
repository skill may guide agents through converting those views incrementally;
that skill is migration tooling, not runtime architecture.
_Avoid_: TextUI compatibility layer, widget adapter

**Capability prototype**:
A deliberately incomplete reproduction of a demanding real interface, used to
expose missing layout, rendering, refresh, or focus behavior. A validated
general finding is extracted behind the smallest TextUI interface and the
prototype is changed to consume it; application-specific policy remains in the
prototype. Prototypes test framework pressure rather than define a component
roadmap.
_Avoid_: Toy demo, product implementation, component request list
