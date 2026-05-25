// This repo ships a C ABI first until further notice.
// Keep build entrypoints aligned around the shipped header and exported symbols, not privileged Zig imports.
// Repo-local Zig roots may exist for tests and proofs, but they are not an embedder-facing contract.

const std = @import("std");

fn addStbImage(module: *std.Build.Module, b: *std.Build) void {
    module.addIncludePath(b.path("../howl-render/src"));
    module.addCSourceFile(.{ .file = b.path("../howl-render/src/stb_image.c") });
}

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
    addStbImage(internal_mod, b);
    const scrollback_verifier_mod = b.createModule(.{
        .root_source_file = b.path("src/fuzz/scrollback.zig"),
        .target = target,
        .optimize = optimize,
    });
    scrollback_verifier_mod.addImport("howl_vt", internal_mod);
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

    const abi_mod = b.createModule(.{
        .root_source_file = b.path("src/test/abi.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    abi_mod.addIncludePath(b.path("include"));
    const abi_ffi_mod = b.createModule(.{
        .root_source_file = b.path("src/ffi.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    abi_ffi_mod.addOptions("vt_options", ffi_options);
    addStbImage(abi_ffi_mod, b);
    abi_mod.addImport("ffi", abi_ffi_mod);
    const abi_tests = b.addTest(.{
        .name = "test-abi",
        .root_module = abi_mod,
        .filters = b.args orelse &.{},
    });
    abi_tests.use_llvm = true;
    const run_abi_tests = b.addRunArtifact(abi_tests);
    if (b.args != null) {
        run_abi_tests.has_side_effects = true;
    }

    const check_step = b.step("check", "Build the shipped VT ABI surface");
    const test_step = b.step("test", "Run all VT correctness proofs");
    const test_abi_step = b.step("test:abi", "Run shipped VT ABI contract tests");
    const test_abi_build_step = b.step("test:abi:build", "Build shipped VT ABI contract tests");
    const test_unit_step = b.step("test:unit", "Run unit tests");
    const test_unit_build_step = b.step("test:unit:build", "Build unit tests");
    test_abi_build_step.dependOn(&abi_tests.step);
    test_abi_step.dependOn(&run_abi_tests.step);
    test_unit_build_step.dependOn(&mod_tests.step);
    test_unit_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(test_abi_step);
    test_step.dependOn(test_unit_step);

    const ffi_mod = b.createModule(.{
        .root_source_file = b.path("src/libhowl_vt.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    ffi_mod.addOptions("vt_options", ffi_options);
    addStbImage(ffi_mod, b);
    const ffi_lib = b.addLibrary(.{
        .name = "howl_vt",
        .linkage = .dynamic,
        .root_module = ffi_mod,
    });
    check_step.dependOn(&ffi_lib.step);
    b.installArtifact(ffi_lib);
    b.installFile("include/howl_vt.h", "include/howl_vt.h");

    const regression_mod = b.createModule(.{
        .root_source_file = b.path("src/test/scrollback_regression.zig"),
        .target = target,
        .optimize = optimize,
    });
    regression_mod.addImport("scrollback_verifier", scrollback_verifier_mod);

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
    test_regression_build_step.dependOn(&regression_tests.step);
    test_regression_step.dependOn(&run_regression_tests.step);
    test_step.dependOn(test_regression_step);

    const fuzz_module = b.createModule(.{
        .root_source_file = b.path("src/fuzz/fuzz_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    fuzz_module.addImport("howl_vt", internal_mod);

    const fuzz_exe = b.addExecutable(.{
        .name = "howl_vt_fuzz",
        .root_module = fuzz_module,
    });
    fuzz_exe.use_llvm = true;
    const fuzz_step = b.step("fuzz", "Run VT protocol and scrollback fuzz search");
    const fuzz_build_step = b.step("fuzz:build", "Build VT protocol and scrollback fuzz search");
    fuzz_build_step.dependOn(&fuzz_exe.step);
    const run_fuzz = b.addRunArtifact(fuzz_exe);
    if (b.args) |args| run_fuzz.addArgs(args);
    fuzz_step.dependOn(&run_fuzz.step);

    const baseline_mod = b.createModule(.{
        .root_source_file = b.path("src/terminal_benchmark_main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });
    addStbImage(baseline_mod, b);
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
