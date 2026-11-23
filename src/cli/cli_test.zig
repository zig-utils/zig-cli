//! Nested subcommands, repeatable options, exit codes and `--json`, through
//! `Parser.parse` and `run`.

const std = @import("std");
const testing = std.testing;
const Command = @import("Command.zig");
const Option = @import("Option.zig");
const Argument = @import("Argument.zig");
const Parser = @import("Parser.zig");
const TypedCommand = @import("CommandBuilder.zig").TypedCommand;
const TypedContext = @import("CommandBuilder.zig").TypedContext;

/// What the last action saw. Actions are plain functions, so they report here.
var seen: struct {
    command: []const u8 = "",
    verbose: bool = false,
    out: ?[]const u8 = null,
    args: [4][]const u8 = undefined,
    arg_count: usize = 0,
    excludes: [4][]const u8 = undefined,
    exclude_count: usize = 0,
    json: bool = false,
    runs: usize = 0,
} = .{};

fn record(ctx: *Command.ParseContext) void {
    seen.runs += 1;
    seen.command = ctx.command_name;
    seen.verbose = ctx.hasOption("verbose") and std.mem.eql(u8, ctx.getOption("verbose").?, "true");
    seen.out = ctx.getOption("out");
    seen.arg_count = ctx.getArgumentCount();
    for (ctx.arguments.items, 0..) |arg, i| seen.args[i] = arg;
    const excludes = ctx.getOptionValues("exclude");
    seen.exclude_count = excludes.len;
    for (excludes, 0..) |e, i| seen.excludes[i] = e;
    seen.json = ctx.wantsJson();
}

fn buildAction(ctx: *Command.ParseContext) !void {
    record(ctx);
    if (ctx.wantsJson()) try ctx.writeJson(.{ .built = ctx.getOption("out") orelse "" });
}

fn verifyAction(ctx: *Command.ParseContext) !u8 {
    record(ctx);
    return if (ctx.getArgumentCount() > 0 and std.mem.eql(u8, ctx.getArgument(0).?, "bad")) 3 else 0;
}

fn failingAction(ctx: *Command.ParseContext) !void {
    record(ctx);
    return error.DatabaseLocked;
}

/// zav [--verbose] (db (build [--out f] [--exclude p]... <src>... | verify <file> | sign key rotate) | scan)
fn zav(allocator: std.mem.Allocator) !*Command {
    const root = try Command.init(allocator, "zav", "Scanner");
    errdefer {
        root.deinit();
        allocator.destroy(root);
    }
    _ = try root.addOption(Option.init("verbose", "verbose", "Chatty", .bool).withShort('v'));

    const db = try Command.init(allocator, "db", "Signature databases");
    _ = try root.addCommand(db);

    const build = try Command.init(allocator, "build", "Build a database");
    _ = try build.addOption(Option.init("out", "out", "Output file", .string).withShort('o'));
    _ = try build.addOption(Option.init("exclude", "exclude", "Skip a path", .string).withRepeatable(true));
    _ = try build.addArgument(Argument.init("sources", "Inputs", .string).withVariadic(true).withRequired(false));
    _ = build.setAction(buildAction);
    _ = try db.addCommand(build);

    const verify = try Command.init(allocator, "verify", "Verify a database");
    _ = try verify.addArgument(Argument.init("file", "Database", .string));
    _ = verify.setActionWithCode(verifyAction);
    _ = try db.addCommand(verify);

    const sign = try Command.init(allocator, "sign", "Signing");
    _ = try db.addCommand(sign);
    const key = try Command.init(allocator, "key", "Keys");
    _ = try sign.addCommand(key);
    const rotate = try Command.init(allocator, "rotate", "Rotate the signing key");
    _ = rotate.setAction(buildAction);
    _ = try key.addCommand(rotate);

    const scan = try Command.init(allocator, "scan", "Scan files");
    _ = scan.setAction(failingAction);
    _ = try root.addCommand(scan);
    return root;
}

