const std = @import("std");
const cli = @import("zig-cli");

fn greetAction(ctx: *cli.Command.ParseContext) !void {
    const name = ctx.getOption("name") orelse "World";
    const count_str = ctx.getOption("count") orelse "1";
    const count = try std.fmt.parseInt(usize, count_str, 10);

    const stdout = std.io.getStdOut().writer();

    var i: usize = 0;
    while (i < count) : (i += 1) {
        try stdout.print("Hello, {s}!\n", .{name});
    }
}

fn infoAction(ctx: *cli.Command.ParseContext) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("This is the info command!\n", .{});
    try stdout.print("Command: {s}\n", .{ctx.command_name});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create CLI application
    var app = try cli.CLI.init(allocator, "example", "1.0.0", "An example CLI application");
    defer app.deinit();

    // Add options to root command
    const name_option = cli.Option.init("name", "name", "Your name", .string)
        .withShort('n')
        .withDefault("World");

    const count_option = cli.Option.init("count", "count", "Number of greetings", .int)
        .withShort('c')
        .withDefault("1");

    _ = try app.option(name_option);
    _ = try app.option(count_option);

    // Set action for root command
    _ = app.action(greetAction);

    // Create a subcommand
    const info_cmd = try cli.Command.init(allocator, "info", "Show information");
    _ = info_cmd.setAction(infoAction);

    _ = try app.command(info_cmd);

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    try app.parse(args);
}
