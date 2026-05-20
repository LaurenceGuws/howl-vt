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

1. Receive one byte through `next(byte)`.
2. If a string control is active, feed that owner and maybe emit byte-step `*_put` or `*_end` actions.
3. Otherwise look up the table effect from `(byte, state)`.
4. Build ordered exit, transition, and entry phases directly.
5. Return parser actions only.
6. CSI and DCS-hook metadata now borrow parser-owned slices until the next `next(byte)` call.
7. Queue batching and parsed-event ownership live in `src/parser/queue.zig` and `src/parser/events.zig`.

## Current Debt List

1. Howl still uses its own smaller incremental OSC owner instead of Ghostty's exact command-state
   ladder and per-command parser shape.
2. Recompare parser-owner boundaries before moving more protocol consequences across parser/action seams.

## Strict Iteration Loop

1. Pick one debt item.
2. Read Ghostty for that exact step.
3. Remove the Howl-only shape.
4. Keep the smallest code that matches Ghostty more closely.
5. Run `zig build test` and `git diff --check`.
6. Recompare both parser roots before starting the next cut.

## Closed Iteration

Iteration 1: parser root API and borrowed action slices.

Closed result:
- parser root exposes byte-step `next(...)`
- slice feeding moved to `src/parser/queue.zig`
- CSI and DCS-hook actions now borrow parser-owned metadata directly instead of copying into a
  second emit buffer first
- `src/parser.zig` no longer advertises slice orchestration as parser truth

## Closed Iteration

Iteration 2: CSI separator truth.

Closed result:
- parser CSI separators now use a Ghostty-like bitset instead of per-param separator bytes
- `src/parser/events.zig` no longer stores per-param separator bytes in the queued parsed-event
  payload path
- SGR colon handling now reads separator truth from that bitset end-to-end

## Active Iteration

Iteration 3: string-control owner shape.

Target:
- compare Howl's remaining buffered OSC owner against Ghostty's exact OSC parser shape
- keep parser ownership syntax-only while making the next difference exact

Closed result so far:
- parser no longer owns APC/DCS/PM payload bytes
- `src/parser/events.zig` is now the real payload owner for APC/DCS/PM queued bytes and limits
- parser string-control state for APC/DCS/PM is now passthrough-only, closer to Ghostty's direct byte-step path
- parser now emits typed OSC command/payload metadata directly instead of relying on queue-side
  OSC reparsing
- parser now classifies OSC incrementally while bytes arrive and no longer reparses buffered OSC text
  at exit
- valid numeric OSC commands now buffer payload bytes only; invalid/raw OSC forms still fall back to
  one raw buffer
- parser now tracks numeric OSC command values incrementally instead of reparsing the numeric prefix
  from stored bytes
- shared BEL/ST/ESC delimiter policy is now centralized for buffered and passthrough string controls;
  OSC keeps separate command/raw ownership on top of that shared delimiter rule
- OSC payload limits now follow per-command owner policy instead of one generic metadata bound;
  large clipboard/text-size/file-transfer families use the large string-control ceiling
- OSC command policy now lives in one parser-owned rule mapping command -> kind + payload bound,
  including raw invalid/title fallback on finish
- raw OSC fallback no longer keeps a separate side-channel for kind classification; it updates the
  same parser-owned policy state used by command-recognized OSC paths
- OSC no longer keeps a separate prefix-byte store; one parser-owned buffer now carries provisional
  prefix bytes and raw fallback bytes, and recognized commands clear that buffer explicitly on
  promotion to payload or command-only completion
- OSC no longer keeps a separate prefix-length counter; prefix truth now comes directly from the
  shared parser-owned buffer
- OSC no longer keeps a separate numeric-prefix validity flag; validity now lives in the optional
  accumulator state itself
- OSC no longer keeps recognized command value outside the command-policy owner; command, kind, and
  payload bound now live together in the same parser-owned policy record
- OSC payload and raw body stepping now share one explicit parser-owned body helper; raw keeps only
  its real extra rule that `;` flips kind to `.other`
- OSC final dispatch data now comes from one parser-owned snapshot instead of separate command/kind/
  payload queries, and recognized-prefix promotion is centralized in one helper
