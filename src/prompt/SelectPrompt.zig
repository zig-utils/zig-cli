const std = @import("std");
const PromptCore = @import("PromptCore.zig");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

const SelectPrompt = @This();

pub const Choice = struct {
    label: []const u8,
    value: []const u8,
    description: ?[]const u8 = null,
};

core: PromptCore,
message: []const u8,
choices: []const Choice,
selected_index: usize,

pub fn init(allocator: std.mem.Allocator, message: []const u8, choices: []const Choice) SelectPrompt {
    return .{
        .core = PromptCore.init(allocator),
        .message = message,
        .choices = choices,
        .selected_index = 0,
    };
}

pub fn deinit(self: *SelectPrompt) void {
    self.core.deinit();
}

pub fn prompt(self: *SelectPrompt) ![]const u8 {
    if (self.choices.len == 0) {
        return error.NoChoices;
    }

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

    try self.renderFinal();
    try self.core.finish();

    if (self.core.isCanceled()) {
        return error.Canceled;
    }

    return try self.core.allocator.dupe(u8, self.choices[self.selected_index].value);
}

fn handleKey(self: *SelectPrompt, key: Terminal.KeyPress) !void {
    switch (key.key) {
        .enter => {
            self.core.transitionTo(.submit);
        },
        .ctrl_c, .escape => {
            self.core.transitionTo(.cancel);
        },
        .up => {
            if (self.selected_index > 0) {
                self.selected_index -= 1;
            }
        },
        .down => {
            if (self.selected_index < self.choices.len - 1) {
                self.selected_index += 1;
            }
        },
        else => {},
    }
}

fn render(self: *SelectPrompt) !void {
    // Clear all choice lines
    for (0..self.choices.len + 1) |_| {
        try self.core.terminal.write("\x1b[2K");
        try self.core.terminal.write("\x1b[1A");
    }
    try self.core.terminal.write("\r");

    const symbols = Ansi.Symbols.forTerminal(self.core.terminal.supports_unicode);

    // Render message
    if (self.core.terminal.supports_color) {
        const colored_msg = try Ansi.bold(self.core.allocator, self.message);
        defer self.core.allocator.free(colored_msg);
        try self.core.terminal.write(colored_msg);
    } else {
        try self.core.terminal.write(self.message);
    }
    try self.core.terminal.write("\n");

    // Render choices
    for (self.choices, 0..) |choice, i| {
        const is_selected = i == self.selected_index;

        if (is_selected) {
            if (self.core.terminal.supports_color) {
                const pointer = try Ansi.cyan(self.core.allocator, symbols.pointer);
                defer self.core.allocator.free(pointer);
                try self.core.terminal.write(pointer);
            } else {
                try self.core.terminal.write(symbols.pointer);
            }
            try self.core.terminal.write(" ");

            if (self.core.terminal.supports_color) {
                const label = try Ansi.cyan(self.core.allocator, choice.label);
                defer self.core.allocator.free(label);
                try self.core.terminal.write(label);
            } else {
                try self.core.terminal.write(choice.label);
            }
        } else {
            try self.core.terminal.write("  ");
            if (self.core.terminal.supports_color) {
                const label = try Ansi.dim(self.core.allocator, choice.label);
                defer self.core.allocator.free(label);
                try self.core.terminal.write(label);
            } else {
                try self.core.terminal.write(choice.label);
            }
        }

        if (choice.description) |desc| {
            try self.core.terminal.write(" - ");
            if (self.core.terminal.supports_color) {
                const colored_desc = try Ansi.dim(self.core.allocator, desc);
                defer self.core.allocator.free(colored_desc);
                try self.core.terminal.write(colored_desc);
            } else {
                try self.core.terminal.write(desc);
            }
        }

        try self.core.terminal.write("\n");
    }
}

fn renderFinal(self: *SelectPrompt) !void {
    // Clear all choice lines
    for (0..self.choices.len + 1) |_| {
        try self.core.terminal.write("\x1b[2K");
        try self.core.terminal.write("\x1b[1A");
    }
    try self.core.terminal.write("\r");

    const symbols = Ansi.Symbols.forTerminal(self.core.terminal.supports_unicode);

    // Render message with result
    if (self.core.terminal.supports_color) {
        const colored_msg = try Ansi.bold(self.core.allocator, self.message);
        defer self.core.allocator.free(colored_msg);
        try self.core.terminal.write(colored_msg);
    } else {
        try self.core.terminal.write(self.message);
    }
    try self.core.terminal.write(" ");

    const selected = self.choices[self.selected_index];
    if (self.core.terminal.supports_color) {
        const check = try Ansi.green(self.core.allocator, symbols.checkmark);
        defer self.core.allocator.free(check);
        try self.core.terminal.write(check);
        try self.core.terminal.write(" ");

        const value = try Ansi.cyan(self.core.allocator, selected.label);
        defer self.core.allocator.free(value);
        try self.core.terminal.write(value);
    } else {
        try self.core.terminal.write(selected.label);
    }
}
