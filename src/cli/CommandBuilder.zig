const std = @import("std");
const Command = @import("Command.zig");
const Option = @import("Option.zig");
const Argument = @import("Argument.zig");

/// Type-safe command builder that validates options/arguments at compile time
///
/// Example:
/// ```
/// const GreetOpts = struct {
///     name: []const u8,
///     age: ?u16 = null,
///     verbose: bool = false,
/// };
///
/// var cmd = try TypedCommand(GreetOpts).init(allocator, "greet", "Greet user");
/// cmd.setAction(greetAction);
/// ```
pub fn TypedCommand(comptime T: type) type {
    // Validate T is a struct at compile time
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("TypedCommand requires a struct type, got: " ++ @typeName(T));
    }

    return struct {
        command: *Command,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, name: []const u8, description: []const u8) !Self {
            const cmd = try Command.init(allocator, name, description);

            // Auto-generate options from struct fields
            const fields = type_info.@"struct".fields;
            inline for (fields) |field| {
                const opt = createOptionFromField(field);
                _ = try cmd.addOption(opt);
            }

            return .{
                .command = cmd,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.command.deinit();
            self.allocator.destroy(self.command);
        }

        fn createOptionFromField(comptime field: std.builtin.Type.StructField) Option {
            const field_type = field.type;

            // Determine if optional
            const field_info = @typeInfo(field_type);
            const is_optional = field_info == .optional;
            const base_type = if (is_optional) field_info.optional.child else field_type;

            // Map Zig types to Option types
            const option_type: Option.OptionType = switch (@typeInfo(base_type)) {
                .bool => .bool,
                .int => .int,
                .float => .float,
                .pointer => |ptr| blk: {
                    if (ptr.size == .slice and ptr.child == u8) {
                        break :blk .string;
                    }
                    @compileError("Unsupported pointer type for field '" ++ field.name ++ "': " ++ @typeName(field_type));
                },
                .@"enum" => .string, // Enums stored as strings, validated on parse
                else => @compileError("Unsupported type for field '" ++ field.name ++ "': " ++ @typeName(field_type)),
            };

            var opt = Option.init(field.name, field.name, "Auto-generated option for " ++ field.name, option_type);

            // Set required based on whether it's optional
            const has_default = field.default_value_ptr != null;
            opt = opt.withRequired(!is_optional and !has_default);

            // Note: Default values are handled at runtime during parsing
            // We just mark the option as not required if it has a default

            return opt;
        }

        pub fn setAction(self: *Self, comptime action: TypedAction(T)) *Self {
            self.command.action = wrapTypedAction(T, action);
            return self;
        }

        pub fn getCommand(self: *Self) *Command {
            return self.command;
        }
    };
}

/// Type-safe parse context that provides compile-time validated field access
pub fn TypedContext(comptime T: type) type {
    return struct {
        parse_context: *Command.ParseContext,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(parse_context: *Command.ParseContext) Self {
            return .{
                .parse_context = parse_context,
                .allocator = parse_context.allocator,
            };
        }

        /// Get a field value with compile-time type checking
        ///
        /// Example: const name = ctx.get(.name);
        pub fn get(self: *Self, comptime field: std.meta.FieldEnum(T)) TypedFieldType(T, field) {
            const field_name = @tagName(field);
            const field_info = std.meta.fieldInfo(T, field);
            const FieldType = field_info.type;

            const type_info = @typeInfo(FieldType);
            const is_optional = type_info == .optional;
            const base_type = if (is_optional) type_info.optional.child else FieldType;

            const value_str = self.parse_context.getOption(field_name);

            // If no value and it's optional, return null
            if (value_str == null) {
                if (is_optional) {
                    return null;
                }
                // Should not happen if validation worked, but handle gracefully
                if (field_info.default_value_ptr) |default_ptr| {
                    return @as(*const FieldType, @ptrCast(@alignCast(default_ptr))).*;
                }
                @panic("Missing required field: " ++ field_name);
            }

            const str = value_str.?;
            const parsed = parseValue(base_type, str) catch |err| {
                std.debug.print("Failed to parse field '{s}': {}\n", .{ field_name, err });
                @panic("Parse error");
            };

            if (is_optional) {
                return parsed;
            }
            return parsed;
        }

        fn parseValue(comptime ValueType: type, str: []const u8) !ValueType {
            return switch (@typeInfo(ValueType)) {
                .bool => std.mem.eql(u8, str, "true"),
                .int => try std.fmt.parseInt(ValueType, str, 10),
                .float => try std.fmt.parseFloat(ValueType, str),
                .pointer => |ptr| blk: {
                    if (ptr.size == .slice and ptr.child == u8) {
                        break :blk str;
                    }
                    return error.UnsupportedType;
                },
                .@"enum" => std.meta.stringToEnum(ValueType, str) orelse return error.InvalidEnumValue,
                else => error.UnsupportedType,
            };
        }

        /// Parse the entire context into a typed struct
        pub fn parse(self: *Self) !T {
            var result: T = undefined;
            const fields = @typeInfo(T).@"struct".fields;

            inline for (fields) |field| {
                @field(result, field.name) = self.get(@field(std.meta.FieldEnum(T), field.name));
            }

            return result;
        }
    };
}

fn TypedFieldType(comptime T: type, comptime field: std.meta.FieldEnum(T)) type {
    return std.meta.fieldInfo(T, field).type;
}

/// Type-safe action function signature
pub fn TypedAction(comptime T: type) type {
    return *const fn (ctx: *TypedContext(T)) anyerror!void;
}

