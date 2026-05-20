# Howl VT Core Sprint

Shared rules: [`../AGENTS.md`](../AGENTS.md), [`../WORKFLOW.md`](../WORKFLOW.md),
[`../design/style-law.md`](../design/style-law.md),
[`../design/reference-index.md`](../design/reference-index.md)

## Purpose

Keep `howl-vt` moving toward a Ghostty-clean VT core under TigerBeetle-style gates.

This sprint is no longer about deleting `terminal.zig` for its own sake. It is about owner truth,
throughput truth, and zero tolerance for stale doc or code posture.

## Bias

- TigerBeetle first for bounds, assertions, simplicity, and hygiene.
- Ghostty second for VT-core split, parser shape, and lib-vt layering lessons.
- Alacritty third for outer-loop burst discipline and host fairness pressure.

## Current Truths

1. `src/terminal.zig` is currently the smallest honest VT aggregate owner. It may survive only while
   it remains an owner, not a facade or runtime bucket.
2. `interpret` is dead and must stay dead.
3. Parser owns syntax only. It does not own terminal meaning.
4. Action routing owns the parent bounded-apply control spine.
5. Screen truth, host consequence truth, kitty state, input encoding, and selection stay in
   separate owners.
6. Repo-local roots may curate exports, but they must not hide or lie about live owners.
7. Throughput constants are design facts. Each one must cite Ghostty or Alacritty, explain why
   Howl keeps it today, and name the proof that closes it.
8. If a bound is still provisional, mark it open. Do not narrate it as settled.
9. Host runtime cadence stays in `howl-linux-host`. VT does not silently take it back.

## Closed Cuts

- `interpret` was deleted in favor of explicit `action/`, `xterm/`, `kitty/`, `host/`, `input/`,
  `selection/`, and parser owners.
- parser byte feed and parsed-event queue now live under `src/parser/`.
- bounded apply control spine now lives under `src/action/dispatch.zig`.
- input encoding no longer hangs off terminal facade methods.
- visible view, history projection, dirty export, and resize ownership now live under
  `screen.zig` and `screen_set.zig`.
- host consequence queries now live under `host/state.zig`.
- kitty retained-state queries now live under `kitty/state.zig`.
- runtime control-signal vocabulary is gone from VT.

## Active Seams

- `src/parser/events.zig`
  - queued style-change and DCS payload shapes are still too heavy inline.
  - the parsed-event queue no longer carries CSI or DCS max-sized arrays inline.
- `src/parser/main.zig`
  - `csi_max_params = 24` now matches Ghostty again.
  - keep it only while the slimmer queue and parser-action shapes still hold the current benchmark
    path.
- `src/terminal.zig`
  - keep shrinking it toward the smallest honest VT aggregate owner.
  - do not let it grow convenience facades or runtime policy back in.
- `src/ffi.zig`, `src/screen.zig`, and `src/screen/history.zig`
  - remaining owner-path style-density hotspots.
- `howl-linux-host/src/terminal/runtime/progress.zig`
  - `vt_apply_events_per_turn = 1024` is the current measured fairness gate.
  - re-derive it again if queue shape or host proof changes.
- colored-output throughput
  - `lsd -la --color=never` vs `lsd -la --color=always` remains the real host-facing repro.
  - exact `PTY -> VT` chunk capture now uses the `howl-pty-vt-hex-v1` fixture format so replay
    tests can feed the same chunk boundaries inside `src/test/pty_feed_record.zig`.

## Throughput Rules

- PTY burst sizes follow Alacritty's `READ_BUFFER_SIZE = 1 MiB` and `MAX_LOCKED_READ ~= 64 KiB`.
- Parser queue and APC bounds may reuse that burst scale only when the worst-case VT event
  materialization still matches it.
- Host apply budgets must stay explicit, small, and justified by current VT shape.
- Changing a throughput bound requires:
  - the reference source
  - the local rationale
  - the proof command set
  - the changed benchmark or runtime result

## Copy From Ghostty

- parser `next(byte)` step shape
- explicit parser/protocol/action/application split
- direct VT write path
- honest C ABI layering
- small, owner-named files

## Do Not Copy Blindly

- large enduring terminal buckets that hold unrelated policy
- broader app/runtime weight that belongs to Ghostty's host
- ABI or file-count decisions that do not fit Howl's current product boundary

## Proof Gates

- `zig build test`
- `zig build fuzz:build`
- `git diff --check`
- `nu "./style.nu" --touched-files --json`
- `nu "./style.nu" --failures --json`

When throughput posture or host-visible runtime behavior moves:

- `zig build terminal-benchmark -- --runs 1 --text`
- `zig build` in `howl-linux-host`

## Review Fails

- stale doc truth
- fake owner posture
- wrapper or namespace bags that only forward
- hidden throughput policy
- any bound without reference, local rationale, and proof
- any change that claims Ghostty parity while keeping Howl-only owner debt hidden

## Closure

This sprint closes only when:

- doc truth and code truth agree
- the remaining terminal owner story is simple and honest
- throughput constants are either closed with reference and proof or explicitly marked open
- the queued-event shape is slim enough that Ghostty-style VT simplification is no longer blocked
  by fake baggage
