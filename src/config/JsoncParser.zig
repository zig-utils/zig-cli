const std = @import("std");

const JsoncParser = @This();

/// JSONC = JSON with Comments (supports // and /* */ comments)
/// Also supports trailing commas
pub const Value = union(enum) {
    null_value: void,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    array: []Value,
    object: std.StringHashMap(Value),

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .array => |arr| {
                for (arr) |*item| {
                    item.deinit(allocator);
                }
                allocator.free(arr);
            },
            .object => |*obj| {
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    var val = entry.value_ptr.*;
                    val.deinit(allocator);
                }
                obj.deinit();
            },
            else => {},
        }
    }
};

pub const ParseError = error{
    UnexpectedEndOfFile,
    InvalidSyntax,
    InvalidEscape,
    InvalidNumber,
    InvalidUnicode,
    OutOfMemory,
};

allocator: std.mem.Allocator,
source: []const u8,
pos: usize,

pub fn init(allocator: std.mem.Allocator, source: []const u8) JsoncParser {
    return .{
        .allocator = allocator,
        .source = source,
        .pos = 0,
    };
}

pub fn parse(self: *JsoncParser) !Value {
    self.skipWhitespaceAndComments();
    return try self.parseValue();
}

fn parseValue(self: *JsoncParser) ParseError!Value {
    self.skipWhitespaceAndComments();

    if (self.pos >= self.source.len) {
        return ParseError.UnexpectedEndOfFile;
    }

    const c = self.source[self.pos];

    return switch (c) {
        '{' => try self.parseObject(),
        '[' => try self.parseArray(),
        '"' => try self.parseString(),
        't', 'f' => try self.parseBoolean(),
        'n' => try self.parseNull(),
        '-', '0'...'9' => try self.parseNumber(),
        else => ParseError.InvalidSyntax,
    };
}

fn parseObject(self: *JsoncParser) !Value {
    self.pos += 1; // Skip '{'
    var obj = std.StringHashMap(Value).init(self.allocator);
    errdefer {
        var iter = obj.iterator();
        while (iter.next()) |entry| {
            var val = entry.value_ptr.*;
            val.deinit(self.allocator);
        }
        obj.deinit();
    }

    self.skipWhitespaceAndComments();

    if (self.pos < self.source.len and self.source[self.pos] == '}') {
        self.pos += 1;
        return Value{ .object = obj };
    }

    while (self.pos < self.source.len) {
        self.skipWhitespaceAndComments();

        // Parse key
        if (self.pos >= self.source.len or self.source[self.pos] != '"') {
            return ParseError.InvalidSyntax;
        }

        const key_value = try self.parseString();
        const key = key_value.string;

        self.skipWhitespaceAndComments();

        // Expect ':'
        if (self.pos >= self.source.len or self.source[self.pos] != ':') {
            return ParseError.InvalidSyntax;
        }
        self.pos += 1;

        // Parse value
        const value = try self.parseValue();
        try obj.put(key, value);

        self.skipWhitespaceAndComments();

        if (self.pos >= self.source.len) {
            return ParseError.UnexpectedEndOfFile;
        }

        if (self.source[self.pos] == '}') {
            self.pos += 1;
            break;
        }

        if (self.source[self.pos] == ',') {
            self.pos += 1;
            self.skipWhitespaceAndComments();
            // Allow trailing comma
            if (self.pos < self.source.len and self.source[self.pos] == '}') {
                self.pos += 1;
                break;
            }
            continue;
        }

        return ParseError.InvalidSyntax;
    }

    return Value{ .object = obj };
}

