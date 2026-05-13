# Howl VT Terminal Scrollback Fuzz Plan

## Goal
Prove that `resize + scroll(viewport) + zoom` cannot silently corrupt scrollback state.

This fuzz suite treats scrollback as source-of-truth and viewport as projection.

## Non-Negotiable Invariants
1. **No silent mutation**: logical content is preserved across operations except explicit prune due to bounded history capacity.
2. **Deterministic state**: same seed and operation stream always yields identical final hash.
3. **Projection integrity**: viewport rows always map to a valid slice of `history + live rows`.
4. **Cursor validity**: cursor row/col and wrap state remain representable for current dimensions.
5. **Offset validity**: scrollback offset is always clamped to current history count.

## Allowed Mutations
Only these are allowed to change logical content:
- bounded history prune when capacity is exceeded,
- explicit clear/erase semantics (when those operations are present in test input).

Everything else (`resize`, `scroll`, `zoom`) must preserve content modulo prune.

## Fuzz Inputs
### Initial state generator
Generate pathological screen/history states to break assumptions:
- exact-wrap boundary rows,
- long wrapped logical lines,
- sparse rows with trailing blanks,
- alternating short/long lines,
- cursor at edges with `wrap_pending` true/false,
- varied history fill levels (empty, partial, near-capacity, full).

### Operation stream (5s blast)
Run high-frequency randomized operations for a fixed wall time per seed:
- `resize(rows, cols)`
- `setScrollbackOffset(offset)`
- `followLiveBottom()`
- `zoom_in` / `zoom_out` / `zoom_jitter`

## Zoom Model
Zoom is mandatory in this suite.

At terminal level, zoom is modeled as deterministic grid-density transitions that induce aggressive resize churn:
- width-dominant shrink/grow cycles,
- height-dominant shrink/grow cycles,
- oscillating in/out sequences,
- tiny-to-large and large-to-tiny bursts.

This directly targets user-observed failures under rapid interactive resize.

## Hashing Strategy
Compute two hashes after each operation and at end-of-run:
1. **Structural hash**
   - rows, cols, history_count, history_capacity,
   - scrollback offset,
   - cursor row/col/wrap,
   - row-wrap metadata,
   - history-wrap metadata.
2. **Logical-content hash**
   - flattened logical stream reconstructed from history + visible rows + wrap metadata.

## Oracle Strategy
Use differential checking against a slow reference model:
- reference model stores logical lines directly,
- applies same operation stream,
- applies same prune rules,
- compares final and step-wise hashes where applicable.

If full reference parity is initially too expensive, start with metamorphic checks:
- round-trip `A -> B -> A` preserves logical content modulo prune,
- repeated oscillation does not increase unexplained loss,
- deterministic replay from seed is exact.

## Failure Reporting
On failure, always emit:
- RNG seed,
- operation count,
- minimal failing suffix (after shrink/minimization pass),
- pre/post structural and logical hashes,
- first divergence summary (row/col/logical-line index).

## Sprint Scope (Current)
1. Implement invariant helpers and hash utilities.
2. Implement seeded fuzz driver with 5s runtime per seed.
3. Implement zoom-churn operation family.
4. Add at least one differential/reference check path.
5. Add CI-friendly deterministic mode (fixed seeds, op-count cap).

## Next Scope (After This Pass)
Add simulated transport pressure while preserving same invariants:
- medium-size PTY-like output bursts,
- interleaved user input and output events,
- continued resize/scroll/zoom churn.

The same no-silent-mutation contract remains the gate.
