const std = @import("std");
const cli = @import("zig-cli");

fn greetAction(ctx: *cli.BaseCommand.ParseContext) !void {
    const name = ctx.getOption("name") orelse "World";
    const count_str = ctx.getOption("count") orelse "1";
    const count = try std.fmt.parseInt(usize, count_str, 10);

    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(std.Options.debug_io, &buf);
    const stdout = &file_writer.interface;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        try stdout.print("Hello, {s}!\n", .{name});
    }
    try stdout.flush();
}

fn infoAction(ctx: *cli.BaseCommand.ParseContext) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(std.Options.debug_io, &buf);
    const stdout = &file_writer.interface;
    try stdout.print("This is the info command!\n", .{});
    try stdout.print("Command: {s}\n", .{ctx.command_name});
    try stdout.flush();
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Create root command
    const root_cmd = try cli.BaseCommand.init(allocator, "example", "An example CLI application");
    defer {
        root_cmd.deinit();
        allocator.destroy(root_cmd);
    }

    // Add options to root command
    const name_option = cli.Option.init("name", "name", "Your name", .string)
        .withShort('n')
        .withDefault("World");

    const count_option = cli.Option.init("count", "count", "Number of greetings", .int)
        .withShort('c')
        .withDefault("1");

    _ = try root_cmd.addOption(name_option);
    _ = try root_cmd.addOption(count_option);

    // Set action for root command
    _ = root_cmd.setAction(greetAction);

    // Create a subcommand
    const info_cmd = try cli.BaseCommand.init(allocator, "info", "Show information");
    _ = info_cmd.setAction(infoAction);

    _ = try root_cmd.addCommand(info_cmd);

    // Collect command line arguments
    var args_list = std.ArrayList([]const u8){};
    defer args_list.deinit(allocator);
    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    _ = args_iter.skip(); // skip program name
    while (args_iter.next()) |arg| {
        try args_list.append(allocator, arg);
    }

    var parser = cli.Parser.init(allocator);
    try parser.parse(root_cmd, args_list.items);
}
