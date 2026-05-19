# Design

Shared rules: [`../design/design-rules.md`](../design/design-rules.md)

## Purpose
`howl-vt` owns the host-neutral terminal model.

It parses terminal input streams, maps parser events into terminal actions, applies screen state, tracks selection, and exposes render-facing and host-output-facing surfaces.

Host wake, PTY control signals, and runtime turn ownership are not VT ownership.
They belong to `howl-pty` or the owning host runtime.

## Doc Set
- `design.md`: owner boundary, file rules, and ABI contract.
- `protocol_matrix.md`: protocol ledger summary, queries, and support table.

## Public Surface
- `include/howl_vt.h`: C ABI header.
- `howl_vt_*` exported symbols: C ABI contract for terminal runtime calls only.
- The shipped embedding boundary is C ABI only.
- `src/howl_vt.zig` is not an embedding surface. If it survives, it is repo-local only.
- Internal workspace wiring is not a public contract and is not a preservation target.
- Accepted cleanup result so far is exact:
  - `src/vt_namespace.zig` is deleted
  - `src/libhowl_vt.zig` is the explicit ABI export root
  - `include/howl_vt.h` carries explicit vocabulary constants instead of exported getter helpers
  - `HowlVtHandle` is an opaque pointer handle contract
  - Linux host consumes explicit VT ABI steps only
  - repo-local terminal and input convenience posture that mirrored deeper owners or old ABI shape is removed

```mermaid
classDiagram
    class HowlVtHeader
    class HowlVtAbi
    class Terminal
    class Input
    class ParserApi
    class Action
    class Dispatch
    class Screen
    class ScreenSet
    class Selection

    HowlVtHeader --> HowlVtAbi
    HowlVtAbi --> Terminal
    Terminal --> Input : key/modifier vocabulary
    Terminal --> ParserApi : feed parser work
    Terminal --> Dispatch : delegate event routing
    Dispatch --> Action : classify actions
    Terminal --> Screen : mutable screen state
    Terminal --> ScreenSet : primary/alternate composition
    Terminal --> Selection : selection state
```

## Ownership Rules
- `src/howl_vt.zig` is repo-local only. It is a curated root for tests and local Zig proofs, not a host integration surface.
- `Terminal` currently owns lifecycle, grouped screen/mode/host/kitty state, and the temporary terminal implementation facade behind the C ABI.
- `Input` owns key, modifier, mouse, host-token parsing, and input encoding vocabulary.
- `Action` owns terminal action vocabulary and payload types.
- `Dispatch` owns the parent event-routing control spine.
- `Action` also owns the parser-event and action export surface through `src/action.zig`.
- `Screen` owns one-screen mutable state and mutation.
- `ScreenSet` owns primary/alternate screen selection plus visible-history projection.
- `Host` owns host-facing consequence state and application.
- `Kitty` owns kitty state, kitty payload parsing, and kitty consequence application.
- `Screen` treats scrollback truth as logical lines; history rows exposed to hosts are width-dependent projections.
- `Selection` owns selection state and validity against screen mutations.
- `ParserApi` owns byte-stream parsing contracts used by action routing, tests, and fuzzing.
- Protocol syntax, parser-event shape, action meaning, screen mutation, and terminal host consequences must stay in separate owners.
- Runtime control signals and wake policy do not belong in `howl-vt`.

## File Rules
- `src/parser/main.zig` owns byte-step parser state and syntax recognition.
- `src/parser/` keeps parser-internal leaf owners only.
- `src/parser.zig` is the curated repo-local parser root.
- `src/howl_vt.zig` is a curated repo-local export root.
- `src/action.zig` is a curated export root for parser-event, routing, and action vocabulary surfaces.
- `src/action/vocabulary.zig` owns terminal action vocabulary.
- `src/action/dispatch.zig` owns the parent event-routing loop.
- `src/action/route.zig` owns parsed-event routing into family owners and owner action slices.
- `src/parser/events.zig` owns parser-event buffering and transport into current action routing.
- `src/parser/queue.zig` owns parser feed plus parsed-event queue state.
- `src/xterm/` owns current xterm-family routing.
- `src/host/state.zig` owns host-facing consequence state.
- `src/host/apply.zig` owns host-facing consequence application.
- `src/kitty/state.zig` owns kitty aggregate state.
- `src/kitty/types.zig` owns kitty local state and payload types.
- `src/kitty/apply.zig` owns kitty consequence application.
- `src/kitty/protocol.zig` owns kitty payload parsing.
- `src/kitty/apc.zig` owns kitty APC action routing.
- `src/screen.zig` is the real one-screen mutable owner.
- `src/screen_set.zig` owns primary/alternate composition and visible-history projection.
- `src/input/encode.zig` owns input encoding logic.
- `src/input/types.zig` owns input event and encoded-value types.
- `src/selection.zig` owns selection state and terminal-facing selection helpers.
- `src/selection/state.zig` owns selection state and mutation.
- `src/screen/` owns screen leaf mutation only.
- `src/input/` keeps key, mouse, token, and encoding owners separate.
- `src/terminal.zig` is the real terminal state owner.
- `src/howl_vt.zig` is the curated repo-local root, in the same role Ghostty gives `src/terminal/main.zig`.
- `howl-vt` does not define PTY or host runtime control-signal vocabulary.
- `protocol_coverage.db` is the protocol source of truth. `unit_test_filters` must stay executable.
- New protocol work defines syntax, parser event shape, action meaning, state mutation, and proof before code lands.
- Normal proof is focused tests plus `zig build test`.

