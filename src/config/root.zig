const std = @import("std");

pub const Config = @import("Config.zig");
pub const TomlParser = @import("TomlParser.zig");
pub const JsoncParser = @import("JsoncParser.zig");
pub const Json5Parser = @import("Json5Parser.zig");

// Re-export common types
pub const Value = Config.Value;
pub const ConfigFormat = Config.ConfigFormat;

/// Convenience function to load config from file
pub fn load(allocator: std.mem.Allocator, path: []const u8) !Config {
    var config = Config.init(allocator);
    errdefer config.deinit();
    try config.loadFromFile(path, .auto);
    return config;
}

/// Convenience function to discover config automatically
pub fn discover(allocator: std.mem.Allocator, app_name: []const u8) !Config {
    return Config.discover(allocator, app_name);
}

test {
    std.testing.refAllDecls(@This());
}
