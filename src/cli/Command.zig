const std = @import("std");
const Option = @import("Option.zig");
const Argument = @import("Argument.zig");

const Command = @This();

/// What a command runs.
pub const CommandAction = *const fn (context: *ParseContext) anyerror!void;

/// What a command runs when it chooses the process exit code
/// (`setActionWithCode`). `Parser.parseForExit` and `cli.run` return it.
pub const CommandActionWithCode = *const fn (context: *ParseContext) anyerror!u8;

pub const ParseContext = struct {
    allocator: std.mem.Allocator,
    options: std.StringHashMap([]const u8),
    /// Every value of a repeatable option, in command-line order.
    option_values: std.StringHashMap(std.ArrayList([]const u8)),
    arguments: std.ArrayList([]const u8),
    /// Name of the command being run (the deepest subcommand).
    command_name: []const u8,
    /// `--json` was given on a command that offers JSON output.
    json: bool = false,
    /// `--help` or `-h` was given.
    help: bool = false,
    /// Where `writeJson` and command output go, when the caller provides it
    /// (`cli.run` does).
    out: ?*std.Io.Writer = null,

    pub fn init(allocator: std.mem.Allocator, command_name: []const u8) ParseContext {
        return .{
            .allocator = allocator,
            .options = std.StringHashMap([]const u8).init(allocator),
            .option_values = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .arguments = std.ArrayList([]const u8).empty,
            .command_name = command_name,
        };
    }

    pub fn deinit(self: *ParseContext) void {
        self.options.deinit();
        var it = self.option_values.valueIterator();
        while (it.next()) |list| list.deinit(self.allocator);
        self.option_values.deinit();
        self.arguments.deinit(self.allocator);
    }

    pub fn getOption(self: *ParseContext, name: []const u8) ?[]const u8 {
        return self.options.get(name);
    }

    /// All values of a repeatable option (`--exclude a --exclude b`), or an
    /// empty slice when it was not given.
    pub fn getOptionValues(self: *ParseContext, name: []const u8) []const []const u8 {
        const list = self.option_values.getPtr(name) orelse return &.{};
        return list.items;
    }

    /// Record one occurrence of a repeatable option.
    pub fn appendOptionValue(self: *ParseContext, name: []const u8, value: []const u8) !void {
        const entry = try self.option_values.getOrPut(name);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.append(self.allocator, value);
        try self.options.put(name, value);
    }

    pub fn hasOption(self: *ParseContext, name: []const u8) bool {
        return self.options.contains(name);
    }

    pub fn getArgument(self: *ParseContext, index: usize) ?[]const u8 {
        if (index >= self.arguments.items.len) return null;
        return self.arguments.items[index];
    }

    pub fn getArgumentCount(self: *ParseContext) usize {
        return self.arguments.items.len;
    }

    /// Whether the caller asked for machine-readable output.
    pub fn wantsJson(self: *const ParseContext) bool {
        return self.json;
    }

    /// Write `value` as one line of JSON to `out`.
    pub fn writeJson(self: *ParseContext, value: anytype) !void {
        const w = self.out orelse return error.NoOutput;
        try std.json.Stringify.value(value, .{}, w);
        try w.writeByte('\n');
    }
};

name: []const u8,
description: []const u8,
aliases: std.ArrayList([]const u8),
options: std.ArrayList(Option),
arguments: std.ArrayList(Argument),
subcommands: std.ArrayList(*Command),
action: ?CommandAction = null,
/// Set by `setActionWithCode`; takes precedence over `action`.
action_with_code: ?CommandActionWithCode = null,
/// Accept the built-in `--json` flag here and in every subcommand.
json_output: bool = false,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, name: []const u8, description: []const u8) !*Command {
    const cmd = try allocator.create(Command);
    cmd.* = .{
        .name = name,
        .description = description,
        .aliases = std.ArrayList([]const u8).empty,
        .options = std.ArrayList(Option).empty,
        .arguments = std.ArrayList(Argument).empty,
        .subcommands = std.ArrayList(*Command).empty,
        .allocator = allocator,
    };
    return cmd;
}

pub fn deinit(self: *Command) void {
    self.aliases.deinit(self.allocator);
    self.options.deinit(self.allocator);
    self.arguments.deinit(self.allocator);

    for (self.subcommands.items) |subcmd| {
        subcmd.deinit();
        self.allocator.destroy(subcmd);
    }
    self.subcommands.deinit(self.allocator);
}

pub fn addAlias(self: *Command, alias: []const u8) !*Command {
    try self.aliases.append(self.allocator, alias);
    return self;
}

pub fn addOption(self: *Command, option: Option) !*Command {
    try self.options.append(self.allocator, option);
    return self;
}

pub fn addArgument(self: *Command, argument: Argument) !*Command {
    try self.arguments.append(self.allocator, argument);
    return self;
}

pub fn addCommand(self: *Command, subcommand: *Command) !*Command {
    try self.subcommands.append(self.allocator, subcommand);
    return self;
}

pub fn setAction(self: *Command, action: CommandAction) *Command {
    self.action = action;
    return self;
}

/// Set an action that returns the process exit code. `Parser.parseForExit`
/// and `cli.run` hand the code back; `Parser.parse` runs it and drops it.
pub fn setActionWithCode(self: *Command, action: CommandActionWithCode) *Command {
    self.action_with_code = action;
    return self;
}

/// Whether the command has anything to run.
pub fn hasAction(self: *const Command) bool {
    return self.action != null or self.action_with_code != null;
}

/// Run the command's action; 0 for an action that returns no code.
pub fn runAction(self: *const Command, context: *ParseContext) anyerror!u8 {
    if (self.action_with_code) |action| return action(context);
    if (self.action) |action| try action(context);
    return 0;
}

/// Offer the built-in `--json` flag on this command and its subcommands.
/// Actions see it as `ctx.wantsJson()`; `cli.run` reports errors as JSON.
pub fn enableJson(self: *Command) *Command {
    self.json_output = true;
    return self;
}

pub fn findOption(self: *Command, arg: []const u8) ?*const Option {
    for (self.options.items) |*opt| {
        if (opt.matches(arg)) {
            return opt;
        }
    }
    return null;
}

pub fn findSubcommand(self: *Command, name: []const u8) ?*Command {
    for (self.subcommands.items) |subcmd| {
        // Check name
        if (std.mem.eql(u8, subcmd.name, name)) {
            return subcmd;
        }

        // Check aliases
        for (subcmd.aliases.items) |alias| {
            if (std.mem.eql(u8, alias, name)) {
                return subcmd;
            }
        }
    }
    return null;
}
