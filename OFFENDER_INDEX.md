# Howl VT Offender Index

Audited against the current native tree on 2026-07-18. The target is 10/10
for every bar. File length is not a score: coherent large owners may remain;
fragmentation and indirect ownership are defects.

## Current score

| Bar | Score | Blocking evidence |
| --- | ---: | --- |
| Foot directness | 7/10 | The embedding root now exposes one state owner; screen behavior is still dispatched through broad structural helpers and CSI routing crosses six files. |
| TigerBeetle defensiveness | 7/10 | Terminal dimensions now reject zero exactly, but many internal owner boundaries infer errors and structural `anytype` hides required state. |
| Character/capability density | 7/10 | ABI projection and compatibility constants are gone; six terminal constructors and a broad implementation-public surface still dilute the engine. |
| Ownership/cleanup | 7/10 | Core owners generally use `errdefer`/`deinit`; allocator provenance and resize/history rollback remain implicit across helpers. |
| Exact failures | 6/10 | `Terminal` construction/resize now expose exact errors; `Screen` construction/resize, selection copying, and paste encoding still infer failures. |
| Documentation | 3/10 | 63 `///` comments cover 502 non-FFI public declarations; almost every source file lacks `//!`; `design.md` names paths that do not exist. |
| Hostile-input evidence | 6/10 | Limit and allocator-failure tests exist, plus deterministic random simulations, but no native fuzz target continuously feeds arbitrary bytes and operation sequences. |
| Embedding surface | 7/10 | `src/howl_vt.zig` now exposes only `Terminal` and proves the current headless host path; additional contracts remain private until earned. |
| Deliberate modification | 5/10 | `protocol_coverage.db` and simulations help, but no executable source-debt gates protect public docs, erased types, exact errors, or ABI absence. |
| Source maturity | 6/10 | Strong protocol breadth and native tests remain, but stale design claims, broad erased helpers, and immature native contracts persist. |

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
  methods such as `Terminal.feed`, `resize`, `surfaceSnapshot`, and selection
  mutation omit ownership, bounds, invalidation, and failure meaning. Almost
  every source file lacks `//!`.
- Bars: documentation, deliberate modification, maturity
- Simpler shape: reduce accidental `pub`; document every retained public owner
  and non-obvious local invariant where it lives.
- Depends on: VT-001 through VT-003, so deleted/transient symbols are not
  documented
- Acceptance evidence: an audit lists no undocumented retained public symbol
  or owned file; comments match executable tests and current paths.

### VT-005 — Terminal construction has six overlapping paths

- Status: open
- Path/symbol: `src/terminal.zig:init`, `initWithOptions`, `initWithCells`,
  `initWithCellsAndOptions`, `initWithCellsAndHistory`,
  `initWithCellsHistoryAndOptions`
- Defect: callers choose between cursor-only and storage-backed states through
  six names rather than one explicit configuration. Nonzero dimensions are
  enforced, but upper dimensions, cell-count multiplication, allocation size,
  and failure-point cleanup are not proven at the terminal boundary.
- Bars: directness, density, bounds, invariants, exact failures, embedding
- Simpler shape: one storage-backed `Terminal.init` with an explicit config and
  exact invalid-dimension/allocation failures; cursor-only machinery, if still
  required for tests, is a private owner.
- Depends on: VT-003
- Acceptance evidence: zero dimensions return exact errors; maximum accepted
  dimensions prove multiplication/allocation bounds; all initialization
  failure points pass allocator-failure cleanup checks.
- Observed progress: every public terminal constructor and resize rejects zero
  dimensions with `error.InvalidDimensions`; rejected resize preserves the
  published dimensions.
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
  and with bounded history. Upper dimension and allocation-size acceptance
  remain unproven and keep this offender open.

### VT-006 — Owner-boundary failures are inferred

