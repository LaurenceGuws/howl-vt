# Terminal Main Loop Plan

Purpose: track the post-deletion cleanup of terminal owner residue now that the nested
`src/terminal/main.zig` file is gone and `src/terminal.zig` is the current VT aggregate owner.

Mapping target:
- Ghostty `src/terminal/Terminal.zig` -> Howl `src/terminal.zig`
- Ghostty `src/terminal/main.zig` -> Howl `src/howl_vt.zig`

## Rules

- `src/terminal.zig` stays only if it remains an honest owner.
- Move storage and mutation to smaller owners when the owner is clear.
- Do not preserve convenience facades once deeper owners exist.
- Prefer Ghostty's owner split and TigerBeetle simplicity.
- If a responsibility is really host runtime or PTY work, move it up.
- Harnesses and benchmarks may falsify assumptions after a design cut. They do not pick the next
  design.
- Each loop closes only with proof and doc updates.

## Closed Moves

- runtime and control signals moved up out of VT
- input encoding moved to `src/input/`
- visible view, history projection, dirty export, and resize moved to `screen.zig` and
  `screen_set.zig`
- selection storage moved under screen-owned state
- parser feed and bounded apply entrypoints moved to `src/parser.zig` and `src/action.zig`
- host consequence queries moved to `src/host/state.zig`
- kitty retained-state queries moved to `src/kitty/state.zig`
- nested `src/terminal/main.zig` is gone and `src/howl_vt.zig` is the curated repo-local root

## Current Loops

### Loop 1: Keep The Terminal Aggregate Honest

Goal:
- stop `src/terminal.zig` from regrowing facade posture

Work:
- delete repo-local forwarding methods as soon as deeper owners exist
- keep lifecycle, aggregate owner state, and only the minimal cross-owner glue here
- fail any new runtime-policy or convenience-owner drift immediately

Close signal:
- `src/terminal.zig` can be explained as one honest aggregate owner in one paragraph

### Loop 2: Keep Direct Feed Honest Before More Terminal Cuts

Goal:
- keep the direct feed path honest

Work:
- keep `src/stream_terminal.zig` as the only live VT mutation path
- do not let a queued feed/apply phase grow back in code or docs
- keep `csi_max_params = 24` only while the direct parsed-event shape stays Ghostty-aligned and
  proof does not falsify it

Close signal:
- Ghostty's `24` ceiling is live on the direct feed path with no queued feed/apply fallback

### Loop 3: Keep The Host PTY Slice Reference-Backed

Goal:
- keep host fairness explicit without reviving VT backlog phases

Work:
- measure only after the reference-backed direct-feed cut lands
- compare against colored-output repro and `terminal-benchmark`
- either keep the PTY slice limits with proof or change them with proof

Close signal:
- the host-side PTY slice comment is reference-backed and no folklore VT apply gate survives

### Loop 4: Reduce Remaining Root Posture

Goal:
- keep only curated roots and honest owners

Work:
- delete any remaining root re-export bag that no longer earns its place
- keep root docs and root exports aligned with the actual owner tree

Close signal:
- root files are either owner roots or curated roots, never both by accident

## Stop Conditions

- ownership became unclear
- a smaller owner cannot be named honestly
- a bound has no reference or proof
- the shortest correct change requires a new umbrella layer

## Proof Per Loop

- `zig build test`
- `zig build fuzz:build` when parser or fuzz code moves
- `zig build terminal-benchmark -- --runs 1 --text` when throughput posture moves
- `git diff --check`
- `nu "./style.nu" --touched-files --json`
- `nu "./style.nu" --failures --json`
- `zig build` in `howl-linux-host` when host-visible runtime behavior moves

## End State

- `src/terminal.zig` either remains the smallest honest VT aggregate owner or is replaced by a
  smaller honest owner
- no stale facade or doc posture survives
- no host runtime phase compensates for deleted VT queue baggage
