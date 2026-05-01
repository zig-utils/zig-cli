# Typed-Only Approach - zig-cli

## Philosophy

**zig-cli is built around one core principle: leverage Zig's compile-time features for maximum type safety with zero runtime overhead.**

There are no duplicate APIs, no "typed vs untyped" choices. Just one way to do things - the type-safe way.

## Why Typed-Only

### 1. **Compile-Time Safety**

```zig
// This catches typos at compile time
const name = ctx.get(.name);
//                   ^^^^^ Compiler validates this exists

// Not at runtime like:
const name = ctx.getOption("nmae"); // Typo only caught when code runs
```

### 2. **Zero Runtime Cost**

All type validation happens at compile time using Zig's `comptime` features:

- No reflection
- No runtime type checking
- No performance overhead
- Same machine code as hand-written parsing

### 3. **Self-Documenting**

```zig
const ServerOptions = struct {
    /// Port to listen on (1-65535)
    port: u16 = 8080,

    /// Host address to bind
    host: []const u8 = "0.0.0.0",

    /// TLS configuration
    tls: ?struct {
        cert_path: []const u8,
        key_path: []const u8,
    } = null,
};
```

The struct IS the documentation. Types, defaults, optionality - all visible at a glance.

### 4. **Superior Developer Experience**

- **IDE Autocomplete**: Full IntelliSense for all fields
- **Refactoring**: Rename fields across entire codebase with confidence
- **Type Inference**: Compiler knows types, you don't specify them twice
- **Immediate Feedback**: Errors at compile time, not runtime

## API Design

### Commands

```zig
// Define options
const Options = struct { name: []const u8 };

// Create command - options auto-generated!
var cmd = try cli.command(Options).init(allocator, "mycmd", "Description");
defer cmd.deinit();

// Set action
_ = cmd.setAction(myAction);
```

**What happens:**

1. `cli.command(Options)` - Returns `TypedCommand(Options)` type
2. Struct introspection at comptime generates CLI options
3. Field types → Option types (string, int, bool, enum)
4. Defaults/optionals → CLI defaults/optional flags

### Context

```zig
fn myAction(ctx: *cli.Context(Options)) !void {
    // Compile-time validated enum field access
    const name = ctx.get(.name);
    //                   ^^^^^ Must be a field of Options

    // Or parse entire struct
    const opts = try ctx.parse();
}
```

**Type safety:**

- `.name` is an enum value checked at compile time
- Return type inferred from struct field type
- No optionals for required fields

### Config

```zig
const AppConfig = struct {
    database: struct {
        host: []const u8,
        port: u16,
    },
    log_level: enum { debug, info } = .info,
};

var config = try cli.config.load(AppConfig, allocator, "config.toml");
defer config.deinit();

// Direct field access - fully typed!
const host = config.value.database.host;  // []const u8
const port = config.value.database.port;  // u16
```

**Benefits:**

- Schema validation at load time
- Type conversion automatic
- Enum values checked
- Nested structs supported

### Middleware

```zig
const AuthData = struct {
    user_id: []const u8 = "",
    role: enum { admin, user } = .user,
};

fn authMiddleware(ctx: *cli.middleware(AuthData)) !bool {
    ctx.set(.user_id, "12345");
    ctx.set(.role, .admin);  // Enum - type checked!

    if (ctx.get(.role) == .admin) {
        // ...
    }

    return true;
}
```

## No String-Based Lookups

Traditional CLI libraries:

```zig
// ❌ String-based (error-prone)
const name = ctx.getOption("name");
const port_str = ctx.getOption("port") orelse "8080";
const port = try std.fmt.parseInt(u16, port_str, 10);
```

zig-cli:

```zig
// ✅ Type-safe (compile-time validated)
const name = ctx.get(.name);
const port = ctx.get(.port);
```

## No Duplication

