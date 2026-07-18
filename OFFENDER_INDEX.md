# Howl VT Offender Index

Audited against the current native tree on 2026-07-18. The target is 10/10
for every bar. File length is not a score: coherent large owners may remain;
fragmentation and indirect ownership are defects.

## Current score

| Bar | Score | Blocking evidence |
| --- | ---: | --- |
| Foot directness | 7/10 | The embedding root now exposes one state owner; screen behavior is still dispatched through broad structural helpers and CSI routing crosses six files. |
| TigerBeetle defensiveness | 7/10 | Terminal dimensions now reject zero exactly, but many internal owner boundaries infer errors and structural `anytype` hides required state. |
| Character/capability density | 7/10 | ABI projection, compatibility constants, and four redundant Terminal constructors are gone; 643 public declarations across implementation modules still expose far more vocabulary than the one-symbol embedding root. |
| Ownership/cleanup | 7/10 | Constructors and transactional Screen/Set resize have exhaustive allocation-failure cleanup proofs; history, host-state, and screen mechanics still rely heavily on structural helpers with ambient ownership. |
| Exact failures | 6/10 | Curated Terminal operations, selection projection, Screen construction/resize, Set resize, and paste allocation now expose exact failures; inferred errors remain elsewhere in internal protocol and host-state owners. |
| Documentation | 3/10 | The tree has 101 `///` lines for 643 public declarations, and only 2 of 62 source files have `//!` owner contracts; many retained public implementation symbols remain undocumented. |
| Hostile-input evidence | 6/10 | Limit and allocator-failure tests exist, plus deterministic random simulations, but no native fuzz target continuously feeds arbitrary bytes and operation sequences. |
| Embedding surface | 7/10 | `src/howl_vt.zig` now exposes only `Terminal` and proves the current headless host path; additional contracts remain private until earned. |
| Deliberate modification | 5/10 | `protocol_coverage.db` and simulations help, but no executable source-debt gates protect public docs, erased types, exact errors, or ABI absence. |
| Source maturity | 6/10 | Strong protocol breadth, native tests, and current design paths remain, but broad erased helpers, undocumented implementation-public symbols, and inferred internal failures persist. |

## Ordered offenders

### VT-001 — Premature C ABI obstructs the native model

- Status: resolved
- Path/symbol: `include/howl_vt.h`; `src/libhowl_vt.zig`; `src/ffi/`;
  `test/abi.zig`; `test_abi.zig`; `test_ffi.zig`; ABI branches in `build.zig`
  and `test_unit.zig`
- Defect: a header, export root, 13 translation files, ABI build graph, and
  ABI tests duplicate and freeze immature state/projection contracts.
- Bars: directness, density, ownership, exact failures, embedding, maturity
- Simpler shape: delete the entire current ABI. `src/howl_vt.zig` is the sole
  embedding root. A future ABI, if earned, starts from scratch.
- Depends on: nothing
- Acceptance evidence: `rg -n
  'howl_vt_|callconv\\(\\.c\\)|@export|c_abi|src/ffi|include/howl_vt.h|test[_/:]abi'
  . --glob '!OFFENDER_INDEX.md'` finds no ABI surface, target, test, alias, or
  compatibility shim;
  `zig build check` and `zig build test` exercise native code only.
- Observed: header, export root, 13 translation files, ABI build/tests, and
  exported symbols deleted; repository audit is empty; native build/tests pass.

### VT-002 — ABI-only render projection duplicates terminal truth

- Status: resolved
- Path/symbol: `src/render_state.zig:RenderState`;
  `src/ffi/render_state.zig:FfiRenderState`
- Defect: a 603-line copied render model and an 828-line reflective getter /
  iterator translation layer duplicate cells, colors, cursor, selection,
  dirty state, and allocation ownership. Outside tests, `RenderState` is used
  only by the ABI.
- Bars: directness, density, ownership, embedding, maturity
- Simpler shape: delete the ABI translation and its ABI-only copied state;
  native embedders consume a documented borrowed snapshot/view owned by
  `Terminal`.
- Depends on: VT-001
- Acceptance evidence: no `render_state` import remains; native snapshot,
  dirty acknowledgement, selection, hyperlink, and color tests pass against
  terminal-owned views.
- Observed: both render projection files and imports deleted; native terminal
  surface tests pass.

### VT-003 — Native embedding root is both broad and incomplete

