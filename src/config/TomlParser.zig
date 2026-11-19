const std = @import("std");

const TomlParser = @This();

/// Maximum array nesting accepted by the parser, bounding recursive stack use.
pub const max_depth = 64;

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
depth: usize = 0,

pub fn init(allocator: std.mem.Allocator, source: []const u8) TomlParser {
    return .{
        .allocator = allocator,
        .source = source,
        .pos = 0,
    };
}

/// Parse a document, rejecting duplicate declarations and malformed arrays.
/// Keys and strings borrow source; the caller keeps it alive and frees the
/// returned tables/arrays with Value.deinit. Array nesting is capped at max_depth.
pub fn parse(self: *TomlParser) !std.StringHashMap(Value) {
    var root = std.StringHashMap(Value).init(self.allocator);
    errdefer {
        var value = Value{ .table = root };
        value.deinit(self.allocator);
    }

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

            // A table header cannot redefine a key or a previous table.
            if (root.contains(section_name)) return ParseError.InvalidSyntax;
            try root.put(section_name, Value{ .table = std.StringHashMap(Value).init(self.allocator) });

            self.pos = section_end + 1;
            try self.finishLine();
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

        const table = if (current_section) |section| blk: {
            const entry = root.getPtr(section) orelse return ParseError.InvalidSyntax;
            break :blk &entry.table;
        } else &root;
        if (table.contains(key)) return ParseError.InvalidSyntax;

        var value = try self.parseValue();
        errdefer value.deinit(self.allocator);
        try self.finishLine();
        try table.put(key, value);
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
        if (std.ascii.isWhitespace(ch) or ch == '#' or ch == ',' or ch == ']') break;
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
        if (self.source[self.pos] == '\n' or self.source[self.pos] == '\r') return ParseError.InvalidSyntax;
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
    if (self.depth >= max_depth) return ParseError.InvalidSyntax;
    self.depth += 1;
    defer self.depth -= 1;

    self.pos += 1; // Skip '['
    var items = std.ArrayList(Value).empty;
    errdefer {
        for (items.items) |*item| {
            item.deinit(self.allocator);
        }
        items.deinit(self.allocator);
    }

    while (true) {
        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len) return ParseError.InvalidSyntax;

        if (self.source[self.pos] == ',') return ParseError.InvalidSyntax;
        if (self.source[self.pos] == ']') {
            self.pos += 1;
            return Value{ .array = try items.toOwnedSlice(self.allocator) };
        }

        {
            var value = try self.parseValue();
            errdefer value.deinit(self.allocator);
            try items.append(self.allocator, value);
        }

        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len) return ParseError.InvalidSyntax;
        switch (self.source[self.pos]) {
            ',' => self.pos += 1,
            ']' => {
                self.pos += 1;
                return Value{ .array = try items.toOwnedSlice(self.allocator) };
            },
            else => return ParseError.InvalidSyntax,
        }
    }
}

fn skipWhitespace(self: *TomlParser) void {
    while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t')) {
        self.pos += 1;
    }
}