fn parseArray(self: *JsoncParser) !Value {
    self.pos += 1; // Skip '['
    var items = std.ArrayList(Value).init(self.allocator);
    errdefer {
        for (items.items) |*item| {
            item.deinit(self.allocator);
        }
        items.deinit();
    }

    self.skipWhitespaceAndComments();

    if (self.pos < self.source.len and self.source[self.pos] == ']') {
        self.pos += 1;
        return Value{ .array = try items.toOwnedSlice() };
    }

    while (self.pos < self.source.len) {
        const value = try self.parseValue();
        try items.append(value);

        self.skipWhitespaceAndComments();

        if (self.pos >= self.source.len) {
            return ParseError.UnexpectedEndOfFile;
        }

        if (self.source[self.pos] == ']') {
            self.pos += 1;
            break;
        }

        if (self.source[self.pos] == ',') {
            self.pos += 1;
            self.skipWhitespaceAndComments();
            // Allow trailing comma
            if (self.pos < self.source.len and self.source[self.pos] == ']') {
                self.pos += 1;
                break;
            }
            continue;
        }

        return ParseError.InvalidSyntax;
    }

    return Value{ .array = try items.toOwnedSlice() };
}

fn parseString(self: *JsoncParser) !Value {
    self.pos += 1; // Skip opening '"'

    var str = std.ArrayList(u8).init(self.allocator);
    errdefer str.deinit();

    while (self.pos < self.source.len) {
        const c = self.source[self.pos];

        if (c == '"') {
            self.pos += 1;
            return Value{ .string = try str.toOwnedSlice() };
        }

        if (c == '\\') {
            self.pos += 1;
            if (self.pos >= self.source.len) {
                return ParseError.InvalidEscape;
            }

            const escaped = self.source[self.pos];
            const unescaped: u8 = switch (escaped) {
                '"' => '"',
                '\\' => '\\',
                '/' => '/',
                'b' => '\x08',
                'f' => '\x0C',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                else => return ParseError.InvalidEscape,
            };

            try str.append(unescaped);
            self.pos += 1;
        } else {
            try str.append(c);
            self.pos += 1;
        }
    }

    return ParseError.UnexpectedEndOfFile;
}

fn parseNumber(self: *JsoncParser) !Value {
    const start = self.pos;

    if (self.source[self.pos] == '-') {
        self.pos += 1;
    }

    if (self.pos >= self.source.len or !std.ascii.isDigit(self.source[self.pos])) {
        return ParseError.InvalidNumber;
    }

    var is_float = false;

    while (self.pos < self.source.len) {
        const c = self.source[self.pos];
        if (c == '.' or c == 'e' or c == 'E') {
            is_float = true;
        } else if (!std.ascii.isDigit(c) and c != '+' and c != '-') {
            break;
        }
        self.pos += 1;
    }

    const num_str = self.source[start..self.pos];

    if (is_float) {
        const f = std.fmt.parseFloat(f64, num_str) catch return ParseError.InvalidNumber;
        return Value{ .float = f };
    } else {
        const i = std.fmt.parseInt(i64, num_str, 10) catch return ParseError.InvalidNumber;
        return Value{ .integer = i };
    }
}

fn parseBoolean(self: *JsoncParser) !Value {
    if (self.pos + 4 <= self.source.len and std.mem.eql(u8, self.source[self.pos .. self.pos + 4], "true")) {
        self.pos += 4;
        return Value{ .boolean = true };
    }

    if (self.pos + 5 <= self.source.len and std.mem.eql(u8, self.source[self.pos .. self.pos + 5], "false")) {
        self.pos += 5;
        return Value{ .boolean = false };
    }

    return ParseError.InvalidSyntax;
}

fn parseNull(self: *JsoncParser) !Value {
    if (self.pos + 4 <= self.source.len and std.mem.eql(u8, self.source[self.pos .. self.pos + 4], "null")) {
        self.pos += 4;
        return Value{ .null_value = {} };
    }

    return ParseError.InvalidSyntax;
}

fn skipWhitespaceAndComments(self: *JsoncParser) void {
    while (self.pos < self.source.len) {
        const c = self.source[self.pos];

        // Whitespace
        if (std.ascii.isWhitespace(c)) {
            self.pos += 1;
            continue;
        }

        // Single-line comment
        if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
            self.pos += 2;
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.pos += 1;
            }
            continue;
        }

        // Multi-line comment
        if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '*') {
            self.pos += 2;
            while (self.pos + 1 < self.source.len) {
                if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') {
                    self.pos += 2;
                    break;
                }
                self.pos += 1;
            }
            continue;
        }

        break;
    }
}
