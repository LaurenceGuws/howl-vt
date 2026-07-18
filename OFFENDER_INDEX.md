# Howl VT Offender Index

Audited from `8606bd5` on 2026-07-18. Scores measure executable ownership,
failure, bounds, invariants, and proof. Comments and file size earn no points
by themselves.

## Current score

| Bar | Score | Blocking evidence |
| --- | ---: | --- |
| Foot directness | 10/10 | Current control flow keeps protocol classification and execution direct; no concrete indirection defect is indexed. |
| TigerBeetle defensiveness | 9/10 | Input failures propagate exactly and Screen runtime allocation failure preserves paired history state; broader typed hostile-operation proof remains. |
| Character/capability density | 10/10 | The root exports one direct native `Terminal` owner without compatibility layers or additional ownership machinery. |
| Ownership/cleanup | 9/10 | Resize and runtime history replacement are transactional; every temporary owner has failure cleanup and successful reuse proof. |
| Exact failures | 7/10 | `Terminal.encodeInput` now owns paste and locator-consequence failures; parser, OSC decode, and resize/history helpers still infer error sets. |
| Documentation | 10/10 | The source audit covers every source owner and retained public declaration and guards the one-symbol embedding root. |
| Hostile-input evidence | 8/10 | Native fuzzing covers bytes, resize, reset, inspection, and post-error reuse; exhaustive allocation proof now covers input and runtime history, while other typed host operations remain absent. |
| Embedding surface | 10/10 | `src/howl_vt.zig` exports one directly owned native `Terminal`; current root-only integration proof exercises the accepted embedding shape. |
| Deliberate modification | 7/10 | Unit, simulation, fuzz, coverage data, and source audits exist; exact-error, assertion-density, and inferred-discard audits remain manual. |
| Source maturity | 9/10 | Protocol breadth, deterministic parsing, transactional history, and allocation-free rectangle copy are proved; inferred failure boundaries and missing typed hostile-operation proof remain. |

## Ordered offenders

### VT-016 — Locator input turns operating failures into panics

- Status: resolved
- Path/symbol: `src/locator.zig:handleMouseEvent`;
  `src/terminal.zig:Terminal.encodeInput`, `encodeMouseInput`
- Defect: locator reports append to bounded heap-backed host output, but both
  `OutOfMemory` and `ConsequenceLimit` are caught as `unreachable`.
  `Terminal.encodeInput` consequently advertises only paste failures.
- Bars: defensiveness, exact failures, hostile-input evidence, maturity
- Shape: propagate the existing exact host consequence errors through mouse
  input and combine them with paste errors at the terminal boundary.
- Proof: allocation failure and output-capacity rejection return exact errors,
  preserve pending output, leave locator state reusable, and never panic.
- Depends on: nothing
- Resolution: `handleMouseEvent` returns `host_state.ApplyError` and mutates
  one-shot/filter latches only after report publication succeeds.
  `Terminal.InputError` combines exact paste and retained-consequence errors.
  Direct tests induce locator allocation failure and a full 64 KiB output
  queue, verify unchanged output, then prove successful reuse and one-shot
  consumption.

### VT-017 — Screen runtime mutation silently loses allocation failures

- Status: resolved
- Path/symbol: `src/screen.zig:storeHistoryRow`, `copyRect`
- Defect: history retention may partially extend an open logical line before
  projection allocation fails; rectangular copy silently ignores temporary
  allocation failure. Callers cannot distinguish applied, rejected, and
  partially retained mutations.
- Bars: defensiveness, ownership, exact failures, hostile-input evidence
- Shape: make each mutation transactional or propagate its exact operating
  failure through semantic routing and `Terminal.feed`.
- Proof: exhaustive allocation failure leaves screen authority and projection
  paired, then accepts a succeeding mutation.
- Depends on: VT-016 establishes operating-error propagation at another
  terminal boundary
- Resolution: `storeHistoryRow` builds the next logical line and reserves
  projection and authority capacity before committing either representation.
  Allocation failure drops only the departing visible row; retained logical
  authority and projected rows remain paired and the next scroll can succeed.
  Full history releases one oldest logical owner and replaces its ring slot in
  constant time. `copyRect` uses overlap-aware row and column direction and
  performs no allocation. Terminal-level failure
  injection covers every allocation while starting and extending logical
  history, then proves successful reuse; Screen tests cover both rectangle
  overlap directions with the allocator set to fail.

### VT-019 — Allocation owners expose inferred failure sets

- Status: open
- Path/symbol: `src/parser.zig:Parser.init`;
  `src/stream_terminal.zig:DcsCapture.start`, `put`,
  `TerminalStreamState.initAlloc`; `src/osc.zig:decodeClipboardSet`;
  `src/screen/resize.zig:reflowLogicalLines`, `allocResizeBuffers`;
  `src/screen.zig:collectLogicalSnapshot`
- Defect: these allocation and decode boundaries infer their error sets, so
  callers cannot review the complete failure vocabulary from the owner
  contract and implementation changes can widen it silently.
- Bars: defensiveness, exact failures, deliberate modification
- Shape: give each owner the smallest exact error set supported by its current
  operations, preserving direct propagation through existing callers.
- Proof: compile-time assignments pin each public boundary to its declared
  errors and direct tests exercise each reachable failure.
- Depends on: VT-017 for the screen mutation chain; parser, stream, and OSC
  owners are independent

### VT-020 — Native hostile proof omits typed host operations

- Status: open
- Path/symbol: `test/fuzz_terminal.zig:fuzzTerminal`
- Defect: the current operation model generates feed, resize, reset, and
  inspect only. Keyboard, mouse, focus, paste, selection, drain, acknowledge
  rejection, and allocator-failure transitions are absent.
- Bars: defensiveness, hostile-input evidence, deliberate modification
- Shape: extend the bounded native operation vocabulary only as each public
  owner gains exact invariants and failure semantics.
- Proof: generated typed operations assert bounds, ownership, post-error reuse,
  and deinitialization through the curated root.
- Depends on: VT-016; screen allocation transitions depend on VT-017

### VT-021 — Source safety properties remain manually audited

- Status: open
- Path/symbol: `tools/audit_source.sh`; repository-wide
- Defect: the executable audit protects owner contracts and public
  declarations only. Inferred error unions, discarded fallible results,
  `anytype`, and assertion gaps can enter silently.
- Bars: defensiveness, exact failures, deliberate modification, maturity
- Shape: add narrow executable checks only after each forbidden pattern has a
  proven exception model; avoid brittle text policy pretending to prove
  semantics.
- Proof: each gate rejects one intentionally introduced violation and accepts
  every documented exception.
- Depends on: VT-017, VT-019, and VT-020 establish the accepted patterns

## Hardening loop

Confirm each cited defect against the live source, implement one coherent
owner slice, add evidence at its real boundary, run format/check/unit,
simulation, fuzz, audit, and diff gates, then update scores only from observed
behavior.