- Status: resolved
- Path/symbol: `src/howl_vt.zig:Terminal`
- Defect: the root exposed parser, owned-action, and screen-set implementation
  namespaces wholesale even though the only external consumer uses the
  terminal owner.
- Bars: directness, density, documentation, embedding, maturity
- Simpler shape: expose `Terminal` only; keep parser and screen implementation
  modules private until an external embedding requirement earns them.
- Depends on: VT-001, VT-002
- Acceptance evidence: one native integration test imports only `howl_vt` and
  can initialize, feed, observe, acknowledge, select/copy, encode input, drain
  output and host consequences, resize, and deinitialize without importing
  repository paths.
- Observed: `Parser`, `ParserOwnedActions`, and `ScreenSet` were removed from
  the root. The root-only test proves initialize, feed, semantic snapshot,
  acknowledge, selection/copy, mode-aware paste encoding, pending reply drain,
  clipboard-consequence drain, resize, and cleanup.

### VT-004 — Public source is largely undocumented

- Status: open
- Path/symbol: repository-wide; immediately `src/terminal.zig:Terminal`,
  `src/screen_set.zig:View`, `src/stream_terminal.zig:Stream`, and
  `src/howl_vt.zig`
- Defect: 63 `///` comments cover 502 non-FFI public declarations. Public
  methods such as `Terminal.feed`, `surfaceSnapshot`, and selection
  mutation omit ownership, bounds, invalidation, and failure meaning. Almost
  every source file lacks `//!`.
- Bars: documentation, deliberate modification, maturity
- Simpler shape: reduce accidental `pub`; document every retained public owner
  and non-obvious local invariant where it lives.
- Depends on: VT-001 through VT-003, so deleted/transient symbols are not
  documented
- Acceptance evidence: an audit lists no undocumented retained public symbol
  or owned file; comments match executable tests and current paths.

### VT-005 — Terminal construction had six overlapping paths

- Status: resolved
- Path/symbol: `src/terminal.zig:Terminal.init`,
  `Terminal.initWithHistory`
- Defect: callers chose between cursor-only and storage-backed states through
  six names. Constructor-time cursor style and a cursor-only terminal were
  exposed despite having no production or native embedding requirement.
- Bars: directness, density, bounds, invariants, exact failures, embedding
- Simpler shape: one direct storage-backed initializer and one initializer for
  the demonstrated distinct bounded-history ownership mode, both with exact
  invalid-dimension/allocation failures.
- Depends on: VT-003
- Acceptance evidence: `test/unit/terminal_test.zig` proves exact zero-dimension
  errors and exhaustively injects failure at every allocation point for both
  retained constructors. A compile-time invariant proves every `u16` row/column
  product fits the grid's `u32` count and `usize`; allocator size failure remains
  exact `error.OutOfMemory`.
- Resolution: `Terminal.init` now always owns primary and alternate storage;
  `Terminal.initWithHistory` adds bounded primary history. The four option or
  cursor-only variants and `InitOptions` are deleted without aliases.
- Caller audit:
  - `initWithOptions`, `initWithCellsAndOptions`, and
    `initWithCellsHistoryAndOptions` have zero callers.
  - Cursor-only `init` has six calls, all tests: one invalid-dimension proof,
    one mode test, and four allocator-failure probes that do not require a
    cursor-only ownership mode.
  - `initWithCells` has 86 in-repository calls and is the only constructor used
    by howl-headless.
  - `initWithCellsAndHistory` has 16 calls across tests, simulations, and
    benchmarks; retained history is a demonstrated distinct capability.
  - Configurable initial cursor style has no Terminal constructor caller.
    Cursor-style behavior is exercised through screen/protocol mutation.
- Audit conclusion: cursor-only Terminal state and constructor-time cursor
  style are test conveniences, not production or native embedding
  requirements. Two storage-backed entrypoints are earned: without history
  and with bounded history.

### VT-006 — Owner-boundary failures are inferred

- Status: resolved
- Path/symbol: `src/screen.zig` storage-backed constructors;
  `src/input/encode.zig:encodePaste`
- Defect: `!T` and `!void` hide whether failure means invalid input, overflow,
  allocation failure, retained-state limit, or internal inconsistency.
- Bars: defensiveness, exact failures, embedding, deliberate modification
- Simpler shape: each public owner declares its exact error set; internal
  helpers narrow or translate failures at the owning boundary.
