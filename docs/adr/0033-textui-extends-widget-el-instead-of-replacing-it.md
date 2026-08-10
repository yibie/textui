# TextUI extends widget.el instead of replacing it

TextUI adopts two constraints articulated by htmx: architectural sympathy with
the host platform, and locality of behaviour at the point where behaviour is
declared. This is an analogy, not an attempt to import the Web's client-server
model into Emacs. This ADR separates three kinds of statements: what htmx
actually says, where the analogy to Emacs holds and breaks, and what TextUI
therefore allows, refuses, and requires of future abstractions.

## What htmx actually says

These are facts from htmx's own documentation, essays, and source, not TextUI
policy:

- Architectural sympathy means conforming to the host architecture instead of
  hiding it behind a parallel conceptual system. htmx deliberately reuses
  HTML, links, forms, URLs, CSS selectors, and the browser's request/response
  model. The resulting constraints are also used to reject features.
- Locality of Behaviour asks that a unit's behaviour be discoverable by
  reading that unit. The essay distinguishes colocating a declaration from
  inlining its implementation, and treats locality as a trade-off with DRY and
  separation of concerns rather than an absolute rule.
- Partial replacement is concrete machinery: `hx-target` identifies the
  destination, `hx-swap` chooses the replacement operation, `hx-select`
  selects part of a response, and `hx-swap-oob` can update additional targets.
  The core swaps HTML fragments; morphing and diffing are extensions.
- htmx augments the Web's existing hypermedia model. Its application model
  exchanges HTML rather than introducing a separate client-side resource
  model as the default.
- htmx also states a boundary: interfaces with many dynamic cross-region
  dependencies or extremely frequent updates, such as spreadsheets and maps,
  are poor fits for a hypermedia approach.

widget.el's own model matters equally. Its documented extension seam is the
widget type and property system: types inherit, `define-widget` creates new
types, and `widget-create` creates instances in the buffer. `:action` handles
activation and the default `:notify` propagates change reports through the
`:parent` chain. In the source, the default `:value-set` deletes and recreates
the widget; widget.el does not provide a retained diff tree.

## Where the analogy holds, and where it breaks

The mapping to TextUI (interpretation, evidenced by the code and earlier
ADRs):

- State-driven rendering maps to `state + width -> render function -> buffer`,
  with the render function as the only evaluation seam (ADRs 0003, 0004).
- Locality of behaviour maps to `:action`/`:notify` living on the element
  plist and to route and effect declarations living inside the render
  function they describe (ADRs 0031, 0032). It does not license inlining
  implementations, and it is a reading aid, not a gate — htmx's own author
  treats it as a trade-off.
- Partial replacement maps to `textui-refresh-region` replacing complete-line
  blocks inside owned markers (ADR 0027) and to one state key routing to
  several regions, which plays the structural role of out-of-band swaps
  (ADR 0032).
- Augmenting the platform maps to TextUI's core position: widget.el keeps
  controls, input, validation, and keymaps; TextUI adds layout, measurement,
  refresh, and lifecycle around them (ADRs 0012, 0019, 0031).

The analogy breaks in specific, nameable places, and this ADR does not
pretend otherwise:

- htmx is client–server: HTML is a serialization of server state crossing a
  network. TextUI is in-process; the buffer is mutable, user-editable, and
  authoritative for editable-field text. A large part of htmx's feature set —
  indicators, trigger throttling, request coordination, history — exists only
  because of network latency and has no Emacs counterpart. Importing that
  vocabulary would manufacture complexity in an environment where ADR 0026
  measured region replacement at about one millisecond.
- TextUI's full-frame path is structurally `UI = f(state)`. What keeps it
  from being React is not the analogy but two concrete properties:
  bounded text replacement instead of element-level diffing, and widget.el
  rather than the framework holding control state.
- "Extends widget.el" is precise only about the interaction model —
  `:action`, `:notify`, keymaps, `define-widget` types. TextUI deliberately
  replaces widget.el's buffer assembly: widgets must measure to one line,
  tolerate a throwaway measurement-time `widget-create`, accept enforced
  widths, and be tracked for teardown (ADR 0019). That is a contract added on
  top of widget.el, not native behavior.
- State-driven rendering is lossy for editable fields by design: unsaved
  field text lives only in the buffer and returns to Lisp state through
  `:notify` (ADR 0021); a full refresh discards what was not notified. Any
  claim that state alone describes the buffer is false here.

Terms like "hypermedia-driven" and "server-driven" have no referent in this
codebase — there is no hypermedia, no media type, no server — and must not
appear in TextUI documentation as if they named a mechanism. The observable
content of this ADR is: replace instead of morph, native controls, explicit
routing, one evaluation seam.

