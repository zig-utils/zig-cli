const std = @import("std");

const TomlParser = @This();

pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
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
            .table => |*table| {
                var iter = table.iterator();
                while (iter.next()) |entry| {
                    var val = entry.value_ptr.*;
                    val.deinit(allocator);
                }
                table.deinit();
            },
            else => {},
        }
    }
};

pub const ParseError = error{
    InvalidSyntax,
    UnexpectedToken,
    InvalidValue,
    OutOfMemory,
};

allocator: std.mem.Allocator,
source: []const u8,
pos: usize,

pub fn init(allocator: std.mem.Allocator, source: []const u8) TomlParser {
    return .{
        .allocator = allocator,
        .source = source,
        .pos = 0,
    };
}

pub fn parse(self: *TomlParser) !std.StringHashMap(Value) {
    var root = std.StringHashMap(Value).init(self.allocator);
    errdefer root.deinit();

    var current_section: ?[]const u8 = null;

    while (self.pos < self.source.len) {
        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len) break;

        const c = self.source[self.pos];

        if (c == '[') {
            // Section header
            self.pos += 1;
            const section_end = std.mem.indexOfScalarPos(u8, self.source, self.pos, ']') orelse
                return ParseError.InvalidSyntax;

            const section_name = std.mem.trim(u8, self.source[self.pos..section_end], &std.ascii.whitespace);
            current_section = section_name;

            // Create or get the table for this section
            const get_or_put = try root.getOrPut(section_name);
            if (!get_or_put.found_existing) {
                get_or_put.value_ptr.* = Value{ .table = std.StringHashMap(Value).init(self.allocator) };
            }

            self.pos = section_end + 1;
            continue;
        }

        // Key-value pair
        const key = try self.parseKey();
        self.skipWhitespace();

        if (self.pos >= self.source.len or self.source[self.pos] != '=') {
            return ParseError.InvalidSyntax;
        }
        self.pos += 1; // Skip '='
        self.skipWhitespace();

        const value = try self.parseValue();

        if (current_section) |section| {
            var entry = root.getPtr(section) orelse return ParseError.InvalidSyntax;
            try entry.table.put(key, value);
        } else {
            try root.put(key, value);
        }
    }

    return root;
}

fn parseKey(self: *TomlParser) ![]const u8 {
    self.skipWhitespace();

    const start = self.pos;
    while (self.pos < self.source.len) {
        const c = self.source[self.pos];
        if (c == '=' or std.ascii.isWhitespace(c)) break;
        self.pos += 1;
    }

    return self.source[start..self.pos];
}

fn parseValue(self: *TomlParser) ParseError!Value {
    self.skipWhitespace();

    if (self.pos >= self.source.len) {
        return ParseError.UnexpectedToken;
    }

    const c = self.source[self.pos];

    // String
    if (c == '"' or c == '\'') {
        return try self.parseString();
    }

    // Array
    if (c == '[') {
        return try self.parseArray();
    }

    // Boolean or number
    const start = self.pos;
    while (self.pos < self.source.len) {
        const ch = self.source[self.pos];
        if (std.ascii.isWhitespace(ch) or ch == '#' or ch == '\n') break;
        self.pos += 1;
    }

    const token = std.mem.trim(u8, self.source[start..self.pos], &std.ascii.whitespace);

    // Boolean
    if (std.mem.eql(u8, token, "true")) {
        return Value{ .boolean = true };
    }
    if (std.mem.eql(u8, token, "false")) {
        return Value{ .boolean = false };
    }

    // Try to parse as number
    if (std.mem.indexOfScalar(u8, token, '.') != null) {
        // Float
        const f = std.fmt.parseFloat(f64, token) catch return ParseError.InvalidValue;
        return Value{ .float = f };
    } else {
        // Integer
        const i = std.fmt.parseInt(i64, token, 10) catch return ParseError.InvalidValue;
        return Value{ .integer = i };
    }
}

fn parseString(self: *TomlParser) !Value {
    const quote = self.source[self.pos];
    self.pos += 1;

    const start = self.pos;
    while (self.pos < self.source.len) {
        if (self.source[self.pos] == quote) {
            const str = self.source[start..self.pos];
            self.pos += 1;
            return Value{ .string = str };
        }
        self.pos += 1;
    }

    return ParseError.InvalidSyntax;
}

fn parseArray(self: *TomlParser) !Value {
    self.pos += 1; // Skip '['
    var items = std.ArrayList(Value).init(self.allocator);
    errdefer {
        for (items.items) |*item| {
            item.deinit(self.allocator);
        }
        items.deinit();
    }

    while (self.pos < self.source.len) {
        self.skipWhitespace();

        if (self.source[self.pos] == ']') {
            self.pos += 1;
            break;
        }

        const value = try self.parseValue();
        try items.append(value);

        self.skipWhitespace();
        if (self.pos < self.source.len and self.source[self.pos] == ',') {
            self.pos += 1;
        }
    }

    return Value{ .array = try items.toOwnedSlice() };
}

fn skipWhitespace(self: *TomlParser) void {
    while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
        self.pos += 1;
    }
}

fn skipWhitespaceAndComments(self: *TomlParser) void {
    while (self.pos < self.source.len) {
        if (std.ascii.isWhitespace(self.source[self.pos])) {
            self.pos += 1;
            continue;
        }

        if (self.source[self.pos] == '#') {
            // Skip comment line
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.pos += 1;
            }
            continue;
        }

        break;
    }
}
