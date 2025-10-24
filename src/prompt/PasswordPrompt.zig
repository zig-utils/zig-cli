const std = @import("std");
const PromptCore = @import("PromptCore.zig");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

const PasswordPrompt = @This();

core: PromptCore,
message: []const u8,
mask_char: u8,
validate: ?ValidateFn,

pub const ValidateFn = *const fn (value: []const u8) ?[]const u8;

pub fn init(allocator: std.mem.Allocator, message: []const u8) PasswordPrompt {
    return .{
        .core = PromptCore.init(allocator),
        .message = message,
        .mask_char = '*',
        .validate = null,
    };
}

pub fn deinit(self: *PasswordPrompt) void {
    self.core.deinit();
}

pub fn withMaskChar(self: *PasswordPrompt, char: u8) *PasswordPrompt {
    self.mask_char = char;
    return self;
}

pub fn withValidation(self: *PasswordPrompt, validate_fn: ValidateFn) *PasswordPrompt {
    self.validate = validate_fn;
    return self;
}

pub fn prompt(self: *PasswordPrompt) ![]const u8 {
    try self.core.start();

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

    return try self.core.allocator.dupe(u8, self.core.getValue());
}

fn handleKey(self: *PasswordPrompt, key: Terminal.KeyPress) !void {
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
        .char => {
            if (key.char) |c| {
                try self.core.appendChar(c);
                self.core.clearError();
            }
        },
        else => {},
    }
}

fn render(self: *PasswordPrompt) !void {
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

    // Render masked password
    const value = self.core.getValue();
    for (0..value.len) |_| {
        try self.core.terminal.write(&[_]u8{self.mask_char});
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
