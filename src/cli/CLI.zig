const std = @import("std");
const Command = @import("Command.zig");
const Parser = @import("Parser.zig");
const Help = @import("Help.zig");

const CLI = @This();

name: []const u8,
version: []const u8,
description: []const u8,
root_command: *Command,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8, description: []const u8) !CLI {
    const root = try Command.init(allocator, name, description);
    return .{
        .name = name,
        .version = version,
        .description = description,
        .root_command = root,
        .allocator = allocator,
    };
}

pub fn deinit(self: *CLI) void {
    self.root_command.deinit();
    self.allocator.destroy(self.root_command);
}

pub fn command(self: *CLI, cmd: *Command) !*CLI {
    _ = try self.root_command.addCommand(cmd);
    return self;
}

pub fn option(self: *CLI, opt: @import("Option.zig")) !*CLI {
    _ = try self.root_command.addOption(opt);
    return self;
}

pub fn argument(self: *CLI, arg: @import("Argument.zig")) !*CLI {
    _ = try self.root_command.addArgument(arg);
    return self;
}

pub fn action(self: *CLI, act: Command.CommandAction) *CLI {
    _ = self.root_command.setAction(act);
    return self;
}

pub fn parse(self: *CLI, args: []const []const u8) !void {
    // Skip the program name (first arg)
    const cli_args = if (args.len > 0) args[1..] else args;

    // Check for global help or version flags
    for (cli_args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try self.showHelp(self.root_command);
            return;
        }
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            try self.showVersion();
            return;
        }
    }

    var parser = Parser.init(self.allocator);
    parser.parse(self.root_command, cli_args) catch |err| {
        if (err == Parser.ParseError.UnknownOption or
            err == Parser.ParseError.UnknownCommand or
            err == Parser.ParseError.MissingRequiredOption or
            err == Parser.ParseError.MissingRequiredArgument or
            err == Parser.ParseError.InvalidOptionValue or
            err == Parser.ParseError.MissingOptionValue or
            err == Parser.ParseError.TooManyArguments)
        {
            std.debug.print("\n", .{});
            try self.showHelp(self.root_command);
        }
        return err;
    };
}

fn showVersion(self: *CLI) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s} v{s}\n", .{ self.name, self.version });
}

fn showHelp(self: *CLI, cmd: *Command) !void {
    var help = Help.init(self.allocator);
    try help.generate(cmd, self.name, self.version);
}