## Decision: allowed

- widget.el keeps all control semantics. Element properties pass through to
  `widget-create` without a second binding or event vocabulary after TextUI's
  own `:type` and `:layout` keys are removed; custom types come from
  `define-widget`; `:action` is wrapped only to schedule one refresh (ADR
  0009) and `:notify` is never wrapped (ADR 0021).
- Full-frame refresh remains erase-and-insert; region refresh remains bounded
  replacement of complete-line blocks (ADR 0027). The block-level shell
  comparison in `textui--reconcile` may stay at block granularity.
- State routing (ADR 0032) and effects (ADR 0031) continue at their current
  boundaries: declared top-level plist keys with shallow comparison, and
  explicit `equal`-compared dependencies reconciled only on full frames.

## Decision: refused

- Virtual DOM, retained component trees, morphing, per-element frame
  comparison, and `replace-buffer-contents` (ADR 0011).
- Reactive dependency graphs: inferred dependencies, nested-key tracking,
  derived or cascading routes (ADR 0032's closing guardrail).
- Component instances, props, or identity namespaces. Internal source-order
  location IDs and package-supplied focus IDs remain navigation anchors (ADRs
  0011, 0019), not persistent component identity.
- Aliased event attributes (`:on-click`), binding systems, model objects
  (ADRs 0009, 0021); the framework reading `widget-value`.
- Multi-buffer application shells (ADR 0026).
- htmx's network vocabulary as framework concepts: request indicators,
  delay/throttle parameters, polling attributes, and out-of-band swap naming.
  Packages may still create native Emacs timers, processes, and subscriptions
  inside `textui-effect`. Request coalescing (ADR 0029) exists because of
  Emacs's event loop, not network latency.

## Decision: admission tests for future abstractions

A proposal for a new runtime, layout, refresh, or state abstraction must pass
all of these, checked in review:

1. Prototype evidence, per ADRs 0026 and 0028: a capability prototype under
   `examples/`, numeric or interaction-recording evidence labeled as
   feasibility rather than a guarantee, and an argument that composing
   existing public functions is insufficient.
2. Granularity: complete-line block replacement remains the default. Finer
   replacement must prove that block replacement cannot meet a measured
   correctness or performance requirement, and it must not require a retained
   element tree or component identity.
3. Explicit dependencies only: any state-to-region mapping is declared via
   `textui-route-state` over top-level plist keys with shallow comparison;
   nothing infers dependencies from code.
4. Native passthrough: no new event, binding, or model attribute. Widget
   properties reach `widget-create` unchanged after TextUI removes only its
   own structural keys.
5. Effect budget: native Emacs timers, processes, subscriptions, and their
   cleanup composed through `textui-effect` are tried before another lifecycle
   primitive. Effects keep explicit `equal`-compared dependencies, and region
   refresh still skips effect evaluation (ADR 0031).
6. API surface: a new public abstraction arrives with an ADR that names the
   repeated caller complexity it removes. A convenience alias is not an
   abstraction and does not justify itself.
7. No borrowed latency machinery: a network-derived concept is admitted only
   for a demonstrated Emacs event-loop problem that native facilities plus
   existing TextUI composition cannot solve.

## Sources

- htmx, [Architectural Sympathy](https://htmx.org/essays/architectural-sympathy/)
- htmx, [Locality of Behaviour](https://htmx.org/essays/locality-of-behaviour/)
- htmx, [Hypermedia-Driven Applications](https://htmx.org/essays/hypermedia-driven-applications/)
- htmx, [When to Use Hypermedia](https://htmx.org/essays/when-to-use-hypermedia/)
- htmx documentation for [`hx-target`](https://htmx.org/attributes/hx-target/),
  [`hx-swap`](https://htmx.org/attributes/hx-swap/),
  [`hx-select`](https://htmx.org/attributes/hx-select/), and
  [`hx-swap-oob`](https://htmx.org/attributes/hx-swap-oob/)
- htmx source, [`src/htmx.js`](https://github.com/bigskysoftware/htmx/blob/master/src/htmx.js)
- GNU Emacs manual, [The Emacs Widget Library](https://www.gnu.org/software/emacs/manual/html_node/widget/),
  especially [Widgets Basics](https://www.gnu.org/software/emacs/manual/html_node/widget/Widgets-Basics.html)
  and [Defining New Widgets](https://www.gnu.org/software/emacs/manual/html_node/widget/Defining-New-Widgets.html)
- GNU Emacs source, [`lisp/widget.el`](https://git.savannah.gnu.org/cgit/emacs.git/tree/lisp/widget.el)
  and [`lisp/wid-edit.el`](https://git.savannah.gnu.org/cgit/emacs.git/tree/lisp/wid-edit.el)
