# howl-vt

Host-neutral terminal model for Howl.

Version `0.1.0-dev` interfaces may change without notice.

`howl-vt` parses terminal byte streams, routes parser events into terminal actions, mutates screen state, owns selection truth, encodes host input according to terminal modes, and exposes visible-surface and protocol consequences through native Zig interfaces.

## Embedding surfaces

- Native Zig module: `howl_vt`
- Native root: `src/howl_vt.zig`
- Curated owner: `howl_vt.Terminal`

The native Zig model is the only embedding surface. The previous C ABI was
removed because it projected contracts before the native state machine had
earned a stable external shape. A future ABI may be designed from scratch
after the native model matures.

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
