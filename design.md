# howl-vt Design

Updated: 2026-05-30.

Shared rules: [`../AGENTS.md`](../AGENTS.md), [`../project-memory.md`](../project-memory.md), [`../libs.yaml`](../libs.yaml)

## Purpose

`howl-vt` owns the host-neutral terminal model.

It parses terminal input streams, maps parser events into terminal actions, mutates screen state, owns selection truth, encodes host input according to terminal modes, and exposes host-facing protocol consequences and visible-surface truth through a C ABI.

It does not own PTY transport, host wake policy, host event loops, render text shaping, or backend presentation.

## Public Surface

- The shipped embedding contract is `include/howl_vt.h` plus exported `howl_vt_*` symbols.
- `src/libhowl_vt.zig` is the C ABI export root.
- Internal Zig roots are repo-local test/fuzz/proof wiring only.
- Hosts and embedders consume VT through the C ABI only.

## Owners

- `src/ffi.zig` translates the C ABI only.
- `src/terminal.zig` owns terminal lifecycle and composes parser, screen, host, kitty, selection, and input state.
- `src/stream_terminal.zig` owns byte-stream batching and parent routing into terminal-owned state.
- `src/parser/` owns byte-step syntax recognition and parser-event materialization.
- `src/action/` owns terminal action vocabulary and parsed-event routing.
- `src/screen.zig` and `src/screen/` own one-screen mutable state and screen mutation.
- `src/screen_set.zig` owns primary/alternate screen composition and visible-history projection.
- `src/selection.zig` and `src/selection/state.zig` own selection state and mutation.
- `src/host/` owns host-facing retained consequences such as title, pending output, clipboard, hyperlink, dynamic color, and visible-surface metadata.
- `src/input/` owns key/mouse/focus/paste input vocabulary and encoding.
- `src/xterm/` owns xterm-family control routing.
- `src/kitty/` owns kitty protocol state, parsing, and consequences.

## Main Flow

1. Host creates an opaque VT terminal handle through the C ABI.
2. Host feeds bytes from PTY transport into `howl_vt_terminal_feed`.
3. Parser owners produce events and action routing delegates mutation to screen, host, kitty, mode, report, and selection owners.
4. Host drains pending protocol consequences such as output, clipboard, title, and visible metadata through ABI calls.
5. Host copies visible-surface truth for render publication.
6. Host encodes keyboard, mouse, focus, and paste input through VT input ABI calls before sending bytes to PTY.

## Invariants

- VT owns terminal state truth; render and host must not invent terminal state.
- Selection coordinates are VT/history-aware and must be mutated through VT selection contracts.
- Dirty and snapshot identities are VT-owned and retired only through the acknowledged ABI path.
- Parser syntax, parser events, action vocabulary, screen mutation, and host consequences remain separate owners.
- Bounded ABI buffers publish their limits in `howl_vt.h`.
- Runtime control signals and wake policy do not belong in VT.

## Non-Goals

- PTY process management or transport reads/writes.
- Host windows, input queues, event loops, or wake threads.
- Render glyph shaping, rasterization, or prepared surfaces.
- Backend presentation or graphics resources.
