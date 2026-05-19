# Parser Ghostty Alignment

Rule: Ghostty is the parser bible. When Howl differs, the default action is to remove the Howl shape unless a hard ownership proof says otherwise.

## Ghostty Step Loop

1. Receive one byte through `next(c)`.
2. Look up the table effect from `(byte, state)`.
3. Compute `next_state` and transition action.
4. Emit exit action if the state changes.
5. Execute the transition action.
6. Emit entry action if the state changes.
7. Store the new parser state.
8. Return only parser actions. Do not batch slices. Do not apply terminal policy here.

## Howl Current Step Loop

1. Receive bytes through `handleByte(output, byte)` or `handleSlice(output, bytes)`.
2. If a string control is active, feed its buffer directly and maybe emit a completed action.
3. If batching is allowed, duplicate an ASCII slice into caller-owned output.
4. Otherwise look up the table effect from `(byte, state)`.
5. Apply the transition through `applyTransition(...)`.
6. Run stream decoding, CSI accumulation, charset selection, and DEC-special mapping from parser-owned helpers.
7. Append Howl parser actions into caller-owned output.
8. Return no direct step result; outer code reads the caller-owned action list.

## Current Debt List

1. Parser root API differs: Ghostty uses `next(byte)`, Howl still exposes `handleByte` and `handleSlice`.
2. Parser root still batches ASCII slices; Ghostty emits byte-step parser actions.
3. Parser root still owns charset and DEC-special interpretation that Ghostty does not keep in parser shape.
4. CSI accumulation is still split into `CsiParser` instead of parser-root fields.
5. String controls are emitted as completed payloads instead of Ghostty-style lifecycle/data steps.
6. Howl does not model explicit exit/transition/entry actions.

## Strict Iteration Loop

1. Pick one debt item.
2. Read Ghostty for that exact step.
3. Remove the Howl-only shape.
4. Keep the smallest code that matches Ghostty more closely.
5. Run `zig build test` and `git diff --check`.
6. Recompare both parser roots before starting the next cut.

## Active Iteration

Iteration 1: parser root API.

Target:
- parser root exposes byte-step `next(...)`
- slice feeding moves to `src/parser/queue.zig`
- `src/parser.zig` stops advertising slice orchestration as parser truth
