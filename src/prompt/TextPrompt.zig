const std = @import("std");
const PromptCore = @import("PromptCore.zig");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

const TextPrompt = @This();

core: PromptCore,
message: []const u8,
default_value: ?[]const u8,
placeholder: ?[]const u8,
validate: ?ValidateFn,

pub const ValidateFn = *const fn (value: []const u8) ?[]const u8;

pub fn init(allocator: std.mem.Allocator, message: []const u8) TextPrompt {
    return .{
        .core = PromptCore.init(allocator),
        .message = message,
        .default_value = null,
        .placeholder = null,
        .validate = null,
    };
}

pub fn deinit(self: *TextPrompt) void {
    self.core.deinit();
}

pub fn withDefault(self: *TextPrompt, default: []const u8) *TextPrompt {
    self.default_value = default;
    return self;
}

pub fn withPlaceholder(self: *TextPrompt, placeholder: []const u8) *TextPrompt {
    self.placeholder = placeholder;
    return self;
}

pub fn withValidation(self: *TextPrompt, validate_fn: ValidateFn) *TextPrompt {
    self.validate = validate_fn;
    return self;
}

pub fn prompt(self: *TextPrompt) ![]const u8 {
    try self.core.start();

    if (self.default_value) |default| {
        try self.core.setValue(default);
    }

    while (!self.core.isFinished()) {
        try self.render();

        if (self.core.terminal.readKey()) |key_opt| {
            if (key_opt) |key| {
                try self.handleKey(key);
            }
        } else |_| {
            // Error reading key, continue
            continue;
        }

        std.time.sleep(10 * std.time.ns_per_ms);
    }

    try self.core.finish();

    if (self.core.isCanceled()) {
        return error.Canceled;
    }

    return try self.core.allocator.dupe(u8, self.core.getValue());
}

fn handleKey(self: *TextPrompt, key: Terminal.KeyPress) !void {
    switch (key.key) {
        .enter => {
            const value = self.core.getValue();

            // Run validation if provided
            if (self.validate) |validate_fn| {
                if (validate_fn(value)) |err_msg| {
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
                try self.core.appendChar(c);
                self.core.clearError();
            }
        },
        else => {},
    }
}

fn render(self: *TextPrompt) !void {
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

    try self.core.terminal.write(" ");

    // Render value or placeholder
    const value = self.core.getValue();
    if (value.len > 0) {
        try self.core.terminal.write(value);
    } else if (self.placeholder) |ph| {
        if (self.core.terminal.supports_color) {
            const colored_ph = try Ansi.dim(self.core.allocator, ph);
            defer self.core.allocator.free(colored_ph);
            try self.core.terminal.write(colored_ph);
        } else {
            try self.core.terminal.write(ph);
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
