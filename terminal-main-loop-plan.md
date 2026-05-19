# Terminal Main Loop Plan

Purpose: delete `src/terminal/main.zig` and keep `src/terminal.zig` as the real
terminal owner by looping over the inventory in `terminal-main-remap.json` until
no runtime ownership remains in the wrong place.

Mapping target:
- Ghostty `src/terminal/Terminal.zig` -> Howl `src/terminal.zig`
- Ghostty `src/terminal/main.zig` -> Howl `src/howl_vt.zig`

## Rules
- Do not preserve `Terminal` as a hidden runtime owner.
- Move ownership first, then delete facade methods.
- Prefer Ghostty's owner split when the path is unclear.
- If Ghostty has no real terminal-owner match, move the responsibility up to
  `howl-pty` or the host runtime.
- Each loop closes only with proof and doc updates.

## Loop Shape
Each loop uses the same shape:

1. pick one owner cut
2. move storage and mutation to the true owner
3. switch repo-local callers and tests to the new owner surface
4. delete the matching `Terminal` fields and methods
5. run proof
6. update `design.md` and remap files if the owner story changed

## Execution Order
The order below is dependency-first. Later loops assume earlier ones are already
done.

### Loop 1: Runtime And Control Signals Move Up
Goal:
- remove non-VT runtime residue from the map first

Inventory groups:
- `g016-runtime-signals-move-up`

Work:
- move `ControlSignal` out of `howl-vt`
- place it in `howl-pty` or `howl-linux-host`, whichever truly owns signal and
  wake/runtime control
- remove any repo-local dependency on `Terminal.ControlSignal`

Why first:
- it is the clearest non-VT ownership breach
- it reduces fake pressure to keep a central `Terminal`

Close signal:
- no runtime/control-signal vocabulary remains in `howl-vt/src/terminal/main.zig`

Status:
- done
- `ControlSignal` had no live callers and was deleted from `howl-vt`
- runtime control signals stay with `howl-pty` or the owning host runtime

### Loop 2: Input Encoding Stops Hanging Off Terminal
Goal:
- remove the biggest convenience surface that still requires callers to go
  through `Terminal`

Inventory groups:
- `g012-input-encoding`

Work:
- define an explicit encoder-facing API under `src/input/`
- stop storing encode scratch in VT state
- switch FFI and repo-local callers away from `terminal.encode*`
- delete:
  - `EncodeScratch`
  - `encode`
  - `encodeKey`
  - `kittyKeyboardFlags`
  - `isApplicationKeypad`
  - `modifyOtherKeys`
  - `keyFormatOption`
  - `isKeyFormatResource`
  - `encodeMouse`
  - `encodeFocusIn`
  - `encodePaste`
  - `encodeFocusOut`
  - `encodePasteStart`
  - `encodePasteEnd`

Why second:
- this removes a wide caller dependency fan-out early
- Ghostty already proves this should not live on the terminal runtime blob

Close signal:
- all input encoding goes through `src/input/` only

Status:
- done
- input encoding now goes through explicit `src/input/` APIs
- terminal encode methods and terminal-owned encode scratch were deleted

### Loop 3: Screen/View/History Surface Stops Using Terminal Facade
Goal:
- make visible state consumers depend on `screen.zig` and `screen_set.zig`, not `Terminal`

Inventory groups:
- `g005-screen-grid-view`
- `g011-snapshot`

Work:
- expose explicit repo-local screen APIs
- switch tests, fuzzers, and ABI glue to `screen.zig` and `screen_set.zig`
- delete terminal facade methods for:
  - `screen`
  - `visibleView`
  - `peekDirtyRows`
  - `clearDirtyRows`
  - `historyRowAt`
  - `historyCellAt`
  - `historyCapacity`
  - `snapshot`
  - `resetScreen`
  - `resize`

Why here:
- once visible-state consumers stop depending on `Terminal`, the facade loses a
  large share of its justification

Close signal:
- repo-local visible-state reads no longer go through `Terminal`

Status:
- done
- visible-state, dirty-row, history, and resize callers now use direct `screen.zig` and `screen_set.zig` owners
- terminal screen/view/snapshot facade methods were deleted

### Loop 4: Selection Storage Becomes Screen-Local
Goal:
- stop keeping selection state at terminal root

Inventory groups:
- `g010-selection`

Work:
- move selection storage under `screen/`
- keep mutation/query helpers in `selection/`
- switch callers away from `terminal.selection*`
- delete terminal field and facade methods for selection

Why after Loop 3:
- selection validity depends on screen/grid mutation and visible-state truth
- screen APIs should be explicit first

Close signal:
- selection state is stored with screen state, not terminal root state

Status:
- done
- selection storage moved into `screen_set.zig`
- selection mutation/query now routes through `src/selection.zig`
- terminal selection field and terminal selection facade methods were deleted