## Lifecycle
```mermaid
stateDiagram-v2
    [*] --> Uninitialized
    Uninitialized --> Ready: init/initWithCells/initWithCellsAndHistory
    Ready --> Ready: feedByte/feedSlice
    Ready --> Ready: apply
    Ready --> Ready: resize
    Ready --> Ready: reset/resetScreen/clear
    Ready --> Destroyed: deinit
    Destroyed --> [*]
```

## Main Flows
### Parse And Apply
```mermaid
sequenceDiagram
    participant Host
    participant V as Terminal
    participant F as Parser.Queue
    participant D as Action.Dispatch
    participant A as Action Routing
    participant G as Screen
    participant S as SelectionState

    Host->>V: feedSlice(bytes)
    V->>F: feedSlice(bytes)
    Host->>V: apply()
    V->>D: applyLimit(max_events)
    D->>F: events()
    D->>A: process(event)
    A-->>D: semantic action
    D->>G: apply screen-visible action
    D->>S: clearIfInvalidatedByGrid(&state)
    V-->>Host: visibleView()/screen()
```

### Resize
```mermaid
sequenceDiagram
    participant Host
    participant V as Terminal
    participant G as Screen
    participant S as SelectionState

    Host->>V: resize(rows, cols)
    V->>G: resize(allocator, rows, cols)
    V->>S: clearIfInvalidatedByGrid(&state)
```

## API Contracts
- The public compatibility promise is the C ABI only.
- `include/howl_vt.h` and `howl_vt_*` exported symbols define the product surface.
- Hosts and embedders consume `howl-vt` through that header and those exported symbols only.
- Zig root imports are not an acceptable host integration path and are not a preservation target.
- `howl_vt_terminal_init` and `howl_vt_terminal_deinit` own opaque terminal-handle lifecycle.
- `howl_vt_terminal_feed`, `howl_vt_terminal_apply`, and `howl_vt_terminal_resize` cover bounded parser/apply/geometry control.
- `howl_vt_terminal_feed` must fail instead of silently dropping parser work when parser-owned
  buffering cannot accept more bytes within its explicit bound, or when parser-owned buffering or
  parser-event materialization cannot allocate. The parsed-event queue must stay explicitly bounded.
- `HowlVtSurface` and `HowlVtSurfaceResult` are the primary renderer-facing VT-surface contract types for visible surface cells, cursor state, and dirtiness truth.
- `howl_vt_terminal_copy_surface` is the bounded VT-surface export call.
- `howl_vt_terminal_ack_surface` is the only public dirty-retirement path. It retires dirty truth only for the captured dirty generation that the renderer-facing VT-surface copy reported.
- `howl_vt_terminal_copy_pending_output`, `howl_vt_terminal_clear_pending_output`, and `howl_vt_terminal_drain_pending_clipboard` cover host-facing protocol consequences.
- `howl_vt_terminal_encode_key`, `howl_vt_terminal_encode_focus`, `howl_vt_terminal_encode_mouse`, and `howl_vt_terminal_encode_paste` cover host input encoding against current terminal modes.
- Header-declared key, modifier, and mouse constants are part of the shipped vocabulary contract. Getter and validator helper exports are not.
- Zig owner names may change as long as the C ABI contract stays stable.

## Repo-Local Surface
- `src/terminal.zig` may expose temporary migration APIs for tests, fuzzers, and internal seams only when they describe true owned state or mutation.
- Root `src/*.zig` files are now curated exports or ABI roots only.
- Repo-local callers should consume visible terminal state through `src/screen.zig` and `src/screen_set.zig`, not through terminal facade methods.
- Repo-local callers should consume parser byte-step and queue feed surfaces through `src/parser.zig` and bounded apply through `src/action.zig`, not through terminal facade methods.
- `src/input.zig` owns input vocabulary and repo-local input encoding entrypoints.
- Repo-local callers should consume input encoding through `src/input.zig`, not through terminal facade methods.
- Repo-local callers should consume selection mutation and selection queries through `src/selection.zig`, not through terminal facade methods.
- Repo-local callers should consume host-facing consequence queries through `src/host/state.zig`, not through terminal facade methods.
- Repo-local callers should consume kitty retained-state queries through `src/kitty/state.zig`, not through terminal facade methods.
- Checkpoint 4 accepted result:
  - repo-local queue, title, history, and alternate-screen convenience getters were removed in favor of `applyLimit` and `visibleView`
  - repo-local token parsing no longer pretends to be owned by `Terminal`
  - repo-local input namespace bag posture was removed

## Internal Invariants
- The implementation still follows the same internal runtime invariants:
  - `init*` returns owned terminal state
  - `feedByte` and `feedSlice` queue parser work only
  - `apply` mutates terminal state and resolves queued host-facing protocol output
  - `resize` preserves terminal semantics while updating visible geometry
- selection validity is rechecked after screen-affecting operations

## Non-Goals
- PTY ownership.
- Host windowing.
- GPU rendering.
- Font loading or rasterization.

## Change Rules
- New visible-state concepts must have a named owner before code is added.
- Parser syntax must not own terminal meaning.
- Action-routing owners must not mutate screen or host state directly.
- Parent routing control flow must stay centralized in one owner.
- Screen mutation owners must not know protocol families.
- `Terminal` boundary owners must keep host consequences explicit.
- Hosts should depend on the C ABI, not deep parser/screen leaves.
- Bounded apply and throughput policy must stay explicit at the owning seam. If a limit changes,
  lock the current Ghostty or Alacritty reference, the reason Howl keeps that value today, and proof
  of the changed host path in the same change.
- Update `protocol_coverage.db` and test filters with the same change that adds protocol behavior.
