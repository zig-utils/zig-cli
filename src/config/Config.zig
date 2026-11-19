const std = @import("std");
const TomlParser = @import("TomlParser.zig");
const JsoncParser = @import("JsoncParser.zig");
const Json5Parser = @import("Json5Parser.zig");

const Config = @This();

fn getIo() std.Io {
    return std.Options.debug_io;
}

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

/// An owned value: strings, table keys and collections are released by deinit.
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
            .string => |str| allocator.free(str),
            .array => |arr| {
                for (arr) |*item| {
                    item.deinit(allocator);
                }
                allocator.free(arr);
            },
            .table => |*tbl| {
                var iter = tbl.iterator();
                while (iter.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                tbl.deinit();
            },
            else => {},
        }
    }

    /// Convert parser values to an independent, owned config value.
    pub fn fromToml(allocator: std.mem.Allocator, value: TomlParser.Value) !Value {
        return clone(allocator, value);
    }

    pub fn fromJsonc(allocator: std.mem.Allocator, value: JsoncParser.Value) !Value {
        return clone(allocator, value);
    }

    pub fn fromJson5(allocator: std.mem.Allocator, value: Json5Parser.Value) !Value {
        return clone(allocator, value);
    }

    fn clone(allocator: std.mem.Allocator, value: anytype) error{OutOfMemory}!Value {
        return switch (value) {
            .string => |str| .{ .string = try allocator.dupe(u8, str) },
            .array => |array| blk: {
                const items = try allocator.alloc(Value, array.len);
                var initialized: usize = 0;
                errdefer {
                    for (items[0..initialized]) |*item| item.deinit(allocator);
                    allocator.free(items);
                }
                for (array, 0..) |item, i| {
                    items[i] = try clone(allocator, item);
                    initialized += 1;
                }
                break :blk .{ .array = items };
            },
            inline else => |payload, tag| blk: {
                if (comptime std.mem.eql(u8, @tagName(tag), "table") or std.mem.eql(u8, @tagName(tag), "object")) {
                    var result = Value{ .table = std.StringHashMap(Value).init(allocator) };
                    errdefer result.deinit(allocator);
                    var iter = payload.iterator();
                    while (iter.next()) |entry| {
                        const key = try allocator.dupe(u8, entry.key_ptr.*);
                        errdefer allocator.free(key);
                        var item = try clone(allocator, entry.value_ptr.*);
                        errdefer item.deinit(allocator);
                        try result.table.put(key, item);
                    }
                    break :blk result;
                }
                break :blk @unionInit(Value, @tagName(tag), payload);
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
        self.allocator.free(entry.key_ptr.*);
        entry.value_ptr.deinit(self.allocator);
    }
    self.data.deinit();
}

/// Load config from a file
pub fn loadFromFile(self: *Config, path: []const u8, format: ConfigFormat) !void {
    const io = getIo();
    const cwd: std.Io.Dir = .cwd();
    const file = try cwd.openFile(io, path, .{});
    defer file.close(io);

    var read_buf: [4096]u8 = undefined;
    var reader = file.readerStreaming(io, &read_buf);
    const content = try reader.interface.allocRemaining(self.allocator, .unlimited);
    defer self.allocator.free(content);

    const actual_format = if (format == .auto) ConfigFormat.fromPath(path) else format;

    try self.loadFromString(content, actual_format);
}

/// Load config from a string, copying keys and values into the config's allocator.
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
                const table = if (entry.value_ptr.* == .table)
                    try self.tomlTable(entry.key_ptr.*)
                else
                    &self.data;
                if (entry.value_ptr.* == .table) {
                    var children = entry.value_ptr.table.iterator();
                    while (children.next()) |child| {
                        try self.putClone(table, child.key_ptr.*, child.value_ptr.*);
                    }
                } else {
                    try self.putClone(table, entry.key_ptr.*, entry.value_ptr.*);
                }
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
                try self.putClone(&self.data, entry.key_ptr.*, entry.value_ptr.*);
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
                try self.putClone(&self.data, entry.key_ptr.*, entry.value_ptr.*);
            }
        },
        .auto => return error.CannotAutoDetectFormat,
    }
}

fn getHomeDir() ?[]const u8 {
    const ptr = std.c.getenv("HOME") orelse return null;
    return std.mem.sliceTo(ptr, 0);
}

