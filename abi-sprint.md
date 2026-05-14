# Howl VT ABI Sprint

Shared rules: [`../AGENTS.md`](../AGENTS.md), [`../WORKFLOW.md`](../WORKFLOW.md),
[`../design/style-law.md`](../design/style-law.md),
[`../design/tigerbeetle-style-sprint.md`](../design/tigerbeetle-style-sprint.md)

## Purpose

This sprint applies the PTY boundary reset standard to `howl-vt`.

Target outcome:

- TigerBeetle-style discipline
- C ABI embeddability as the real product boundary
- no Zig-shaped host facades
- no wrapper namespace roots
- no getter-heavy ABI convenience posture where header contract values should be explicit

`howl-pty` is the reference result.

## Current Smells

- `src/howl_vt.zig` mixes ABI export root and repo-local root posture
- `src/vt_namespace.zig` is wrapper namespace theater
- `build.zig` preserves a fake dual-surface story with the same root used for internal and ABI shape
- `include/howl_vt.h` is getter-heavy and validator-heavy for keys, modifiers, and mouse vocabulary
- `HowlVtHandle` is still `uintptr_t` instead of an opaque handle contract
- `design.md` says C ABI only, but the root/build shape still preserves Zig-shaped integration posture

## Baseline

Current measured totals:

- `prod=8860`
- `usizes=375`
- `asserts=196`
- `long_funcs=8`

Current proof:

- `zig build test` passes in `howl-vt`

## Required End State

- one explicit shipped contract: `include/howl_vt.h`
- one explicit ABI export root: `src/libhowl_vt.zig`
- no wrapper namespace root
- no host-facing Zig root story in docs, roots, or build wiring
- no stale exported symbols remain
- vocabulary contract is explicit in the header where appropriate
- Linux host consumes the cleaned VT ABI only

## Checkpoints

### Checkpoint 1

Theme: contract lock.

Assigned files:

- `design.md`

Must do:

- rewrite `design.md` facts to describe C ABI as the only real embedding boundary
- name every Zig-shaped facade or root scheduled for deletion
- remove wording that preserves Zig-root consumption as an acceptable integration path

### Checkpoint 2

Theme: root and facade deletion.

Assigned files:

- `src/vt_namespace.zig`
- `src/howl_vt.zig`
- `src/libhowl_vt.zig`
- `build.zig`

Must do:

- delete `src/vt_namespace.zig`
- stop `src/howl_vt.zig` from acting as host-facing convenience aggregation
- add `src/libhowl_vt.zig` as the explicit ABI export root
- remove build wiring that preserves fake dual-surface posture

### Checkpoint 3

Theme: ABI sharpening.

Must do:

- inventory and delete getter-heavy ABI convenience symbols that should be header-declared contract
  values instead
- replace integer-handle posture with a stricter opaque-handle contract if the host can consume it
- remove stale validators and convenience helpers that do not belong in the shipped ABI

### Checkpoint 4

Theme: owner cleanup.

Must do:

- keep parser syntax, interpret meaning, grid mutation, and host consequences owner-separated
- remove remaining public shape that suggests host-facing Zig owner access
- tighten docs so shipped ABI and repo-local owner APIs are not mixed

### Checkpoint 5

Theme: Linux host proof.

Must do:

- update `howl-linux-host` to the cleaned VT ABI as needed
- remove stale host assumptions about deleted symbols
- prove the host still builds and runs on the owned path

## Proof Gates

Each checkpoint must close with all of the following:

- `zig build test` in `howl-vt`
- `nu "./style.nu" --touched-files --json`
- `nu "./style.nu" --failures --json`
- `git diff --check`
- when ABI changes reach the host seam, `zig build` in `howl-linux-host`

## Review Gates

A checkpoint fails review if it does any of the following:

- preserves a Zig-shaped facade or root because it is convenient
- adds a compatibility wrapper
- keeps duplicate public stories alive in parallel
- exports a symbol that exists only to mirror Zig internals
- leaves ownership unclear between terminal, input, parser, grid, and FFI
- keeps hidden policy in a root or wrapper
- claims C ABI first while preserving Zig integration as a practical bypass
- closes without exact proof on the changed path