- Status: open
- Path/symbol: `src/terminal.zig` constructors and `resize`;
  `src/screen.zig` constructors and `resize`;
  `src/screen_set.zig:Set.resize`;
  `src/selection_projection.zig:copyText`;
  `src/input/encode.zig:encodePaste`
- Defect: `!T` and `!void` hide whether failure means invalid input, overflow,
  allocation failure, retained-state limit, or internal inconsistency.
  `Terminal.ResizeError` now has exact membership, but that does not constitute
  a transactional owner contract: allocation failure can leave primary and
  alternate screens at divergent dimensions.
- Bars: defensiveness, exact failures, embedding, deliberate modification
- Simpler shape: each public owner declares its exact error set; internal
  helpers narrow or translate failures at the owning boundary.
- Depends on: VT-003, VT-005
- Acceptance evidence: no inferred error union remains on the curated native
  surface; tests assert each public failure and unchanged/valid post-failure
  state.
- Observed progress: `Terminal.InitError` and `Terminal.ResizeError` now name
  invalid dimensions and allocation failure exactly; resize rollback remains
  unproven and is tracked by VT-012.

### VT-007 — Structural `anytype` erases screen and terminal ownership

- Status: open
- Path/symbol: `src/screen/history.zig` (25 occurrences);
  `src/host_state.zig` (21); `src/screen/edit.zig` and
  `src/input/encode.zig` (11 each); `src/screen/resize.zig` (7)
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

### VT-008 — Screen mutation is fragmented by mechanics, not owners

- Status: open
- Path/symbol: `src/screen.zig` delegating to `src/screen/apply.zig`,
  `edit.zig`, `erase.zig`, `margins.zig`, `scroll.zig`, `style.zig`,
  `tabs.zig`, and `write.zig`
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
  `src/screen/resize.zig:collectLogicalLines`, `rewrapLogicalLines`,
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

### VT-012 — Cleanup proofs are narrow around transactional mutations

- Status: open
- Path/symbol: `src/screen/resize.zig:resizeWithReflow`;
  `src/screen/history.zig:replaceAuthority` and `rebuildProjection`;
  `src/screen_set.zig:Set.resize`
- Defect: implementation uses cleanup branches, but allocator-failure tests
  concentrate on OSC handling. Resize/history replacement has many temporary
  lists and buffers without exhaustive failure-point evidence.
  `Set.resize` mutates the primary screen before resizing the alternate, so
  allocation failure can leave paired screens at divergent dimensions.
- Bars: defensiveness, ownership, cleanup, hostile-input evidence
- Simpler shape: prepare complete replacement state, validate it, then swap
  once; one deinitializer for every temporary owner.
- Depends on: VT-002, VT-010
- Acceptance evidence: `std.testing.checkAllAllocationFailures` covers each
  retained transactional owner and verifies the pre-operation state remains
  usable after every failure.

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

### VT-015 — Input vocabulary remains integerly typed

- Status: open
- Path/symbol: `src/input/keyboard.zig:Key`, `Modifier`, and public `key_*` /
  `mod_*` constants
- Defect: the C-era duplicate aliases are removed. The remaining native
  vocabulary is still `Key = u32`, `Modifier = u8`, plus many public integer
  constants, so invalid values and modifier bits are representable.
- Bars: directness, density, embedding, documentation, maturity
- Simpler shape: native Zig enums/structs and enum literals only; conversion
  belongs to a future external projection if one is later earned.
- Depends on: VT-001, VT-003
- Acceptance evidence: key identity and modifier bits use native typed
  vocabulary; encoding tests cover valid values and explicit rejection of
  invalid external integers at any future conversion boundary.
- Observed progress: repository audit finds no `VTERM_` or duplicate mouse
  aliases; enum completion is not claimed.

## Hardening loop

For each offender: confirm the cited code still exists, make one owner-sized
change, add only evidence that exercises the changed boundary, run native
format/build/tests plus the relevant simulation, update status and score only
from observed evidence, then commit. Newly discovered concrete debt is added
with a path and symbol before it is changed.
