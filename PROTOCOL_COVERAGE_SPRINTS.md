# Protocol Coverage Sprints

Execute these in order. Do not mix sprints. A sprint is not complete until every matching `protocol_coverage.db` row has real implemented behavior and unit coverage; documenting a deferral does not close a row.

## Sprint 1: Core VT parity
- Finish remaining practical `C0`, `ESC`, and core `CSI` behavior.
- Prioritize normal TUI correctness over obscure legacy features.
- Status: partial. Previously prioritized baseline/common-app rows were handled, but lower-priority and unclassified `C0`/`ESC`/`CSI` rows remain open in the database.

## Sprint 2: Reports and queries
- Finish `DA`/`DSR`/`DECRQM`/`DECRQPSR`/`DECRQSS`-style replies.
- Prefer explicit conservative replies over silent ignore.
- Status: partial. `DECRQSS`, `XTGETTCAP`, and `XTGETXRES` now have explicit replies, but the sprint remains open until all report/query database rows are implemented and tested.

## Sprint 3: String protocol foundations
- Finish `DCS`, `APC`, and `PM` transport and typed parser events.
- Keep syntax in `parser/`, typed event shaping in `interpret/parser_events.zig`, meaning in `interpret/*_actions.zig`, and consequences in `vt_core/` owners.
- Status: partial. APC, DCS, and PM are buffered to terminators and emitted as typed parser events, but feature-specific DCS/APC/PM database rows remain open until implemented and tested.

## Sprint 4: Modern input
- Finish kitty keyboard and xterm keyboard-reporting gaps.
- Close remaining negotiated mode and emitted-sequence gaps.
- Status: partial. Kitty keyboard, modifyOtherKeys, focus/paste gates, and xterm key-format set/reset/query are implemented and unit tested, but remaining modern input database rows stay open until implemented and tested.

## Sprint 5: Visual metadata protocols
- Finish underlines, pointer shapes, shell marks, notifications, and multiple cursors.
- Expose clean host-neutral state first.
- Status: partial. Underline SGR variants, pointer shape/hyperlink interaction rows, notification rows, xterm pointer mode, and multiple-cursor query/clear rows have concrete behavior and tests; remaining visual metadata rows stay open until implemented and tested.

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
