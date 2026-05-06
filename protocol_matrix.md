# Protocol Matrix

## Goal
Drive `howl-vt-core` toward explicit xterm baseline parity and staged kitty protocol adoption.

`protocol_coverage.db` is the source of truth for protocol maturity work in this repo.
This file is a human summary of that ledger.

The SQLite ledger is generated from `src/fuzz/assets/xterm-ctlseqs.ms` and records one row per parsed control-sequence entry, including separate `planned`, `implemented`, `test_verified`, and `host_verified` flags. Its `metadata` table records the `howl-vt-core` commit used when reviewing support flags.

Example query:
```sh
sqlite3 protocol_coverage.db \
  "SELECT id, sequence FROM protocol_entries WHERE planned = 1 AND test_verified = 0;"
```

## Status
- `supported`: parser, semantic mapping, and grid/input behavior exist with tests.
- `partial`: some layers exist, but behavior is incomplete, dropped, or mode-insensitive.
- `unsupported`: no meaningful handling yet.
- `deferred`: intentionally not in the current tranche.

## Corpus
- Vendored xterm reference: `src/fuzz/assets/xterm-ctlseqs.ms`
- Current deterministic fuzzers:
  - `src/fuzz/scrollback.zig`
  - `src/fuzz/protocol.zig`

## Current Matrix

| Family | Status | Notes |
| --- | --- | --- |
| Printable text + UTF-8 stream decode | supported | Parser emits ASCII slices and UTF-8 codepoints deterministically. |
| Basic C0 controls: `LF`, `CR`, `BS`, `HT` | supported | Mapped in `interpret/semantic.zig` and applied in `grid/model.zig`. |
| Remaining common C0 controls: `BEL`, `VT`, `FF`, `SO`, `SI`, `SUB`, `CAN` | unsupported | Not mapped into semantic behavior today. |
| CSI cursor movement: `CUU`, `CUD`, `CUF`, `CUB`, `CNL`, `CPL`, `CHA`, `VPA`, `CUP`, `HVP` | supported | Covered in semantic and screen behavior tests. |
| CSI tab movement: `CHT`, `CBT` | supported | Uses mutable tab-stop state, defaulting to every 8 columns and honoring custom stops set/cleared by HTS/TBC. |
| Tab-stop management: `HTS`, `TBC`, custom stops | supported | `ESC H` sets a stop at the cursor, `CSI 0 g` clears current stop, `CSI 3 g` clears all stops, and reset restores default 8-column stops. |
| CSI insert/delete/scroll region edits: `IL`, `DL`, `SU`, `SD`, `DECSTBM` | supported | Recent tranche; covered by regression tests. |
| Erase in display/line: `ED`, `EL`, `DECSED`, `DECSEL` | partial | Standard `ED`/`EL` modes `0-3` are implemented, including `ED 3` scrollback erase. DEC selective erase now honors `DECSCA`-protected cells. Broader erase/query parity work remains. |
| Rectangular and column edits: `DECCRA`, `DECCARA`, `DECRARA`, `DECFRA`, `DECERA`, `DECSERA`, `DECIC`, `DECDC`, `DECSACE`, `DECRQCRA`, `XTCHECKSUM` | partial | Page-1 rectangular copy/fill/erase/selective-erase, column insert/delete, rectangular-or-stream attribute changes, and rectangular checksum replies are implemented with clipping and overlap-safe copy buffering. Checksum semantics are still conservative and broader rectangle/report surfaces remain pending. |
| Character protection: `DECSCA` | partial | Current-cell protection now gates selective erase behavior, but broader protected-cell interactions are not fully covered yet. |
| SGR text attributes | partial | Supports reset, bold, underline, blink, reverse, ANSI 16, 256-color, RGB fg/bg, underline color, and kitty underline styles. Missing much of extended xterm attribute surface. |
| DECSTR (`CSI ! p`) | supported | Mapped to `reset_screen`. |
| DEC private modes: `?6`, `?7`, `?25`, `?47`, `?69`, `?1047`, `?1049` | supported | Origin mode, wrap, cursor visibility, left/right margin mode, and alt-screen variants are implemented with DEC-mode query/save/restore coverage. |
| DEC private modes beyond that baseline | partial | High-impact focus/paste/mouse/app-cursor modes exist, and supported DEC modes now answer `DECRQM`. Broader mode families remain unsupported. |
| Locator protocols: `DECELR`, `DECEFR`, `DECSLE`, `DECRQLP` | partial | Locator reporting mode, filter rectangles, button-event selection, explicit locator requests, and conservative `DECLRP` replies are implemented on the host-neutral mouse path. Pixel-perfect host integration and the broader locator/status family remain pending. |
| ANSI modes and mode reports: `SM`, `RM`, `DECRQM`, `DSR`, `DA`, `DA2`, `DA3`, `DECXCPR`, `DECRQDE`, `DECRQPSR` (`DECCIR`, `DECTABSR`), `DECREQTPARM`, `XTREPORTCOLORS` | partial | `DSR`, `CPR`, `DA`, `DA2`, `DA3`, supported ANSI/DEC `DECRQM`, tracked ANSI `SM`/`RM` modes (`KAM`, `IRM`, `SRM`, `LNM`), displayed extent, cursor-information and tab-stop presentation-state reporting, VT100 terminal-parameter replies, and conservative color-stack reporting now work. Full presentation-state and broader ANSI-mode families remain unsupported. |
| ESC single-byte control finals | partial | Parser and bridge preserve ESC finals; DEC save/restore cursor (`ESC 7`/`ESC 8`) is implemented, broader ESC-final semantics remain unsupported. |
| Charset designation: `ESC (`, `ESC )`, DEC Special Graphics select | partial | Parser tracks G0/G1 designation and DEC Special Graphics maps through visible cells. Broader charset families remain unsupported. |
| Shift in/out charset use: `SI`, `SO` | partial | G0/G1 GL switching is wired for the supported charset set, including DEC Special Graphics. |
| OSC transport | partial | Parser transports OSC with BEL/ST terminators and bridge now preserves typed OSC command/payload records, including command-only OSC forms such as kitty color stack push/pop. Semantic/host handling is still narrow. |
| OSC window title/icon title | partial | Bridge recognizes title OSC selectors and `latestTitleSet()` exposes them, but no broader host callback surface exists yet. |
| OSC 8 hyperlinks | partial | OSC 8 drives stable `link_id` cell metadata, `VtCore` URI lookup, render surface propagation, and Linux-host `Ctrl+left click` opening behind explicit policy. Hover polish remains pending. |
| OSC 52 clipboard | partial | OSC 52 surfaces pending clipboard requests and Linux-host applies explicit allow/deny policy. Queries and broader selector behavior remain unsupported. |
| OSC color queries/setters (`4`, `10`, `11`, `12`, etc.) | partial | VT-core tracks terminal foreground/background/cursor colors and a 256-color palette. Xterm `OSC 4`, `10`, `11`, `12`, `104`, `110`, `111`, and `112` set/query/reset state. Render/host consumption and the broader xterm dynamic-color family remain pending. |
| DCS transport | partial | Parser and bridge preserve DCS payloads now; semantics and host integration are still absent. |
| APC transport | partial | Parser and bridge preserve APC payloads now; kitty graphics semantics are partially implemented, but general APC host integration is still absent. |
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

