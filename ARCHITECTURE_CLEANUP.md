# Architecture Rules

1. The directory tree must answer the first ownership question before a file is opened. Parser syntax goes in `src/parser/`; parser-event buffering goes in `src/interpret/parser_events.zig`; action meaning goes in `src/interpret/*_actions.zig`; grid mutation goes in `src/grid/`; host-facing consequences go in `src/vt_core/`; public facade behavior stays in `src/vt_core.zig` only when it is truly facade behavior.

2. Do not create dumping grounds. Avoid vague owners such as `utils`, `common`, `helpers`, or broad `protocol`. If a name cannot tell the next protocol author what belongs there, pick a stronger name or do not create the file.

3. Split by stable reason to change, not by line count alone. LOC is a warning signal, not the goal. A large cohesive boundary owner is better than several pass-through files with unclear ownership.

4. Keep parser syntax free of terminal meaning. `src/parser/` recognizes bytes, CSI shape, UTF-8, stream controls, and OSC/APC/DCS/PM string-control boundaries. It must not decide screen behavior, modes, reports, or host consequences.

5. Keep parser-event shaping explicit. `src/interpret/parser_events.zig` owns queued parser payloads and transport from parser callbacks into interpret. Do not hide raw payload policy in unrelated action or vt-core code.

6. Keep action mapping in owner-shaped files. C0, ESC, CSI, OSC, APC, DCS, kitty, and CSI subfamilies belong in their named `src/interpret/` owners. `src/interpret/actions.zig` is a router/converter, not a place for new protocol-family details.

7. Keep grid files about grid mutation only. `src/grid/state.zig` owns `GridModel` fields, lifecycle, resize orchestration, and wrapper surface. Cursor, write, erase, edit, scroll, history, tabs, margins, rect, style, dirty tracking, and apply dispatch stay in their named owners. Do not put protocol interpretation in grid.

8. Keep `VtCore` state grouped. `ScreenState`, `ModeState`, `HostState`, `KittyState`, and `EncodeScratch` are intentional local groups. New state must either fit one of those groups cleanly or earn a new named group with a clear lifecycle.

9. Keep `ScreenState` boring. It owns primary/alternate buffers, active-screen selection, alt-screen lifecycle, saved primary cursor, reset, resize, and deinit. It must not own CSI behavior, scrolling semantics, erase/edit behavior, reports, parser apply flow, or kitty graphics behavior.

10. Keep vt-core boundary helpers consequence-focused. `src/vt_core/reports.zig` owns replies and queries, `modes.zig` owns mode consequences, `kitty.zig` owns kitty-family consequences, and `host.zig` owns host-edge requests. If one grows unrelated reasons to change, split by boundary concern.

11. Keep input ownership separated. Key vocabulary stays in `input/keymap.zig`; mouse vocabulary stays in `input/mouse.zig`; mouse encoding stays in `input/mouse_encode.zig`; host token parsing stays in `input/tokens.zig`; `input/codec.zig` remains the stable facade and key encoding owner.

12. File headers are required for source units. Use short, strong declarations: `Responsibility`, `Ownership`, and `Reason`. They must describe why the file exists now, not its implementation mechanics.

13. Public symbols need intent comments when exported across a file boundary. Comments should be concise contracts, not restatements of names. Prefer no comment over a weak comment that repeats the symbol.

14. Tests must keep owner-shaped filters. Use prefixes such as `parser:`, `actions:`, `screen:`, `replay:`, and vt-core surface names. Broad regression files may remain as safety nets, but protocol ledger rows should point at focused filters.

15. The protocol ledger must stay executable. `protocol_coverage.db` is the source of truth. `unit_test_filters` must use current test names. Notes must use current owner names. Do not leave translation work for the next protocol sprint.

16. `protocol_matrix.md` and `PROTOCOL_COVERAGE_SPRINTS.md` must describe the current owner flow. Protocol work starts from syntax owner, then parser-event owner, then action owner, then grid/vt-core/input consequence owner, then ledger update.

17. Every protocol slice must define behavior before editing. Decide parser acceptance, parser event shape, action meaning, state mutation, host/render observation, and test filters before widening behavior.

18. Implement the smallest complete change. Preserve behavior unless the slice explicitly changes it with tests. Do not add compatibility paths without a concrete persisted data, shipped behavior, external consumer, or explicit requirement.

19. Verification for normal iterations is focused tests plus `zig build test`. `zig build test` runs unit tests. `zig build test:regression` and `zig build fuzz` are separate and should be used deliberately, not on every iteration.

20. Architecture cleanup stays done only while these rules stay true. If a new change makes ownership unclear, stop and fix the owner boundary before adding more protocol surface.
