const std = @import("std");
const PromptCore = @import("PromptCore.zig");
const Terminal = @import("Terminal.zig");
const Ansi = @import("Ansi.zig");

const PathPrompt = @This();

pub const PathType = enum {
    file,
    directory,
    any,
};

core: PromptCore,
message: []const u8,
path_type: PathType,
must_exist: bool,
suggestions: std.ArrayList([]const u8),
selected_suggestion: usize,
show_suggestions: bool,

pub fn init(allocator: std.mem.Allocator, message: []const u8, path_type: PathType) PathPrompt {
    return .{
        .core = PromptCore.init(allocator),
        .message = message,
        .path_type = path_type,
        .must_exist = false,
        .suggestions = std.ArrayList([]const u8).init(allocator),
        .selected_suggestion = 0,
        .show_suggestions = false,
    };
}

pub fn deinit(self: *PathPrompt) void {
    for (self.suggestions.items) |suggestion| {
        self.core.allocator.free(suggestion);
    }
    self.suggestions.deinit();
    self.core.deinit();
}

pub fn withMustExist(self: *PathPrompt, must_exist: bool) *PathPrompt {
    self.must_exist = must_exist;
    return self;
}

pub fn prompt(self: *PathPrompt) ![]const u8 {
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

fn handleKey(self: *PathPrompt, key: Terminal.KeyPress) !void {
    switch (key.key) {
        .enter => {
            if (self.show_suggestions and self.suggestions.items.len > 0) {
                // Accept suggestion
                const suggestion = self.suggestions.items[self.selected_suggestion];
                try self.core.setValue(suggestion);
                self.show_suggestions = false;
                try self.updateSuggestions();
            } else {
                // Submit
                const value = self.core.getValue();

                if (self.must_exist) {
                    std.fs.cwd().access(value, .{}) catch {
                        self.core.setError("Path does not exist");
                        return;
                    };

                    // Check type
                    const stat = std.fs.cwd().statFile(value) catch {
                        self.core.setError("Cannot access path");
                        return;
                    };

                    switch (self.path_type) {
                        .file => {
                            if (stat.kind != .file) {
                                self.core.setError("Path must be a file");
                                return;
                            }
                        },
                        .directory => {
                            if (stat.kind != .directory) {
                                self.core.setError("Path must be a directory");
                                return;
                            }
                        },
                        .any => {},
                    }
                }

                self.core.clearError();
                self.core.transitionTo(.submit);
            }
        },
        .tab => {
            // Trigger autocomplete
            if (!self.show_suggestions) {
                try self.updateSuggestions();
                self.show_suggestions = true;
            } else if (self.suggestions.items.len > 0) {
                // Accept current suggestion
                const suggestion = self.suggestions.items[self.selected_suggestion];
                try self.core.setValue(suggestion);
                self.show_suggestions = false;
                try self.updateSuggestions();
            }
        },
        .ctrl_c, .escape => {
            self.core.transitionTo(.cancel);
        },
        .backspace => {
            self.core.deleteChar();
            self.show_suggestions = false;
            self.core.clearError();
        },
        .delete => {
            self.core.deleteCharForward();
            self.show_suggestions = false;
            self.core.clearError();
        },
        .left => {
            self.core.moveCursorLeft();
        },
        .right => {
            self.core.moveCursorRight();
        },
        .up => {
            if (self.show_suggestions and self.suggestions.items.len > 0) {
                if (self.selected_suggestion > 0) {
                    self.selected_suggestion -= 1;
                }
            }
        },
        .down => {
            if (self.show_suggestions and self.suggestions.items.len > 0) {
                if (self.selected_suggestion < self.suggestions.items.len - 1) {
                    self.selected_suggestion += 1;
                }
            }
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
                self.show_suggestions = false;
                self.core.clearError();
            }
        },
        else => {},
    }
}

fn updateSuggestions(self: *PathPrompt) !void {
    // Clear old suggestions
    for (self.suggestions.items) |suggestion| {
        self.core.allocator.free(suggestion);
    }
    self.suggestions.clearRetainingCapacity();
    self.selected_suggestion = 0;

    const value = self.core.getValue();
    if (value.len == 0) {
        return;
    }

    // Parse path into directory and prefix
    const dir_path = std.fs.path.dirname(value) orelse ".";
    const file_prefix = std.fs.path.basename(value);

    // Open directory
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch {
        return; // Can't open, no suggestions
    };
    defer dir.close();

    var iter = dir.iterate();
    var count: usize = 0;
    while (try iter.next()) |entry| {
        if (count >= 10) break; // Limit to 10 suggestions

        // Filter by type
        switch (self.path_type) {
            .file => if (entry.kind != .file) continue,
            .directory => if (entry.kind != .directory) continue,
            .any => {},
        }

        // Check prefix match
        if (!std.mem.startsWith(u8, entry.name, file_prefix)) {
            continue;
        }

        // Build full path
        const full_path = try std.fs.path.join(self.core.allocator, &[_][]const u8{ dir_path, entry.name });
        try self.suggestions.append(full_path);
        count += 1;
    }
}

fn render(self: *PathPrompt) !void {
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

    // Render value
    const value = self.core.getValue();
    try self.core.terminal.write(value);

    // Render suggestions
    if (self.show_suggestions and self.suggestions.items.len > 0) {
        try self.core.terminal.write("\n");

        for (self.suggestions.items, 0..) |suggestion, i| {
            const is_selected = i == self.selected_suggestion;

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

            if (is_selected and self.core.terminal.supports_color) {
                const colored = try Ansi.cyan(self.core.allocator, suggestion);
                defer self.core.allocator.free(colored);
                try self.core.terminal.write(colored);
            } else {
                try self.core.terminal.write(suggestion);
            }

            try self.core.terminal.write("\n");
        }

        try self.core.terminal.write("\r");
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
