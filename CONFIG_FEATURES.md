# Configuration System Documentation

## Overview

zig-cli now includes a powerful configuration system supporting three popular formats:
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

### 2. Auto-discovery

The config system can automatically discover configuration files:

```zig
var config = try cli.config.discover(allocator, "myapp");
```

Search locations (in order):
1. `./myapp.{toml,json5,jsonc,json}`
2. `./.config/myapp.{toml,json5,jsonc,json}`
3. `~/.config/myapp/myapp.{toml,json5,jsonc,json}`

First found file is loaded.

### 3. Type-safe Access

```zig
// Typed getters with optional returns
const name = config.getString("name");        // ?[]const u8
const port = config.getInt("port");           // ?i64
const debug = config.getBool("debug");        // ?bool
const timeout = config.getFloat("timeout");   // ?f64

// Raw value access for complex types
const value = config.get("database");         // ?*Value
```

### 4. Nested Configuration

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

### 5. Format Auto-detection

Auto-detect based on file extension:

```zig
try config.loadFromFile("config.toml", .auto);  // Detects TOML
try config.loadFromFile("config.json5", .auto); // Detects JSON5
try config.loadFromFile("config.jsonc", .auto); // Detects JSONC
try config.loadFromFile("config.json", .auto);  // Treats as JSONC
```

Or specify explicitly:

```zig
try config.loadFromFile("myfile", .toml);
try config.loadFromFile("myfile", .jsonc);
try config.loadFromFile("myfile", .json5);
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

The `Config` type provides the high-level API:

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

## Usage Examples

### Basic Usage

```zig
const std = @import("std");
const cli = @import("zig-cli");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load config
    var config = try cli.config.load(allocator, "config.toml");
    defer config.deinit();

    // Use config values
    const port = config.getInt("port") orelse 8080;
    const host = config.getString("host") orelse "localhost";

    std.debug.print("Server: {s}:{d}\n", .{host, port});
}
```

### With CLI Integration

```zig
fn serverAction(ctx: *cli.Command.ParseContext) !void {
    const allocator = ctx.allocator;

    // Load config
    var config = cli.config.discover(allocator, "myserver") catch |err| {
        if (err == error.FileNotFound) {
            // No config file, use defaults
            std.debug.print("No config found, using defaults\n", .{});
            return;
        }
        return err;
    };
    defer config.deinit();

    // CLI options override config
    const port = if (ctx.getOption("port")) |p|
        try std.fmt.parseInt(u16, p, 10)
    else
        @intCast(config.getInt("port") orelse 8080);

    std.debug.print("Starting server on port {d}\n", .{port});
}
```

### Config with Nested Values

```zig
var config = try cli.config.load(allocator, "config.toml");
defer config.deinit();

// Access nested database config
if (config.get("database")) |db_value| {
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

        std.debug.print("Database: {s}:{d}\n", .{host, port});
    }
}
```

## File Examples

See `examples/configs/` for complete examples:

- `example.toml` - TOML with all features
- `example.jsonc` - JSONC with comments and trailing commas
- `example.json5` - JSON5 with extended syntax

Run `examples/config.zig` for a live demonstration.

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
var config = cli.config.load(allocator, "config.toml") catch |err| {
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

Test the config system:

```bash
# Run config example
zig build-exe examples/config.zig --dep zig-cli --mod zig-cli src/root.zig
./config
```

## Future Enhancements

Potential additions:
- [ ] YAML support
- [ ] Environment variable expansion
- [ ] Config validation schemas
- [ ] Hot-reload support
- [ ] Config migration tools
- [ ] Deep merge for complex configs
- [ ] Dotted path access (`database.host`)

## Summary

The configuration system adds approximately:
- **~1,200 lines of code** across 5 files
- **3 format parsers** with full feature support
- **Type-safe API** for accessing configuration
- **Auto-discovery** for easy setup
- **Zero runtime dependencies** - pure Zig stdlib

This brings zig-cli to feature parity with popular CLI frameworks while maintaining Zig's philosophy of explicitness and safety.
