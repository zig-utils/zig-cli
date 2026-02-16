# Configuration System Documentation

## Overview

zig-cli includes a powerful configuration system supporting three popular formats:
- **TOML** - Simple, readable configuration format
- **JSONC** - JSON with Comments (also handles standard JSON)
- **JSON5** - JSON with extended syntax (more JavaScript-like)

## Features

### 1. Multiple Format Support

Each format has its own strengths:

**TOML:**
- Simple, INI-like syntax
- Great for human editing
- Native support for nested tables
- Comments with `#`

**JSONC:**
- JSON with `//` and `/* */` comments
- Trailing commas allowed
- Familiar to JavaScript developers
- Works with standard JSON files too

**JSON5:**
- Unquoted object keys
- Single and double quotes for strings
- Trailing commas
- Hexadecimal numbers (`0x755`)
- Leading/trailing decimal points (`.5`, `50.`)
- Special values: `Infinity`, `-Infinity`, `NaN`
- Multi-line strings

### 2. Type-Safe Config Loading (Recommended)

Define your config schema as a Zig struct and get compile-time validation:

```zig
const AppConfig = struct {
    database: struct {
        host: []const u8,
        port: u16,
    },
    log_level: enum { debug, info, warn, @"error" } = .info,
    debug: bool = false,
};

// Load with full type checking
var config = try cli.config.load(AppConfig, allocator, "config.toml");
defer config.deinit();

// Direct field access - type-safe!
std.debug.print("DB: {s}:{d}\n", .{
    config.value.database.host,
    config.value.database.port,
});
```

### 3. Auto-discovery

The config system can automatically discover configuration files:

```zig
var config = try cli.config.discover(AppConfig, allocator, "myapp");
defer config.deinit();
```

Search locations (in order):
1. `./myapp.{toml,json5,jsonc,json}`
2. `./.config/myapp.{toml,json5,jsonc,json}`
3. `~/.config/myapp/myapp.{toml,json5,jsonc,json}`

First found file is loaded.

### 4. Untyped Access

For cases where you don't have a schema, use the raw `Config` type:

```zig
var raw_config = cli.config.Config.init(allocator);
defer raw_config.deinit();

try raw_config.loadFromFile("config.toml", .auto);

// Typed getters with optional returns
const name = raw_config.getString("name");        // ?[]const u8
const port = raw_config.getInt("port");           // ?i64
const debug = raw_config.getBool("debug");        // ?bool
const timeout = raw_config.getFloat("timeout");   // ?f64

// Raw value access for complex types
const value = raw_config.get("database");         // ?*Value
```

### 5. Nested Configuration

All formats support nested structures:

```toml
[database]
host = "localhost"
port = 5432

[database.pool]
size = 10
timeout = 30
```

```jsonc
{
  "database": {
    "host": "localhost",
    "port": 5432,
    "pool": {
      "size": 10,
      "timeout": 30
    }
  }
}
```

### 6. Format Auto-detection

Auto-detect based on file extension:

```zig
try raw_config.loadFromFile("config.toml", .auto);  // Detects TOML
try raw_config.loadFromFile("config.json5", .auto); // Detects JSON5
try raw_config.loadFromFile("config.jsonc", .auto); // Detects JSONC
try raw_config.loadFromFile("config.json", .auto);  // Treats as JSONC
```

Or specify explicitly:

```zig
try raw_config.loadFromFile("myfile", .toml);
try raw_config.loadFromFile("myfile", .jsonc);
try raw_config.loadFromFile("myfile", .json5);
```

## Implementation Details

### Parser Architecture

Each format has its own dedicated parser:

1. **TomlParser.zig** (~240 lines)
   - Section-based parsing
   - Support for tables and arrays
   - String and numeric values
   - Comment handling

2. **JsoncParser.zig** (~330 lines)
   - Standard JSON parser
   - `//` and `/* */` comment support
   - Trailing comma support
   - Escape sequence handling

3. **Json5Parser.zig** (~420 lines)
   - Extended JSON syntax
   - Unquoted keys
   - Single-quoted strings
   - Hexadecimal numbers
   - Infinity/NaN support
   - More flexible number syntax

### Value Types

Unified `Value` type across all formats:

```zig
pub const Value = union(enum) {
    null_value: void,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    array: []Value,
    table: std.StringHashMap(Value),
};
```

### Config Manager

The `Config` type provides the low-level API:

```zig
pub const Config = struct {
    allocator: std.mem.Allocator,
    data: std.StringHashMap(Value),

    // Loading
    pub fn loadFromFile(path, format) !void
    pub fn loadFromString(content, format) !void
    pub fn discover(allocator, app_name) !Config

    // Accessing
    pub fn get(key) ?*Value
    pub fn getString(key) ?[]const u8
    pub fn getInt(key) ?i64
    pub fn getBool(key) ?bool
    pub fn getFloat(key) ?f64

    // Merging
    pub fn merge(other) !void
};
```

### Typed Config Loader

The `ConfigLoader` provides the high-level typed API:

```zig
// These are available via cli.config namespace:
pub fn load(comptime T: type, allocator, path) !ConfigLoader(T)
pub fn loadFromString(comptime T: type, allocator, content, format) !ConfigLoader(T)
pub fn discover(comptime T: type, allocator, app_name) !ConfigLoader(T)
```

## Usage Examples

### Basic Typed Usage

```zig
const std = @import("std");
const cli = @import("zig-cli");

const ServerConfig = struct {
    host: []const u8 = "localhost",
    port: u16 = 8080,
    debug: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load typed config
    var config = try cli.config.load(ServerConfig, allocator, "server.toml");
    defer config.deinit();

    std.debug.print("Server: {s}:{d}\n", .{
        config.value.host,
        config.value.port,
    });
}
```

### With CLI Integration

```zig
fn serverAction(ctx: *cli.BaseCommand.ParseContext) !void {
    const allocator = ctx.allocator;

    const ServerConfig = struct {
        host: []const u8 = "localhost",
        port: u16 = 8080,
    };

    // Load typed config
    var config = cli.config.load(ServerConfig, allocator, "server.toml") catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Config not found, using defaults\n", .{});
            return;
        }
        return err;
    };
    defer config.deinit();

    // CLI options can override config values
    const port = if (ctx.getOption("port")) |p|
        try std.fmt.parseInt(u16, p, 10)
    else
        config.value.port;

    std.debug.print("Starting server on port {d}\n", .{port});
}
```

### Untyped Config with Nested Values

```zig
var raw_config = cli.config.Config.init(allocator);
defer raw_config.deinit();

try raw_config.loadFromFile("config.toml", .auto);

// Access nested database config
if (raw_config.get("database")) |db_value| {
    if (db_value.* == .table) {
        const db_table = &db_value.table;

        const host = if (db_table.get("host")) |h|
            if (h == .string) h.string else "localhost"
        else
            "localhost";

        const port = if (db_table.get("port")) |p|
            if (p == .integer) p.integer else 5432
        else
            5432;

        std.debug.print("Database: {s}:{d}\n", .{ host, port });
    }
}
```

## File Examples

See `examples/configs/` for complete examples:

- `example.toml` - TOML with all features
- `example.jsonc` - JSONC with comments and trailing commas
- `example.json5` - JSON5 with extended syntax

Build and run the config example:

```bash
zig build run-config
```

## Performance Considerations

- **Parsing is done once at startup** - negligible impact
- **No runtime overhead** - parsed values are stored in memory
- **Memory efficient** - uses arena allocation for config data
- **File size limits** - 10MB default maximum (configurable)

## Error Handling

All config operations use Zig error unions:

```zig
pub const ParseError = error{
    UnexpectedEndOfFile,
    InvalidSyntax,
    InvalidEscape,
    InvalidNumber,
    InvalidUnicode,
    OutOfMemory,
};
```

Errors are descriptive and can be handled gracefully:

```zig
var config = cli.config.load(MyConfig, allocator, "config.toml") catch |err| {
    switch (err) {
        error.FileNotFound => {
            std.debug.print("Config not found, using defaults\n", .{});
            // Continue with defaults
        },
        error.InvalidSyntax => {
            std.debug.print("Config file has invalid syntax\n", .{});
            return err;
        },
        else => return err,
    }
};
```

## Testing

```bash
# Run all tests including config tests
zig build test

# Run config example
zig build run-config
```

## Summary

The configuration system provides:
- **3 format parsers** with full feature support (TOML, JSONC, JSON5)
- **Type-safe API** via `cli.config.load(T, ...)` for compile-time schema validation
- **Untyped API** via `cli.config.Config` for dynamic config access
- **Auto-discovery** for easy setup
- **Zero runtime dependencies** - pure Zig stdlib
