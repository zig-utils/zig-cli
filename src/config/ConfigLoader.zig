const std = @import("std");
const Config = @import("Config.zig");

/// Type-safe config loader with compile-time schema validation
///
/// Example:
/// ```
/// const AppConfig = struct {
///     database: struct {
///         host: []const u8,
///         port: u16,
///     },
///     debug: bool = false,
/// };
///
/// const config = try TypedConfig(AppConfig).load(allocator, "config.toml");
/// defer config.deinit();
///
/// std.debug.print("DB Host: {s}:{d}\n", .{config.value.database.host, config.value.database.port});
/// ```
pub fn TypedConfig(comptime T: type) type {
    // Validate T is a struct at compile time
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("TypedConfig requires a struct type, got: " ++ @typeName(T));
    }

    return struct {
        value: T,
        allocator: std.mem.Allocator,
        _raw_config: Config,

        const Self = @This();

        /// Load and parse a typed config from file
        pub fn load(allocator: std.mem.Allocator, path: []const u8) !Self {
            const format = Config.ConfigFormat.fromPath(path);
            var raw_config = Config.init(allocator);
            errdefer raw_config.deinit();

            try raw_config.loadFromFile(path, format);

            const value = try parseStruct(T, allocator, &raw_config, "");

            return .{
                .value = value,
                .allocator = allocator,
                ._raw_config = raw_config,
            };
        }

        /// Load from config string with explicit format
        pub fn loadFromString(allocator: std.mem.Allocator, content: []const u8, format: Config.ConfigFormat) !Self {
            var raw_config = Config.init(allocator);
            errdefer raw_config.deinit();

            try raw_config.loadFromString(content, format);

            const value = try parseStruct(T, allocator, &raw_config, "");

            return .{
                .value = value,
                .allocator = allocator,
                ._raw_config = raw_config,
            };
        }

        /// Auto-discover and load typed config
        pub fn discover(allocator: std.mem.Allocator, app_name: []const u8) !Self {
            var raw_config = try Config.discover(allocator, app_name);
            errdefer raw_config.deinit();

            const value = try parseStruct(T, allocator, &raw_config, "");

            return .{
                .value = value,
                .allocator = allocator,
                ._raw_config = raw_config,
            };
        }

        pub fn deinit(self: *Self) void {
            self._raw_config.deinit();
        }

        /// Parse a struct type from config
        fn parseStruct(comptime StructType: type, allocator: std.mem.Allocator, config: *Config, prefix: []const u8) !StructType {
            const struct_info = @typeInfo(StructType);
            if (struct_info != .@"struct") {
                @compileError("parseStruct requires a struct type");
            }

            var result: StructType = undefined;
            const fields = struct_info.@"struct".fields;

            inline for (fields) |field| {
                const full_key = if (prefix.len > 0)
                    try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, field.name })
                else
                    field.name;
                defer if (prefix.len > 0) allocator.free(full_key);

                const field_value = try parseField(field.type, allocator, config, full_key, field.default_value_ptr);
                @field(result, field.name) = field_value;
            }

            return result;
        }

        /// Parse a single field value
        fn parseField(
            comptime FieldType: type,
            allocator: std.mem.Allocator,
            config: *Config,
            key: []const u8,
            default_value: ?*const anyopaque,
        ) !FieldType {
            const field_type_info = @typeInfo(FieldType);

            // Handle optional types
            const is_optional = field_type_info == .optional;
            const base_type = if (is_optional) field_type_info.optional.child else FieldType;

            // Try to get value from config
            const config_value = config.get(key);

            // If no value found
            if (config_value == null) {
                // Return default if available
                if (default_value) |default_ptr| {
                    return @as(*const FieldType, @ptrCast(@alignCast(default_ptr))).*;
                }
                // Return null for optional
                if (is_optional) {
                    return null;
                }
                // Error for required field
                std.debug.print("Missing required config key: {s}\n", .{key});
                return error.MissingRequiredField;
            }

            const value = config_value.?;
            const parsed = try parseValue(base_type, allocator, config, key, value);

            if (is_optional) {
                return parsed;
            }
            return parsed;
        }

        /// Parse a value based on its type
        fn parseValue(
            comptime ValueType: type,
            allocator: std.mem.Allocator,
            config: *Config,
            key: []const u8,
            value: Config.Value,
        ) !ValueType {
            const value_type_info = @typeInfo(ValueType);

            return switch (value_type_info) {
                .bool => switch (value) {
                    .boolean => |b| b,
                    else => error.TypeMismatch,
                },
                .int => switch (value) {
                    .integer => |i| blk: {
                        if (i < std.math.minInt(ValueType) or i > std.math.maxInt(ValueType)) {
                            return error.IntegerOverflow;
                        }
                        break :blk @intCast(i);
                    },
                    else => error.TypeMismatch,
                },
                .float => switch (value) {
                    .float => |f| @floatCast(f),
                    .integer => |i| @floatFromInt(i),
                    else => error.TypeMismatch,
                },
                .pointer => |ptr| blk: {
                    if (ptr.size == .slice and ptr.child == u8) {
                        break :blk switch (value) {
                            .string => |s| s,
                            else => error.TypeMismatch,
                        };
                    }
                    @compileError("Unsupported pointer type");
                },
                .@"struct" => try parseStruct(ValueType, allocator, config, key),
                .array => |arr| blk: {
                    switch (value) {
                        .array => |items| {
                            if (items.len != arr.len) {
                                return error.ArrayLengthMismatch;
                            }
                            var result: ValueType = undefined;
                            for (items, 0..) |item, i| {
                                result[i] = try parseValue(arr.child, allocator, config, key, item);
                            }
                            break :blk result;
                        },
                        else => return error.TypeMismatch,
                    }
                },
                .@"enum" => |enum_info| blk: {
                    const str = switch (value) {
                        .string => |s| s,
                        else => return error.TypeMismatch,
                    };
                    inline for (enum_info.fields) |enum_field| {
                        if (std.mem.eql(u8, str, enum_field.name)) {
                            break :blk @field(ValueType, enum_field.name);
                        }
                    }
                    return error.InvalidEnumValue;
                },
                else => @compileError("Unsupported config type: " ++ @typeName(ValueType)),
            };
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "TypedConfig: basic primitives" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestConfig = struct {
        name: []const u8,
        port: u16,
        debug: bool,
    };

    const toml_content =
        \\name = "test-app"
        \\port = 3000
        \\debug = true
    ;

    var config = try TypedConfig(TestConfig).loadFromString(allocator, toml_content, .toml);
    defer config.deinit();

    try testing.expectEqualStrings("test-app", config.value.name);
    try testing.expectEqual(@as(u16, 3000), config.value.port);
    try testing.expectEqual(true, config.value.debug);
}

