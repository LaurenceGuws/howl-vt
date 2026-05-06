# Protocol Coverage Sprints

Execute these in order. Do not mix sprints.

## Sprint 1: Core VT parity
- Finish remaining practical `C0`, `ESC`, and core `CSI` behavior.
- Prioritize normal TUI correctness over obscure legacy features.
- Status: baseline/common-app gaps are closed or reclassified. Remaining open `C0`/`ESC`/`CSI` rows are legacy, VT52/Tektronix, modern-input, visual/heavy, host-resource, or unclassified follow-up work.

## Sprint 2: Reports and queries
- Finish `DA`/`DSR`/`DECRQM`/`DECRQPSR`/`DECRQSS`-style replies.
- Prefer explicit conservative replies over silent ignore.
- Status: baseline/common/high report-query gaps are closed. DCS `DECRQSS`, `XTGETTCAP`, and `XTGETXRES` now have explicit replies; unsupported resource values reply conservatively instead of silently disappearing.

## Sprint 3: String protocol foundations
- Finish `DCS`, `APC`, and `PM` transport and typed parser events.
- Keep syntax in `parser/`, typed event shaping in `interpret/parser_events.zig`, meaning in `interpret/*_actions.zig`, and consequences in `vt_core/` owners.
- Status: transport foundations are closed. APC, DCS, and PM are buffered to terminators and emitted as typed parser events; PM and unknown APC are intentionally ignored at action mapping. Remaining DCS rows are feature protocols for later graphics/legacy work, not transport-foundation gaps.

## Sprint 4: Modern input
- Finish kitty keyboard and xterm keyboard-reporting gaps.
- Close remaining negotiated mode and emitted-sequence gaps.

## Sprint 5: Visual metadata protocols
- Finish underlines, pointer shapes, shell marks, notifications, and multiple cursors.
- Expose clean host-neutral state first.

## Sprint 6: Heavy protocols
- Finish kitty graphics.
- Decide explicitly whether file transfer and other large surfaces are in or deferred.

## Sprint 7: Host verification
- Close `host_tested=0` rows for already implemented features.
- Verify runtime behavior across host edges, not just unit coverage.

## Done rule for every sprint
1. Pick one coherent slice from `protocol_gaps`.
2. Define behavior before editing.
3. Add focused tests.
4. Implement the smallest complete change.
5. Run focused tests, then `zig build test`.
6. Update `protocols` metadata only after code and tests land.
