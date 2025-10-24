const std = @import("std");
const Ansi = @import("Ansi.zig");

/// Chainable style builder for composable ANSI styling
pub const Style = struct {
    allocator: std.mem.Allocator,
    text: []const u8,
    owned: bool,
    color: ?Ansi.Color = null,
    bg_color: ?Ansi.Color = null,
    bold_enabled: bool = false,
    dim_enabled: bool = false,
    italic_enabled: bool = false,
    underline_enabled: bool = false,

    pub fn init(allocator: std.mem.Allocator, text: []const u8) Style {
        return .{
            .allocator = allocator,
            .text = text,
            .owned = false,
        };
    }

    pub fn deinit(self: *Style) void {
        if (self.owned) {
            self.allocator.free(self.text);
        }
    }

    // Color methods
    pub fn black(self: Style) Style {
        return self.withColor(.black);
    }

    pub fn red(self: Style) Style {
        return self.withColor(.red);
    }

    pub fn green(self: Style) Style {
        return self.withColor(.green);
    }

    pub fn yellow(self: Style) Style {
        return self.withColor(.yellow);
    }

    pub fn blue(self: Style) Style {
        return self.withColor(.blue);
    }

    pub fn magenta(self: Style) Style {
        return self.withColor(.magenta);
    }

    pub fn cyan(self: Style) Style {
        return self.withColor(.cyan);
    }

    pub fn white(self: Style) Style {
        return self.withColor(.white);
    }

    pub fn brightBlack(self: Style) Style {
        return self.withColor(.bright_black);
    }

    pub fn brightRed(self: Style) Style {
        return self.withColor(.bright_red);
    }

    pub fn brightGreen(self: Style) Style {
        return self.withColor(.bright_green);
    }

    pub fn brightYellow(self: Style) Style {
        return self.withColor(.bright_yellow);
    }

    pub fn brightBlue(self: Style) Style {
        return self.withColor(.bright_blue);
    }

    pub fn brightMagenta(self: Style) Style {
        return self.withColor(.bright_magenta);
    }

    pub fn brightCyan(self: Style) Style {
        return self.withColor(.bright_cyan);
    }

    pub fn brightWhite(self: Style) Style {
        return self.withColor(.bright_white);
    }

    // Background color methods
    pub fn bgBlack(self: Style) Style {
        return self.withBgColor(.black);
    }

    pub fn bgRed(self: Style) Style {
        return self.withBgColor(.red);
    }

    pub fn bgGreen(self: Style) Style {
        return self.withBgColor(.green);
    }

    pub fn bgYellow(self: Style) Style {
        return self.withBgColor(.yellow);
    }

    pub fn bgBlue(self: Style) Style {
        return self.withBgColor(.blue);
    }

    pub fn bgMagenta(self: Style) Style {
        return self.withBgColor(.magenta);
    }

    pub fn bgCyan(self: Style) Style {
        return self.withBgColor(.cyan);
    }

    pub fn bgWhite(self: Style) Style {
        return self.withBgColor(.white);
    }

    // Style methods
    pub fn bold(self: Style) Style {
        var result = self;
        result.bold_enabled = true;
        return result;
    }

    pub fn dim(self: Style) Style {
        var result = self;
        result.dim_enabled = true;
        return result;
    }

    pub fn italic(self: Style) Style {
        var result = self;
        result.italic_enabled = true;
        return result;
    }

    pub fn underline(self: Style) Style {
        var result = self;
        result.underline_enabled = true;
        return result;
    }

    // Internal helpers
    fn withColor(self: Style, color: Ansi.Color) Style {
        var result = self;
        result.color = color;
        return result;
    }

    fn withBgColor(self: Style, color: Ansi.Color) Style {
        var result = self;
        result.bg_color = color;
        return result;
    }

    /// Render the styled text
    pub fn render(self: *Style) ![]u8 {
        // If no styles applied, return original text
        if (self.color == null and self.bg_color == null and
            !self.bold_enabled and !self.dim_enabled and
            !self.italic_enabled and !self.underline_enabled)
        {
            return try self.allocator.dupe(u8, self.text);
        }

        // Build ANSI code sequence
        var codes = std.ArrayList(u8).init(self.allocator);
        defer codes.deinit();

        var first = true;

        // Styles
        if (self.bold_enabled) {
            if (!first) try codes.append(';');
            try codes.writer().print("{d}", .{Ansi.Style.bold.toCode()});
            first = false;
        }

        if (self.dim_enabled) {
            if (!first) try codes.append(';');
            try codes.writer().print("{d}", .{Ansi.Style.dim.toCode()});
            first = false;
        }

        if (self.italic_enabled) {
            if (!first) try codes.append(';');
            try codes.writer().print("{d}", .{Ansi.Style.italic.toCode()});
            first = false;
        }

        if (self.underline_enabled) {
            if (!first) try codes.append(';');
            try codes.writer().print("{d}", .{Ansi.Style.underline.toCode()});
            first = false;
        }

        // Foreground color
        if (self.color) |color| {
            if (!first) try codes.append(';');
            try codes.writer().print("{d}", .{color.toCode()});
            first = false;
        }

        // Background color
        if (self.bg_color) |bg| {
            if (!first) try codes.append(';');
            try codes.writer().print("{d}", .{bg.toCode() + 10}); // BG is FG + 10
            first = false;
        }

        // Build final string
        return try std.fmt.allocPrint(
            self.allocator,
            "\x1b[{s}m{s}\x1b[0m",
            .{ codes.items, self.text },
        );
    }

    /// Convenience method to render and print
    pub fn print(self: *Style) !void {
        const styled = try self.render();
        defer self.allocator.free(styled);

        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}", .{styled});
    }

    /// Convenience method to render and return with newline
    pub fn println(self: *Style) !void {
        const styled = try self.render();
        defer self.allocator.free(styled);

        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}\n", .{styled});
    }
};

/// Quick style function
pub fn style(allocator: std.mem.Allocator, text: []const u8) Style {
    return Style.init(allocator, text);
}