- Depends on: VT-003, VT-005
- Acceptance evidence: no inferred error union remains on the curated native
  surface; tests assert each public failure and unchanged/valid post-failure
  state.
- Observed progress: the curated Terminal surface now has exact errors for
  construction, feed, runtime progress, resize, selection copying, input
  encoding, hyperlink lookup, and pending consequence drains. Screen/Set
  resize expose only `error.OutOfMemory` and have transactional failure proofs.
  `selection_projection.CopyError` now owns exact UTF-8/allocation failures;
  exhaustive allocation injection proves selection/content remain usable, and
  invalid stored codepoints return errors rather than trapping.
- Resolution: `Screen.InitError` is the storage owner's exact
  `error{InvalidDimensions, OutOfMemory}` set. Direct tests reject zero rows or
  columns; the only zero-sized caller uses the distinct nonallocating
  cursor-only `Screen.init`. Existing Terminal constructor failure injection
  retains cleanup evidence across every Screen allocation point. `encodePaste`
  owns `PasteError`, distinguishing `LengthOverflow` from `OutOfMemory`; its
  production length helper has a direct overflow test. Plain paste still
  borrows without allocation, bracketed paste owns the fixed CSI 200/201 pair,
  failure returns no partial owner, and both successful variants accept one
  `Encoded.deinit`. `Terminal.encodeInput` exposes `PasteError` unchanged.

### VT-007 — Structural `anytype` erases screen and terminal ownership

- Status: open
- Path/symbol: `src/screen/history.zig` (25 occurrences);
  `src/screen/style.zig` and `apply.zig` (9 each);
  `src/screen/resize.zig` (7). Repository total: 74 occurrences across
  16 files; `src/input/encode.zig`, `src/host_state.zig`,
  `src/kitty/state.zig`, `src/selection.zig`, and
  `src/screen/cursor.zig`, `src/screen/tabs.zig`, and
  `src/screen/dirty.zig` and `src/screen/erase.zig` now have zero.
- Defect: helpers accept undeclared field/method shapes, making dependencies,
  mutation authority, and compile failures implicit. This is indirection even
  when the helper body is small.
- Bars: directness, defensiveness, ownership, deliberate modification,
  maturity
- Simpler shape: methods on concrete owners or narrow named value parameters;
  generics remain only where multiple proven owner types require them.
- Depends on: VT-003, then owner-by-owner
- Acceptance evidence: every retained `anytype` has at least two concrete,
  intentional callers and a documented reason; owner tests compile through
  explicit types.
- Observed progress: `Terminal.encodeInput` now directly orchestrates its
  public Event, modes, Kitty flags, locator consequences, allocator, and
  scratch lifetime. It calls the pure keyboard/mouse encoders directly;
  newline adjustment, focus markers, and locator routing stay with Terminal.
  `src/input/encode.zig` retains only Scratch copying and paste allocation
  ownership, with zero `anytype`. Flattened dependency lists and four
  field-proxy query helpers were deleted; no context/config wrapper was added.
  `host_state.State` now owns consequence retention through concrete methods
  and one lifetime allocator; Terminal drains and bounded title replacement
  call State directly. Four terminal-mode proxies and the structural title
  helper were deleted, while shared bounded output-list mechanics retain
  narrow `*std.ArrayList(u8)` parameters. Kitty global and active-screen
  queries are concrete owner methods; active-screen queries receive only the
  explicit `alt_active` domain fact. Five test-only selection forwarders were
  deleted; tests exercise Terminal's existing concrete selection surface.
  Five cursor boundary calculations now live directly on concrete Screen;
  `screen/cursor.zig` retains only cursor value state and behavior. Screen now
  owns its three margin mutations directly; the empty structural margins
  module was deleted. Seven tab behaviors now live directly on Screen, while
  `screen/tabs.zig` retains only typed buffer allocation/default/copy
  mechanics. Four dirty-region mutations now live directly on Screen, while
  `screen/dirty.zig` retains typed dirty-state allocation and projection
  mechanics. The complete write path now lives on Screen; the empty
  structural write module was deleted. Seven scrolling operations now live
  directly on Screen; the empty structural scroll module was deleted. The
  complete edit path now lives on Screen; the empty structural edit module
  was deleted. Nine erase behaviors now live directly on Screen;
  `screen/erase.zig` retains only the shared `EraseMode` value definition.

