const std = @import("std");
const Command = @import("Command.zig");
const Option = @import("Option.zig");
const Argument = @import("Argument.zig");

const Parser = @This();

pub const ParseError = error{
    UnknownOption,
    UnknownCommand,
    /// The command only groups subcommands and none was given.
    MissingCommand,
    MissingRequiredOption,
    MissingRequiredArgument,
    InvalidOptionValue,
    MissingOptionValue,
    TooManyArguments,
    /// Subcommands nested deeper than `max_depth`.
    CommandTooDeep,
};

/// Deepest command path `parse` follows (root included).
pub const max_depth = 16;

allocator: std.mem.Allocator,
/// Print parse errors to stderr as they happen. `cli.run` turns this off and
/// reports `diagnostic()` itself.
report_errors: bool = true,
/// Handed to the action as `ParseContext.out`.
out: ?*std.Io.Writer = null,
/// Handed to the action as `ParseContext.user_data`.
user_data: ?*anyopaque = null,
/// After `parse`: `--help`/`-h` was given, so no action ran.
help_requested: bool = false,
/// After `parse`: `--json` appeared on the command line (before any `--`).
json_requested: bool = false,

path_buffer: [max_depth]*Command = undefined,
path_len: usize = 0,
diagnostic_buffer: [256]u8 = undefined,
diagnostic_len: usize = 0,

pub fn init(allocator: std.mem.Allocator) Parser {
    return .{ .allocator = allocator };
}

/// The commands from the root to the one `parse` resolved.
pub fn path(self: *const Parser) []const *Command {
    return self.path_buffer[0..self.path_len];
}

/// Why the last `parse` failed, in words.
pub fn diagnostic(self: *const Parser) []const u8 {
    return self.diagnostic_buffer[0..self.diagnostic_len];
}

/// Parse `args` (without the program name) against `command`, follow
/// subcommands, and run the resolved command's action.
///
/// Compatible with zig-cli 0.1: an exit code from `setActionWithCode` is
/// dropped, a command group given without a command does nothing, and a word
/// that is neither a subcommand nor an expected argument is
/// `error.TooManyArguments`. Use `parseForExit` (or `cli.run`) for exit codes
/// and the `UnknownCommand` / `MissingCommand` errors.
///
/// Options of a command apply to its subcommands too, before or after the
/// subcommand name. `--name=value` and `--` (end of options) are understood.
pub fn parse(self: *Parser, command: *Command, args: []const []const u8) !void {
    _ = self.parseImpl(command, args, .legacy) catch |err| switch (err) {
        error.MissingCommand => return,
        error.UnknownCommand => return error.TooManyArguments,
        else => |e| return e,
    };
}

/// Like `parse`, but returns the exit code of the resolved command's action
/// (0 for `setAction` actions, and when `--help` was given; see
/// `help_requested`), and reports `UnknownCommand` and `MissingCommand`.
pub fn parseForExit(self: *Parser, command: *Command, args: []const []const u8) !u8 {
    return self.parseImpl(command, args, .exit_code);
}

const Mode = enum { legacy, exit_code };

