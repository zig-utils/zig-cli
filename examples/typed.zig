const std = @import("std");
const cli = @import("zig-cli");

// ============================================================================
// Example 1: Type-Safe Command with Compile-Time Validation
// ============================================================================

/// Define your command options as a struct
/// Fields are automatically converted to CLI options with proper types
const GreetOptions = struct {
    name: []const u8,
    age: ?u16 = null,
    times: u8 = 1,
    verbose: bool = false,
    format: OutputFormat = .text,
};

const OutputFormat = enum {
    text,
    json,
    yaml,
};

/// Type-safe action function - gets typed context instead of strings
fn greetAction(ctx: *cli.Context(GreetOptions)) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(std.Options.debug_io, &buf);
    const stdout = &file_writer.interface;

    // Compile-time validated field access - no string lookups!
    const name = ctx.get(.name);
    const age = ctx.get(.age);
    const times = ctx.get(.times);
    const verbose = ctx.get(.verbose);
    const format = ctx.get(.format);

    // Or parse entire struct at once
    const opts = try ctx.parse();

    if (verbose) {
        try stdout.print("Running in verbose mode\n", .{});
        try stdout.print("Options: name={s}, age={?d}, times={d}, format={s}\n", .{
            opts.name,
            opts.age,
            opts.times,
            @tagName(opts.format),
        });
    }

    switch (format) {
        .text => {
            var i: u8 = 0;
            while (i < times) : (i += 1) {
                if (age) |a| {
                    try stdout.print("Hello, {s}! You are {d} years old.\n", .{ name, a });
                } else {
                    try stdout.print("Hello, {s}!\n", .{name});
                }
            }
        },
        .json => {
            try stdout.print("{{\"greeting\":\"Hello\",\"name\":\"{s}\"", .{name});
            if (age) |a| {
                try stdout.print(",\"age\":{d}", .{a});
            }
            try stdout.print("}}\n", .{});
        },
        .yaml => {
            try stdout.print("greeting: Hello\nname: {s}\n", .{name});
            if (age) |a| {
                try stdout.print("age: {d}\n", .{a});
            }
        },
    }
    try stdout.flush();
}

// ============================================================================
// Example 2: Type-Safe Configuration
// ============================================================================

const DatabaseConfig = struct {
    host: []const u8,
    port: u16,
    username: []const u8,
    password: []const u8,
    max_connections: u32 = 100,
};

const AppConfig = struct {
    app_name: []const u8,
    database: DatabaseConfig,
    log_level: LogLevel = .info,
    debug: bool = false,
};

const LogLevel = enum {
    debug,
    info,
    warn,
    @"error",
};

fn showTypedConfig(allocator: std.mem.Allocator) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(std.Options.debug_io, &buf);
    const stdout = &file_writer.interface;

    try stdout.print("\n=== Type-Safe Config Example ===\n", .{});

    // Create example TOML config
    const toml_content =
        \\app_name = "my-awesome-app"
        \\log_level = "debug"
        \\debug = true
        \\
        \\[database]
        \\host = "localhost"
        \\port = 5432
        \\username = "admin"
        \\password = "secret123"
        \\max_connections = 50
    ;

    // Load with compile-time type checking
    var config = try cli.config.loadFromString(
        AppConfig,
        allocator,
        toml_content,
        .toml,
    );
    defer config.deinit();

    // Access fields with full type safety - no optionals, no string parsing!
    try stdout.print("App: {s}\n", .{config.value.app_name});
    try stdout.print("Database: {s}:{d}\n", .{
        config.value.database.host,
        config.value.database.port,
    });
    try stdout.print("Max Connections: {d}\n", .{config.value.database.max_connections});
    try stdout.print("Log Level: {s}\n", .{@tagName(config.value.log_level)});
    try stdout.print("Debug: {}\n", .{config.value.debug});
    try stdout.flush();
}

// ============================================================================
// Main Example Runner
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(std.Options.debug_io, &buf);
    const stdout = &file_writer.interface;

    try stdout.print("=== zig-cli Type-Safe API Examples ===\n\n", .{});

    // Example 1: Type-safe command
    try stdout.print("=== Type-Safe Command Example ===\n", .{});
    try stdout.print("Creating typed command with GreetOptions struct...\n", .{});

    var typed_cmd = try cli.Command(GreetOptions).init(
        allocator,
        "greet",
        "Greet a user with type-safe options",
    );
    defer typed_cmd.deinit();

    _ = typed_cmd.setAction(greetAction);

    try stdout.print("Command has {} auto-generated options from struct fields\n", .{
        typed_cmd.command.options.items.len,
    });

    // Show the options that were created
    for (typed_cmd.command.options.items) |opt| {
        try stdout.print("  - {s}: {s} (required: {})\n", .{
            opt.name,
            @tagName(opt.option_type),
            opt.required,
        });
    }

    // Example 2: Type-safe config
    try stdout.flush();
    try showTypedConfig(allocator);

    // Benefits summary
    try stdout.print("\n=== Type Safety Benefits ===\n", .{});
    try stdout.print("  Compile-time field validation\n", .{});
    try stdout.print("  No string-based lookups\n", .{});
    try stdout.print("  Automatic type conversion\n", .{});
    try stdout.print("  IDE autocomplete support\n", .{});
    try stdout.print("  Catch errors at compile time, not runtime\n", .{});
    try stdout.print("  Zero-cost abstractions\n", .{});

    try stdout.print("\nComparison:\n", .{});
    try stdout.print("Runtime API:  ctx.getOption(\"name\") -> ?[]const u8\n", .{});
    try stdout.print("Typed API:    ctx.get(.name)        -> []const u8\n", .{});
    try stdout.print("              ^^^^^^^^ Compile-time validated enum field!\n", .{});
    try stdout.flush();
}