Close signal:
- selection state is stored with screen state, not terminal root state

### Loop 5: Parser Flow And Dispatch Become Direct Owners
Goal:
- remove parser/apply turn ownership from `Terminal`

Inventory groups:
- `g013-parser-flow`
- `g002-action-dispatch`

Work:
- define the owner-true state object that dispatch consumes directly
- make parser feed/reset/clear live under `parser/`
- make bounded apply turn live under `action/dispatch`
- delete:
  - `allocator`
  - `queue`
  - `init*`
  - `deinit`
  - `feedByte`
  - `feedSlice`
  - `apply`
  - `applyLimit`
  - `clear`
  - `reset`

Why not first:
- too many callers still depend on the convenience facade today
- earlier loops shrink the blast radius first

Close signal:
- parser state and bounded apply turn are callable without `Terminal`

Status:
- in progress
- parser feed/reset entrypoints now live under `src/parser.zig`
- bounded apply entrypoints now live under `src/action.zig`
- repo callers no longer use terminal feed/apply/reset methods
- terminal parser/apply shim methods were deleted
- remaining work in this loop is the state/lifecycle cut:
  - `allocator`
  - `queue`
  - `init*`
  - `deinit`

### Loop 6: Host Consequences Become Direct Host APIs
Goal:
- remove host-facing consequence getters from the terminal facade

Inventory groups:
- `g006-host-consequences`
- `g014-dcs-and-status`
- `g007-screen-hyperlinks`
- `g017-kitty-clipboard-mode`

Work:
- expose explicit host consequence access through `host/`
- decide remaining ambiguous items one by one:
  - `hyperlinkUriForId`
  - `kittyClipboardMode`
  - DCS/report accessors
  - report residue such as `xtchecksum_flags`
- move any non-VT consequence state upward if needed
- delete terminal host-facing getters

Why after parser/direct-owner work:
- host consequences are easier to wire once the state root is no longer the old
  terminal facade

Close signal:
- no host-facing consequence accessor remains on `Terminal`

Status:
- done for repo-local query surface
- repo-local callers now use `src/host/state.zig` directly
- terminal host-facing query methods were deleted

### Loop 7: Kitty Retained State Stops Using Terminal Facade
Goal:
- keep kitty explicit, but remove terminal-root forwarding

Inventory groups:
- `g008-kitty-state`
- `g009-kitty-osc-consequences`

Work:
- keep kitty state under `src/kitty/`
- switch repo-local users away from `terminal.kitty*`
- split any items that really belong to screen-local state versus host
  consequence queues
- delete all remaining kitty getters from `Terminal`

Why late:
- kitty touches screen, host consequences, colors, and input mode surfaces
- earlier loops sharpen those seams first

Close signal:
- kitty users depend on `kitty/` and related explicit owners only

Status:
- done for repo-local query surface
- repo-local callers now use `src/kitty/state.zig` directly
- terminal kitty query methods were deleted

### Loop 8: Modes And Dynamic Colors Lose Terminal Root Storage
Goal:
- remove the last terminal-root retained config/state bags

Inventory groups:
- `g003-mode-owner`
- `g004-dynamic-colors`

Work:
- keep or rename `control/mode.zig` only if the owner name remains honest
- decide whether dynamic color state remains under current owner or gets a more
  explicit owner folder
- delete terminal-root storage and direct mode/color getters

Why late:
- input, host, screen, and kitty loops clarify what these owners really need to
  retain

Close signal:
- no mode or dynamic-color storage remains in terminal root state

### Loop 9: Delete Terminal Main Only
Goal:
- remove the wrong-shaped nested file once nothing real remains there

Inventory groups:
- `g015-terminal-root-deletion`
- `g018-terminal-tests`

Work:
- redistribute any last terminal-root tests to owner modules
- delete `src/terminal/main.zig`
- keep `src/terminal.zig` as the real terminal owner
- update `src/howl_vt.zig` curated exports
- update docs and sprint closure notes

Close signal:
- `src/terminal/main.zig` is gone
- `src/terminal.zig` is the owner-true terminal file
- `src/howl_vt.zig` is the curated root

## Stop Conditions Per Loop
- ownership became unclear
- the next move requires a fake umbrella layer
- a target owner cannot be named honestly
- a responsibility is actually host or PTY runtime work and must move up first

## Proof Per Loop
- `zig build test`
- `git diff --check`
- `nu "./style.nu" --touched-files --json`
- `nu "./style.nu" --failures --json`
- when ABI-observable host behavior moves: `zig build` in `howl-linux-host`

## End State
- `terminal-main-remap.json` has no remaining live loop groups
- `src/terminal/main.zig` is deleted
- `src/terminal.zig` is the owner-true terminal file
- runtime stays in host and PTY owners
- `howl-vt` keeps only VT-owned model, parsing, action, screen, selection,
  kitty, input, and host-consequence owners
