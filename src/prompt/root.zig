const std = @import("std");

pub const Terminal = @import("Terminal.zig");
pub const Ansi = @import("Ansi.zig");
pub const PromptCore = @import("PromptCore.zig");
pub const PromptState = @import("PromptState.zig");
pub const TextPrompt = @import("TextPrompt.zig");
pub const ConfirmPrompt = @import("ConfirmPrompt.zig");
pub const SelectPrompt = @import("SelectPrompt.zig");
pub const MultiSelectPrompt = @import("MultiSelectPrompt.zig");
pub const PasswordPrompt = @import("PasswordPrompt.zig");
pub const NumberPrompt = @import("NumberPrompt.zig");
pub const SpinnerPrompt = @import("SpinnerPrompt.zig");
pub const PathPrompt = @import("PathPrompt.zig");
pub const GroupPrompt = @import("GroupPrompt.zig");
pub const Message = @import("Message.zig");
pub const Box = @import("Box.zig");
pub const Table = @import("Table.zig");
pub const ProgressBar = @import("ProgressBar.zig");
pub const Style = @import("Style.zig");

// Convenience functions for quick prompts
pub fn text(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    var prompt_obj = TextPrompt.init(allocator, message);
    defer prompt_obj.deinit();
    return try prompt_obj.prompt();
}

pub fn confirm(allocator: std.mem.Allocator, message: []const u8) !bool {
    var prompt_obj = ConfirmPrompt.init(allocator, message);
    defer prompt_obj.deinit();
    return try prompt_obj.prompt();
}

pub fn select(allocator: std.mem.Allocator, message: []const u8, choices: []const SelectPrompt.Choice) ![]const u8 {
    var prompt_obj = SelectPrompt.init(allocator, message, choices);
    defer prompt_obj.deinit();
    return try prompt_obj.prompt();
}

// Export Message convenience functions
pub const intro = Message.intro;
pub const outro = Message.outro;
pub const note = Message.note;
pub const log = Message.log;
pub const cancel = Message.cancel;

// Export Box convenience function
pub const box = Box.render;

// Export Style convenience function
pub const style = Style.style;

test {
    std.testing.refAllDecls(@This());
}
