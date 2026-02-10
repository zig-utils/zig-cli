const std = @import("std");
const cli = @import("zig-cli");

fn createAction(ctx: *cli.BaseCommand.ParseContext) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(std.Options.debug_io, &buf);
    const stdout = &file_writer.interface;

    const name = ctx.getArgument(0) orelse return error.MissingName;
    const template = ctx.getOption("template") orelse "default";
    const force = ctx.hasOption("force");

    try stdout.print("Creating project: {s}\n", .{name});
    try stdout.print("Template: {s}\n", .{template});
    try stdout.print("Force: {s}\n", .{if (force) "yes" else "no"});
    try stdout.flush();
}

fn buildAction(ctx: *cli.BaseCommand.ParseContext) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(std.Options.debug_io, &buf);
    const stdout = &file_writer.interface;

    const mode = ctx.getOption("mode") orelse "debug";
    const optimize_str = ctx.getOption("optimize") orelse "false";
    const optimize = std.mem.eql(u8, optimize_str, "true");

    try stdout.print("Building project...\n", .{});
    try stdout.print("Mode: {s}\n", .{mode});
    try stdout.print("Optimize: {s}\n", .{if (optimize) "yes" else "no"});

    // Get all targets (variadic argument)
    var i: usize = 0;
    while (ctx.getArgument(i)) |target| : (i += 1) {
        try stdout.print("Target: {s}\n", .{target});
    }
    try stdout.flush();
}

fn testAction(ctx: *cli.BaseCommand.ParseContext) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(std.Options.debug_io, &buf);
    const stdout = &file_writer.interface;

    const filter = ctx.getOption("filter");
    const verbose = ctx.hasOption("verbose");

    try stdout.print("Running tests...\n", .{});
    if (filter) |f| {
        try stdout.print("Filter: {s}\n", .{f});
    }
    try stdout.print("Verbose: {s}\n", .{if (verbose) "yes" else "no"});
    try stdout.flush();
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Create root command
    const root_cmd = try cli.BaseCommand.init(
        allocator,
        "advanced-cli",
        "An advanced CLI application demonstrating complex features",
    );
    defer {
        root_cmd.deinit();
        allocator.destroy(root_cmd);
    }

    // Create 'create' command
    const create_cmd = try cli.BaseCommand.init(allocator, "create", "Create a new project");

    const create_name_arg = cli.Argument.init("name", "Project name", .string);
    _ = try create_cmd.addArgument(create_name_arg);

    const template_opt = cli.Option.init("template", "template", "Project template", .string)
        .withShort('t')
        .withDefault("default");
    _ = try create_cmd.addOption(template_opt);

    const force_opt = cli.Option.init("force", "force", "Overwrite existing files", .bool)
        .withShort('f');
    _ = try create_cmd.addOption(force_opt);

    _ = create_cmd.setAction(createAction);
    _ = try root_cmd.addCommand(create_cmd);

    // Create 'build' command
    const build_cmd = try cli.BaseCommand.init(allocator, "build", "Build the project");

    const mode_opt = cli.Option.init("mode", "mode", "Build mode (debug/release)", .string)
        .withShort('m')
        .withDefault("debug");
    _ = try build_cmd.addOption(mode_opt);

    const optimize_opt = cli.Option.init("optimize", "optimize", "Enable optimizations", .bool)
        .withShort('O');
    _ = try build_cmd.addOption(optimize_opt);

    const targets_arg = cli.Argument.init("targets", "Build targets", .string)
        .withRequired(false)
        .withVariadic(true);
    _ = try build_cmd.addArgument(targets_arg);

    _ = build_cmd.setAction(buildAction);
    _ = try root_cmd.addCommand(build_cmd);

    // Create 'test' command
    const test_cmd = try cli.BaseCommand.init(allocator, "test", "Run tests");

    const filter_opt = cli.Option.init("filter", "filter", "Filter tests by name", .string)
        .withShort('f');
    _ = try test_cmd.addOption(filter_opt);

    const verbose_opt = cli.Option.init("verbose", "verbose", "Verbose output", .bool)
        .withShort('v');
    _ = try test_cmd.addOption(verbose_opt);

    _ = test_cmd.setAction(testAction);
    _ = try root_cmd.addCommand(test_cmd);

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
