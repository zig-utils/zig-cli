const std = @import("std");
const cli = @import("zig-cli");

fn createAction(ctx: *cli.Command.ParseContext) !void {
    const stdout = std.io.getStdOut().writer();

    const name = ctx.getArgument(0) orelse return error.MissingName;
    const template = ctx.getOption("template") orelse "default";
    const force = ctx.hasOption("force");

    try stdout.print("Creating project: {s}\n", .{name});
    try stdout.print("Template: {s}\n", .{template});
    try stdout.print("Force: {s}\n", .{if (force) "yes" else "no"});
}

fn buildAction(ctx: *cli.Command.ParseContext) !void {
    const stdout = std.io.getStdOut().writer();

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
}

fn testAction(ctx: *cli.Command.ParseContext) !void {
    const stdout = std.io.getStdOut().writer();

    const filter = ctx.getOption("filter");
    const verbose = ctx.hasOption("verbose");

    try stdout.print("Running tests...\n", .{});
    if (filter) |f| {
        try stdout.print("Filter: {s}\n", .{f});
    }
    try stdout.print("Verbose: {s}\n", .{if (verbose) "yes" else "no"});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create CLI application
    var app = try cli.CLI.init(
        allocator,
        "advanced-cli",
        "2.0.0",
        "An advanced CLI application demonstrating complex features",
    );
    defer app.deinit();

    // Create 'create' command
    const create_cmd = try cli.Command.init(allocator, "create", "Create a new project");

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
    _ = try app.command(create_cmd);

    // Create 'build' command
    const build_cmd = try cli.Command.init(allocator, "build", "Build the project");

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
    _ = try app.command(build_cmd);

    // Create 'test' command
    const test_cmd = try cli.Command.init(allocator, "test", "Run tests");

    const filter_opt = cli.Option.init("filter", "filter", "Filter tests by name", .string)
        .withShort('f');
    _ = try test_cmd.addOption(filter_opt);

    const verbose_opt = cli.Option.init("verbose", "verbose", "Verbose output", .bool)
        .withShort('v');
    _ = try test_cmd.addOption(verbose_opt);

    _ = test_cmd.setAction(testAction);
    _ = try app.command(test_cmd);

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    try app.parse(args);
}