const Outputs = struct {
    stdout: std.Io.Writer.Allocating,
    stderr: std.Io.Writer.Allocating,

    fn init() Outputs {
        return .{ .stdout = .init(testing.allocator), .stderr = .init(testing.allocator) };
    }

    fn deinit(self: *Outputs) void {
        self.stdout.deinit();
        self.stderr.deinit();
    }

    fn run(self: *Outputs, root: *Command, args: []const []const u8) u8 {
        self.stdout.clearRetainingCapacity();
        self.stderr.clearRetainingCapacity();
        seen = .{};
        return @import("run.zig").run(testing.allocator, root, args, .{
            .stdout = &self.stdout.writer,
            .stderr = &self.stderr.writer,
            .version = "1.0.0",
        });
    }
};

fn destroy(root: *Command) void {
    root.deinit();
    testing.allocator.destroy(root);
}

test "nested subcommands resolve two and three levels deep" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var out: Outputs = .init();
    defer out.deinit();

    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "db", "build", "--out", "x.db", "a", "b" }));
    try testing.expectEqualStrings("build", seen.command);
    try testing.expectEqualStrings("x.db", seen.out.?);
    try testing.expectEqual(@as(usize, 2), seen.arg_count);
    try testing.expectEqualStrings("b", seen.args[1]);

    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "db", "sign", "key", "rotate" }));
    try testing.expectEqualStrings("rotate", seen.command);
    try testing.expectEqual(@as(usize, 1), seen.runs);
}

test "options of an enclosing command work before and after the subcommand" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var out: Outputs = .init();
    defer out.deinit();

    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "--verbose", "db", "build" }));
    try testing.expect(seen.verbose);
    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "db", "build", "-v", "--out=y.db" }));
    try testing.expect(seen.verbose);
    try testing.expectEqualStrings("y.db", seen.out.?);
    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "db", "build" }));
    try testing.expect(!seen.verbose);
}

test "a command group without a command, or with an unknown one, is a usage error" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var out: Outputs = .init();
    defer out.deinit();

    try testing.expectEqual(@as(u8, 2), out.run(root, &.{"db"}));
    try testing.expect(std.mem.indexOf(u8, out.stderr.written(), "'db' needs a command") != null);
    try testing.expect(std.mem.indexOf(u8, out.stderr.written(), "zav db [OPTIONS] <COMMAND>") == null);
    try testing.expect(std.mem.indexOf(u8, out.stderr.written(), "zav db <COMMAND>") != null);

    try testing.expectEqual(@as(u8, 2), out.run(root, &.{ "db", "biuld" }));
    try testing.expect(std.mem.indexOf(u8, out.stderr.written(), "Unknown command 'biuld'") != null);
    try testing.expectEqual(@as(usize, 0), seen.runs);
}

test "repeatable options collect every value in order" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var out: Outputs = .init();
    defer out.deinit();

    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "db", "build", "--exclude", "a", "--exclude=b", "--exclude", "c" }));
    try testing.expectEqual(@as(usize, 3), seen.exclude_count);
    try testing.expectEqualStrings("a", seen.excludes[0]);
    try testing.expectEqualStrings("b", seen.excludes[1]);
    try testing.expectEqualStrings("c", seen.excludes[2]);

    // A plain option keeps the last value.
    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "db", "build", "-o", "1", "-o", "2" }));
    try testing.expectEqualStrings("2", seen.out.?);
    try testing.expectEqual(@as(usize, 0), seen.exclude_count);
}

test "exit codes: the action's own, 1 for an action error, 2 for usage, 0 for help" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var out: Outputs = .init();
    defer out.deinit();

    try testing.expectEqual(@as(u8, 3), out.run(root, &.{ "db", "verify", "bad" }));
    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "db", "verify", "good" }));

    try testing.expectEqual(@as(u8, 1), out.run(root, &.{"scan"}));
    try testing.expectEqualStrings("Error: DatabaseLocked\n", out.stderr.written());

    try testing.expectEqual(@as(u8, 2), out.run(root, &.{ "db", "verify" }));
    try testing.expectEqual(@as(u8, 2), out.run(root, &.{ "--nope", "scan" }));
    try testing.expectEqualStrings("Error: Unknown option '--nope'\n", out.stderr.written());
    try testing.expectEqual(@as(u8, 2), out.run(root, &.{ "db", "build", "--out" }));

    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "db", "build", "--help" }));
    try testing.expectEqual(@as(usize, 0), seen.runs);
    try testing.expect(std.mem.indexOf(u8, out.stdout.written(), "zav db build [OPTIONS] [sources]...") != null);
    try testing.expect(std.mem.indexOf(u8, out.stdout.written(), "GLOBAL OPTIONS:") != null);
    try testing.expect(std.mem.indexOf(u8, out.stdout.written(), "(repeatable)") != null);
}

