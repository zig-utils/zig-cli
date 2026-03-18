# Type-Safe API - zig-cli

## Overview

zig-cli now includes a **fully type-safe API layer** that leverages Zig's powerful comptime features to provide compile-time validation, zero runtime overhead, and excellent developer experience.

## Key Benefits

### 1. Compile-Time Validation ✨

**Before (Runtime API):**
```zig
const name = ctx.getOption("name");  // Typo in "name" only caught at runtime!
//                         ^^^^^^ String literal - no compile-time checking
```

**After (Typed API):**
```zig
const name = ctx.get(.name);  // Typo caught at compile time!
//                   ^^^^^ Enum field - validated by compiler
```

### 2. Zero Runtime Overhead 🚀

The typed API is implemented using Zig's comptime features, which means:
- All type checking happens at compile time
- No runtime reflection or parsing
- Same performance as hand-written code
- Zero-cost abstraction

### 3. Superior Developer Experience 💡

- **IDE Autocomplete**: Full IntelliSense/LSP support for field names
- **Type Inference**: No need for manual type casting
- **Documentation**: Self-documenting code through type definitions
- **Refactoring**: Rename fields with confidence

## Features

### 1. TypedCommand

Auto-generate CLI options from a struct definition.

**Example:**
```zig
const ServerOptions = struct {
    port: u16 = 8080,
    host: []const u8 = "localhost",
    workers: u8 = 4,
    verbose: bool = false,
    log_level: enum { debug, info, warn, @"error" } = .info,
};

var cmd = try cli.TypedCommand(ServerOptions).init(allocator, "serve", "Start the server");
defer cmd.deinit();
```

**What happens under the hood:**
- Struct fields → CLI options automatically
- Field types → Option types (string, int, float, bool, enum)
- Optionals (`?T`) → Optional CLI options
- Default values → Option defaults
- Required fields → Required options

### 2. TypedContext

Access parsed options with compile-time validation.

**API:**
```zig
fn serverAction(ctx: *cli.TypedContext(ServerOptions)) !void {
    // Individual field access
    const port = ctx.get(.port);           // u16
    const host = ctx.get(.host);           // []const u8
    const log_level = ctx.get(.log_level); // enum

    // Or parse entire struct
    const opts = try ctx.parse();  // Returns ServerOptions

    std.debug.print("Starting server on {s}:{d}\n", .{opts.host, opts.port});
}
```

**Type Safety:**
- Field names validated at compile time
- Types automatically inferred
- No optionals for required fields
- Compile error if field doesn't exist

### 3. TypedConfig

Load configuration files with compile-time schema validation.

**Example:**
```zig
const AppConfig = struct {
    app_name: []const u8,
    database: struct {
        host: []const u8,
        port: u16,
        username: []const u8,
        password: []const u8,
        pool_size: u32 = 100,
    },
    features: struct {
        auth: bool = true,
        metrics: bool = false,
    },
    log_level: enum { debug, info, warn, @"error" } = .info,
};

// Load with full type checking
var config = try cli.config.loadTyped(AppConfig, allocator, "config.toml");
defer config.deinit();

// Access fields directly
const db_url = try std.fmt.allocPrint(allocator, "{s}:{d}", .{
    config.value.database.host,
    config.value.database.port,
});
```

**Supported Types:**
- ✅ Primitives: `bool`, `i8`-`i64`, `u8`-`u64`, `f32`, `f64`
- ✅ Strings: `[]const u8`
- ✅ Enums: Any Zig enum
- ✅ Optionals: `?T`
- ✅ Nested structs: Arbitrary depth
- ✅ Fixed arrays: `[N]T`

**Validation:**
- Missing required fields → Compile error
- Type mismatches → Runtime error with clear message
- Integer overflow → Checked and reported
- Invalid enum values → Error

### 4. TypedMiddleware

Type-safe middleware context with compile-time field validation.

**Example:**
```zig
const RequestContext = struct {
    request_id: []const u8 = "",
    user_id: []const u8 = "",
    role: enum { admin, user, guest } = .guest,
    authenticated: bool = false,
    start_time: i64 = 0,
};

fn authMiddleware(ctx: *cli.TypedMiddleware(RequestContext)) !bool {
    // Compile-time validated field access
    ctx.set(.user_id, "12345");
    ctx.set(.role, .admin);  // Enum - type checked!
    ctx.set(.authenticated, true);
    ctx.set(.start_time, std.time.milliTimestamp());

    // Type-safe retrieval
    if (ctx.get(.role) == .admin) {
        std.debug.print("Admin access\n", .{});
    }

    return true;
}

// Use in chain
var chain = cli.TypedMiddlewareChain(RequestContext).init(allocator);
defer chain.deinit();

try chain.useTyped(authMiddleware, "auth");
try chain.use(someRegularMiddleware);  // Can mix typed and regular
```

**Benefits:**
- No string keys → Compile-time field validation
- No type casting → Direct type access
- Enum support → Type-safe state management
- IDE support → Autocomplete for all fields

## Implementation Details

### How It Works

1. **Comptime Introspection**: Uses `@typeInfo()` to inspect struct fields at compile time
2. **Code Generation**: Generates wrapper code that bridges typed and runtime APIs
3. **Zero Overhead**: All type info resolved at compile time, no runtime cost
4. **Compatibility**: Typed API wraps runtime API, can be mixed freely

### Example: What Gets Generated

**Your code:**
```zig
const Opts = struct {
    name: []const u8,
    count: u32 = 1,
};
```

