const std = @import("std");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

/// Simple message output utilities for CLI
pub const Message = struct {
    terminal: Terminal,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Message {
        return .{
            .terminal = Terminal.init(),
            .allocator = allocator,
        };
    }

    /// Display an introductory message
    pub fn intro(self: *Message, title: []const u8) !void {
        const symbols = Ansi.Symbols.forTerminal(self.terminal.supports_unicode);

        try self.terminal.write("\n");
        if (self.terminal.supports_color) {
            const colored_title = try Ansi.colorizeStyle(self.allocator, title, .cyan, .bold);
            defer self.allocator.free(colored_title);
            try self.terminal.writeLine(colored_title);
        } else {
            try self.terminal.writeLine(title);
        }

        // Draw a line
        const width = 50; // Could be terminal width
        var i: usize = 0;
        while (i < width) : (i += 1) {
            try self.terminal.write(symbols.line);
        }
        try self.terminal.write("\n\n");
    }

    /// Display a closing message
    pub fn outro(self: *Message, message: []const u8) !void {
        const symbols = Ansi.Symbols.forTerminal(self.terminal.supports_unicode);

        try self.terminal.write("\n");
        if (self.terminal.supports_color) {
            const check = try Ansi.green(self.allocator, symbols.checkmark);
            defer self.allocator.free(check);
            try self.terminal.write(check);
        } else {
            try self.terminal.write(symbols.checkmark);
        }

        try self.terminal.write(" ");

        if (self.terminal.supports_color) {
            const colored_msg = try Ansi.green(self.allocator, message);
            defer self.allocator.free(colored_msg);
            try self.terminal.writeLine(colored_msg);
        } else {
            try self.terminal.writeLine(message);
        }
        try self.terminal.write("\n");
    }

    /// Display a note/info message
    pub fn note(self: *Message, message: []const u8, note_text: ?[]const u8) !void {
        if (self.terminal.supports_color) {
            const colored_msg = try Ansi.bold(self.allocator, message);
            defer self.allocator.free(colored_msg);
            try self.terminal.write(colored_msg);
        } else {
            try self.terminal.write(message);
        }

        if (note_text) |text| {
            try self.terminal.write(" ");
            if (self.terminal.supports_color) {
                const dimmed = try Ansi.dim(self.allocator, text);
                defer self.allocator.free(dimmed);
                try self.terminal.write(dimmed);
            } else {
                try self.terminal.write(text);
            }
        }

        try self.terminal.write("\n");
    }

    /// Display a log message with optional prefix
    pub fn log(self: *Message, level: LogLevel, message: []const u8) !void {
        const symbols = Ansi.Symbols.forTerminal(self.terminal.supports_unicode);

        const prefix = switch (level) {
            .info => "ℹ",
            .success => symbols.checkmark,
            .warning => "⚠",
            .error_level => symbols.cross,
        };

        const color: Ansi.Color = switch (level) {
            .info => .cyan,
            .success => .green,
            .warning => .yellow,
            .error_level => .red,
        };

        if (self.terminal.supports_color) {
            const colored_prefix = try Ansi.colorize(self.allocator, prefix, color);
            defer self.allocator.free(colored_prefix);
            try self.terminal.write(colored_prefix);
        } else {
            try self.terminal.write(prefix);
        }

        try self.terminal.write(" ");
        try self.terminal.writeLine(message);
    }

    /// Display a cancel message
    pub fn cancel(self: *Message, message: []const u8) !void {
        const symbols = Ansi.Symbols.forTerminal(self.terminal.supports_unicode);

        if (self.terminal.supports_color) {
            const cross = try Ansi.red(self.allocator, symbols.cross);
            defer self.allocator.free(cross);
            try self.terminal.write(cross);
        } else {
            try self.terminal.write(symbols.cross);
        }

        try self.terminal.write(" ");

        if (self.terminal.supports_color) {
            const colored_msg = try Ansi.red(self.allocator, message);
            defer self.allocator.free(colored_msg);
            try self.terminal.writeLine(colored_msg);
        } else {
            try self.terminal.writeLine(message);
        }
    }

    pub const LogLevel = enum {
        info,
        success,
        warning,
        error_level,
    };
};

// Convenience functions
pub fn intro(allocator: std.mem.Allocator, title: []const u8) !void {
    var msg = Message.init(allocator);
    try msg.intro(title);
}

pub fn outro(allocator: std.mem.Allocator, message: []const u8) !void {
    var msg = Message.init(allocator);
    try msg.outro(message);
}

pub fn note(allocator: std.mem.Allocator, message: []const u8, note_text: ?[]const u8) !void {
    var msg = Message.init(allocator);
    try msg.note(message, note_text);
}

pub fn log(allocator: std.mem.Allocator, level: Message.LogLevel, message: []const u8) !void {
    var msg = Message.init(allocator);
    try msg.log(level, message);
}

pub fn cancel(allocator: std.mem.Allocator, message: []const u8) !void {
    var msg = Message.init(allocator);
    try msg.cancel(message);
}
