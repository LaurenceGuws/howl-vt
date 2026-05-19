# Howl VT Core Sprint

Shared rules: [`../AGENTS.md`](../AGENTS.md), [`../WORKFLOW.md`](../WORKFLOW.md),
[`../design/style-law.md`](../design/style-law.md),
[`../design/reference-index.md`](../design/reference-index.md)

## Purpose

This sprint cleans `howl-vt` internal ownership before any further ABI storytelling.

Bias:

- TigerBeetle for owner truth, simplicity, bounds, and hygiene
- Ghostty for VT-core split and protocol naming
- Alacritty for render/display ownership boundaries

This sprint is about internal truth first, not final ABI shape.

## Non-Negotiable Truths

These are the source of truth for the sprint. The road may change. These do not.

1. `howl-vt/src/` must end as an export and ABI layer, not as a state-owner layer.
2. `howl-vt/src/terminal.zig` must not survive as a real owner. It may exist only as a temporary migration shell, and sprint closure deletes it.
3. `interpret` is not a valid long-term owner name. It is a phase name, and phase names are hiding ownership.
4. VT core must separate four concerns explicitly: syntax parsing, protocol-family decoding, terminal action vocabulary, and owned state application.
5. One explicit parent owner must own event-routing control flow. Parser, family decoders, and state owners are leaves under that spine.
6. Parser code must recognize bytes and sequence syntax only. It must not own terminal meaning.
7. Protocol-family code must be named plainly by family, especially xterm, kitty, and iterm when present. Generic mixed buckets are not acceptable.
8. Screen and host consequences must not be mixed in one owner path.
9. Render-facing visible truth must come from VT-owned screen state, not from host reconstruction.
10. Root docs and code must stop presenting `Terminal` and `Interpret` as acceptable enduring owners once this sprint closes.
11. ABI shape is not allowed to get ahead of owner truth. If ownership is unclear, ABI design stays open.

## Research Outcome

The initial theory held directionally, but not perfectly.

What held:

- `terminal.zig` is the biggest owner lie
- `interpret` is the wrong organizing idea
- owner nouns are required
- VT truth must be cleaned before ABI freezing

What changed after reading:

- the split is not merely `parser -> interpret -> screen/host`
- Ghostty shows a sharper model:
  - parser
  - protocol-family domains
  - terminal action vocabulary
  - owned state application
- `howl-vt` already has pieces of an action vocabulary in `interpret/event.zig`, but they are buried in the wrong bucket and dispatched through the wrong owner story

## Current Offenders

### `src/terminal.zig`

Current owner violations:

- owns lifecycle
- owns parser feed/apply loop
- owns screen-set state
- owns host consequence queues
- owns visible view construction
- owns input encoding
- owns snapshot export
- owns final semantic dispatch policy

This file is the main blocker because it centralizes too much truth under one product noun.

Checkpoint 1 inventory:

- public type bag
  - `ApplySummary`
  - `ControlSignal`
  - `VisibleViewOptions`
  - `VisibleRowSource`
  - `VisibleView`
- mode state bag
  - keyboard modes
  - paste/focus/mouse modes
  - DEC save/restore state
- host state bag
  - pending output
  - hyperlink target intern table
  - pending clipboard
  - locator state
  - DCS payload retention
  - legacy control retention
  - terminal color state
- kitty state bag
  - main/alt kitty screen state
  - global kitty state
- screen-set bag
  - primary grid
  - alternate grid
  - alt-active state
  - saved primary cursor
- lifecycle
  - `init*`
  - `deinit`
- parser/apply control spine
  - `feedByte`
  - `feedSlice`
  - `apply`
  - `applyLimit`
  - `clear`
  - `reset`
- host consequence accessors
  - pending output
  - clipboard
  - hyperlink lookup
  - DCS payload
  - media copy
  - legacy control
  - terminal color state
- kitty consequence accessors
  - shell marks
  - notifications
  - file transfer
  - text sizing
  - pointer shape
  - multiple cursor count
  - color stack depth
  - graphics image/placement/frame accessors
- screen/view accessors
  - `screen`
  - `visibleView`
  - `historyRowAt`
  - `historyCellAt`
  - `historyCapacity`
  - `peekDirtyRows`
  - `clearDirtyRows`
  - `synchronizedOutputActive`
- selection operations
  - `selectionState`
  - `selectionStart`
  - `selectionUpdate`
  - `selectionFinish`
  - `selectionClear`
- input encoding
  - `encodeKey`
  - `encodeMouse`
  - `encodeFocusIn`
  - `encodeFocusOut`
  - `encodePaste*`
  - keyboard mode accessors
