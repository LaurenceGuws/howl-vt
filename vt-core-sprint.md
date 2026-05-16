# Howl VT Core Sprint

Shared rules: [`../AGENTS.md`](../AGENTS.md), [`../WORKFLOW.md`](../WORKFLOW.md),
[`../design/style-law.md`](../design/style-law.md),
[`../design/reference-index.md`](../design/reference-index.md)

## Purpose

This sprint cleans `howl-vt` internal ownership before any further ABI storytelling.

Bias:

- TigerBeetle for owner truth, simplicity, bounds, and hygiene
- Ghostty for VT-core split and protocol naming
- Alacritty for render/display ownership boundaries

This sprint is about internal truth first, not final ABI shape.

## Non-Negotiable Truths

These are the source of truth for the sprint. The road may change. These do not.

1. `howl-vt/src/` must end as an export and ABI layer, not as a state-owner layer.
2. `howl-vt/src/terminal.zig` must not survive as a real owner. It may exist only as a temporary migration shell, and sprint closure deletes it.
3. `interpret` is not a valid long-term owner name. It is a phase name, and phase names are hiding ownership.
4. VT core must separate four concerns explicitly: syntax parsing, protocol-family decoding, terminal action vocabulary, and owned state application.
5. Parser code must recognize bytes and sequence syntax only. It must not own terminal meaning.
6. Protocol-family code must be named plainly by family, especially xterm, kitty, and iterm when present. Generic mixed buckets are not acceptable.
7. Screen and host consequences must not be mixed in one owner path.
8. Render-facing visible truth must come from VT-owned screen state, not from host reconstruction.
9. Root docs and code must stop presenting `Terminal` and `Interpret` as acceptable enduring owners once this sprint closes.
10. ABI shape is not allowed to get ahead of owner truth. If ownership is unclear, ABI design stays open.

## Research Outcome

The initial theory held directionally, but not perfectly.

What held:

- `terminal.zig` is the biggest owner lie
- `interpret` is the wrong organizing idea
- owner nouns are required
- VT truth must be cleaned before ABI freezing

What changed after reading:

- the split is not merely `parser -> interpret -> screen/host`
- Ghostty shows a sharper model:
  - parser
  - protocol-family domains
  - terminal action vocabulary
  - owned state application
- `howl-vt` already has pieces of an action vocabulary in `interpret/event.zig`, but they are buried in the wrong bucket and dispatched through the wrong owner story

## Current Offenders

### `src/terminal.zig`

Current owner violations:

- owns lifecycle
- owns parser feed/apply loop
- owns screen-set state
- owns host consequence queues
- owns visible view construction
- owns input encoding
- owns snapshot export
- owns final semantic dispatch policy

This file is the main blocker because it centralizes too much truth under one product noun.

### `src/interpret.zig`

Current owner violations:

- phase-name umbrella
- re-exports event, queue, mapping, and host-application behavior
- hides the real split between protocol meaning and owned consequences

### `src/interpret/event.zig`

Current owner violations:

- giant mixed semantic union
- carries screen, mode, report, kitty, and host consequences together
- acts like the action seam, but lives in a bucket that lies about what it is

### `src/parser.zig`

Cleaner than `terminal.zig`, but still too broad for the target shape:

- parser state
- charset designation tracking
- string-control buffering
- sink contract

This is not catastrophic, but it is not yet Ghostty-clean.

### `design.md`

Current design facts are now too permissive:

- treats `Terminal` as an acceptable enduring facade owner
- treats `Interpret` as a first-class owner
- does not describe the parser/protocol/action/state split now indicated by research

## Target Model

The target is smaller than Ghostty, but conceptually similar where ownership is real.

### Root `src/`

Allowed long-term root files:

- `howl_vt.zig`
- `ffi.zig`
- `libhowl_vt.zig`
- possibly other pure export or ABI files only

Disallowed long-term root files:

- root state owners
- root mutation owners
- root phase buckets
- root umbrella product files

### Target Owner Groups

- `parser/`
  - byte stream parsing
  - raw sequence syntax
  - bounded string-control transport
- `action/` or `stream/`
  - explicit terminal action vocabulary
  - the seam between protocol decoding and state application
- `xterm/`
  - ANSI, CSI, OSC, DCS, APC, DEC baseline meaning
- `kitty/`
  - kitty-specific decoding and owned state
- `iterm/`
  - iTerm-specific decoding and owned state when present
- `screen/`
  - screen-set ownership
  - alt/main switching
  - visible view contract
  - viewport-visible truth
