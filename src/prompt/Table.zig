const std = @import("std");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

const Table = @This();

pub const Alignment = enum {
    left,
    center,
    right,
};

pub const TableStyle = enum {
    simple,     // Simple ASCII
    rounded,    // Rounded corners
    double,     // Double lines
    minimal,    // Minimal borders
};

pub const Column = struct {
    header: []const u8,
    alignment: Alignment = .left,
    width: ?usize = null, // Auto-calculate if null
};

allocator: std.mem.Allocator,
terminal: Terminal,
columns: []const Column,
rows: std.ArrayList([]const []const u8),
style: TableStyle,
show_header: bool,

pub fn init(allocator: std.mem.Allocator, columns: []const Column) Table {
    const terminal = Terminal.init();

    return .{
        .allocator = allocator,
        .terminal = terminal,
        .columns = columns,
        .rows = std.ArrayList([]const []const u8).init(allocator),
        .style = if (terminal.supports_unicode) .rounded else .simple,
        .show_header = true,
    };
}

pub fn deinit(self: *Table) void {
    for (self.rows.items) |row| {
        self.allocator.free(row);
    }
    self.rows.deinit();
}

pub fn withStyle(self: Table, style: TableStyle) Table {
    var result = self;
    result.style = style;
    return result;
}

pub fn addRow(self: *Table, row: []const []const u8) !void {
    if (row.len != self.columns.len) {
        return error.ColumnCountMismatch;
    }

    const row_copy = try self.allocator.dupe([]const u8, row);
    try self.rows.append(row_copy);
}

pub fn render(self: *Table) !void {
    // Calculate column widths
    var widths = try self.allocator.alloc(usize, self.columns.len);
    defer self.allocator.free(widths);

    for (self.columns, 0..) |col, i| {
        if (col.width) |w| {
            widths[i] = w;
        } else {
            widths[i] = col.header.len;
            for (self.rows.items) |row| {
                if (row[i].len > widths[i]) {
                    widths[i] = row[i].len;
                }
            }
        }
    }

    const borders = self.getBorders();

    // Top border
    if (self.style != .minimal) {
        try self.renderBorder(widths, borders.top_left, borders.top_mid, borders.top_right, borders.horizontal);
    }

    // Header
    if (self.show_header) {
        try self.renderRow(self.columns, widths, true);

        // Header separator
        if (self.style == .minimal) {
            try self.renderSeparator(widths, borders.horizontal);
        } else {
            try self.renderBorder(widths, borders.mid_left, borders.mid_mid, borders.mid_right, borders.horizontal);
        }
    }

    // Data rows
    for (self.rows.items) |row| {
        try self.renderDataRow(row, widths);
    }

    // Bottom border
    if (self.style != .minimal) {
        try self.renderBorder(widths, borders.bottom_left, borders.bottom_mid, borders.bottom_right, borders.horizontal);
    }
}

const BorderChars = struct {
    top_left: []const u8,
    top_mid: []const u8,
    top_right: []const u8,
    mid_left: []const u8,
    mid_mid: []const u8,
    mid_right: []const u8,
    bottom_left: []const u8,
    bottom_mid: []const u8,
    bottom_right: []const u8,
    horizontal: []const u8,
    vertical: []const u8,
};

fn getBorders(self: *Table) BorderChars {
    return switch (self.style) {
        .simple => .{
            .top_left = "+",
            .top_mid = "+",
            .top_right = "+",
            .mid_left = "+",
            .mid_mid = "+",
            .mid_right = "+",
            .bottom_left = "+",
            .bottom_mid = "+",
            .bottom_right = "+",
            .horizontal = "-",
            .vertical = "|",
        },
        .rounded => .{
            .top_left = "╭",
            .top_mid = "┬",
            .top_right = "╮",
            .mid_left = "├",
            .mid_mid = "┼",
            .mid_right = "┤",
            .bottom_left = "╰",
            .bottom_mid = "┴",
            .bottom_right = "╯",
            .horizontal = "─",
            .vertical = "│",
        },
        .double => .{
            .top_left = "╔",
            .top_mid = "╦",
            .top_right = "╗",
            .mid_left = "╠",
            .mid_mid = "╬",
            .mid_right = "╣",
            .bottom_left = "╚",
            .bottom_mid = "╩",
            .bottom_right = "╝",
            .horizontal = "═",
            .vertical = "║",
        },
        .minimal => .{
            .top_left = "",
            .top_mid = "",
            .top_right = "",
            .mid_left = "",
            .mid_mid = " ",
            .mid_right = "",
            .bottom_left = "",
            .bottom_mid = "",
            .bottom_right = "",
            .horizontal = "-",
            .vertical = " ",
        },
    };
}

