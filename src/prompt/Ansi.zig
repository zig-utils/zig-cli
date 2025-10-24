const std = @import("std");

pub const Color = enum {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,

    pub fn toCode(self: Color) u8 {
        return switch (self) {
            .black => 30,
            .red => 31,
            .green => 32,
            .yellow => 33,
            .blue => 34,
            .magenta => 35,
            .cyan => 36,
            .white => 37,
            .bright_black => 90,
            .bright_red => 91,
            .bright_green => 92,
            .bright_yellow => 93,
            .bright_blue => 94,
            .bright_magenta => 95,
            .bright_cyan => 96,
            .bright_white => 97,
        };
    }
};

pub const Style = enum {
    reset,
    bold,
    dim,
    italic,
    underline,

    pub fn toCode(self: Style) u8 {
        return switch (self) {
            .reset => 0,
            .bold => 1,
            .dim => 2,
            .italic => 3,
            .underline => 4,
        };
    }
};

pub fn colorize(allocator: std.mem.Allocator, text: []const u8, color: Color) ![]u8 {
    return std.fmt.allocPrint(allocator, "\x1b[{d}m{s}\x1b[0m", .{ color.toCode(), text });
}

pub fn style(allocator: std.mem.Allocator, text: []const u8, s: Style) ![]u8 {
    return std.fmt.allocPrint(allocator, "\x1b[{d}m{s}\x1b[0m", .{ s.toCode(), text });
}

pub fn colorizeStyle(allocator: std.mem.Allocator, text: []const u8, color: Color, s: Style) ![]u8 {
    return std.fmt.allocPrint(allocator, "\x1b[{d};{d}m{s}\x1b[0m", .{ s.toCode(), color.toCode(), text });
}

// Pre-built common styles
pub fn bold(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return style(allocator, text, .bold);
}

pub fn dim(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return style(allocator, text, .dim);
}

pub fn green(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return colorize(allocator, text, .green);
}

pub fn red(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return colorize(allocator, text, .red);
}

pub fn yellow(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return colorize(allocator, text, .yellow);
}

pub fn blue(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return colorize(allocator, text, .blue);
}

pub fn cyan(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return colorize(allocator, text, .cyan);
}

// Symbols with Unicode/ASCII fallback
pub const Symbols = struct {
    checkmark: []const u8,
    cross: []const u8,
    arrow_right: []const u8,
    arrow_left: []const u8,
    arrow_up: []const u8,
    arrow_down: []const u8,
    radio_on: []const u8,
    radio_off: []const u8,
    checkbox_on: []const u8,
    checkbox_off: []const u8,
    pointer: []const u8,
    line: []const u8,
    spinner: []const []const u8,

    pub fn unicode() Symbols {
        return .{
            .checkmark = "✔",
            .cross = "✖",
            .arrow_right = "→",
            .arrow_left = "←",
            .arrow_up = "↑",
            .arrow_down = "↓",
            .radio_on = "◉",
            .radio_off = "◯",
            .checkbox_on = "☑",
            .checkbox_off = "☐",
            .pointer = "❯",
            .line = "─",
            .spinner = &[_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
        };
    }

    pub fn ascii() Symbols {
        return .{
            .checkmark = "[x]",
            .cross = "[!]",
            .arrow_right = "->",
            .arrow_left = "<-",
            .arrow_up = "^",
            .arrow_down = "v",
            .radio_on = "(*)",
            .radio_off = "( )",
            .checkbox_on = "[x]",
            .checkbox_off = "[ ]",
            .pointer = ">",
            .line = "-",
            .spinner = &[_][]const u8{ "|", "/", "-", "\\", "|", "/", "-", "\\" },
        };
    }

    pub fn forTerminal(supports_unicode: bool) Symbols {
        return if (supports_unicode) unicode() else ascii();
    }
};
