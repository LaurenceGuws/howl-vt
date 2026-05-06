# Protocol Matrix

## Goal
Drive `howl-vt-core` toward explicit xterm baseline parity and staged kitty protocol adoption.

`protocol_coverage.db` is the source of truth for protocol maturity work in this repo.
This file is a human summary of that ledger.

The stable day-to-day table is `protocols`, with human-facing protocol names,
sequence shapes, stable unit-test filter names, and three completeness flags:
- `implemented`
- `unit_tested`
- `host_tested`

`unit_test_filters` stores newline-delimited Zig test filter strings. It is intentionally human-curated, file-agnostic, and aimed at targeted regression runs.

Source provenance remains available through:

- `protocol_sources`
- `protocol_source_items`
- `protocol_source_item_dispositions`
- `protocol_source_links`
- `protocol_aliases`

Useful working views:

- `protocol_gaps`
- `protocol_summary`
- `protocol_learning_inventory`
- `protocol_source_audit`
- `protocol_source_item_disposition_review`

Repo-local source material now lives in `official_docs/xterm/` and `official_docs/kitty/`.

Example query:
```sh
sqlite3 protocol_coverage.db \
  "SELECT id, family, kind, name, sequence FROM protocol_gaps WHERE implemented = 0 OR unit_tested = 0;"
```

Targeted regression query:
```sh
sqlite3 protocol_coverage.db \
  "SELECT id, unit_test_filters FROM protocols WHERE unit_tested = 1 AND unit_test_filters <> '';"
```

Source audit query:
```sh
sqlite3 protocol_coverage.db \
  "SELECT source_id, inventory_state, source_items, linked_items, classified_items, unlinked_items FROM protocol_source_audit;"
```

Disposition query:
```sh
sqlite3 protocol_coverage.db \
  "SELECT disposition, source_id, title, sequence FROM protocol_source_item_disposition_review ORDER BY source_id, source_order;"
```

## Status
- `supported`: parser, action mapping, and grid/input behavior exist with tests.
- `partial`: some layers exist, but behavior is incomplete, dropped, or mode-insensitive.
- `unsupported`: no meaningful handling yet.
- `deferred`: intentionally not in the current tranche.

## Corpus
- Human reference inputs used when curating the ledger:
  - `official_docs/xterm/ctlseqs.html.md`
  - `official_docs/xterm/ctlseqs-contents.md`
  - `official_docs/kitty/*.md`
- Current deterministic fuzzers:
  - `src/fuzz/scrollback.zig`
  - `src/fuzz/protocol.zig`

The current baseline is frozen.

- `protocols` is the authoritative implementation scope.
- Source material exists for provenance and clarification, not for ongoing
  inventory generation.
- Non-canonical source artifacts are tracked explicitly in
  `protocol_source_item_dispositions`.

## Development Loop

Use this loop for every protocol slice:

1. Pick a narrow slice from `protocol_gaps`.
   Group by shared parser or action-mapping work, not by document order.
2. Read the canonical row and linked source excerpts.
   Use `protocol_learning_inventory` to confirm exact sequence shape,
   terminology, and nearby related rows.
3. Define the behavioral contract before editing code.
   Decide what the parser must accept, what parser event must exist, what
   terminal action/state must change, and what host or render behavior must be
   observable.
4. Add or tighten tests first when practical.
   Prefer targeted regression tests near the owning layer. Use the row's
   `unit_test_filters` field to keep focused reruns easy.
5. Implement the smallest complete change.
   Keep syntax handling in the parser, typed event shaping in parser events,
   protocol meaning in action mapping, and UI or host consequences at the edge.
6. Run focused tests, then `zig build test`.
   Do not mark a row implemented or tested until behavior and tests actually
   land.
7. Update `protocols` metadata.
   Set `implemented`, `unit_tested`, `host_tested`, adjust
   `unit_test_filters`, and tighten notes so the ledger stays executable.
8. Repeat by tranche.
   Prefer finishing one coherent family cleanly over scattering partial
   support across unrelated rows.

## Structure Rules

Maintain these invariants while implementing:

1. Parser syntax owners: recognize syntax only.
   Do not bury protocol meaning in parse-time shape handling unless syntax
   requires it.
2. Parser-event owners: preserve typed protocol events.
   This is the boundary between raw escape decoding and terminal actions.
