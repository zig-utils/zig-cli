const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.standardTargetOptions(.{});
    _ = b.standardOptimizeOption(.{});

    // Create a module that can be imported by other projects
    _ = b.addModule("zig-cli", .{
        .root_source_file = b.path("src/root.zig"),
    });
}
