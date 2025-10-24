const std = @import("std");
const TomlParser = @import("TomlParser.zig");
const JsoncParser = @import("JsoncParser.zig");
const Json5Parser = @import("Json5Parser.zig");

const Config = @This();

pub const ConfigFormat = enum {
    toml,
    jsonc,
    json5,
    auto, // Auto-detect from extension

    pub fn fromPath(path: []const u8) ConfigFormat {
        if (std.mem.endsWith(u8, path, ".toml")) return .toml;
        if (std.mem.endsWith(u8, path, ".jsonc")) return .jsonc;
        if (std.mem.endsWith(u8, path, ".json5")) return .json5;
        if (std.mem.endsWith(u8, path, ".json")) return .jsonc; // Treat .json as JSONC
        return .auto;
    }
};

pub const Value = union(enum) {
    null_value: void,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    array: []Value,
    table: std.StringHashMap(Value),

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .array => |arr| {
                for (arr) |*item| {
                    item.deinit(allocator);
                }
                allocator.free(arr);
            },
            .table => |*tbl| {
                var iter = tbl.iterator();
                while (iter.next()) |entry| {
                    var val = entry.value_ptr.*;
                    val.deinit(allocator);
                }
                tbl.deinit();
            },
            else => {},
        }
    }

    /// Convert from parser-specific value types
    pub fn fromToml(allocator: std.mem.Allocator, toml_val: TomlParser.Value) !Value {
        return switch (toml_val) {
            .string => |s| Value{ .string = s },
            .integer => |i| Value{ .integer = i },
            .float => |f| Value{ .float = f },
            .boolean => |b| Value{ .boolean = b },
            .array => |arr| blk: {
                var items = try allocator.alloc(Value, arr.len);
                for (arr, 0..) |item, i| {
                    items[i] = try fromToml(allocator, item);
                }
                break :blk Value{ .array = items };
            },
            .table => |tbl| blk: {
                var map = std.StringHashMap(Value).init(allocator);
                var iter = tbl.iterator();
                while (iter.next()) |entry| {
                    const val = try fromToml(allocator, entry.value_ptr.*);
                    try map.put(entry.key_ptr.*, val);
                }
                break :blk Value{ .table = map };
            },
        };
    }

    pub fn fromJsonc(allocator: std.mem.Allocator, json_val: JsoncParser.Value) !Value {
        return switch (json_val) {
            .null_value => Value{ .null_value = {} },
            .boolean => |b| Value{ .boolean = b },
            .integer => |i| Value{ .integer = i },
            .float => |f| Value{ .float = f },
            .string => |s| Value{ .string = s },
            .array => |arr| blk: {
                var items = try allocator.alloc(Value, arr.len);
                for (arr, 0..) |item, i| {
                    items[i] = try fromJsonc(allocator, item);
                }
                break :blk Value{ .array = items };
            },
            .object => |obj| blk: {
                var map = std.StringHashMap(Value).init(allocator);
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const val = try fromJsonc(allocator, entry.value_ptr.*);
                    try map.put(entry.key_ptr.*, val);
                }
                break :blk Value{ .table = map };
            },
        };
    }

    pub fn fromJson5(allocator: std.mem.Allocator, json5_val: Json5Parser.Value) !Value {
        return switch (json5_val) {
            .null_value => Value{ .null_value = {} },
            .boolean => |b| Value{ .boolean = b },
            .integer => |i| Value{ .integer = i },
            .float => |f| Value{ .float = f },
            .string => |s| Value{ .string = s },
            .array => |arr| blk: {
                var items = try allocator.alloc(Value, arr.len);
                for (arr, 0..) |item, i| {
                    items[i] = try fromJson5(allocator, item);
                }
                break :blk Value{ .array = items };
            },
            .object => |obj| blk: {
                var map = std.StringHashMap(Value).init(allocator);
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const val = try fromJson5(allocator, entry.value_ptr.*);
                    try map.put(entry.key_ptr.*, val);
                }
                break :blk Value{ .table = map };
            },
        };
    }
};

allocator: std.mem.Allocator,
data: std.StringHashMap(Value),

pub fn init(allocator: std.mem.Allocator) Config {
    return .{
        .allocator = allocator,
        .data = std.StringHashMap(Value).init(allocator),
    };
}

pub fn deinit(self: *Config) void {
    var iter = self.data.iterator();
    while (iter.next()) |entry| {
        var val = entry.value_ptr.*;
        val.deinit(self.allocator);
    }
    self.data.deinit();
}

/// Load config from a file
pub fn loadFromFile(self: *Config, path: []const u8, format: ConfigFormat) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
    defer self.allocator.free(content);

    const actual_format = if (format == .auto) ConfigFormat.fromPath(path) else format;

    try self.loadFromString(content, actual_format);
}

