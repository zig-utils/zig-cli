const std = @import("std");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

pub const BoxStyle = enum {
    single,
    double,
    rounded,
    ascii,

    pub fn chars(self: BoxStyle) BoxChars {
        return switch (self) {
            .single => BoxChars{
                .top_left = "┌",
                .top_right = "┐",
                .bottom_left = "└",
                .bottom_right = "┘",
                .horizontal = "─",
                .vertical = "│",
            },
            .double => BoxChars{
                .top_left = "╔",
                .top_right = "╗",
                .bottom_left = "╚",
                .bottom_right = "╝",
                .horizontal = "═",
                .vertical = "║",
            },
            .rounded => BoxChars{
                .top_left = "╭",
                .top_right = "╮",
                .bottom_left = "╰",
                .bottom_right = "╯",
                .horizontal = "─",
                .vertical = "│",
            },
            .ascii => BoxChars{
                .top_left = "+",
                .top_right = "+",
                .bottom_left = "+",
                .bottom_right = "+",
                .horizontal = "-",
                .vertical = "|",
            },
        };
    }
};

pub const BoxChars = struct {
    top_left: []const u8,
    top_right: []const u8,
    bottom_left: []const u8,
    bottom_right: []const u8,
    horizontal: []const u8,
    vertical: []const u8,
};

pub const Box = struct {
    allocator: std.mem.Allocator,
    terminal: Terminal,
    style: BoxStyle,
    padding: usize,

    pub fn init(allocator: std.mem.Allocator) Box {
        const terminal = Terminal.init();
        const style = if (terminal.supports_unicode) .rounded else .ascii;

        return .{
            .allocator = allocator,
            .terminal = terminal,
            .style = style,
            .padding = 1,
        };
    }

    pub fn withStyle(self: Box, style: BoxStyle) Box {
        var result = self;
        result.style = style;
        return result;
    }

    pub fn withPadding(self: Box, padding: usize) Box {
        var result = self;
        result.padding = padding;
        return result;
    }

    pub fn render(self: *Box, title: ?[]const u8, content: []const u8) !void {
        const chars = self.style.chars();
        const lines = try self.splitLines(content);
        defer self.allocator.free(lines);

        // Calculate dimensions
        var max_width: usize = 0;
        for (lines) |line| {
            if (line.len > max_width) max_width = line.len;
        }

        if (title) |t| {
            if (t.len + 2 > max_width) max_width = t.len + 2;
        }

        const inner_width = max_width + (self.padding * 2);

        // Top border
        try self.terminal.write(chars.top_left);
        if (title) |t| {
            try self.terminal.write(" ");
            if (self.terminal.supports_color) {
                const colored = try Ansi.bold(self.allocator, t);
                defer self.allocator.free(colored);
                try self.terminal.write(colored);
            } else {
                try self.terminal.write(t);
            }
            try self.terminal.write(" ");

            const remaining = inner_width -| (t.len + 2);
            var i: usize = 0;
            while (i < remaining) : (i += 1) {
                try self.terminal.write(chars.horizontal);
            }
        } else {
            var i: usize = 0;
            while (i < inner_width) : (i += 1) {
                try self.terminal.write(chars.horizontal);
            }
        }
        try self.terminal.write(chars.top_right);
        try self.terminal.write("\n");

        // Content lines
        for (lines) |line| {
            try self.terminal.write(chars.vertical);

            // Left padding
            var i: usize = 0;
            while (i < self.padding) : (i += 1) {
                try self.terminal.write(" ");
            }

            try self.terminal.write(line);

            // Right padding
            const right_pad = inner_width -| (line.len + self.padding);
            i = 0;
            while (i < right_pad) : (i += 1) {
                try self.terminal.write(" ");
            }

            try self.terminal.write(chars.vertical);
            try self.terminal.write("\n");
        }

        // Bottom border
        try self.terminal.write(chars.bottom_left);
        var i: usize = 0;
        while (i < inner_width) : (i += 1) {
            try self.terminal.write(chars.horizontal);
        }
        try self.terminal.write(chars.bottom_right);
        try self.terminal.write("\n");
    }

    fn splitLines(self: *Box, content: []const u8) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(self.allocator);
        errdefer list.deinit();

        var iter = std.mem.splitScalar(u8, content, '\n');
        while (iter.next()) |line| {
            try list.append(line);
        }

        return list.toOwnedSlice();
    }
};

// Convenience function
pub fn render(allocator: std.mem.Allocator, title: ?[]const u8, content: []const u8) !void {
    var box = Box.init(allocator);
    try box.render(title, content);
}
