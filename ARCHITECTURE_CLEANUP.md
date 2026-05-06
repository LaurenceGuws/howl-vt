# Architecture Cleanup

Use this as the execution tracker for the architecture pass before protocol completion resumes.

## Program

| # | Issue | Goal | Next concrete steps |
| --- | --- | --- | --- |
| 1 | Root dispatch split | `root.zig` orchestrates instead of owning every protocol consequence. | Extract report/query dispatch first, then mode/state, then kitty/host helpers. |
| 2 | Action model split | Stop mixing grid mutations with host/protocol actions in one mega-union. | Define separate screen, protocol, and host action families behind the semantic boundary. |
| 3 | String transport path | Make `DCS`, `APC`, and `PM` first-class typed protocol paths. | Add typed transport records, conservative replies, and dedicated dispatchers. |
| 4 | State ownership cleanup | Make protocol state ownership explicit and stable. | Write ownership table, then move misplaced state into the correct owner. |
| 5 | Grid file split | Keep one `GridModel`, but split implementation by concern. | Separate cursor/write, erase/edit, scroll/history, tabs/margins, and rect ops. |
| 6 | ESC/mode model | Remove ambiguous `ESC` handling assumptions. | Add explicit mode boundaries before broadening the remaining `ESC` backlog. |
| 7 | Ledger normalization | Make sprint accounting match real implementation work. | Collapse duplicate behavior rows, keep aliases explicit, and align filters to code owners. |
| 8 | Pipeline consequence extension | Preserve deterministic queue/apply flow while supporting non-grid effects cleanly. | Add structured non-screen consequence handling parallel to grid application. |

## Active Now

1. String transport path
   - Complete string framing coverage across `APC`, `DCS`, and `PM`.
   - `PM` transport is now explicit in parser/bridge/fuzz paths.
   - `DCS DECRQSS` now has a typed consequence path with conservative replies.
   - Next: broaden typed `DCS` coverage and stop treating non-kitty `APC` as raw drop-only transport.
   - Keep behavior deterministic.
   - Prove with `zig build test`.
