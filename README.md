# howl-vt

Host-neutral terminal model for Howl.

`howl-vt` parses terminal byte streams, routes parser events into terminal actions, mutates screen state, owns selection truth, encodes host input according to terminal modes, and exposes visible-surface and protocol consequences through a C ABI.

## Embedding surfaces

- Native Zig module: `howl_vt`
- Native root: `src/howl_vt.zig`
- C header: `include/howl_vt.h`
- C exports: `howl_vt_*`
- C root: `src/libhowl_vt.zig`

The native Zig model is the primary development surface. The C ABI remains
available as language-neutral glue while it continues to earn its maintenance
cost.

## Build

```sh
zig build check
zig build test
```

## Boundary

- VT owns terminal state truth, parser state, selection, input encoding, and host-facing protocol consequences.
- PTY owns transport.
- Render owns rendering contracts and prepared surfaces.
- Hosts own event loops, windows, wake policy, and presentation.

See `design.md` for the current owner map and invariants.
