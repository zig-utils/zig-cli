const std = @import("std");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

const ProgressBar = @This();

pub const ProgressBarStyle = enum {
    bar,        // [=====>    ]
    blocks,     // ████████░░░
    dots,       // ⣿⣿⣿⣿⣿⣀⣀⣀⣀⣀
    ascii,      // [###>      ]
};

terminal: Terminal,
allocator: std.mem.Allocator,
total: usize,
current: usize,
width: usize,
style: ProgressBarStyle,
label: []const u8,
show_percentage: bool,
show_count: bool,

pub fn init(allocator: std.mem.Allocator, total: usize, label: []const u8) ProgressBar {
    const terminal = Terminal.init();

    return .{
        .terminal = terminal,
        .allocator = allocator,
        .total = total,
        .current = 0,
        .width = @min(terminal.width -| 30, 50), // Leave room for label and stats
        .style = if (terminal.supports_unicode) .blocks else .ascii,
        .label = label,
        .show_percentage = true,
        .show_count = true,
    };
}

pub fn withStyle(self: ProgressBar, style: ProgressBarStyle) ProgressBar {
    var result = self;
    result.style = style;
    return result;
}

pub fn withWidth(self: ProgressBar, width: usize) ProgressBar {
    var result = self;
    result.width = width;
    return result;
}

pub fn start(self: *ProgressBar) !void {
    try self.terminal.hideCursor();
    try self.render();
}

pub fn increment(self: *ProgressBar) !void {
    self.current = @min(self.current + 1, self.total);
    try self.render();
}

pub fn update(self: *ProgressBar, current: usize) !void {
    self.current = @min(current, self.total);
    try self.render();
}

pub fn finish(self: *ProgressBar) !void {
    self.current = self.total;
    try self.render();
    try self.terminal.write("\n");
    try self.terminal.showCursor();
}

fn render(self: *ProgressBar) !void {
    try self.terminal.clearLine();

    // Label
    if (self.terminal.supports_color) {
        const colored_label = try Ansi.bold(self.allocator, self.label);
        defer self.allocator.free(colored_label);
        try self.terminal.write(colored_label);
    } else {
        try self.terminal.write(self.label);
    }
    try self.terminal.write(" ");

    // Progress bar
    const percentage = if (self.total > 0)
        @as(f64, @floatFromInt(self.current)) / @as(f64, @floatFromInt(self.total))
    else
        1.0;

    const filled = @as(usize, @intFromFloat(percentage * @as(f64, @floatFromInt(self.width))));

    switch (self.style) {
        .bar => try self.renderBar(filled),
        .blocks => try self.renderBlocks(filled),
        .dots => try self.renderDots(filled),
        .ascii => try self.renderAscii(filled),
    }

    // Stats
    if (self.show_percentage) {
        const pct = @as(usize, @intFromFloat(percentage * 100.0));
        var buf: [32]u8 = undefined;
        const pct_str = try std.fmt.bufPrint(&buf, " {d}%", .{pct});

        if (self.terminal.supports_color) {
            const colored = try Ansi.cyan(self.allocator, pct_str);
            defer self.allocator.free(colored);
            try self.terminal.write(colored);
        } else {
            try self.terminal.write(pct_str);
        }
    }

    if (self.show_count) {
        var buf: [64]u8 = undefined;
        const count_str = try std.fmt.bufPrint(&buf, " ({d}/{d})", .{ self.current, self.total });

        if (self.terminal.supports_color) {
            const colored = try Ansi.dim(self.allocator, count_str);
            defer self.allocator.free(colored);
            try self.terminal.write(colored);
        } else {
            try self.terminal.write(count_str);
        }
    }
}

fn renderBar(self: *ProgressBar, filled: usize) !void {
    try self.terminal.write("[");

    var i: usize = 0;
    while (i < self.width) : (i += 1) {
        if (i < filled) {
            if (i == filled - 1) {
                if (self.terminal.supports_color) {
                    const colored = try Ansi.green(self.allocator, ">");
                    defer self.allocator.free(colored);
                    try self.terminal.write(colored);
                } else {
                    try self.terminal.write(">");
                }
            } else {
                if (self.terminal.supports_color) {
                    const colored = try Ansi.green(self.allocator, "=");
                    defer self.allocator.free(colored);
                    try self.terminal.write(colored);
                } else {
                    try self.terminal.write("=");
                }
            }
        } else {
            try self.terminal.write(" ");
        }
    }

    try self.terminal.write("]");
}

fn renderBlocks(self: *ProgressBar, filled: usize) !void {
    var i: usize = 0;
    while (i < self.width) : (i += 1) {
        const block = if (i < filled) "█" else "░";

        if (i < filled and self.terminal.supports_color) {
            const colored = try Ansi.green(self.allocator, block);
            defer self.allocator.free(colored);
            try self.terminal.write(colored);
        } else {
            try self.terminal.write(block);
        }
    }
}

fn renderDots(self: *ProgressBar, filled: usize) !void {
    var i: usize = 0;
    while (i < self.width) : (i += 1) {
        const dot = if (i < filled) "⣿" else "⣀";

        if (i < filled and self.terminal.supports_color) {
            const colored = try Ansi.green(self.allocator, dot);
            defer self.allocator.free(colored);
            try self.terminal.write(colored);
        } else {
            try self.terminal.write(dot);
        }
    }
}

fn renderAscii(self: *ProgressBar, filled: usize) !void {
    try self.terminal.write("[");

    var i: usize = 0;
    while (i < self.width) : (i += 1) {
        if (i < filled) {
            if (i == filled - 1) {
                try self.terminal.write(">");
            } else {
                try self.terminal.write("#");
            }
        } else {
            try self.terminal.write(" ");
        }
    }

    try self.terminal.write("]");
}

/// Convenience function for quick progress tracking
pub fn withProgress(
    allocator: std.mem.Allocator,
    total: usize,
    label: []const u8,
    task: *const fn (progress: *ProgressBar) anyerror!void,
) !void {
    var progress = ProgressBar.init(allocator, total, label);
    try progress.start();
    defer progress.finish() catch {};

    try task(&progress);
}
