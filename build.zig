//! Builds the native Howl VT model, tests, simulations, and benchmarks.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const internal_mod = b.addModule("howl_vt", .{
        .root_source_file = b.path("src/howl_vt.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const unit_test_mod = b.createModule(.{
        .root_source_file = b.path("test_unit.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const mod_tests = add_test_artifact(b, "test-unit", unit_test_mod);
    const run_mod_tests = add_test_run_artifact(b, mod_tests);

    const check_step = b.step("check", "Build the native VT model");
    const test_step = b.step("test", "Run native VT correctness proofs");
    const test_unit_step = b.step("test:unit", "Run unit tests");
    const test_unit_build_step = b.step("test:unit:build", "Build unit tests");
    test_unit_build_step.dependOn(&mod_tests.step);
    test_unit_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(test_unit_step);
    check_step.dependOn(&mod_tests.step);

    const simulation_module = b.createModule(.{
        .root_source_file = b.path("simulation/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    simulation_module.addImport("howl_vt", internal_mod);

    const simulation_exe = b.addExecutable(.{
        .name = "howl_vt_simulate",
        .root_module = simulation_module,
    });
    simulation_exe.use_llvm = true;
    const simulation_step = b.step("simulate", "Run VT protocol and scrollback simulations");
    const simulation_build_step = b.step("simulate:build", "Build VT protocol and scrollback simulations");
    simulation_build_step.dependOn(&simulation_exe.step);
    const run_simulation = b.addRunArtifact(simulation_exe);
    if (b.args) |args| run_simulation.addArgs(args);
    simulation_step.dependOn(&run_simulation.step);

    const baseline_mod = b.createModule(.{
        .root_source_file = b.path("benchmark_m7_baseline.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });
    const baseline_exe = b.addExecutable(.{
        .name = "m7_baseline",
        .root_module = baseline_mod,
    });
    const run_baseline = b.addRunArtifact(baseline_exe);
    if (b.args) |args| run_baseline.addArgs(args);
    const baseline_build_step = b.step("benchmark:m7_baseline:build", "Build the m7_baseline VT benchmark");
    const baseline_step = b.step("benchmark:m7_baseline", "Run the m7_baseline VT benchmark");
    baseline_build_step.dependOn(&baseline_exe.step);
    baseline_step.dependOn(&run_baseline.step);
}

fn add_test_artifact(b: *std.Build, name: []const u8, root_module: *std.Build.Module) *std.Build.Step.Compile {
    const tests = b.addTest(.{
        .name = name,
        .root_module = root_module,
        .filters = b.args orelse &.{},
    });
    tests.use_llvm = true;
    return tests;
}

fn add_test_run_artifact(b: *std.Build, tests: *std.Build.Step.Compile) *std.Build.Step.Run {
    const run_tests = b.addRunArtifact(tests);
    if (b.args != null) {
        run_tests.has_side_effects = true;
    }
    return run_tests;
}
