const std = @import("std");

// ============================================================================
// CLI Framework
// ============================================================================

/// Create a command from a struct definition
/// Example: `var cmd = try cli.Command(MyOptions).init(allocator, "mycmd", "Description");`
pub const Command = @import("cli/CommandBuilder.zig").TypedCommand;

/// Context for accessing parsed options with compile-time validation
pub const Context = @import("cli/CommandBuilder.zig").TypedContext;

/// Action function signature
pub const Action = @import("cli/CommandBuilder.zig").TypedAction;

// ============================================================================
// Configuration
// ============================================================================

/// Configuration loader - supports TOML, JSONC, JSON5
pub const config = @import("config/root.zig");

// ============================================================================
// Interactive Prompts
// ============================================================================

/// All prompt types: text, confirm, select, password, number, path, etc.
pub const prompt = @import("prompt/root.zig");

// ============================================================================
// Low-Level Utilities
// ============================================================================

/// Option definition (usually auto-generated from struct fields)
pub const Option = @import("cli/Option.zig");

/// Argument definition
pub const Argument = @import("cli/Argument.zig");

/// Command-line argument parser
pub const Parser = @import("cli/Parser.zig");

/// Help text generator
pub const Help = @import("cli/Help.zig");

/// Base command type (for low-level use)
pub const BaseCommand = @import("cli/Command.zig");

test {
    std.testing.refAllDecls(@This());
}
