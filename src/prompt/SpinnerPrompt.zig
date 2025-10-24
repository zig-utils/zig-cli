const std = @import("std");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

const SpinnerPrompt = @This();

terminal: Terminal,
message: []const u8,
is_running: std.atomic.Value(bool),
thread: ?std.Thread,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, message: []const u8) SpinnerPrompt {
    return .{
        .terminal = Terminal.init(),
        .message = message,
        .is_running = std.atomic.Value(bool).init(false),
        .thread = null,
        .allocator = allocator,
    };
}

pub fn start(self: *SpinnerPrompt) !void {
    self.is_running.store(true, .monotonic);
    try self.terminal.hideCursor();

    // Start spinner in background thread
    self.thread = try std.Thread.spawn(.{}, spinnerLoop, .{self});
}

pub fn stop(self: *SpinnerPrompt, final_message: ?[]const u8) !void {
    self.is_running.store(false, .monotonic);

    if (self.thread) |thread| {
        thread.join();
        self.thread = null;
    }

    // Clear the spinner line
    try self.terminal.clearLine();

    // Show final message if provided
    if (final_message) |msg| {
        const symbols = Ansi.Symbols.forTerminal(self.terminal.supports_unicode);
        if (self.terminal.supports_color) {
            const check = try Ansi.green(self.allocator, symbols.checkmark);
            defer self.allocator.free(check);
            try self.terminal.write(check);
        } else {
            try self.terminal.write(symbols.checkmark);
        }
        try self.terminal.write(" ");
        try self.terminal.writeLine(msg);
    }

    try self.terminal.showCursor();
}

fn spinnerLoop(self: *SpinnerPrompt) void {
    const symbols = Ansi.Symbols.forTerminal(self.terminal.supports_unicode);
    var frame: usize = 0;

    while (self.is_running.load(.monotonic)) {
        const spinner_char = symbols.spinner[frame % symbols.spinner.len];

        // Render spinner
        self.terminal.clearLine() catch {};

        if (self.terminal.supports_color) {
            const colored = Ansi.cyan(self.allocator, spinner_char) catch spinner_char;
            defer if (colored.ptr != spinner_char.ptr) self.allocator.free(colored);
            self.terminal.write(colored) catch {};
        } else {
            self.terminal.write(spinner_char) catch {};
        }

        self.terminal.write(" ") catch {};
        self.terminal.write(self.message) catch {};

        // Sleep for animation frame
        std.time.sleep(80 * std.time.ns_per_ms);
        frame += 1;
    }
}

// Convenience function for spinner with task
pub fn withTask(allocator: std.mem.Allocator, message: []const u8, task: anytype) !void {
    var spinner = SpinnerPrompt.init(allocator, message);
    try spinner.start();

    const result = task() catch |err| {
        try spinner.stop(null);
        return err;
    };

    try spinner.stop(message);
    return result;
}
