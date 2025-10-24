const std = @import("std");
const Terminal = @import("Terminal.zig");
const PromptState = @import("PromptState.zig");

const PromptCore = @This();

pub const RenderFn = *const fn (self: *PromptCore) anyerror!void;

allocator: std.mem.Allocator,
terminal: Terminal,
state: PromptState.State,
raw_mode: ?Terminal.RawMode,
value: std.ArrayList(u8),
cursor: usize,
error_message: ?[]const u8,

pub fn init(allocator: std.mem.Allocator) PromptCore {
    return .{
        .allocator = allocator,
        .terminal = Terminal.init(),
        .state = .initial,
        .raw_mode = null,
        .value = std.ArrayList(u8).init(allocator),
        .cursor = 0,
        .error_message = null,
    };
}

pub fn deinit(self: *PromptCore) void {
    self.value.deinit();
    if (self.raw_mode) |rm| {
        rm.disable();
    }
}

pub fn start(self: *PromptCore) !void {
    if (self.state != .initial) return error.InvalidState;

    self.raw_mode = try Terminal.RawMode.enable();
    try self.terminal.hideCursor();
    self.transitionTo(.active);
}

pub fn finish(self: *PromptCore) !void {
    if (self.raw_mode) |rm| {
        rm.disable();
        self.raw_mode = null;
    }
    try self.terminal.showCursor();
    try self.terminal.write("\n");
}

pub fn transitionTo(self: *PromptCore, new_state: PromptState.State) void {
    if (self.state.canTransitionTo(new_state)) {
        self.state = new_state;
    }
}

pub fn setValue(self: *PromptCore, value: []const u8) !void {
    self.value.clearRetainingCapacity();
    try self.value.appendSlice(value);
    self.cursor = value.len;
}

pub fn appendChar(self: *PromptCore, char: u8) !void {
    if (self.cursor >= self.value.items.len) {
        try self.value.append(char);
    } else {
        try self.value.insert(self.cursor, char);
    }
    self.cursor += 1;
}

pub fn deleteChar(self: *PromptCore) void {
    if (self.cursor > 0 and self.value.items.len > 0) {
        _ = self.value.orderedRemove(self.cursor - 1);
        self.cursor -= 1;
    }
}

pub fn deleteCharForward(self: *PromptCore) void {
    if (self.cursor < self.value.items.len) {
        _ = self.value.orderedRemove(self.cursor);
    }
}

pub fn moveCursorLeft(self: *PromptCore) void {
    if (self.cursor > 0) {
        self.cursor -= 1;
    }
}

pub fn moveCursorRight(self: *PromptCore) void {
    if (self.cursor < self.value.items.len) {
        self.cursor += 1;
    }
}

pub fn moveCursorHome(self: *PromptCore) void {
    self.cursor = 0;
}

pub fn moveCursorEnd(self: *PromptCore) void {
    self.cursor = self.value.items.len;
}

pub fn setError(self: *PromptCore, message: []const u8) void {
    self.error_message = message;
    self.transitionTo(.error_state);
}

pub fn clearError(self: *PromptCore) void {
    self.error_message = null;
    if (self.state == .error_state) {
        self.transitionTo(.active);
    }
}

pub fn getValue(self: *PromptCore) []const u8 {
    return self.value.items;
}

pub fn isSubmitted(self: *PromptCore) bool {
    return self.state == .submit;
}

pub fn isCanceled(self: *PromptCore) bool {
    return self.state == .cancel;
}

pub fn isFinished(self: *PromptCore) bool {
    return self.state == .submit or self.state == .cancel;
}