fn finishLine(self: *TomlParser) ParseError!void {
    self.skipWhitespace();
    if (self.pos < self.source.len and self.source[self.pos] == '#') {
        while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
    }
    if (self.pos == self.source.len) return;
    if (self.source[self.pos] == '\r') {
        self.pos += 1;
        if (self.pos == self.source.len or self.source[self.pos] != '\n') return ParseError.InvalidSyntax;
    }
    if (self.source[self.pos] != '\n') return ParseError.InvalidSyntax;
    self.pos += 1;
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

test "duplicate keys are rejected without leaking parsed values" {
    var parser = TomlParser.init(std.testing.allocator,
        \\rules = ["first"]
        \\rules = ["second"]
    );
    if (parser.parse()) |root| {
        var value = Value{ .table = root };
        defer value.deinit(std.testing.allocator);
        return error.ExpectedDuplicateKeyError;
    } else |err| {
        try std.testing.expectEqual(ParseError.InvalidSyntax, err);
    }
}

test "section duplicate keys are rejected and existing values are freed" {
    var parser = TomlParser.init(std.testing.allocator,
        \\root = ["allocated"]
        \\[metadata]
        \\tags = [["first"]]
        \\tags = ["second"]
    );
    try std.testing.expectError(ParseError.InvalidSyntax, parser.parse());
}

test "arrays must have a closing bracket" {
    const invalid = [_][]const u8{ "items = [ ", "items = [", "items = [\"first\"", "items = [\"first\", ", "items = [[\"first\"]" };
    for (invalid) |source| {
        var parser = TomlParser.init(std.testing.allocator, source);
        if (parser.parse()) |root| {
            var value = Value{ .table = root };
            defer value.deinit(std.testing.allocator);
            return error.ExpectedUnterminatedArrayError;
        } else |err| {
            try std.testing.expectEqual(ParseError.InvalidSyntax, err);
        }
    }
}

test "scalar and table declarations cannot conflict" {
    var parser = TomlParser.init(std.testing.allocator,
        \\metadata = "scalar"
        \\[metadata]
        \\version = "1"
    );
    try std.testing.expectError(ParseError.InvalidSyntax, parser.parse());
}

test "table headers cannot be declared twice including empty tables" {
    const invalid = [_][]const u8{
        "[metadata]\nversion = \"1\"\n[metadata]\nother = true",
        "[metadata]\n[metadata]",
        "metadata = [\"allocated\"]\n[metadata]",
    };
    for (invalid) |source| {
        var parser = TomlParser.init(std.testing.allocator, source);
        try std.testing.expectError(ParseError.InvalidSyntax, parser.parse());
    }
}

test "array elements require commas" {
    const invalid = [_][]const u8{ "items = [\"one\" \"two\"]", "items = [,]", "items = [1,,2]" };
    for (invalid) |source| {
        var parser = TomlParser.init(std.testing.allocator, source);
        try std.testing.expectError(ParseError.InvalidSyntax, parser.parse());
    }
}

test "arrays allow nested values comments and trailing commas" {
    var parser = TomlParser.init(std.testing.allocator,
        \\items = [1, true, ["nested",], # comment
        \\ 2.5, # another comment
        \\]
        \\[metadata]
        \\items = []
    );
    var root = Value{ .table = try parser.parse() };
    defer root.deinit(std.testing.allocator);
    const items = root.table.get("items").?.array;
    try std.testing.expectEqual(@as(usize, 4), items.len);
    try std.testing.expectEqual(@as(i64, 1), items[0].integer);
    try std.testing.expect(items[1].boolean);
    try std.testing.expectEqualStrings("nested", items[2].array[0].string);
    try std.testing.expectEqual(@as(f64, 2.5), items[3].float);
    try std.testing.expectEqual(@as(usize, 0), root.table.get("metadata").?.table.get("items").?.array.len);
}

fn parseWithAllocationFailures(backing: std.mem.Allocator) !void {
    // Force remap to take the allocation path on every run, independent of the heap layout.
    var no_resize = std.testing.FailingAllocator.init(backing, .{ .resize_fail_index = 0 });
    const allocator = no_resize.allocator();
    var parser = TomlParser.init(allocator,
        \\items = [["one", "two"], [1, 2]]
        \\[metadata]
        \\tags = ["first", "second"]
    );
    var root = Value{ .table = try parser.parse() };
    defer root.deinit(allocator);
}

test "parsing frees partial documents when allocation fails" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, parseWithAllocationFailures, .{});
}

test "array nesting is bounded before exhausting the stack" {
    var parser = TomlParser.init(std.testing.allocator, "items = " ++ nestedArray(65));
    if (parser.parse()) |root| {
        var value = Value{ .table = root };
        defer value.deinit(std.testing.allocator);
        return error.ExpectedNestingLimitError;
    } else |err| {
        try std.testing.expectEqual(ParseError.InvalidSyntax, err);
    }
}

fn nestedArray(comptime depth: usize) [depth * 2 + 1]u8 {
    var source: [depth * 2 + 1]u8 = undefined;
    @memset(source[0..depth], '[');
    source[depth] = '0';
    @memset(source[depth + 1 ..], ']');
    return source;
}

test "arrays at the nesting limit remain valid" {
    var parser = TomlParser.init(std.testing.allocator, "items = " ++ nestedArray(max_depth));
    var root = Value{ .table = try parser.parse() };
    defer root.deinit(std.testing.allocator);
    var item = root.table.getPtr("items").?;
    for (0..max_depth) |_| {
        try std.testing.expectEqual(@as(usize, 1), item.array.len);
        item = &item.array[0];
    }
    try std.testing.expectEqual(@as(i64, 0), item.integer);
}

test "entries must end at a newline and scalar values stay on their line" {
    const invalid = [_][]const u8{
        "name = \"one\" owner = \"two\"",
        "[metadata] owner = \"two\"",
        "owner =\n\"two\"",
        "owner\n= \"two\"",
        "owner = \"two\nlines\"",
    };
    for (invalid) |source| {
        var parser = TomlParser.init(std.testing.allocator, source);
        if (parser.parse()) |root| {
            var value = Value{ .table = root };
            defer value.deinit(std.testing.allocator);
            return error.ExpectedLineSyntaxError;
        } else |err| {
            try std.testing.expect(err == ParseError.InvalidSyntax or err == ParseError.InvalidValue);
        }
    }
}

test "line endings comments and distinct sections preserve valid values" {
    var parser = TomlParser.init(
        std.testing.allocator,
        "root = [1] # root\r\n[first] # first\r\nname = \"one\"\r\n[second]\nname = 'two' # EOF",
    );
    var root = Value{ .table = try parser.parse() };
    defer root.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 1), root.table.get("root").?.array[0].integer);
    try std.testing.expectEqualStrings("one", root.table.get("first").?.table.get("name").?.string);
    try std.testing.expectEqualStrings("two", root.table.get("second").?.table.get("name").?.string);
}
