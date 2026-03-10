const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Library module (public, exposable to dependents) ────────────────
    const zig_cli = b.addModule("zig-cli", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // ── Tests ───────────────────────────────────────────────────────────
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const lib_tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);

    // ── Examples ────────────────────────────────────────────────────────
    const example_names = [_][]const u8{
        "simple",
        "basic",
        "typed",
        "advanced",
        "prompts",
        "showcase",
        "config",
    };

    const examples_step = b.step("examples", "Build all examples");

    for (example_names) |name| {
        const example_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig-cli", .module = zig_cli },
            },
        });

        const example = b.addExecutable(.{
            .name = name,
            .root_module = example_module,
        });

        const install_example = b.addInstallArtifact(example, .{});
        examples_step.dependOn(&install_example.step);

        const run_example = b.addRunArtifact(example);
        run_example.step.dependOn(&install_example.step);
        if (b.args) |args| {
            run_example.addArgs(args);
        }

        const run_step = b.step(
            b.fmt("run-{s}", .{name}),
            b.fmt("Run the {s} example", .{name}),
        );
        run_step.dependOn(&run_example.step);
    }
}
