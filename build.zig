// This repo ships a C ABI first until further notice.
// Keep build entrypoints aligned around the shipped header and exported symbols, not privileged Zig imports.
// Repo-local Zig roots may exist for tests and proofs, but they are not an embedder-facing contract.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module_options = b.addOptions();
    module_options.addOption(bool, "c_abi", false);
    module_options.addOption(bool, "howl_vt", true);
    const ffi_options = b.addOptions();
    ffi_options.addOption(bool, "c_abi", true);
    ffi_options.addOption(bool, "howl_vt", true);
    const internal_mod = b.createModule(.{
        .root_source_file = b.path("src/howl_vt.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    internal_mod.addOptions("vt_options", module_options);
    const fuzz_scrollback_mod = b.createModule(.{
        .root_source_file = b.path("src/fuzz/scrollback.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mod_tests = b.addTest(.{
        .name = "test-unit",
        .root_module = internal_mod,
        .filters = b.args orelse &.{},
    });
    mod_tests.use_llvm = true;
    const run_mod_tests = b.addRunArtifact(mod_tests);
    if (b.args != null) {
        run_mod_tests.has_side_effects = true;
    }

    const test_step = b.step("test", "Run all tests");
    const test_unit_step = b.step("test:unit", "Run unit tests");
    const test_unit_build_step = b.step("test:unit:build", "Build unit tests");
    test_unit_build_step.dependOn(&b.addInstallArtifact(mod_tests, .{}).step);
    test_unit_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(test_unit_step);

    const ffi_mod = b.createModule(.{
        .root_source_file = b.path("src/libhowl_vt.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    ffi_mod.addOptions("vt_options", ffi_options);
    const ffi_lib = b.addLibrary(.{
        .name = "howl_vt",
        .linkage = .dynamic,
        .root_module = ffi_mod,
    });
    const ffi_build_step = b.step("ffi:build", "Build the howl-vt C FFI library");
    ffi_build_step.dependOn(&b.addInstallArtifact(ffi_lib, .{}).step);
    b.installArtifact(ffi_lib);
    b.installFile("include/howl_vt.h", "include/howl_vt.h");

    const regression_mod = b.createModule(.{
        .root_source_file = b.path("src/test/scrollback_regression.zig"),
        .target = target,
        .optimize = optimize,
    });
    regression_mod.addImport("fuzz_scrollback", fuzz_scrollback_mod);

    const regression_tests = b.addTest(.{
        .name = "test-regression",
        .root_module = regression_mod,
        .filters = b.args orelse &.{},
    });
    regression_tests.use_llvm = true;
    const run_regression_tests = b.addRunArtifact(regression_tests);
    if (b.args != null) {
        run_regression_tests.has_side_effects = true;
    }

    const test_regression_step = b.step("test:regression", "Run slow regression tests");
    const test_regression_build_step = b.step("test:regression:build", "Build slow regression tests");
    test_regression_build_step.dependOn(&b.addInstallArtifact(regression_tests, .{}).step);
    test_regression_step.dependOn(&run_regression_tests.step);

    const fuzz_module = b.createModule(.{
        .root_source_file = b.path("src/fuzz/fuzz_tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const fuzz_exe = b.addExecutable(.{
        .name = "howl_vt_fuzz",
        .root_module = fuzz_module,
    });
    const fuzz_step = b.step("fuzz", "Run fuzzers");
    const fuzz_build_step = b.step("fuzz:build", "Build fuzzers");
    fuzz_build_step.dependOn(&b.addInstallArtifact(fuzz_exe, .{}).step);
    const run_fuzz = b.addRunArtifact(fuzz_exe);
    if (b.args) |args| run_fuzz.addArgs(args);
    fuzz_step.dependOn(&run_fuzz.step);

    const baseline_mod = b.createModule(.{
        .root_source_file = b.path("src/test/terminal_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const baseline_exe = b.addExecutable(.{
        .name = "m7_baseline",
        .root_module = baseline_mod,
    });
    const run_baseline = b.addRunArtifact(baseline_exe);
    if (b.args) |args| run_baseline.addArgs(args);
    const baseline_step = b.step("terminal-benchmark", "Run terminal benchmark suite");
    baseline_step.dependOn(&run_baseline.step);
}