fn parseImpl(self: *Parser, command: *Command, args: []const []const u8, mode: Mode) !u8 {
    self.path_len = 0;
    self.diagnostic_len = 0;
    self.help_requested = false;
    self.json_requested = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--")) break;
        if (std.mem.eql(u8, arg, "--json")) self.json_requested = true;
    }

    var context = Command.ParseContext.init(self.allocator, command.name);
    defer context.deinit();
    context.out = self.out;
    context.user_data = self.user_data;

    try self.push(command);
    var current = command;
    var options_done = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (!options_done and std.mem.eql(u8, arg, "--")) {
            options_done = true;
            continue;
        }

        if (!options_done and arg.len > 1 and arg[0] == '-') {
            var flag = arg;
            var inline_value: ?[]const u8 = null;
            if (std.mem.startsWith(u8, arg, "--")) {
                if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
                    flag = arg[0..eq];
                    inline_value = arg[eq + 1 ..];
                }
            }

            if (self.findOption(flag)) |opt| {
                if (opt.option_type == .bool) {
                    const value = inline_value orelse "true";
                    if (!std.mem.eql(u8, value, "true") and !std.mem.eql(u8, value, "false")) {
                        return self.fail(ParseError.InvalidOptionValue, "Option '--{s}' expects true or false", .{opt.long});
                    }
                    try context.options.put(opt.name, value);
                } else {
                    const value = inline_value orelse blk: {
                        i += 1;
                        if (i >= args.len) {
                            return self.fail(ParseError.MissingOptionValue, "Option '{s}' requires a value", .{arg});
                        }
                        break :blk args[i];
                    };
                    try self.validateOptionValue(opt.*, value);
                    if (opt.repeatable) {
                        try context.appendOptionValue(opt.name, value);
                    } else {
                        try context.options.put(opt.name, value);
                    }
                }
            } else if (std.mem.eql(u8, flag, "--help") or std.mem.eql(u8, flag, "-h")) {
                context.help = true;
                try context.options.put("help", "true");
            } else if (std.mem.eql(u8, flag, "--json") and self.jsonEnabled()) {
                context.json = true;
            } else {
                return self.fail(ParseError.UnknownOption, "Unknown option '{s}'", .{flag});
            }
            continue;
        }

        // A positional: the next subcommand, if this command groups any and has
        // not started taking its own arguments.
        if (!options_done and current.subcommands.items.len > 0 and context.arguments.items.len == 0) {
            if (current.findSubcommand(arg)) |sub| {
                try self.push(sub);
                current = sub;
                context.command_name = sub.name;
                continue;
            }
            if (current.arguments.items.len == 0) {
                if (mode == .legacy) return self.fail(ParseError.UnknownCommand, "Too many arguments provided", .{});
                return self.fail(ParseError.UnknownCommand, "Unknown command '{s}'", .{arg});
            }
        }
        try context.arguments.append(context.allocator, arg);
    }

    if (context.help) {
        self.help_requested = true;
        return 0;
    }

    // Defaults and required options, for every command on the path.
    for (self.path()) |cmd| {
        for (cmd.options.items) |opt| {
            if (context.hasOption(opt.name)) continue;
            if (opt.default_value) |default| {
                try context.options.put(opt.name, default);
            } else if (opt.required) {
                return self.fail(ParseError.MissingRequiredOption, "Missing required option '--{s}'", .{opt.long});
            }
        }
    }

    var required_count: usize = 0;
    for (current.arguments.items) |arg_def| {
        if (arg_def.required) required_count += 1;
    }
    if (context.getArgumentCount() < required_count) {
        return self.fail(ParseError.MissingRequiredArgument, "Missing required arguments", .{});
    }

    // Check for too many arguments (unless last one is variadic)
    const has_variadic = if (current.arguments.items.len > 0)
        current.arguments.items[current.arguments.items.len - 1].variadic
    else
        false;
    if (!has_variadic and context.getArgumentCount() > current.arguments.items.len) {
        return self.fail(ParseError.TooManyArguments, "Too many arguments provided", .{});
    }

    if (current.hasAction()) return current.runAction(&context) catch |err| {
        const message = context.diagnostic();
        @memcpy(self.diagnostic_buffer[0..message.len], message);
        self.diagnostic_len = message.len;
        if (self.report_errors and message.len != 0) std.debug.print("Error: {s}\n", .{message});
        return err;
    };
    if (current.subcommands.items.len > 0) {
        if (mode == .legacy) return error.MissingCommand; // silently nothing, as before
        return self.fail(ParseError.MissingCommand, "'{s}' needs a command", .{current.name});
    }
    return 0;
}

fn push(self: *Parser, command: *Command) !void {
    if (self.path_len == max_depth) {
        return self.fail(ParseError.CommandTooDeep, "Commands nested deeper than {d}", .{max_depth});
    }
    self.path_buffer[self.path_len] = command;
    self.path_len += 1;
}

/// Look `flag` up on the current command, then on each enclosing command.
fn findOption(self: *Parser, flag: []const u8) ?*const Option {
    var depth = self.path_len;
    while (depth > 0) {
        depth -= 1;
        if (self.path_buffer[depth].findOption(flag)) |opt| return opt;
    }
    return null;
}

fn jsonEnabled(self: *const Parser) bool {
    for (self.path()) |cmd| {
        if (cmd.json_output) return true;
    }
    return false;
}

fn fail(self: *Parser, err: ParseError, comptime fmt: []const u8, args: anytype) ParseError {
    const message = std.fmt.bufPrint(&self.diagnostic_buffer, fmt, args) catch blk: {
        const ellipsis = "...";
        @memcpy(self.diagnostic_buffer[self.diagnostic_buffer.len - ellipsis.len ..], ellipsis);
        break :blk self.diagnostic_buffer[0..];
    };
    self.diagnostic_len = message.len;
    if (self.report_errors) std.debug.print("Error: {s}\n", .{message});
    return err;
}

fn validateOptionValue(self: *Parser, option: Option, value: []const u8) !void {
    switch (option.option_type) {
        .string => {}, // Always valid
        .int => {
            _ = std.fmt.parseInt(i64, value, 10) catch {
                return self.fail(ParseError.InvalidOptionValue, "Option '--{s}' expects an integer value", .{option.long});
            };
        },
        .float => {
            _ = std.fmt.parseFloat(f64, value) catch {
                return self.fail(ParseError.InvalidOptionValue, "Option '--{s}' expects a float value", .{option.long});
            };
        },
        .bool => {}, // Already handled
    }
}
