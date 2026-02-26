const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // eth.zig dependency (replaces zabi for contract interaction layer)
    const eth_dep = b.dependency("eth", .{
        .target = target,
        .optimize = optimize,
    });
    const eth_module = eth_dep.module("eth");

    // Main library module (includes eth for contract interaction)
    const sdk_module = b.addModule("perpcity_sdk", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    sdk_module.addImport("eth", eth_module);

    // Pure math module (no eth dependency -- for unit tests)
    // Uses math_root.zig which only exports pure-Zig modules.
    const math_module = b.createModule(.{
        .root_source_file = b.path("src/math_root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unit tests -- pure math, no eth
    const unit_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/unit_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_test_mod.addImport("perpcity_sdk", math_module);

    const unit_tests = b.addTest(.{
        .root_module = unit_test_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests -- needs eth for contract interaction
    const integration_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_test_mod.addImport("perpcity_sdk", sdk_module);
    integration_test_mod.addImport("eth", eth_module);

    const integration_tests = b.addTest(.{
        .root_module = integration_test_mod,
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_step = b.step("integration-test", "Run integration tests (requires Anvil + compiled mocks)");
    integration_step.dependOn(&run_integration_tests.step);
}