- snapshot export
  - `snapshot`
- final action dispatch
  - `applySemantic`

### `src/interpret.zig`

Current owner violations:

- phase-name umbrella
- re-exports event, queue, mapping, and host-application behavior
- hides the real split between protocol meaning and owned consequences

### `src/interpret/event.zig`

Current owner violations:

- giant mixed semantic union
- carries screen, mode, report, kitty, and host consequences together
- acts like the action seam, but lives in a bucket that lies about what it is

### `src/parser.zig`

Cleaner than `terminal.zig`, but still too broad for the target shape:

- parser state
- charset designation tracking
- string-control buffering
- sink contract

This is not catastrophic, but it is not yet Ghostty-clean.

### `design.md`

Current design facts are now too permissive:

- treats `Terminal` as an acceptable enduring facade owner
- treats `Interpret` as a first-class owner
- does not describe the parser/protocol/action/state split now indicated by research

## Target Model

The target is smaller than Ghostty, but conceptually similar where ownership is real.

### Root `src/`

Allowed long-term root files:

- `howl_vt.zig`
- `ffi.zig`
- `libhowl_vt.zig`
- possibly other pure export or ABI files only

Disallowed long-term root files:

- root state owners
- root mutation owners
- root phase buckets
- root umbrella product files

### Target Owner Groups

- `parser/`
  - byte stream parsing
  - raw sequence syntax
  - bounded string-control transport
- `action/`
  - explicit terminal action vocabulary
  - the seam between protocol decoding and state application
- `xterm/`
  - ANSI, CSI, OSC, DCS, APC, DEC baseline meaning
- `kitty/`
  - kitty-specific decoding and owned state
- `iterm/`
  - iTerm-specific decoding and owned state when present
- `screen/`
  - screen-set ownership
  - alt/main switching
  - visible view contract
  - viewport-visible truth
- `grid/`
  - cells, history, dirty, margins, tabs, erase, scroll, write
- `host/`
  - pending output
  - clipboard
  - title/report side effects
  - locator and other host-neutral outbound consequences
- `input/`
  - key, mouse, paste, and focus encoding only
- `selection/`
  - selection owner only

## Responsibility Map

This is the Checkpoint 1 map. It is the current working cut plan.

| Current responsibility | Current home | Target owner | Notes |
| --- | --- | --- | --- |
| Parser byte feed state | `terminal.zig` via `queue` | `parser/` | Keep syntax-only. |
| Parsed event queue | `interpret/apply_flow.zig` | `parser/` or `action/` | Queue owner stays open. |
| Semantic action vocabulary | `action/vocabulary.zig` | `action/` | First explicit action seam cut is complete. |
| Event-to-action mapping | `interpret/actions/*` and `xterm/*` | `xterm/`, `kitty/`, `iterm/` | Split by protocol family is underway. |
| Final dispatch policy | `terminal.zig` | temporary top-level owner, then split | Must not fossilize under `terminal`. |
| Grid mutation | `grid/` | `grid/` | Already mostly true. |
| Primary/alternate screen set | `screen/set.zig` | `screen/` | Includes alt switching and saved cursor. |
| Visible view contract | `screen/view.zig` | `screen/` | Render-facing truth now lives here. |
| Scrollback-visible projection | `terminal.zig` and `screen/view.zig` | `screen/` | Builder logic still needs a final home. |
| Dirty-view exposure | `terminal.zig` + `grid/` | `screen/` over `grid/` | `grid` stores dirtiness, `screen` exports visible truth. |
| Selection state and mutation | `terminal.zig` + `selection.zig` | `selection/` | Keep screen validity seam explicit. |
| ANSI/DEC mode state | `terminal.zig` + `control/mode.zig` | `screen/` and/or dedicated mode owner | Needs sharper decision later. |
| Host pending output and reports | `terminal.zig` + `control/report.zig` | `host/` | Output queue ownership is host-side consequence, not screen. |
| Clipboard/title/hyperlink retention | `terminal.zig` | `host/` | Not screen truth. |
| Locator outbound behavior | `terminal.zig` + `control/locator.zig` | `host/` | Host-neutral outbound behavior. |
| Terminal dynamic colors | `terminal.zig` + `control/osc_color.zig` | `host/` now, maybe dedicated color owner later | Keep separate from render color consumption. |
| Kitty per-screen state | `terminal.zig` + `kitty.zig` | `kitty/` and `screen/` seam | Some state is screen-local, some global. |
| Kitty global queues/assets | `terminal.zig` + `kitty.zig` | `kitty/` | Keep explicit. |
| Input encoding | `input/encode.zig` + `input/*` | `input/` | Input now owns encoding logic. |
| Snapshot export | `terminal.zig` + `screen/snapshot.zig` | `screen/` | Screen-owned export contract cut is complete. |