test "Parser.parseForExit returns the action's exit code" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var parser = Parser.init(testing.allocator);
    parser.report_errors = false;
    try testing.expectEqual(@as(u8, 3), try parser.parseForExit(root, &.{ "db", "verify", "bad" }));
    try testing.expectEqual(@as(usize, 3), parser.path().len);
    try testing.expectError(error.MissingCommand, parser.parseForExit(root, &.{"db"}));
    try testing.expectError(error.UnknownCommand, parser.parseForExit(root, &.{"nope"}));
}

test "Parser.parse keeps the 0.1 contract" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var parser = Parser.init(testing.allocator);
    parser.report_errors = false;

    // Returns void; an exit code from the action is run and dropped.
    seen = .{};
    try parser.parse(root, &.{ "db", "verify", "bad" });
    try testing.expectEqual(@as(usize, 1), seen.runs);
    // A group without a command does nothing, as before.
    try parser.parse(root, &.{"db"});
    // An unknown word is still TooManyArguments, which callers match on.
    try testing.expectError(error.TooManyArguments, parser.parse(root, &.{"nope"}));
    try testing.expectError(error.UnknownOption, parser.parse(root, &.{"--nope"}));
}

test "--json is offered where enabled and reaches the action" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var out: Outputs = .init();
    defer out.deinit();

    // Not enabled yet: an unknown option.
    try testing.expectEqual(@as(u8, 2), out.run(root, &.{ "db", "build", "--json" }));

    _ = root.enableJson();
    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "db", "build", "--json", "-o", "z.db" }));
    try testing.expect(seen.json);
    try testing.expectEqualStrings("{\"built\":\"z.db\"}\n", out.stdout.written());

    // Errors become one JSON object on stderr.
    try testing.expectEqual(@as(u8, 2), out.run(root, &.{ "--json", "db", "nope" }));
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, out.stderr.written(), .{});
    defer parsed.deinit();
    const err = parsed.value.object.get("error").?.object;
    try testing.expectEqualStrings("UnknownCommand", err.get("kind").?.string);
    try testing.expectEqualStrings("Unknown command 'nope'", err.get("message").?.string);

    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "db", "build", "--help" }));
    try testing.expect(std.mem.indexOf(u8, out.stdout.written(), "--json") != null);
}

test "-- ends option parsing" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var out: Outputs = .init();
    defer out.deinit();

    try testing.expectEqual(@as(u8, 0), out.run(root, &.{ "db", "build", "--", "-weird-name", "--out" }));
    try testing.expectEqual(@as(usize, 2), seen.arg_count);
    try testing.expectEqualStrings("-weird-name", seen.args[0]);
    try testing.expectEqual(@as(?[]const u8, null), seen.out);
}

const ScanOptions = struct {
    exclude: []const []const u8 = &.{},
    depth: u8 = 4,
};

var typed_seen: struct { excludes: usize = 0, depth: u8 = 0, first: []const u8 = "" } = .{};

fn typedScan(ctx: *TypedContext(ScanOptions)) !u8 {
    const opts = try ctx.parse();
    typed_seen = .{ .excludes = opts.exclude.len, .depth = opts.depth, .first = if (opts.exclude.len > 0) opts.exclude[0] else "" };
    return if (opts.exclude.len > 1) 5 else 0;
}

