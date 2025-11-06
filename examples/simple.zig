const std = @import("std");
const cli = @import("zig-cli");

// Define your CLI options as a struct - that's it!
const GreetOptions = struct {
    name: []const u8,              // Required
    age: ?u16 = null,              // Optional
    times: u8 = 1,                 // With default
    enthusiastic: bool = false,    // Boolean flag
};

// Type-safe action - no string lookups!
fn greet(ctx: *cli.Context(GreetOptions)) !void {
    const stdout = std.io.getStdOut().writer();

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
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create command - options auto-generated from struct!
    var cmd = try cli.command(GreetOptions).init(allocator, "greet", "Greet someone");
    defer cmd.deinit();

    _ = cmd.setAction(greet);

    // Parse and execute
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    try cli.Parser.init(allocator).parse(cmd.getCommand(), args[1..]);
}