## Layer Notes

### Parser Stronger Than Semantics
- `src/parser/parser.zig` already understands CSI payloads with leaders/intermediates.
- It also transports OSC, APC, DCS, ESC finals, and charset designation state.
- Several gaps are not parser gaps anymore; they are bridge/semantic/host-response gaps.

### Bridge Is Still A Key Boundary
- `src/interpret/bridge.zig` now preserves:
  - typed OSC payloads
  - APC payloads
  - DCS payloads
  - ESC finals
- Remaining gaps are now mostly in semantic interpretation and host/render policy, not raw bridge transport.

### Response Path Exists, But Is Incomplete
- `vt-core` now owns a host-output queue for:
  - DSR/CPR replies
  - DA/DA2 replies
  - supported DEC-mode `DECRQM` replies
  - negotiated focus/paste wrappers
  - negotiated mouse output
- Remaining gaps are broader OSC query replies, richer keyboard negotiation, and more legacy/extended mouse encodings.

## First Tranche

### Tranche 1A: xterm compatibility core
Completed:
1. Explicit non-title OSC event typing in the bridge.
2. Semantic/host-facing support for device and status reports.
3. High-impact DECSET/DECRST modes:
   - focus
   - bracketed paste
   - app cursor
   - initial mouse tracking entry points
4. xterm-correct `ED 3` scrollback erase semantics.
5. DEC mode query replies for supported tracked modes.

### Tranche 1B: modern host interaction
Completed:
1. Mouse reporting encoder path for SGR (`1006`).
2. Mode-aware arrow-key encoding for application cursor mode.
3. OSC 8 hyperlink handling.
4. OSC 52 clipboard handling with explicit host-facing pending request surface.

Next:
1. Legacy and extended mouse protocol families beyond current SGR path.
2. Richer keyboard negotiation and keypad mode support.
3. Broader DEC private mode families and remaining xterm query/setter surfaces.

## Slice Rules
Every protocol slice should land with:
1. parser coverage if new syntax is required
2. bridge event coverage
3. semantic mapping coverage
4. screen/input/response behavior coverage
5. protocol fuzz seed or regression fixture when behavior is stateful