test "typed commands nest, take repeatable slice fields and return exit codes" {
    var root = try TypedCommand(struct { verbose: bool = false }).init(testing.allocator, "zav", "Scanner");
    defer root.deinit();
    var scan = try TypedCommand(ScanOptions).init(testing.allocator, "scan", "Scan");
    _ = scan.setActionWithCode(typedScan);
    _ = try root.addCommand(scan);

    try testing.expect(scan.command.options.items[0].repeatable);
    try testing.expect(!scan.command.options.items[0].required);

    var out: Outputs = .init();
    defer out.deinit();
    try testing.expectEqual(@as(u8, 5), out.run(root.command, &.{ "--verbose", "scan", "--exclude", "a", "--exclude", "b", "--depth", "9" }));
    try testing.expectEqual(@as(usize, 2), typed_seen.excludes);
    try testing.expectEqual(@as(u8, 9), typed_seen.depth);
    try testing.expectEqualStrings("a", typed_seen.first);

    try testing.expectEqual(@as(u8, 0), out.run(root.command, &.{"scan"}));
    try testing.expectEqual(@as(usize, 0), typed_seen.excludes);
    try testing.expectEqual(@as(u8, 4), typed_seen.depth);
}

test "--version prints the name and version when one is configured" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var out: Outputs = .init();
    defer out.deinit();
    try testing.expectEqual(@as(u8, 0), out.run(root, &.{"--version"}));
    try testing.expectEqualStrings("zav 1.0.0\n", out.stdout.written());
    try testing.expectEqual(@as(u8, 0), out.run(root, &.{"-V"}));
    try testing.expectEqual(@as(u8, 2), out.run(root, &.{ "--version", "--invalid" }));
    try testing.expectEqual(@as(usize, 0), seen.runs);
}

test "run passes application state to actions and reports their diagnostics" {
    const App = struct {
        called: bool = false,

        fn execute(ctx: *Command.ParseContext) !void {
            const app: *@This() = @ptrCast(@alignCast(ctx.user_data.?));
            app.called = true;
            ctx.setDiagnostic("the action rejected this option");
            return error.InvalidOptionValue;
        }
    };
    var app: App = .{};
    const root = try Command.init(testing.allocator, "app", "An app");
    defer destroy(root);
    _ = root.setAction(App.execute);
    _ = root.enableJson();
    var out: Outputs = .init();
    defer out.deinit();
    const code = @import("run.zig").run(testing.allocator, root, &.{"--json"}, .{
        .stdout = &out.stdout.writer,
        .stderr = &out.stderr.writer,
        .user_data = &app,
    });
    try testing.expectEqual(@as(u8, 2), code);
    try testing.expect(app.called);
    try testing.expectEqualStrings(
        "{\"error\":{\"kind\":\"InvalidOptionValue\",\"message\":\"the action rejected this option\"}}\n",
        out.stderr.written(),
    );
}

test "a bool option takes --flag and every true/false spelling, case-insensitively" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var out: Outputs = .init();
    defer out.deinit();

    for ([_][]const u8{ "--verbose", "--verbose=true", "--verbose=yes", "--verbose=on", "--verbose=1", "--verbose=YES", "--verbose=True", "--verbose=ON" }) |arg| {
        try testing.expectEqual(@as(u8, 0), out.run(root, &.{ arg, "db", "build" }));
        try testing.expect(seen.verbose);
    }
    for ([_][]const u8{ "--verbose=false", "--verbose=no", "--verbose=off", "--verbose=0", "--verbose=No", "--verbose=OFF" }) |arg| {
        try testing.expectEqual(@as(u8, 0), out.run(root, &.{ arg, "db", "build" }));
        try testing.expect(!seen.verbose);
    }
}

test "a bool option rejects other values and names the accepted spellings" {
    const root = try zav(testing.allocator);
    defer destroy(root);
    var out: Outputs = .init();
    defer out.deinit();

    for ([_][]const u8{ "--verbose=maybe", "--verbose=", "--verbose=2", "--verbose=yess" }) |arg| {
        try testing.expectEqual(@as(u8, 2), out.run(root, &.{ arg, "db", "build" }));
        const err = out.stderr.written();
        try testing.expect(std.mem.indexOf(u8, err, "Option '--verbose' expects true, false, yes, no, on, off, 1 or 0") != null);
        try testing.expectEqual(@as(usize, 0), seen.runs);
    }
}

test "Option.parseBool" {
    try testing.expectEqual(@as(?bool, true), Option.parseBool("Yes"));
    try testing.expectEqual(@as(?bool, false), Option.parseBool("0"));
    try testing.expectEqual(@as(?bool, null), Option.parseBool("y"));
}