- `grid/`
  - cells, history, dirty, margins, tabs, erase, scroll, write
- `host/`
  - pending output
  - clipboard
  - title/report side effects
  - locator and other host-neutral outbound consequences
- `input/`
  - key, mouse, paste, and focus encoding only
- `selection/`
  - selection owner only

## Naming Rules For This Sprint

Prefer:

- owner nouns
- protocol-family nouns
- state nouns
- contract nouns

Reject:

- `interpret`
- `process`
- `manager`
- `helper`
- `util`
- any new umbrella noun that merely replaces `Terminal`

## Sprint Scope

### In Scope

- internal owner map cleanup
- protocol taxonomy cleanup
- root export-layer cleanup
- design-doc truth update
- migration toward parser/protocol/action/state separation

### Out Of Scope

- final public ABI freeze
- render seam closure
- host UX policy work
- protocol completeness expansion for its own sake
- copying Ghostty file-for-file without owner justification

## Checkpoints

### Checkpoint 1

Theme: truth map.

Must do:

- inventory every responsibility currently living in `src/terminal.zig`
- assign each responsibility to a real owner group
- identify mixed seams that block clean movement
- rewrite sprint/design docs to describe the new target honestly

Close signal:

- doc truth is accepted
- no file moves required yet

### Checkpoint 2

Theme: action seam.

Must do:

- name and isolate the explicit terminal action vocabulary
- stop calling that seam `interpret`
- define which actions belong to screen, host, mode, report, kitty, and protocol families

Close signal:

- the action seam is explicit in names and docs
- current mixed event/action buckets are reduced or clearly scheduled for deletion

### Checkpoint 3

Theme: protocol-family cut.

Must do:

- pull baseline xterm-family meaning out of the `interpret` bucket
- keep kitty explicit
- create iterm ownership only where real behavior exists or is imminent
- stop mixing protocol-family meaning under generic action-mapping names

Close signal:

- family naming is explicit
- generic protocol buckets shrink materially

### Checkpoint 4

Theme: screen and host truth.

Must do:

- move visible-view and screen-set truth toward `screen/`
- move pending output and host consequences toward `host/`
- stop letting one owner file carry both screen truth and host truth

Close signal:

- screen and host seams are explicit
- visible-state export truth is VT-owned and clearly named

### Checkpoint 5

Theme: root cleanup.

Must do:

- reduce root `src/` to export and ABI files only
- delete `interpret` as an organizing concept
- delete `terminal.zig`
- update `howl_vt.zig` to curated exports only

Close signal:

- root `src/` stop criteria is met

## First Cut Guidance

Do not start with broad file churn.

Prefer this order:

1. lock doc truth
2. isolate the action seam
3. separate protocol-family meaning
4. separate screen and host owners
5. collapse root `src/` to exports only

This order avoids smearing today’s confusion across more folders.

## Ghostty Takeaways To Copy

- root export shape
- explicit protocol-family names
- explicit parser owner
- explicit screen owner
- explicit action vocabulary seam

## Ghostty Takeaways Not To Copy Blindly

- giant `Terminal.zig` as an enduring owner
- exact file count
- broader app/runtime needs that Howl does not have

Howl should copy the split, not the weight.

## Design Rules For Decisions

When a move is unclear, answer these questions in order:

1. who owns the invariant?
2. who mutates the state?
3. is this syntax, meaning, action vocabulary, or application?
4. is the current name an owner name or a phase name?
5. if ABI callers saw this today, would it freeze a lie?

If any answer is unclear, stop and mark `work-not-clear`.

## Proof Gates

Each checkpoint must close with:

- docs updated with the same checkpoint
- `zig build test` in `howl-vt`
- `git diff --check`
- `nu "./style.nu" --touched-files --json`
- `nu "./style.nu" --failures --json`

When a checkpoint moves ABI-observable behavior:

- `zig build` in `howl-linux-host`

## Review Fails

A checkpoint fails if it:

- preserves `interpret` as a long-term concept
- preserves `terminal.zig` because deleting it feels like too much churn
- moves code into folders without clarifying ownership
- invents ABI shape while owner truth is still open
- mixes protocol-family meaning with screen or host mutation
- mixes screen-visible truth with host consequence queues
- leaves root `src/` owning live state or behavior

## Closure

This sprint closes when all of the following are true:

- the numbered non-negotiable truths are satisfied
- `design.md` matches the new owner story
- `src/` is export/ABI layer only
- `terminal.zig` is deleted
- `interpret` is deleted as an organizing concept
- parser/protocol/action/state separation is visible in the tree and in names
