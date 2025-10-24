const std = @import("std");
const PromptCore = @import("PromptCore.zig");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

const ConfirmPrompt = @This();

core: PromptCore,
message: []const u8,
default_value: bool,

pub fn init(allocator: std.mem.Allocator, message: []const u8) ConfirmPrompt {
    return .{
        .core = PromptCore.init(allocator),
        .message = message,
        .default_value = false,
    };
}

pub fn deinit(self: *ConfirmPrompt) void {
    self.core.deinit();
}

pub fn withDefault(self: *ConfirmPrompt, default: bool) *ConfirmPrompt {
    self.default_value = default;
    return self;
}

pub fn prompt(self: *ConfirmPrompt) !bool {
    try self.core.start();

    // Set initial value based on default
    const initial = if (self.default_value) "y" else "n";
    try self.core.setValue(initial);

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

    const value = self.core.getValue();
    return value.len > 0 and (value[0] == 'y' or value[0] == 'Y');
}

fn handleKey(self: *ConfirmPrompt, key: Terminal.KeyPress) !void {
    switch (key.key) {
        .enter => {
            self.core.transitionTo(.submit);
        },
        .ctrl_c, .escape => {
            self.core.transitionTo(.cancel);
        },
        .char => {
            if (key.char) |c| {
                if (c == 'y' or c == 'Y' or c == 'n' or c == 'N') {
                    try self.core.setValue(&[_]u8{c});
                }
            }
        },
        else => {},
    }
}

fn render(self: *ConfirmPrompt) !void {
    try self.core.terminal.clearLine();

    // Render prompt message
    if (self.core.terminal.supports_color) {
        const colored_msg = try Ansi.bold(self.core.allocator, self.message);
        defer self.core.allocator.free(colored_msg);
        try self.core.terminal.write(colored_msg);
    } else {
        try self.core.terminal.write(self.message);
    }

    try self.core.terminal.write(" ");

    // Render options
    const value = self.core.getValue();
    const is_yes = value.len > 0 and (value[0] == 'y' or value[0] == 'Y');

    if (self.core.terminal.supports_color) {
        if (is_yes) {
            const yes = try Ansi.green(self.core.allocator, "Yes");
            defer self.core.allocator.free(yes);
            try self.core.terminal.write(yes);
            try self.core.terminal.write(" / ");
            const no = try Ansi.dim(self.core.allocator, "no");
            defer self.core.allocator.free(no);
            try self.core.terminal.write(no);
        } else {
            const yes = try Ansi.dim(self.core.allocator, "yes");
            defer self.core.allocator.free(yes);
            try self.core.terminal.write(yes);
            try self.core.terminal.write(" / ");
            const no = try Ansi.red(self.core.allocator, "No");
            defer self.core.allocator.free(no);
            try self.core.terminal.write(no);
        }
    } else {
        if (is_yes) {
            try self.core.terminal.write("Yes / no");
        } else {
            try self.core.terminal.write("yes / No");
        }
    }

    try self.core.terminal.write(" ");
}