/// Load config from a string
pub fn loadFromString(self: *Config, content: []const u8, format: ConfigFormat) !void {
    switch (format) {
        .toml => {
            var parser = TomlParser.init(self.allocator, content);
            var parsed = try parser.parse();
            defer {
                var iter = parsed.iterator();
                while (iter.next()) |entry| {
                    var val = entry.value_ptr.*;
                    val.deinit(self.allocator);
                }
                parsed.deinit();
            }

            var iter = parsed.iterator();
            while (iter.next()) |entry| {
                const val = try Value.fromToml(self.allocator, entry.value_ptr.*);
                try self.data.put(entry.key_ptr.*, val);
            }
        },
        .jsonc => {
            var parser = JsoncParser.init(self.allocator, content);
            var parsed = try parser.parse();
            defer parsed.deinit(self.allocator);

            if (parsed != .object) {
                return error.InvalidConfigFormat;
            }

            var iter = parsed.object.iterator();
            while (iter.next()) |entry| {
                const val = try Value.fromJsonc(self.allocator, entry.value_ptr.*);
                try self.data.put(entry.key_ptr.*, val);
            }
        },
        .json5 => {
            var parser = Json5Parser.init(self.allocator, content);
            var parsed = try parser.parse();
            defer parsed.deinit(self.allocator);

            if (parsed != .object) {
                return error.InvalidConfigFormat;
            }

            var iter = parsed.object.iterator();
            while (iter.next()) |entry| {
                const val = try Value.fromJson5(self.allocator, entry.value_ptr.*);
                try self.data.put(entry.key_ptr.*, val);
            }
        },
        .auto => return error.CannotAutoDetectFormat,
    }
}

/// Discover and load config files automatically
pub fn discover(allocator: std.mem.Allocator, app_name: []const u8) !Config {
    var config = Config.init(allocator);
    errdefer config.deinit();

    // Try to find config files in order of precedence
    const search_paths = [_][]const u8{
        ".",                              // Current directory
        try std.fs.path.join(allocator, &[_][]const u8{ ".", ".config" }),
        try std.fs.path.join(allocator, &[_][]const u8{ std.os.getenv("HOME") orelse ".", ".config", app_name }),
    };
    defer {
        for (search_paths[1..]) |p| allocator.free(p);
    }

    const config_names = [_][]const u8{
        try std.fmt.allocPrint(allocator, "{s}.toml", .{app_name}),
        try std.fmt.allocPrint(allocator, "{s}.json5", .{app_name}),
        try std.fmt.allocPrint(allocator, "{s}.jsonc", .{app_name}),
        try std.fmt.allocPrint(allocator, "{s}.json", .{app_name}),
    };
    defer {
        for (config_names) |n| allocator.free(n);
    }

    for (search_paths) |dir| {
        for (config_names) |name| {
            const path = try std.fs.path.join(allocator, &[_][]const u8{ dir, name });
            defer allocator.free(path);

            config.loadFromFile(path, .auto) catch |err| {
                if (err != error.FileNotFound) {
                    return err;
                }
                continue;
            };

            // Successfully loaded
            return config;
        }
    }

    // No config found, return empty config
    return config;
}

/// Get a value by key
pub fn get(self: *Config, key: []const u8) ?*Value {
    return self.data.getPtr(key);
}

/// Get a string value
pub fn getString(self: *Config, key: []const u8) ?[]const u8 {
    const val = self.get(key) orelse return null;
    return switch (val.*) {
        .string => |s| s,
        else => null,
    };
}

/// Get an integer value
pub fn getInt(self: *Config, key: []const u8) ?i64 {
    const val = self.get(key) orelse return null;
    return switch (val.*) {
        .integer => |i| i,
        else => null,
    };
}

/// Get a boolean value
pub fn getBool(self: *Config, key: []const u8) ?bool {
    const val = self.get(key) orelse return null;
    return switch (val.*) {
        .boolean => |b| b,
        else => null,
    };
}

/// Get a float value
pub fn getFloat(self: *Config, key: []const u8) ?f64 {
    const val = self.get(key) orelse return null;
    return switch (val.*) {
        .float => |f| f,
        else => null,
    };
}

/// Merge another config into this one (other takes precedence)
pub fn merge(self: *Config, other: *const Config) !void {
    var iter = other.data.iterator();
    while (iter.next()) |entry| {
        const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
        errdefer self.allocator.free(key_copy);

        const val_copy = entry.value_ptr.*;
        // Note: This is a shallow copy. For production, implement deep copy.
        try self.data.put(key_copy, val_copy);
    }
}
