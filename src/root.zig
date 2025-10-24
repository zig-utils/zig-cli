const std = @import("std");

pub const CLI = @import("cli/CLI.zig");
pub const Command = @import("cli/Command.zig");
pub const Option = @import("cli/Option.zig");
pub const Argument = @import("cli/Argument.zig");
pub const Parser = @import("cli/Parser.zig");
pub const Help = @import("cli/Help.zig");

pub const prompt = @import("prompt/root.zig");

test {
    std.testing.refAllDecls(@This());
}
