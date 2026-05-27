const snapshot_regression = @import("test/snapshot_regression.zig");

// Proof statement: this root runs VT snapshot regression proofs only.

test {
    _ = snapshot_regression;
}