fn renderBorder(self: *Table, widths: []const usize, left: []const u8, mid: []const u8, right: []const u8, horiz: []const u8) !void {
    try self.terminal.write(left);

    for (widths, 0..) |width, i| {
        var j: usize = 0;
        while (j < width + 2) : (j += 1) {
            try self.terminal.write(horiz);
        }

        if (i < widths.len - 1) {
            try self.terminal.write(mid);
        }
    }

    try self.terminal.write(right);
    try self.terminal.write("\n");
}

fn renderSeparator(self: *Table, widths: []const usize, horiz: []const u8) !void {
    for (widths, 0..) |width, i| {
        var j: usize = 0;
        while (j < width) : (j += 1) {
            try self.terminal.write(horiz);
        }

        if (i < widths.len - 1) {
            try self.terminal.write("   ");
        }
    }
    try self.terminal.write("\n");
}

fn renderRow(self: *Table, columns: []const Column, widths: []const usize, is_header: bool) !void {
    const borders = self.getBorders();

    if (self.style != .minimal) {
        try self.terminal.write(borders.vertical);
        try self.terminal.write(" ");
    }

    for (columns, 0..) |col, i| {
        const text = col.header;
        const width = widths[i];

        const padded = try self.padText(text, width, col.alignment);
        defer self.allocator.free(padded);

        if (is_header and self.terminal.supports_color) {
            const colored = try Ansi.bold(self.allocator, padded);
            defer self.allocator.free(colored);
            try self.terminal.write(colored);
        } else {
            try self.terminal.write(padded);
        }

        if (self.style != .minimal) {
            try self.terminal.write(" ");
            try self.terminal.write(borders.vertical);
            if (i < columns.len - 1) {
                try self.terminal.write(" ");
            }
        } else {
            if (i < columns.len - 1) {
                try self.terminal.write("   ");
            }
        }
    }

    try self.terminal.write("\n");
}

fn renderDataRow(self: *Table, row: []const []const u8, widths: []const usize) !void {
    const borders = self.getBorders();

    if (self.style != .minimal) {
        try self.terminal.write(borders.vertical);
        try self.terminal.write(" ");
    }

    for (row, 0..) |cell, i| {
        const width = widths[i];
        const alignment = self.columns[i].alignment;

        const padded = try self.padText(cell, width, alignment);
        defer self.allocator.free(padded);

        try self.terminal.write(padded);

        if (self.style != .minimal) {
            try self.terminal.write(" ");
            try self.terminal.write(borders.vertical);
            if (i < row.len - 1) {
                try self.terminal.write(" ");
            }
        } else {
            if (i < row.len - 1) {
                try self.terminal.write("   ");
            }
        }
    }

    try self.terminal.write("\n");
}

fn padText(self: *Table, text: []const u8, width: usize, alignment: Alignment) ![]u8 {
    if (text.len >= width) {
        return try self.allocator.dupe(u8, text[0..width]);
    }

    const padding = width - text.len;
    var result = try self.allocator.alloc(u8, width);

    switch (alignment) {
        .left => {
            @memcpy(result[0..text.len], text);
            @memset(result[text.len..], ' ');
        },
        .right => {
            @memset(result[0..padding], ' ');
            @memcpy(result[padding..], text);
        },
        .center => {
            const left_pad = padding / 2;
            @memset(result[0..left_pad], ' ');
            @memcpy(result[left_pad .. left_pad + text.len], text);
            @memset(result[left_pad + text.len ..], ' ');
        },
    }

    return result;
}