### VT-008 — Screen mutation is fragmented by mechanics, not owners

- Status: open
- Path/symbol: `src/screen.zig` delegating to `src/screen/apply.zig`,
  and `style.zig`
- Defect: one `Screen` authority is spread across structural helpers that
  reach into its fields through `anytype`. Mutation and invariants require
  cross-file reconstruction; file smallness has displaced ownership.
- Bars: directness, density, ownership, invariants, maturity
- Simpler shape: group behavior by coherent state owner. A large `Screen`
  implementation is acceptable; split only independently owned state or
  algorithms with explicit typed inputs/outputs.
- Depends on: VT-007
- Acceptance evidence: each screen field has one evident mutation owner;
  helpers do not gain ambient structural access; cursor/margin/history/dirty
  invariants are asserted after mutation and resize.

### VT-009 — CSI/event routing crosses redundant vocabularies

- Status: open
- Path/symbol: `src/csi.zig`, `csi_plain.zig`, `csi_private.zig`,
  `csi_intermediate.zig`, `csi_leader.zig`, `semantic_event.zig`,
  `route.zig`
- Defect: CSI classification fragments across five dispatch files, then maps
  through a large semantic-event vocabulary and a second route layer before
  reaching owners. The hops do not consistently correspond to independent
  state ownership.
- Bars: directness, density, deliberate modification, maturity
- Simpler shape: parse once into the smallest action owned by the mutation
  target; retain a routing layer only where it enforces a real boundary.
- Depends on: VT-007; audit protocol coverage before changing mappings
- Acceptance evidence: every retained dispatch hop names an owner boundary;
  protocol mapping and terminal end-to-end tests preserve supported controls.

### VT-010 — History and resize duplicate reflow mechanics

- Status: open
- Path/symbol: `src/screen/history.zig:collectLogicalLines`,
  `appendProjectionRows`, `projectedRowCountForCells`;
  `src/screen/resize.zig:collectLogicalLines`, `reflowLogicalLines`,
  `rebuildResizeAuthority`
- Defect: logical-line collection, row projection, row-count arithmetic, and
  storage replacement are implemented in overlapping paths with erased owner
  types and separate temporary allocations.
- Bars: density, ownership, cleanup, bounds, invariants, maturity
- Simpler shape: one typed reflow operation owns logical-line collection and
  projection; history storage installation remains transactional.
- Depends on: VT-007, VT-008
- Acceptance evidence: resize/history share one arithmetic and projection
  path; allocation failure at every temporary buffer leaves the original
  screen valid and leak-free; randomized scrollback/resize simulation passes.

### VT-011 — Retained protocol state has coarse oversized bounds

- Status: open
- Path/symbol: `src/parser.zig:large_osc_control_max_bytes` (1 MiB),
  `apc_max_bytes` (65 MiB); `src/host_state.zig:retained_payload_max_bytes`;
  `src/parser/string_control.zig:OscControl`
- Defect: comments borrow burst scales from Ghostty/PTY behavior, but parser
  buffering and retained host consequences are different owners. One parser
  can reserve/grow very large payloads without protocol-specific retained-state
  evidence.
- Bars: bounds, ownership, density, hostile-input evidence, maturity
- Simpler shape: protocol-family limits sized from native ownership and
  retention behavior; streaming or rejection where bulk payload ownership
  does not belong in VT.
- Depends on: VT-003 and protocol-owner audit
- Acceptance evidence: each retained payload limit has a concrete consumer and
  boundary test at limit-1/limit/limit+1; rejected input resets parser state
  and does not retain partial payloads.

### VT-012 — Resize/history replacement was not transactional

- Status: resolved
- Path/symbol: `src/screen/resize.zig:prepareResize`;
  `src/screen/history.zig:replaceAuthority` and `rebuildProjection`;
  `src/screen_set.zig:Set.resize`
- Defect: resize installed visible buffers before history authority/projection
  allocation completed, and `Set.resize` committed primary before preparing
  alternate. Failure could leave one Screen partially replaced or the pair at
  divergent dimensions. History clones also leaked if destination append
  failed.
- Bars: defensiveness, ownership, cleanup, hostile-input evidence
- Simpler shape: prepare complete replacement state, validate it, then swap
  once; one deinitializer for every temporary owner.
