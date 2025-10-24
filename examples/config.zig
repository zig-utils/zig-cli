const std = @import("std");
const cli = @import("zig-cli");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n=== Config File Examples ===\n\n", .{});

    // Example 1: Load TOML config
    try stdout.print("1. Loading TOML config...\n", .{});
    try demonstrateToml(allocator);

    // Example 2: Load JSONC config
    try stdout.print("\n2. Loading JSONC config...\n", .{});
    try demonstrateJsonc(allocator);

    // Example 3: Load JSON5 config
    try stdout.print("\n3. Loading JSON5 config...\n", .{});
    try demonstrateJson5(allocator);

    // Example 4: Auto-discovery
    try stdout.print("\n4. Config auto-discovery...\n", .{});
    try demonstrateDiscovery(allocator);

    try stdout.print("\n=== All examples completed! ===\n", .{});
}

fn demonstrateToml(allocator: std.mem.Allocator) !void {
    const toml_content =
        \\# Example TOML configuration
        \\name = "my-app"
        \\version = "1.0.0"
        \\debug = true
        \\port = 8080
        \\
        \\[database]
        \\host = "localhost"
        \\port = 5432
        \\name = "mydb"
        \\
        \\[server]
        \\workers = 4
        \\timeout = 30.5
    ;

    var config = cli.config.Config.init(allocator);
    defer config.deinit();

    try config.loadFromString(toml_content, .toml);

    const stdout = std.io.getStdOut().writer();

    // Read values
    if (config.getString("name")) |name| {
        try stdout.print("  App name: {s}\n", .{name});
    }

    if (config.getInt("port")) |port| {
        try stdout.print("  Port: {d}\n", .{port});
    }

    if (config.getBool("debug")) |debug| {
        try stdout.print("  Debug: {}\n", .{debug});
    }

    // Access nested values
    if (config.get("database")) |db_val| {
        if (db_val.* == .table) {
            try stdout.print("  Database config found\n", .{});
            if (db_val.table.get("host")) |host| {
                if (host == .string) {
                    try stdout.print("    Host: {s}\n", .{host.string});
                }
            }
        }
    }
}

fn demonstrateJsonc(allocator: std.mem.Allocator) !void {
    const jsonc_content =
        \\{
        \\  // Application settings
        \\  "name": "my-app",
        \\  "version": "1.0.0",
        \\  /* Multi-line comment
        \\     describing the config */
        \\  "features": [
        \\    "logging",
        \\    "caching",
        \\    "monitoring",  // trailing comma allowed
        \\  ],
        \\  "settings": {
        \\    "timeout": 30,
        \\    "retries": 3,
        \\  }
        \\}
    ;

    var config = cli.config.Config.init(allocator);
    defer config.deinit();

    try config.loadFromString(jsonc_content, .jsonc);

    const stdout = std.io.getStdOut().writer();

    if (config.getString("name")) |name| {
        try stdout.print("  App name: {s}\n", .{name});
    }

    if (config.get("features")) |features| {
        if (features.* == .array) {
            try stdout.print("  Features: ", .{});
            for (features.array) |feature| {
                if (feature == .string) {
                    try stdout.print("{s} ", .{feature.string});
                }
            }
            try stdout.print("\n", .{});
        }
    }
}

fn demonstrateJson5(allocator: std.mem.Allocator) !void {
    const json5_content =
        \\{
        \\  // JSON5 allows unquoted keys
        \\  name: 'my-app',  // single quotes allowed
        \\  version: '2.0.0',
        \\  // Hexadecimal numbers
        \\  permissions: 0x755,
        \\  // Infinity and NaN
        \\  maxValue: Infinity,
        \\  // Leading decimal point
        \\  ratio: .5,
        \\  // Trailing comma
        \\  tags: [
        \\    'cli',
        \\    'config',
        \\    'zig',
        \\  ],
        \\}
    ;

    var config = cli.config.Config.init(allocator);
    defer config.deinit();

    try config.loadFromString(json5_content, .json5);

    const stdout = std.io.getStdOut().writer();

    if (config.getString("name")) |name| {
        try stdout.print("  App name: {s}\n", .{name});
    }

    if (config.getInt("permissions")) |perms| {
        try stdout.print("  Permissions: 0o{o} (from hex 0x{x})\n", .{ perms, perms });
    }

    if (config.getFloat("maxValue")) |max| {
        try stdout.print("  Max value: {d}\n", .{max});
    }

    if (config.get("tags")) |tags| {
        if (tags.* == .array) {
            try stdout.print("  Tags: ", .{});
            for (tags.array) |tag| {
                if (tag == .string) {
                    try stdout.print("{s} ", .{tag.string});
                }
            }
            try stdout.print("\n", .{});
        }
    }
}

fn demonstrateDiscovery(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    // Try to discover config for "myapp"
    var config = cli.config.discover(allocator, "myapp") catch |err| {
        try stdout.print("  No config file found (this is expected): {}\n", .{err});
        return;
    };
    defer config.deinit();

    try stdout.print("  Config file discovered and loaded!\n", .{});

    // Print all keys
    var iter = config.data.iterator();
    while (iter.next()) |entry| {
        try stdout.print("    {s}: ", .{entry.key_ptr.*});
        switch (entry.value_ptr.*) {
            .string => |s| try stdout.print("{s}\n", .{s}),
            .integer => |i| try stdout.print("{d}\n", .{i}),
            .boolean => |b| try stdout.print("{}\n", .{b}),
            .float => |f| try stdout.print("{d}\n", .{f}),
            else => try stdout.print("(complex value)\n", .{}),
        }
    }
}