3. Action owners: own protocol interpretation and state transitions.
   Mode toggles, reports, cursor movement, protection semantics, and similar
   rules belong here.
4. Host/render edges: stay explicit.
   Clipboard, title, notifications, hyperlinks, mouse output, and rendering
   side effects should remain visible at the boundary rather than leaking back
   into parser logic.
5. Minimality wins.
   Prefer extending an existing protocol path over adding one-off helpers or
   parallel state machines.
6. Ledger accuracy matters.
   If support is partial, keep the row partial. Do not collapse multiple wire
   surfaces into a vague success state.

## Current Matrix

| Family | Status | Notes |
| --- | --- | --- |
| Printable text + UTF-8 stream decode | supported | Parser emits ASCII slices and UTF-8 codepoints deterministically. |
| Basic C0 controls: `LF`, `CR`, `BS`, `HT` | supported | Mapped by `interpret/c0_actions.zig` and applied through grid mutation owners. |
| Additional common C0 controls: `BEL`, `ENQ`, `VT`, `FF`, `SI`, `SO`, `SP` | supported | `BEL` and default `ENQ` answerback are no-ops, `VT`/`FF` alias line feed, and `SI`/`SO` switch GL between the supported `G0`/`G1` charset set. |
| Rare C0 controls: `SUB`, `CAN` | unsupported | Not mapped into terminal action behavior today. |
| CSI cursor movement: `CUU`, `CUD`, `CUF`, `CUB`, `CNL`, `CPL`, `CHA`, `VPA`, `CUP`, `HVP` | supported | Covered in action-mapping and screen behavior tests. |
| CSI tab movement: `CHT`, `CBT` | supported | Uses mutable tab-stop state, defaulting to every 8 columns and honoring custom stops set/cleared by HTS/TBC. |
| Tab-stop management: `HTS`, `TBC`, `DECST8C`, custom stops | supported | `ESC H` sets a stop at the cursor, `CSI 0 g` clears current stop, `CSI 3 g` clears all stops, `CSI ? 5 W` restores default 8-column stops, and reset restores defaults. |
| CSI insert/delete/scroll region edits: `IL`, `DL`, `SU`, `SD`, `SL`, `SR`, `DECSTBM` | supported | Covered by regression tests, including horizontal shifts across the active scroll region. |
| Erase in display/line/chars: `ED`, `EL`, `ECH`, `DECSED`, `DECSEL` | partial | Standard `ED`/`EL` modes `0-3` and `ECH` are implemented, including `ED 3` scrollback erase. DEC selective erase now honors `DECSCA`-protected cells. Broader erase/query parity work remains. |
| Rectangular and column edits: `DECCRA`, `DECCARA`, `DECRARA`, `DECFRA`, `DECERA`, `DECSERA`, `DECIC`, `DECDC`, `DECSACE`, `DECRQCRA`, `XTCHECKSUM` | partial | Page-1 rectangular copy/fill/erase/selective-erase, column insert/delete, rectangular-or-stream attribute changes, and rectangular checksum replies are implemented with clipping and overlap-safe copy buffering. Checksum semantics are still conservative and broader rectangle/report surfaces remain pending. |
| Character protection: `DECSCA` | partial | Current-cell protection now gates selective erase behavior, but broader protected-cell interactions are not fully covered yet. |
| SGR text attributes | partial | Supports reset, bold, underline, blink, reverse, ANSI 16, 256-color, RGB fg/bg, underline color, and kitty underline styles. Missing much of extended xterm attribute surface. |
| DECSTR (`CSI ! p`) | supported | Mapped to `reset_screen`. |
| DEC private modes: `?6`, `?7`, `?25`, `?47`, `?69`, `?1047`, `?1049` | supported | Origin mode, wrap, cursor visibility, left/right margin mode, and alt-screen variants are implemented with DEC-mode query/save/restore coverage. |
| DEC private modes beyond that baseline | partial | High-impact focus/paste/mouse/app-cursor modes exist, and supported DEC modes now answer `DECRQM`. Broader mode families remain unsupported. |
| Locator protocols: `DECELR`, `DECEFR`, `DECSLE`, `DECRQLP` | partial | Locator reporting mode, filter rectangles, button-event selection, explicit locator requests, conservative `DECLRP` replies, and DEC locator status/type reports now work on the host-neutral mouse path. Pixel-perfect host integration and broader locator parity remain pending. |
| ANSI modes and mode reports: `SM`, `RM`, `DECRQM`, `DSR`, `DA`, `DA2`, `DA3`, `DECXCPR`, `DECRQDE`, `DECRQPSR` (`DECCIR`, `DECTABSR`), `DECREQTPARM`, `XTVERSION`, `XTTITLEPOS`, `XTREPORTCOLORS`, `XTREPORTSGR` | partial | `DSR`, `CPR`, `DA`, `DA2`, `DA3`, supported ANSI/DEC `DECRQM`, tracked ANSI `SM`/`RM` modes (`KAM`, `IRM`, `SRM`, `LNM`), displayed extent, cursor-information and tab-stop presentation-state reporting, VT100 terminal-parameter replies, fixed `XTVERSION` identity replies, conservative empty-stack `XTTITLEPOS` replies, conservative color-stack reporting, and conservative rectangle-common `XTREPORTSGR` replies now work. Full presentation-state and broader ANSI-mode families remain unsupported. |
| DCS report/resource queries: `DECRQSS`, `XTGETTCAP`, `XTGETXRES` | partial | `DECRQSS` replies for owned state and invalid requests. `XTGETTCAP` and `XTGETXRES` return explicit conservative invalid replies rather than silent ignore; no host-neutral resource values are exposed yet. |
| String-control transport: `OSC`, `DCS`, `APC`, `PM` | partial | OSC, DCS, APC, and PM payloads are buffered to terminators and emitted as typed parser events. Unknown APC and PM have no host-neutral action and are intentionally ignored after classification; feature-specific DCS payloads such as SIXEL, ReGIS, DECUDK, and DECRSPS remain separate protocol work. |
| Modern keyboard input: kitty keyboard, `modifyOtherKeys`, `XTFMTKEYS`, `XTQFMTKEYS`, focus and bracketed paste | partial | Kitty keyboard flags, stack/query behavior, focus reports, bracketed paste wrappers, modifyOtherKeys, and xterm key-format resources are implemented. `formatOtherKeys=1` changes ordinary-key modifyOtherKeys emission to CSI-u style. Broader platform-specific key resources remain out of host-neutral scope. |
| Visual metadata: underlines, pointer mode/shapes, notifications, multiple cursors | partial | Kitty underline SGR styles/colors, OSC 22 pointer-shape stacks/queries, OSC 9/99 notification request queueing, xterm `pointerMode`, and kitty multiple-cursor support/empty query/clear controls have host-neutral state or replies. Full extra-cursor placement/color storage and desktop/host UI effects remain open database work. |
| ESC single-byte control finals | partial | Parser events preserve ESC finals; DEC save/restore cursor (`ESC 7`/`ESC 8`) is implemented, broader ESC-final semantics remain unsupported. |
| VT52/Tektronix legacy controls | deferred | VT52 cursor/erase aliases and Tektronix plot controls are intentionally outside normal ANSI/VT100 core parity until explicit VT52/Tektronix mode ownership exists. |
| Charset designation: `ESC (`, `ESC )`, DEC Special Graphics select | partial | Parser tracks G0/G1 designation and DEC Special Graphics maps through visible cells. Broader charset families remain unsupported. |
| Shift in/out charset use: `SI`, `SO` | partial | G0/G1 GL switching is wired for the supported charset set, including DEC Special Graphics. |
| OSC transport | partial | Parser transports OSC with BEL/ST terminators and parser events now preserve typed OSC command/payload records, including command-only OSC forms such as kitty color stack push/pop. Action/host handling is still narrow. |
| OSC window title/icon title | partial | Parser-event handling recognizes title OSC selectors and `latestTitleSet()` exposes them, but no broader host callback surface exists yet. |
| OSC 8 hyperlinks | partial | OSC 8 drives stable `link_id` cell metadata, `VtCore` URI lookup, render surface propagation, and Linux-host `Ctrl+left click` opening behind explicit policy. Hover polish remains pending. |
| OSC 52 clipboard | partial | OSC 52 surfaces pending clipboard requests and Linux-host applies explicit allow/deny policy. Queries and broader selector behavior remain unsupported. |
| OSC color queries/setters (`4`, `10`, `11`, `12`, etc.) | partial | VT-core tracks terminal foreground/background/cursor colors and a 256-color palette. Xterm `OSC 4`, `10`, `11`, `12`, `104`, `110`, `111`, and `112` set/query/reset state. Render/host consumption and the broader xterm dynamic-color family remain pending. |
| DCS transport | partial | Parser events preserve DCS payloads now; action mapping and host integration are still narrow. |
| APC transport | partial | Parser events preserve APC payloads now; kitty graphics action mapping is partially implemented, but general APC host integration is still absent. |
| Kitty colored/styled underlines | supported | CSI subparameter separators are preserved; `SGR 4:0..5`, `58`, and `59` propagate through VT state and text-scene decoration rendering. |
| Kitty keyboard protocol | partial | Negotiation/query/push/pop for progressive flags is implemented with separate main/alternate stacks, and the current host non-text key surface emits Kitty CSI-u/functional forms when flags are active. Text-associated, alternate-key, repeat, and release reporting need richer host events. |
| Kitty graphics protocol | partial | APC `_G` command parsing exists for core control keys, `a=q` gets an immediate conservative unsupported reply, direct `t=d` base64 uploads are assembled/stored across chunks, image ids replace prior data, image numbers allocate terminal-owned ids, placements/animation frames are tracked as metadata, and delete selectors cover ids, placement ids, cell/row/column/z intersections, ranges, and frames. Pixel decoding and render plumbing remain unsupported. |
| Kitty shell integration marks | partial | OSC 133 prompt/command/output marks are parsed and latest mark metadata/status is retained host-neutrally. Prompt scrollback navigation and shell integration host behavior remain pending. |
| Kitty desktop notifications | partial | OSC 99 metadata/payload notifications are queued as host-neutral requests. Desktop display, activation/close callbacks, icon/button/sound handling, and alive polling remain pending. |
| Kitty pointer shapes | partial | OSC 22 set/push/pop/query is parsed with separate main/alternate pointer stacks and support/current replies. Applying the shape in host UI remains unverified. |
| Kitty OSC 21 color control | partial | `foreground`, `background`, `cursor`, `cursor_text`, selection colors, and `0..255` palette keys support set/query/reset in VT-core. Render/host consumption remains pending. |
| Kitty color stack | partial | OSC 30001/30101 now snapshot and restore VT-core terminal color state, including dynamic colors and the ANSI palette. Render/host consumption remains pending. |
| Bracketed paste mode (`?2004`) | supported | Mode tracking, host paste routing, and paste wrapper emission are wired through `howl-term` and Linux-host. |
| Focus in/out (`?1004`) | supported | Mode tracking, effective host focus routing, and focus report emission are wired through `howl-term` and Linux-host. |
| Mouse tracking (`9/1000/1002/1003/1005/1006/1015`) | supported | X10, normal, button-event, and any-event tracking modes are distinct; legacy, UTF-8 extended, SGR, and urxvt encodings cover press/release/wheel/motion gating with modifiers and DECRQM/save/restore coverage. Host runtime verification is still broader than unit coverage. |
| Application cursor / keypad modes | supported | `?1` application cursor mode changes arrow-key encoding. `ESC =`/`ESC >` and `?66` switch numeric keypad keys between normal characters and SS3 application keypad sequences, with DECRQM/save-restore coverage. |
| modifyOtherKeys / enhanced keyboard reporting | partial | XTMODKEYS/XTQMODKEYS support now tracks `modifyOtherKeys` resource `4`, emits xterm `CSI 27;modifier;code~` reports for printable keys in levels 2/3, and supports disable/query. Other modifier/format resources remain pending. |
| Function/navigation key encoding | partial | Basic xterm-style sequences exist, but not gated by negotiated modes and not extended past current key set. |
| Alt-screen enter/exit and primary scrollback preservation | supported | Explicit tests exist for `1049` save/restore behavior and full-dirty transitions. |
| Snapshot / replay determinism across chunking | supported | Unit/regression/fuzz coverage exists. |

## Slice Rules
Every protocol slice should land with:
1. parser coverage if new syntax is required
2. parser-event coverage
3. action-mapping coverage
4. screen/input/response behavior coverage
5. protocol fuzz seed or regression fixture when behavior is stateful