/// Wrap a typed action to work with the regular Command.ParseContext
fn wrapTypedAction(comptime T: type, comptime typed_action: TypedAction(T)) Command.CommandAction {
    const Wrapper = struct {
        fn wrapper(ctx: *Command.ParseContext) anyerror!void {
            var typed_ctx = TypedContext(T).init(ctx);
            try typed_action(&typed_ctx);
        }
    };
    return Wrapper.wrapper;
}

// ============================================================================
// Tests
// ============================================================================

test "TypedCommand: basic struct with primitives" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestOpts = struct {
        name: []const u8,
        count: u32 = 1,
        verbose: bool = false,
    };

    var cmd = try TypedCommand(TestOpts).init(allocator, "test", "Test command");
    defer cmd.deinit();

    // Verify options were created
    try testing.expectEqual(@as(usize, 3), cmd.command.options.items.len);

    // Verify option types
    try testing.expectEqual(Option.OptionType.string, cmd.command.options.items[0].option_type);
    try testing.expectEqual(Option.OptionType.int, cmd.command.options.items[1].option_type);
    try testing.expectEqual(Option.OptionType.bool, cmd.command.options.items[2].option_type);

    // Verify required flags
    try testing.expect(cmd.command.options.items[0].required); // name is required
    try testing.expect(!cmd.command.options.items[1].required); // count has default
    try testing.expect(!cmd.command.options.items[2].required); // verbose has default
}

test "TypedCommand: optional fields" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestOpts = struct {
        required: []const u8,
        optional: ?u16 = null,
    };

    var cmd = try TypedCommand(TestOpts).init(allocator, "test", "Test");
    defer cmd.deinit();

    try testing.expectEqual(@as(usize, 2), cmd.command.options.items.len);
    try testing.expect(cmd.command.options.items[0].required);
    try testing.expect(!cmd.command.options.items[1].required);
}

test "TypedCommand: enum fields" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const LogLevel = enum { debug, info, warn };
    const TestOpts = struct {
        level: LogLevel = .info,
    };

    var cmd = try TypedCommand(TestOpts).init(allocator, "test", "Test");
    defer cmd.deinit();

    try testing.expectEqual(@as(usize, 1), cmd.command.options.items.len);
    try testing.expectEqual(Option.OptionType.string, cmd.command.options.items[0].option_type);
}

test "TypedContext: get required fields" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestOpts = struct {
        name: []const u8,
        count: u32,
    };

    var parse_ctx = Command.ParseContext.init(allocator, "test");
    defer parse_ctx.deinit();

    try parse_ctx.options.put("name", "Alice");
    try parse_ctx.options.put("count", "42");

    var typed_ctx = TypedContext(TestOpts).init(&parse_ctx);

    const name = typed_ctx.get(.name);
    const count = typed_ctx.get(.count);

    try testing.expectEqualStrings("Alice", name);
    try testing.expectEqual(@as(u32, 42), count);
}

test "TypedContext: get optional fields" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestOpts = struct {
        required: []const u8,
        optional: ?u16 = null,
    };

    var parse_ctx = Command.ParseContext.init(allocator, "test");
    defer parse_ctx.deinit();

    try parse_ctx.options.put("required", "test");

    var typed_ctx = TypedContext(TestOpts).init(&parse_ctx);

    const required = typed_ctx.get(.required);
    const optional = typed_ctx.get(.optional);

    try testing.expectEqualStrings("test", required);
    try testing.expectEqual(@as(?u16, null), optional);
}

test "TypedContext: parse entire struct" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestOpts = struct {
        name: []const u8,
        age: u8,
        active: bool,
    };

    var parse_ctx = Command.ParseContext.init(allocator, "test");
    defer parse_ctx.deinit();

    try parse_ctx.options.put("name", "Bob");
    try parse_ctx.options.put("age", "30");
    try parse_ctx.options.put("active", "true");

    var typed_ctx = TypedContext(TestOpts).init(&parse_ctx);

    const opts = try typed_ctx.parse();

    try testing.expectEqualStrings("Bob", opts.name);
    try testing.expectEqual(@as(u8, 30), opts.age);
    try testing.expectEqual(true, opts.active);
}

test "TypedContext: enum parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const LogLevel = enum { debug, info, warn, @"error" };
    const TestOpts = struct {
        level: LogLevel,
    };

    var parse_ctx = Command.ParseContext.init(allocator, "test");
    defer parse_ctx.deinit();

    try parse_ctx.options.put("level", "debug");

    var typed_ctx = TypedContext(TestOpts).init(&parse_ctx);

    const level = typed_ctx.get(.level);
    try testing.expectEqual(LogLevel.debug, level);
}

test "TypedCommand: all integer types" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestOpts = struct {
        u8_val: u8 = 1,
        u16_val: u16 = 2,
        u32_val: u32 = 3,
        u64_val: u64 = 4,
        i8_val: i8 = -1,
        i16_val: i16 = -2,
        i32_val: i32 = -3,
        i64_val: i64 = -4,
    };

    var cmd = try TypedCommand(TestOpts).init(allocator, "test", "Test");
    defer cmd.deinit();

    try testing.expectEqual(@as(usize, 8), cmd.command.options.items.len);
    for (cmd.command.options.items) |opt| {
        try testing.expectEqual(Option.OptionType.int, opt.option_type);
    }
}

test "TypedCommand: float types" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestOpts = struct {
        f32_val: f32 = 1.5,
        f64_val: f64 = 2.5,
    };

    var cmd = try TypedCommand(TestOpts).init(allocator, "test", "Test");
    defer cmd.deinit();

    try testing.expectEqual(@as(usize, 2), cmd.command.options.items.len);
    for (cmd.command.options.items) |opt| {
        try testing.expectEqual(Option.OptionType.float, opt.option_type);
    }
}
