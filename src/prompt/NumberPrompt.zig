const std = @import("std");
const PromptCore = @import("PromptCore.zig");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

const NumberPrompt = @This();

pub const NumberType = enum {
    integer,
    float,
};

core: PromptCore,
message: []const u8,
number_type: NumberType,
min: ?f64,
max: ?f64,
default_value: ?f64,
validate: ?ValidateFn,

pub const ValidateFn = *const fn (value: f64) ?[]const u8;

pub fn init(allocator: std.mem.Allocator, message: []const u8, number_type: NumberType) NumberPrompt {
    return .{
        .core = PromptCore.init(allocator),
        .message = message,
        .number_type = number_type,
        .min = null,
        .max = null,
        .default_value = null,
        .validate = null,
    };
}

pub fn deinit(self: *NumberPrompt) void {
    self.core.deinit();
}

pub fn withMin(self: *NumberPrompt, min: f64) *NumberPrompt {
    self.min = min;
    return self;
}

pub fn withMax(self: *NumberPrompt, max: f64) *NumberPrompt {
    self.max = max;
    return self;
}

pub fn withRange(self: *NumberPrompt, min: f64, max: f64) *NumberPrompt {
    self.min = min;
    self.max = max;
    return self;
}

pub fn withDefault(self: *NumberPrompt, default: f64) *NumberPrompt {
    self.default_value = default;
    return self;
}

pub fn withValidation(self: *NumberPrompt, validate_fn: ValidateFn) *NumberPrompt {
    self.validate = validate_fn;
    return self;
}

pub fn prompt(self: *NumberPrompt) !f64 {
    try self.core.start();

    if (self.default_value) |default| {
        const default_str = if (self.number_type == .integer)
            try std.fmt.allocPrint(self.core.allocator, "{d}", .{@as(i64, @intFromFloat(default))})
        else
            try std.fmt.allocPrint(self.core.allocator, "{d}", .{default});
        defer self.core.allocator.free(default_str);

        try self.core.setValue(default_str);
    }

    while (!self.core.isFinished()) {
        try self.render();

        if (self.core.terminal.readKey()) |key_opt| {
            if (key_opt) |key| {
                try self.handleKey(key);
            }
        } else |_| {
            continue;
        }

        std.time.sleep(10 * std.time.ns_per_ms);
    }

    try self.core.finish();

    if (self.core.isCanceled()) {
        return error.Canceled;
    }

    const value_str = self.core.getValue();
    return try self.parseNumber(value_str);
}

fn handleKey(self: *NumberPrompt, key: Terminal.KeyPress) !void {
    switch (key.key) {
        .enter => {
            const value_str = self.core.getValue();

            if (value_str.len == 0 and self.default_value != null) {
                self.core.transitionTo(.submit);
                return;
            }

            // Try to parse and validate
            const number = self.parseNumber(value_str) catch {
                self.core.setError("Invalid number format");
                return;
            };

            // Check min/max
            if (self.min) |min| {
                if (number < min) {
                    const err = try std.fmt.allocPrint(
                        self.core.allocator,
                        "Number must be at least {d}",
                        .{min},
                    );
                    defer self.core.allocator.free(err);
                    self.core.setError(err);
                    return;
                }
            }

            if (self.max) |max| {
                if (number > max) {
                    const err = try std.fmt.allocPrint(
                        self.core.allocator,
                        "Number must be at most {d}",
                        .{max},
                    );
                    defer self.core.allocator.free(err);
                    self.core.setError(err);
                    return;
                }
            }

            // Custom validation
            if (self.validate) |validate_fn| {
                if (validate_fn(number)) |err_msg| {
                    self.core.setError(err_msg);
                    return;
                }
            }

            self.core.clearError();
            self.core.transitionTo(.submit);
        },
        .ctrl_c, .escape => {
            self.core.transitionTo(.cancel);
        },
        .backspace => {
            self.core.deleteChar();
            self.core.clearError();
        },
        .delete => {
            self.core.deleteCharForward();
            self.core.clearError();
        },
        .left => {
            self.core.moveCursorLeft();
        },
        .right => {
            self.core.moveCursorRight();
        },
        .home => {
            self.core.moveCursorHome();
        },
        .end => {
            self.core.moveCursorEnd();
        },
        .char => {
            if (key.char) |c| {
                // Only allow numeric characters, decimal point, minus sign
                if (std.ascii.isDigit(c) or c == '.' or c == '-') {
                    try self.core.appendChar(c);
                    self.core.clearError();
                }
            }
        },
        else => {},
    }
}

fn parseNumber(self: *NumberPrompt, value_str: []const u8) !f64 {
    if (value_str.len == 0 and self.default_value != null) {
        return self.default_value.?;
    }

    return switch (self.number_type) {
        .integer => blk: {
            const int_val = try std.fmt.parseInt(i64, value_str, 10);
            break :blk @floatFromInt(int_val);
        },
        .float => try std.fmt.parseFloat(f64, value_str),
    };
}

fn render(self: *NumberPrompt) !void {
    try self.core.terminal.clearLine();

    const symbols = Ansi.Symbols.forTerminal(self.core.terminal.supports_unicode);

    // Render prompt message
    if (self.core.terminal.supports_color) {
        const colored_msg = try Ansi.bold(self.core.allocator, self.message);
        defer self.core.allocator.free(colored_msg);
        try self.core.terminal.write(colored_msg);
    } else {
        try self.core.terminal.write(self.message);
    }

    // Show range hint
    if (self.min != null or self.max != null) {
        var hint_buf: [128]u8 = undefined;
        const hint = if (self.min != null and self.max != null)
            try std.fmt.bufPrint(&hint_buf, " ({d}-{d})", .{ self.min.?, self.max.? })
        else if (self.min != null)
            try std.fmt.bufPrint(&hint_buf, " (min: {d})", .{self.min.?})
        else
            try std.fmt.bufPrint(&hint_buf, " (max: {d})", .{self.max.?});

        if (self.core.terminal.supports_color) {
            const colored_hint = try Ansi.dim(self.core.allocator, hint);
            defer self.core.allocator.free(colored_hint);
            try self.core.terminal.write(colored_hint);
        } else {
            try self.core.terminal.write(hint);
        }
    }

    try self.core.terminal.write(" ");

    // Render value
    const value = self.core.getValue();
    if (value.len > 0) {
        try self.core.terminal.write(value);
    } else if (self.default_value) |default| {
        const default_str = if (self.number_type == .integer)
            try std.fmt.allocPrint(self.core.allocator, "{d}", .{@as(i64, @intFromFloat(default))})
        else
            try std.fmt.allocPrint(self.core.allocator, "{d}", .{default});
        defer self.core.allocator.free(default_str);

        if (self.core.terminal.supports_color) {
            const colored_default = try Ansi.dim(self.core.allocator, default_str);
            defer self.core.allocator.free(colored_default);
            try self.core.terminal.write(colored_default);
        } else {
            try self.core.terminal.write(default_str);
        }
    }

    // Render error message if present
    if (self.core.error_message) |err_msg| {
        try self.core.terminal.write("\n");
        if (self.core.terminal.supports_color) {
            const colored_err = try Ansi.red(self.core.allocator, err_msg);
            defer self.core.allocator.free(colored_err);
            try self.core.terminal.write(symbols.cross);
            try self.core.terminal.write(" ");
            try self.core.terminal.write(colored_err);
        } else {
            try self.core.terminal.write("Error: ");
            try self.core.terminal.write(err_msg);
        }
        try self.core.terminal.write("\r");
    }
}
