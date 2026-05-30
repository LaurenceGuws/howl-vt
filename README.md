# howl-vt

Host-neutral terminal model for Howl.

`howl-vt` parses terminal byte streams, routes parser events into terminal actions, mutates screen state, owns selection truth, encodes host input according to terminal modes, and exposes visible-surface and protocol consequences through a C ABI.

## Public ABI

- Header: `include/howl_vt.h`
- Exported symbols: `howl_vt_*`
- Public root: `src/libhowl_vt.zig`

Internal Zig roots are repo-local test/fuzz/proof wiring only.

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