## Mixed Seams Blocking Clean Moves

These seams must be respected or clarified before broad code motion.

- action vocabulary now lives in `action/vocabulary.zig`, but dispatch policy still lives in `terminal.zig`
- `queue` couples parser feed, event queue ownership, and direct screen application helpers
- `VisibleView` is a good screen-facing contract, but it is nested inside `Terminal`
- `HostState` keeps true host consequences, but its public accessors are mixed with screen and kitty accessors in one file
- `ModeState` currently mixes screen behavior toggles, host input encoding policy, and DEC save/restore state
- kitty state is split between per-screen and global truth, but both are hidden inside `Terminal`
- `snapshot.zig` is named too vaguely to keep unless it becomes strictly a screen-owned visible export contract

## Checkpoint Progress Notes

- Checkpoint 2 started:
  - semantic action vocabulary moved from `interpret/event.zig` to `action/vocabulary.zig`
- Checkpoint 3 started narrowly:
  - kitty payload parsing moved from `interpret/actions/kitty.zig` to `kitty/protocol.zig`
  - `kitty.zig` and `kitty/graphics.zig` no longer depend on `interpret` for kitty action payload types
  - xterm-family routing moved from `interpret/actions/*` and `interpret/csi/*` to `xterm/*`
- Checkpoint 4 started narrowly:
  - visible view moved from `terminal.zig` to `screen/view.zig`
  - primary/alternate screen-set state moved from `terminal.zig` to `screen/set.zig`
- Checkpoint 2 control-spine cut landed:
  - `action/dispatch.zig` now owns the parent event-routing loop
  - `terminal.zig` delegates `applyLimit` to that owner
  - `interpret/apply_flow.zig` no longer owns screen-apply shortcuts
  - screen-only regression helpers now depend on `action/dispatch.zig`, not parser ownership
- Checkpoint 3 kept progressing:
  - parsed-event routing moved from `interpret/actions/map.zig` to `action/route.zig`
  - kitty APC handling moved out of `interpret/actions` into `kitty/apc.zig`
- Mode ownership sharpened:
  - mode storage moved from `terminal.zig` to `control/mode.zig`
- Host ownership sharpened:
  - host consequence application moved from `interpret.zig` to `host/apply.zig`
  - host state moved from `terminal.zig` to `host/state.zig`
- Kitty ownership sharpened:
  - kitty aggregate state moved from `terminal.zig` to `kitty/state.zig`
- Screen export ownership sharpened:
  - snapshot moved from root `snapshot.zig` to `screen/snapshot.zig`
- Input ownership sharpened:
  - input encoding moved from `terminal.zig` to `input/encode.zig`
- Selection ownership sharpened:
  - selection-facing helper logic now lives in `selection.zig`
- Screen export ownership sharpened further:
  - terminal snapshot facade now delegates to `screen/snapshot.zig`
- Root export-layer progress:
  - `control.zig` was deleted in favor of direct owner imports and precise root exports
  - `interpret.zig` was deleted in favor of `action.zig`
  - `src/interpret/` no longer exists on the live path
  - `selection.zig` now re-exports `selection/state.zig`
  - `input.zig` now re-exports `input/types.zig`
  - `kitty.zig` now re-exports `kitty/types.zig`, `kitty/protocol.zig`, and `kitty/apply.zig`
  - `parser.zig` now re-exports `parser/main.zig` plus the repo-local queue surface
  - `grid.zig` now re-exports `grid/main.zig`
  - `terminal.zig` now re-exports `terminal/main.zig`
  - `action.zig` now re-exports parser-event, routing, and vocabulary surfaces
  - `howl_vt.zig` now acts as a curated repo-local root instead of a test-only stub

Root `src/*.zig` now present:

- `howl_vt.zig`
- `action.zig`
- `terminal.zig`
- `grid.zig`
- `parser.zig`
- `kitty.zig`
- `input.zig`
- `selection.zig`
- `ffi.zig`
- `libhowl_vt.zig`

All current root `src/*.zig` files are now export or ABI layers only.

## Design Doc Rule For This Sprint

`design.md` must keep describing the repo as implemented today.

Therefore:

