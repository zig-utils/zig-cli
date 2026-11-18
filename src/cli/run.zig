//! `run`: parse, dispatch and report, returning the process exit code.

const std = @import("std");
const Command = @import("Command.zig");
const Parser = @import("Parser.zig");
const Help = @import("Help.zig");

pub const RunOptions = struct {
    /// Command output, help, and `ParseContext.writeJson`.
    stdout: *std.Io.Writer,
    /// Error reports.
    stderr: *std.Io.Writer,
    /// Shown in help headers.
    version: []const u8 = "",
};

/// Exit code for a command line that does not parse (unknown option or
/// command, missing value or argument), following the BSD `EX_USAGE` habit of
/// shells and most CLIs.
pub const exit_usage: u8 = 2;
/// Exit code when an action returns an error.
pub const exit_failure: u8 = 1;

/// Parse `args` (without the program name) against `root`, run the resolved
/// command and return the exit code for `main` to return:
///
/// - the action's own code (an action returning `!void` gives 0),
/// - 0 after printing help for `--help` / `-h`,
/// - `exit_usage` (2) when the command line does not parse, or names a command
///   group without one of its commands (its help goes to stderr),
/// - `exit_failure` (1) when the action returns an error.
///
/// With `--json` on the command line, errors are reported as one JSON object,
/// `{"error":{"kind":"UnknownOption","message":"..."}}`, on stderr.
/// Both writers are flushed before returning.
pub fn run(allocator: std.mem.Allocator, root: *Command, args: []const []const u8, options: RunOptions) u8 {
    defer options.stdout.flush() catch {};
    defer options.stderr.flush() catch {};

    var parser = Parser.init(allocator);
    parser.report_errors = false;
    parser.out = options.stdout;

    const code = parser.parse(root, args) catch |err| {
        const usage = isParseError(err);
        const message = if (parser.diagnostic().len > 0) parser.diagnostic() else @errorName(err);
        report(options.stderr, parser.json_requested, err, message) catch {};
        if (err == error.MissingCommand and !parser.json_requested) {
            Help.write(options.stderr, parser.path(), .{ .version = options.version }) catch {};
        }
        return if (usage) exit_usage else exit_failure;
    };

    if (parser.help_requested) {
        Help.write(options.stdout, parser.path(), .{ .version = options.version }) catch {};
        return 0;
    }
    return code;
}

fn isParseError(err: anyerror) bool {
    inline for (comptime @typeInfo(Parser.ParseError).error_set.error_names.?) |name| {
        if (err == @field(anyerror, name)) return true;
    }
    return false;
}

fn report(w: *std.Io.Writer, json: bool, err: anyerror, message: []const u8) !void {
    if (json) {
        try std.json.Stringify.value(.{ .@"error" = .{ .kind = @errorName(err), .message = message } }, .{}, w);
        try w.writeByte('\n');
    } else {
        try w.print("Error: {s}\n", .{message});
    }
}