**Generated (conceptually):**
```zig
// Options auto-created
Option.init("name", "name", "Auto-generated", .string).withRequired(true);
Option.init("count", "count", "Auto-generated", .int).withDefault("1");

// Type-safe accessor
fn get(ctx, comptime field) FieldType(Opts, field) {
    comptime {
        // Validates field exists at compile time
        _ = std.meta.fieldInfo(Opts, field);
    }
    const str = ctx.parse_context.getOption(@tagName(field)).?;
    return parseValue(FieldType(Opts, field), str);
}
```

## Migration Guide

### Runtime → Typed API

**Before:**
```zig
fn myAction(ctx: *cli.Command.ParseContext) !void {
    const name_opt = ctx.getOption("name");
    const name = name_opt orelse return error.MissingName;

    const port_str = ctx.getOption("port") orelse "8080";
    const port = try std.fmt.parseInt(u16, port_str, 10);

    std.debug.print("Server {s} on port {d}\n", .{name, port});
}
```

**After:**
```zig
const MyOptions = struct {
    name: []const u8,
    port: u16 = 8080,
};

fn myAction(ctx: *cli.TypedContext(MyOptions)) !void {
    const opts = try ctx.parse();
    std.debug.print("Server {s} on port {d}\n", .{opts.name, opts.port});
}
```

## API Reference

### TypedCommand(T: type)

```zig
pub fn TypedCommand(comptime T: type) type
```

Creates a type-safe command builder from a struct type `T`.

**Methods:**
- `init(allocator, name, description)` - Create typed command
- `setAction(typed_action)` - Set type-safe action function
- `getCommand()` - Get underlying Command for parsing
- `deinit()` - Clean up resources

### TypedContext(T: type)

```zig
pub fn TypedContext(comptime T: type) type
```

Type-safe context for accessing parsed options.

**Methods:**
- `get(comptime field)` - Get field value with compile-time validation
- `parse()` - Parse entire struct at once

### TypedConfig(T: type)

```zig
pub fn TypedConfig(comptime T: type) type
```

Type-safe config loader with schema validation.

**Methods:**
- `load(allocator, path)` - Load config from file
- `loadFromString(allocator, content, format)` - Load from string
- `discover(allocator, app_name)` - Auto-discover config file
- `deinit()` - Clean up resources

**Field:** `.value: T` - The parsed config data

### TypedMiddleware(T: type)

```zig
pub fn TypedMiddleware(comptime T: type) type
```

Type-safe middleware context.

**Methods:**
- `init(base_context)` - Create from base context
- `set(comptime field, value)` - Set field with compile-time validation
- `get(comptime field)` - Get field value
- `parseContext()`, `command()`, `allocator()` - Access underlying resources

## Performance Characteristics

| Feature | Runtime API | Typed API |
|---------|-------------|-----------|
| Compile Time | ✅ Fast | ⚠️ Slower (more comptime work) |
| Runtime Performance | ✅ Good | ✅ Good (identical) |
| Binary Size | ✅ Small | ✅ Small (no overhead) |
| Memory Usage | ✅ Low | ✅ Low (no overhead) |
| Type Safety | ⚠️ Runtime only | ✅ Compile-time |
| IDE Support | ⚠️ Limited | ✅ Full autocomplete |

## Best Practices

### 1. Use Typed API for New Code

For new projects, prefer the typed API for better type safety and developer experience.

### 2. Define Clear Struct Schemas

```zig
/// Server configuration options
const ServerOptions = struct {
    /// Port to listen on (1-65535)
    port: u16 = 8080,

    /// Host address to bind
    host: []const u8 = "0.0.0.0",

    /// Number of worker threads
    workers: ?u8 = null,
};
```

### 3. Use Enums for State

```zig
const LogLevel = enum { debug, info, warn, @"error" };
const Environment = enum { development, staging, production };

const AppConfig = struct {
    log_level: LogLevel = .info,
    environment: Environment = .development,
};
```

### 4. Leverage Optionals

```zig
const BuildOptions = struct {
    target: []const u8,           // Required
    optimize: ?[]const u8 = null, // Optional
    verbose: bool = false,        // Optional with default
};
```

### 5. Nest for Organization

```zig
const AppConfig = struct {
    server: struct {
        port: u16,
        host: []const u8,
    },
    database: struct {
        url: []const u8,
        pool_size: u32,
    },
    features: struct {
        auth: bool = true,
        metrics: bool = false,
    },
};
```

## Examples

See `examples/typed.zig` for a comprehensive demonstration of all typed API features.

## Limitations

1. **Slice Types**: Only `[]const u8` slices supported (no `[]u32`, etc.)
2. **Dynamic Arrays**: No `ArrayList` or `std.ArrayList` support (use fixed arrays)
3. **Hashmaps**: No `HashMap` support in config structs
4. **Unions**: No union type support (except tagged unions/enums)
5. **Pointers**: Only slice pointers supported

## Future Enhancements

- [ ] Support for dynamic arrays in config
- [ ] Custom validation at struct level
- [ ] Automatic help text from doc comments
- [ ] Schema export (JSON Schema, OpenAPI)
- [ ] Migration tools from runtime to typed API

## Summary

The typed API provides:

✅ **Compile-time safety** - Catch errors before runtime
✅ **Zero overhead** - No performance cost
✅ **Better DX** - IDE autocomplete, refactoring
✅ **Self-documenting** - Types are documentation
✅ **Gradual adoption** - Use alongside runtime API

Use it for maximum type safety in your Zig CLI applications!
