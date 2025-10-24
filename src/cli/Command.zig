const std = @import("std");
const Option = @import("Option.zig");
const Argument = @import("Argument.zig");

const Command = @This();

pub const CommandAction = *const fn (context: *ParseContext) anyerror!void;

pub const ParseContext = struct {
    allocator: std.mem.Allocator,
    options: std.StringHashMap([]const u8),
    arguments: std.ArrayList([]const u8),
    command_name: []const u8,

    pub fn init(allocator: std.mem.Allocator, command_name: []const u8) ParseContext {
        return .{
            .allocator = allocator,
            .options = std.StringHashMap([]const u8).init(allocator),
            .arguments = std.ArrayList([]const u8).init(allocator),
            .command_name = command_name,
        };
    }

    pub fn deinit(self: *ParseContext) void {
        self.options.deinit();
        self.arguments.deinit();
    }

    pub fn getOption(self: *ParseContext, name: []const u8) ?[]const u8 {
        return self.options.get(name);
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
};

name: []const u8,
description: []const u8,
aliases: std.ArrayList([]const u8),
options: std.ArrayList(Option),
arguments: std.ArrayList(Argument),
subcommands: std.ArrayList(*Command),
action: ?CommandAction = null,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, name: []const u8, description: []const u8) !*Command {
    const cmd = try allocator.create(Command);
    cmd.* = .{
        .name = name,
        .description = description,
        .aliases = std.ArrayList([]const u8).init(allocator),
        .options = std.ArrayList(Option).init(allocator),
        .arguments = std.ArrayList(Argument).init(allocator),
        .subcommands = std.ArrayList(*Command).init(allocator),
        .allocator = allocator,
    };
    return cmd;
}

pub fn deinit(self: *Command) void {
    self.aliases.deinit();
    self.options.deinit();
    self.arguments.deinit();

    for (self.subcommands.items) |subcmd| {
        subcmd.deinit();
        self.allocator.destroy(subcmd);
    }
    self.subcommands.deinit();
}

pub fn addAlias(self: *Command, alias: []const u8) !*Command {
    try self.aliases.append(alias);
    return self;
}

pub fn addOption(self: *Command, option: Option) !*Command {
    try self.options.append(option);
    return self;
}

pub fn addArgument(self: *Command, argument: Argument) !*Command {
    try self.arguments.append(argument);
    return self;
}

pub fn addCommand(self: *Command, subcommand: *Command) !*Command {
    try self.subcommands.append(subcommand);
    return self;
}

pub fn setAction(self: *Command, action: CommandAction) *Command {
    self.action = action;
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
