const std = @import("std");
const PromptCore = @import("PromptCore.zig");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

const MultiSelectPrompt = @This();

pub const Choice = struct {
    label: []const u8,
    value: []const u8,
    description: ?[]const u8 = null,
};

core: PromptCore,
message: []const u8,
choices: []const Choice,
selected_index: usize,
checked: std.ArrayList(bool),

pub fn init(allocator: std.mem.Allocator, message: []const u8, choices: []const Choice) !MultiSelectPrompt {
    var checked = std.ArrayList(bool).init(allocator);
    try checked.appendNTimes(false, choices.len);

    return .{
        .core = PromptCore.init(allocator),
        .message = message,
        .choices = choices,
        .selected_index = 0,
        .checked = checked,
    };
}

pub fn deinit(self: *MultiSelectPrompt) void {
    self.checked.deinit();
    self.core.deinit();
}

pub fn prompt(self: *MultiSelectPrompt) ![][]const u8 {
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

    // Collect checked values
    var result = std.ArrayList([]const u8).init(self.core.allocator);
    for (self.choices, 0..) |choice, i| {
        if (self.checked.items[i]) {
            const value_copy = try self.core.allocator.dupe(u8, choice.value);
            try result.append(value_copy);
        }
    }

    return try result.toOwnedSlice();
}

fn handleKey(self: *MultiSelectPrompt, key: Terminal.KeyPress) !void {
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
        .char => {
            if (key.char) |c| {
                if (c == ' ') {
                    // Toggle current selection
                    self.checked.items[self.selected_index] = !self.checked.items[self.selected_index];
                }
            }
        },
        else => {},
    }
}

fn render(self: *MultiSelectPrompt) !void {
    // Clear all choice lines
    for (0..self.choices.len + 2) |_| {
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

    // Render hint
    if (self.core.terminal.supports_color) {
        const hint = try Ansi.dim(self.core.allocator, "(Space to select, Enter to confirm)");
        defer self.core.allocator.free(hint);
        try self.core.terminal.write(hint);
    } else {
        try self.core.terminal.write("(Space to select, Enter to confirm)");
    }
    try self.core.terminal.write("\n");

    // Render choices
    for (self.choices, 0..) |choice, i| {
        const is_selected = i == self.selected_index;
        const is_checked = self.checked.items[i];

        // Pointer
        if (is_selected) {
            if (self.core.terminal.supports_color) {
                const pointer = try Ansi.cyan(self.core.allocator, symbols.pointer);
                defer self.core.allocator.free(pointer);
                try self.core.terminal.write(pointer);
            } else {
                try self.core.terminal.write(symbols.pointer);
            }
        } else {
            try self.core.terminal.write(" ");
        }

        try self.core.terminal.write(" ");

        // Checkbox
        if (is_checked) {
            if (self.core.terminal.supports_color) {
                const checkbox = try Ansi.green(self.core.allocator, symbols.checkbox_on);
                defer self.core.allocator.free(checkbox);
                try self.core.terminal.write(checkbox);
            } else {
                try self.core.terminal.write(symbols.checkbox_on);
            }
        } else {
            try self.core.terminal.write(symbols.checkbox_off);
        }

        try self.core.terminal.write(" ");

        // Label
        if (is_selected) {
            if (self.core.terminal.supports_color) {
                const label = try Ansi.cyan(self.core.allocator, choice.label);
                defer self.core.allocator.free(label);
                try self.core.terminal.write(label);
            } else {
                try self.core.terminal.write(choice.label);
            }
        } else {
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

fn renderFinal(self: *MultiSelectPrompt) !void {
    // Clear all lines
    for (0..self.choices.len + 2) |_| {
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

    if (self.core.terminal.supports_color) {
        const check = try Ansi.green(self.core.allocator, symbols.checkmark);
        defer self.core.allocator.free(check);
        try self.core.terminal.write(check);
    } else {
        try self.core.terminal.write("Done");
    }

    // Show selected count
    var count: usize = 0;
    for (self.checked.items) |is_checked| {
        if (is_checked) count += 1;
    }

    var buf: [64]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, " {d} selected", .{count});
    if (self.core.terminal.supports_color) {
        const colored = try Ansi.dim(self.core.allocator, msg);
        defer self.core.allocator.free(colored);
        try self.core.terminal.write(colored);
    } else {
        try self.core.terminal.write(msg);
    }
}