test "TypedConfig: with defaults" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestConfig = struct {
        name: []const u8,
        port: u16 = 8080,
        debug: bool = false,
    };

    const toml_content =
        \\name = "test-app"
    ;

    var config = try TypedConfig(TestConfig).loadFromString(allocator, toml_content, .toml);
    defer config.deinit();

    try testing.expectEqualStrings("test-app", config.value.name);
    try testing.expectEqual(@as(u16, 8080), config.value.port);
    try testing.expectEqual(false, config.value.debug);
}

test "TypedConfig: nested structs" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const DatabaseConfig = struct {
        host: []const u8,
        port: u16,
    };

    const AppConfig = struct {
        database: DatabaseConfig,
        debug: bool = false,
    };

    const toml_content =
        \\[database]
        \\host = "localhost"
        \\port = 5432
        \\
        \\debug = true
    ;

    var config = try TypedConfig(AppConfig).loadFromString(allocator, toml_content, .toml);
    defer config.deinit();

    try testing.expectEqualStrings("localhost", config.value.database.host);
    try testing.expectEqual(@as(u16, 5432), config.value.database.port);
    try testing.expectEqual(true, config.value.debug);
}

test "TypedConfig: with enums" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const LogLevel = enum { debug, info, warn, @"error" };

    const TestConfig = struct {
        log_level: LogLevel = .info,
    };

    const toml_content =
        \\log_level = "debug"
    ;

    var config = try TypedConfig(TestConfig).loadFromString(allocator, toml_content, .toml);
    defer config.deinit();

    try testing.expectEqual(LogLevel.debug, config.value.log_level);
}

test "TypedConfig: with optionals" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestConfig = struct {
        required: []const u8,
        optional: ?u16 = null,
    };

    const toml_content =
        \\required = "value"
    ;

    var config = try TypedConfig(TestConfig).loadFromString(allocator, toml_content, .toml);
    defer config.deinit();

    try testing.expectEqualStrings("value", config.value.required);
    try testing.expectEqual(@as(?u16, null), config.value.optional);
}