- `vt-core-sprint.md` is the migration source of truth during Checkpoint 1
- `design.md` should not pretend the new owner shape already exists
- `design.md` should be rewritten when the code crosses a real owner boundary, not before
- if `design.md` continues to bless fake enduring owners after those code moves, that becomes a checkpoint failure

## Naming Rules For This Sprint

Prefer:

- owner nouns
- protocol-family nouns
- state nouns
- contract nouns

Reject:

- `interpret`
- `process`
- `manager`
- `helper`
- `util`
- any new umbrella noun that merely replaces `Terminal`

## Sprint Scope

### In Scope

- internal owner map cleanup
- protocol taxonomy cleanup
- root export-layer cleanup
- design-doc truth update
- migration toward parser/protocol/action/state separation

### Out Of Scope

- final public ABI freeze
- render seam closure
- host UX policy work
- protocol completeness expansion for its own sake
- copying Ghostty file-for-file without owner justification

## Checkpoints

### Checkpoint 1

Theme: truth map.

Must do:

- inventory every responsibility currently living in `src/terminal.zig`
- assign each responsibility to a real owner group
- identify mixed seams that block clean movement
- rewrite sprint/design docs to describe the new target honestly

Close signal:

- doc truth is accepted
- no file moves required yet

### Checkpoint 2

Theme: action seam.

Must do:

- name and isolate the explicit terminal action vocabulary
- stop calling that seam `interpret`
- define which actions belong to screen, host, mode, report, kitty, and protocol families

Close signal:

- the action seam is explicit in names and docs
- current mixed event/action buckets are reduced or clearly scheduled for deletion

### Checkpoint 3

Theme: protocol-family cut.

Must do:

- pull baseline xterm-family meaning out of the `interpret` bucket
- keep kitty explicit
- create iterm ownership only where real behavior exists or is imminent
- stop mixing protocol-family meaning under generic action-mapping names

Close signal:

- family naming is explicit
- generic protocol buckets shrink materially

### Checkpoint 4

Theme: screen and host truth.

Must do:

- move visible-view and screen-set truth toward `screen/`
- move pending output and host consequences toward `host/`
- stop letting one owner file carry both screen truth and host truth

Close signal:

- screen and host seams are explicit
- visible-state export truth is VT-owned and clearly named

### Checkpoint 5

Theme: root cleanup.

Must do:

- reduce root `src/` to export and ABI files only
- delete `interpret` as an organizing concept
- delete `terminal.zig`
- update `howl_vt.zig` to curated exports only

Close signal:

- root `src/` stop criteria is met

## First Cut Guidance

Do not start with broad file churn.

Prefer this order:

1. lock doc truth
2. isolate the action seam
3. separate protocol-family meaning
4. separate screen and host owners
5. collapse root `src/` to exports only

This order avoids smearing today’s confusion across more folders.

## Ghostty Takeaways To Copy

- root export shape
- explicit protocol-family names
- explicit parser owner
- explicit screen owner
- explicit action vocabulary seam

## Ghostty Takeaways Not To Copy Blindly

- giant `Terminal.zig` as an enduring owner
- exact file count
- broader app/runtime needs that Howl does not have

Howl should copy the split, not the weight.

## Design Rules For Decisions

When a move is unclear, answer these questions in order:

1. who owns the invariant?
2. who mutates the state?
3. is this syntax, meaning, action vocabulary, or application?
4. is the current name an owner name or a phase name?
5. if ABI callers saw this today, would it freeze a lie?

If any answer is unclear, stop and mark `work-not-clear`.

## Proof Gates

Each checkpoint must close with:

- docs updated with the same checkpoint
- `zig build test` in `howl-vt`
- `git diff --check`
- `nu "./style.nu" --touched-files --json`
- `nu "./style.nu" --failures --json`

When a checkpoint moves ABI-observable behavior:

- `zig build` in `howl-linux-host`

## Review Fails

A checkpoint fails if it:

- preserves `interpret` as a long-term concept
- preserves `terminal.zig` because deleting it feels like too much churn
- moves code into folders without clarifying ownership
- invents ABI shape while owner truth is still open
- mixes protocol-family meaning with screen or host mutation
- mixes screen-visible truth with host consequence queues
- leaves root `src/` owning live state or behavior

## Closure

This sprint closes when all of the following are true:

- the numbered non-negotiable truths are satisfied
- `design.md` matches the new owner story
- `src/` is export/ABI layer only
- `terminal.zig` is deleted
- `interpret` is deleted as an organizing concept
- parser/protocol/action/state separation is visible in the tree and in names