**One way to define commands**: Struct-based
**One way to access options**: `ctx.get(.field)`
**One way to load config**: `config.load(T, ...)`

No "advanced vs simple" APIs. No "typed vs untyped" paths. Just one elegant, type-safe approach.

## Implementation Details

### How It Works

1. **Struct Introspection**:

   ```zig
   const fields = @typeInfo(T).Struct.fields;
   inline for (fields) |field| {
       // Generate options at compile time
   }
   ```

2. **Type Mapping**:
   - `[]const u8` → String option
   - `u8`-`u64`, `i8`-`i64` → Integer option
   - `f32`, `f64` → Float option
   - `bool` → Boolean flag
   - `enum` → Validated enum values
   - `?T` → Optional option

3. **Accessor Generation**:

   ```zig
   pub fn get(self: *Self, comptime field: std.meta.FieldEnum(T)) FieldType(T, field) {
       comptime {
           // Validate field exists
           _ = std.meta.fieldInfo(T, field);
       }
       const str = self.parse_context.getOption(@tagName(field)).?;
       return parseValue(FieldType(T, field), str);
   }
   ```

### Performance

| Operation | Runtime Cost |
|-----------|--------------|
| Struct introspection | **Compile-time only** |
| Field validation | **Compile-time only** |
| Type generation | **Compile-time only** |
| Option parsing | Same as manual parsing |
| Field access | **Zero overhead** (direct access) |

**Result**: Identical performance to hand-written parsing, but with full type safety.

## Supported Types

### Primitives

- ✅ `bool`
- ✅ `i8`, `i16`, `i32`, `i64`, `i128`
- ✅ `u8`, `u16`, `u32`, `u64`, `u128`
- ✅ `f32`, `f64`

### Strings

- ✅ `[]const u8`

### Complex Types

- ✅ Enums (any Zig enum)
- ✅ Optionals (`?T`)
- ✅ Nested structs (arbitrary depth)
- ✅ Fixed arrays (`[N]T`)

### Not Supported

- ❌ Slices of non-u8 (`[]T` where T != u8)
- ❌ Dynamic arrays (`ArrayList`)
- ❌ Hashmaps
- ❌ Unions (except tagged unions/enums)
- ❌ Function pointers

## Examples

### Simple CLI

```zig
const Options = struct {
    input: []const u8,
    output: []const u8,
    verbose: bool = false,
};

fn process(ctx: _cli.Context(Options)) !void {
    const opts = try ctx.parse();
    std.debug.print("Processing {s} -> {s}\n", .{opts.input, opts.output});
}
```

### With Enum

```zig
const Options = struct {
    mode: enum { fast, slow, balanced } = .balanced,
    threads: u8 = 4,
};
```

### Nested Config

```zig
const Config = struct {
    server: struct {
        host: []const u8,
        port: u16,
        tls: ?struct {
            cert: []const u8,
            key: []const u8,
        } = null,
    },
    database: struct {
        url: []const u8,
        pool_size: u32 = 100,
    },
};
```

## Migration Guide

If you have string-based CLI code:

### Before

```zig
fn action(ctx: _Command.ParseContext) !void {
    const name = ctx.getOption("name") orelse return error.Missing;
    const port_str = ctx.getOption("port") orelse "8080";
    const port = try std.fmt.parseInt(u16, port_str, 10);
}
```

### After

```zig
const Options = struct {
    name: []const u8,
    port: u16 = 8080,
};

fn action(ctx: *cli.Context(Options)) !void {
    const opts = try ctx.parse();
    // opts.name and opts.port are ready to use!
}
```

## Philosophy Recap

1. **One True Way**: No API duplication, one typed approach
2. **Compile-Time First**: Leverage Zig's strengths
3. **Zero Cost**: No runtime overhead whatsoever
4. **Self-Documenting**: Types are documentation
5. **IDE-Friendly**: Full autocomplete and refactoring support

**zig-cli: Type-safe CLIs. The Zig way.**