/// Discover and load config files automatically
pub fn discover(allocator: std.mem.Allocator, app_name: []const u8) !Config {
    var config = Config.init(allocator);
    errdefer config.deinit();

    const home = getHomeDir() orelse ".";

    // Try to find config files in order of precedence
    const local_config = try std.fs.path.join(allocator, &.{ ".", ".config" });
    defer allocator.free(local_config);
    const home_config = try std.fs.path.join(allocator, &.{ home, ".config", app_name });
    defer allocator.free(home_config);
    const search_paths = [_][]const u8{ ".", local_config, home_config };

    var config_names: [4][]const u8 = undefined;
    var initialized: usize = 0;
    defer for (config_names[0..initialized]) |name| allocator.free(name);
    for ([_][]const u8{ "toml", "json5", "jsonc", "json" }, 0..) |extension, i| {
        config_names[i] = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ app_name, extension });
        initialized += 1;
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

/// Get a value by a dotted path. An exact key takes precedence at each level.
pub fn get(self: *Config, key: []const u8) ?*Value {
    var table = &self.data;
    var remaining = key;
    while (true) {
        if (table.getPtr(remaining)) |value| return value;
        const dot = std.mem.indexOfScalar(u8, remaining, '.') orelse return null;
        const value = table.getPtr(remaining[0..dot]) orelse return null;
        table = switch (value.*) {
            .table => |*nested| nested,
            else => return null,
        };
        remaining = remaining[dot + 1 ..];
    }
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
    if (self == other) return;
    var iter = other.data.iterator();
    while (iter.next()) |entry| {
        try self.putClone(&self.data, entry.key_ptr.*, entry.value_ptr.*);
    }
}

fn putClone(self: *Config, table: *std.StringHashMap(Value), key: []const u8, value: anytype) !void {
    var copy = try Value.clone(self.allocator, value);
    errdefer copy.deinit(self.allocator);
    if (table.getPtr(key)) |existing| {
        existing.deinit(self.allocator);
        existing.* = copy;
    } else {
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);
        try table.put(owned_key, copy);
    }
}

// The standalone TOML parser represents dotted section names as flat keys.
// Materialize their parent tables here for typed and dotted config access.
fn tomlTable(self: *Config, path: []const u8) !*std.StringHashMap(Value) {
    var parts = std.mem.splitScalar(u8, path, '.');
    var table = &self.data;
    while (parts.next()) |part| {
        if (part.len == 0) return error.InvalidConfigFormat;
        if (!table.contains(part)) {
            const key = try self.allocator.dupe(u8, part);
            errdefer self.allocator.free(key);
            try table.put(key, .{ .table = std.StringHashMap(Value).init(self.allocator) });
        }
        const value = table.getPtr(part).?;
        table = switch (value.*) {
            .table => |*nested| nested,
            else => return error.InvalidConfigFormat,
        };
    }
    return table;
}

test "config owns its input and resolves dotted sections" {
    var source = "[service.database]\nhost = 'local'\nport = 5432".*;
    var config = Config.init(std.testing.allocator);
    defer config.deinit();
    try config.loadFromString(&source, .toml);
    @memset(&source, 'x');
    try std.testing.expectEqualStrings("local", config.getString("service.database.host").?);
    try std.testing.expectEqual(@as(?i64, 5432), config.getInt("service.database.port"));
    try std.testing.expect(config.get("service").?.* == .table);
    try std.testing.expect(config.get("service.database.host.missing") == null);
    try std.testing.expect(config.get("service.missing") == null);
}

test "config getters preserve exact keys before dotted traversal" {
    var config = Config.init(std.testing.allocator);
    defer config.deinit();
    try config.loadFromString(
        \\{"a.b":"literal","a":{"b":"nested"},"enabled":true,"ratio":1.5}
    , .jsonc);
    try std.testing.expectEqualStrings("literal", config.getString("a.b").?);
    try std.testing.expectEqual(@as(?bool, true), config.getBool("enabled"));
    try std.testing.expectEqual(@as(?f64, 1.5), config.getFloat("ratio"));
}

test "config merge owns copies after source deinit and replacement" {
    var destination = Config.init(std.testing.allocator);
    defer destination.deinit();
    try destination.loadFromString("{\"nested\":{\"value\":\"old\"}}", .jsonc);
    var source = Config.init(std.testing.allocator);
    try source.loadFromString("{nested:{value:'new'}, names:['one','two']}", .json5);
    destination.merge(&source) catch |err| {
        source.deinit();
        return err;
    };
    source.deinit();
    try std.testing.expectEqualStrings("new", destination.getString("nested.value").?);
    try std.testing.expectEqualStrings("two", destination.get("names").?.array[1].string);
    try destination.merge(&destination);
    try destination.loadFromString("{\"nested\":\"replaced\"}", .jsonc);
    try std.testing.expectEqualStrings("replaced", destination.getString("nested").?);
}
