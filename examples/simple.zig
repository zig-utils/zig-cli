const std = @import("std");
const cli = @import("zig_cli");

// Define your CLI options as a struct - that's it!
const GreetOptions = struct {
    name: []const u8,
    age: ?u16 = null,
    times: u8 = 1,
    enthusiastic: bool = false,
};

// Type-safe action - no string lookups!
fn greet(ctx: *cli.Context(GreetOptions)) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(std.Options.debug_io, &buf);
    const stdout = &file_writer.interface;

    // Compile-time validated field access
    const name = ctx.get(.name);
    const age = ctx.get(.age);
    const times = ctx.get(.times);
    const enthusiastic = ctx.get(.enthusiastic);

    const punct: []const u8 = if (enthusiastic) "!" else ".";

    var i: u8 = 0;
    while (i < times) : (i += 1) {
        try stdout.print("Hello, {s}", .{name});
        if (age) |a| {
            try stdout.print(" (age {d})", .{a});
        }
        try stdout.print("{s}\n", .{punct});
    }
    try stdout.flush();
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;

    // Create command - options auto-generated from struct!
    var cmd = try cli.Command(GreetOptions).init(allocator, "greet", "Greet someone");
    defer cmd.deinit();

    _ = cmd.setAction(greet);

    // Collect command line arguments
    var args_list: std.ArrayList([]const u8) = .empty;
    defer args_list.deinit(allocator);
    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    _ = args_iter.skip(); // skip program name
    while (args_iter.next()) |arg| {
        try args_list.append(allocator, arg);
    }

    // Parse, run the command and hand its exit code back to the shell.
    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buf);
    var stderr_buf: [1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(init.io, &stderr_buf);
    return cli.run(allocator, cmd.getCommand(), args_list.items, .{
        .stdout = &stdout.interface,
        .stderr = &stderr.interface,
    });
}