- Depends on: VT-002, VT-010
- Acceptance evidence: `std.testing.checkAllAllocationFailures` covers each
  retained transactional owner and verifies the pre-operation state remains
  usable after every failure.
- Resolution: `prepareResize` builds a complete replacement Screen without
  mutating its source. `Screen.resize` swaps one completed replacement;
  `Set.resize` prepares both screens before either swap and deinitializes old
  storage only after commit. Failure injection covers Screen directly and a
  history-enabled Terminal in both active-screen modes, proving dimensions,
  content/history, selection, configured cursor defaults, margins, active mode,
  and publication generation remain unchanged and usable after failure.

### VT-013 — Hostile-input testing is simulation-only, not a fuzz boundary

- Status: open
- Path/symbol: `simulation/protocol.zig`, `simulation/scrollback.zig`;
  missing native arbitrary-byte/operation fuzz target in `build.zig`
- Defect: deterministic random simulations cover selected generated actions,
  and unit tests cover known limits, but arbitrary byte chunking, malformed
  UTF-8/control interleaving, resize/feed sequences, and post-error reuse are
  not continuously explored through the native embedding root.
- Bars: defensiveness, hostile-input evidence, deliberate modification,
  maturity
- Simpler shape: one native fuzz entry feeds arbitrary bytes and bounded model
  operations directly into `Terminal`, asserting state invariants and cleanup.
- Depends on: VT-003, VT-005, VT-006
- Acceptance evidence: reproducible seeded corpus tests run under `zig build
  test`; a dedicated fuzz command reports seed/input and minimizes failures
  without introducing product runtime machinery.

### VT-014 — Design and package metadata describe dead structure

- Status: resolved
- Path/symbol: `design.md`; `README.md`; `build.zig.zon:.version`
- Defect: design names nonexistent `src/ffi.zig`, `src/action/`, `src/host/`,
  `src/selection/state.zig`, and `src/xterm/`; current prose centers C ABI;
  package version remains `0.0.0`.
- Bars: documentation, embedding, deliberate modification, maturity
- Simpler shape: development version `0.1.x-dev`; docs describe only current
  native owners and explicitly defer any future external ABI design.
- Depends on: VT-001 so deleted structure is not rewritten twice
- Acceptance evidence: every documented path exists; package/version docs
  agree; repository-wide search finds no claim that a current C ABI exists.
- Observed: stale owner paths removed, current fragmented paths named
  explicitly, package and README agree on `0.1.0-dev`, and only native
  embedding is described.

### VT-015 — Input vocabulary was integerly typed

- Status: resolved
- Path/symbol: `src/input/keyboard.zig:Key`, `NamedKey`, `UnicodeScalar`,
  `Modifier`; `src/input/event.zig:KeyEvent`
- Defect: after the C-era aliases were removed, native input still used
  `Key = u32`, `Modifier = u8`, and public integer constants, so Unicode values
  collided with named keys and arbitrary modifier bits remained representable.
- Bars: directness, density, embedding, documentation, maturity
- Simpler shape: a tagged key identity separates named keys from validated
  Unicode scalars; a packed modifier value exposes only Shift, Alt, and Control.
- Acceptance evidence: encoding tests distinguish Unicode codepoint 1 from the
  formerly colliding Enter value, reject surrogate construction, cover every
  modifier combination, and exercise control, navigation, editing, function,
  keypad, and modifier-only named-key classes. Existing mode tests preserve
  Kitty keyboard, modify-other-keys, application cursor/keypad, and mouse
  modifier behavior. The root-only embedding test sends a typed named key and
  committed Unicode text through `Terminal.InputEvent`.
- Resolution: all public `key_*` and `mod_*` integers are deleted without
  aliases or conversion functions. `Key` is now `.named` or `.unicode`;
  `UnicodeScalar.init` validates scalar identity, and `Modifier` is a packed
  three-boolean value whose protocol arithmetic is private to the encoder.
  Unused `PhysicalKey` and `KeyboardAlternateMetadata` declarations were
  deleted rather than retained as speculative host metadata.
- Depends on: VT-001, VT-003

## Hardening loop

For each offender: confirm the cited code still exists, make one owner-sized
change, add only evidence that exercises the changed boundary, run native
format/build/tests plus the relevant simulation, update status and score only
from observed evidence, then commit. Newly discovered concrete debt is added
with a path and symbol before it is changed.