test "TypedConfig: optional with value" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestConfig = struct {
        optional: ?u16 = null,
    };

    const toml_content =
        \\optional = 42
    ;

    var config = try TypedConfig(TestConfig).loadFromString(allocator, toml_content, .toml);
    defer config.deinit();

    try testing.expectEqual(@as(?u16, 42), config.value.optional);
}

test "TypedConfig: all integer types" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestConfig = struct {
        u8_val: u8,
        u16_val: u16,
        u32_val: u32,
        i8_val: i8,
        i16_val: i16,
        i32_val: i32,
    };

    const toml_content =
        \\u8_val = 255
        \\u16_val = 65535
        \\u32_val = 4294967295
        \\i8_val = -128
        \\i16_val = -32768
        \\i32_val = -2147483648
    ;

    var config = try TypedConfig(TestConfig).loadFromString(allocator, toml_content, .toml);
    defer config.deinit();

    try testing.expectEqual(@as(u8, 255), config.value.u8_val);
    try testing.expectEqual(@as(u16, 65535), config.value.u16_val);
    try testing.expectEqual(@as(u32, 4294967295), config.value.u32_val);
    try testing.expectEqual(@as(i8, -128), config.value.i8_val);
    try testing.expectEqual(@as(i16, -32768), config.value.i16_val);
    try testing.expectEqual(@as(i32, -2147483648), config.value.i32_val);
}

test "TypedConfig: float types" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestConfig = struct {
        f32_val: f32,
        f64_val: f64,
    };

    const toml_content =
        \\f32_val = 1.5
        \\f64_val = 2.5
    ;

    var config = try TypedConfig(TestConfig).loadFromString(allocator, toml_content, .toml);
    defer config.deinit();

    try testing.expectApproxEqAbs(@as(f32, 1.5), config.value.f32_val, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 2.5), config.value.f64_val, 0.001);
}

test "TypedConfig: deeply nested structs" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestConfig = struct {
        level1: struct {
            level2: struct {
                level3: struct {
                    value: []const u8,
                },
            },
        },
    };

    const toml_content =
        \\[level1.level2.level3]
        \\value = "deep"
    ;

    var config = try TypedConfig(TestConfig).loadFromString(allocator, toml_content, .toml);
    defer config.deinit();

    try testing.expectEqualStrings("deep", config.value.level1.level2.level3.value);
}

test "TypedConfig: JSONC format" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestConfig = struct {
        name: []const u8,
        port: u16,
    };

    const jsonc_content =
        \\{
        \\  // This is a comment
        \\  "name": "test",
        \\  "port": 8080
        \\}
    ;

    var config = try TypedConfig(TestConfig).loadFromString(allocator, jsonc_content, .jsonc);
    defer config.deinit();

    try testing.expectEqualStrings("test", config.value.name);
    try testing.expectEqual(@as(u16, 8080), config.value.port);
}

test "TypedConfig: JSON5 format" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestConfig = struct {
        name: []const u8,
        port: u16,
    };

    const json5_content =
        \\{
        \\  name: 'test',  // unquoted key, single quotes
        \\  port: 8080,    // trailing comma OK
        \\}
    ;

    var config = try TypedConfig(TestConfig).loadFromString(allocator, json5_content, .json5);
    defer config.deinit();

    try testing.expectEqualStrings("test", config.value.name);
    try testing.expectEqual(@as(u16, 8080), config.value.port);
}

test "TypedConfig: missing required field returns error" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestConfig = struct {
        required: []const u8,
    };

    const toml_content = ""; // Empty config

    const result = TypedConfig(TestConfig).loadFromString(allocator, toml_content, .toml);
    try testing.expectError(error.MissingRequiredField, result);
}

test "TypedConfig: integer overflow detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestConfig = struct {
        small: u8,
    };

    const toml_content =
        \\small = 999999
    ;

    const result = TypedConfig(TestConfig).loadFromString(allocator, toml_content, .toml);
    try testing.expectError(error.IntegerOverflow, result);
}

test "TypedConfig: invalid enum value returns error" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const LogLevel = enum { debug, info };
    const TestConfig = struct {
        level: LogLevel,
    };

    const toml_content =
        \\level = "invalid"
    ;

    const result = TypedConfig(TestConfig).loadFromString(allocator, toml_content, .toml);
    try testing.expectError(error.InvalidEnumValue, result);
}
