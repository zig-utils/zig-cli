const std = @import("std");

// ============================================================================
// Configuration Loader
// ============================================================================

const ConfigLoader = @import("ConfigLoader.zig").TypedConfig;

/// Load config from file (auto-detects format from extension)
///
/// Example:
/// ```zig
/// const AppConfig = struct {
///     database: struct {
///         host: []const u8,
///         port: u16,
///     },
///     debug: bool = false,
/// };
///
/// var cfg = try config.load(AppConfig, allocator, "config.toml");
/// defer cfg.deinit();
/// ```
pub fn load(comptime T: type, allocator: std.mem.Allocator, path: []const u8) !ConfigLoader(T) {
    return ConfigLoader(T).load(allocator, path);
}

/// Load config from string with explicit format
pub fn loadFromString(comptime T: type, allocator: std.mem.Allocator, content: []const u8, format: Format) !ConfigLoader(T) {
    return ConfigLoader(T).loadFromString(allocator, content, format);
}

/// Auto-discover config file for an application
///
/// Searches for: {app_name}.toml, {app_name}.json5, {app_name}.jsonc
/// In directories: ., ./.config, ~/.config/{app_name}
pub fn discover(comptime T: type, allocator: std.mem.Allocator, app_name: []const u8) !ConfigLoader(T) {
    return ConfigLoader(T).discover(allocator, app_name);
}

// Re-export types
const BaseConfig = @import("Config.zig");
pub const Format = BaseConfig.ConfigFormat;
pub const Value = BaseConfig.Value;

// Parsers (for advanced use)
pub const TomlParser = @import("TomlParser.zig");
pub const JsoncParser = @import("JsoncParser.zig");
pub const Json5Parser = @import("Json5Parser.zig");

test {
    std.testing.refAllDecls(@This());
}
