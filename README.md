# zig-cli

A **type-safe, compile-time validated** CLI library for Zig 0.16+. Define your CLI with structs, get full type safety and zero runtime overhead.

**No string-based lookups. No runtime parsing. Just pure, type-safe Zig.**

```zig
// Define options as a struct
const MyOptions = struct {
    name: []const u8,
    port: u16 = 8080,
};

// Type-safe action
fn run(ctx: *cli.Context(MyOptions)) !void {
    const name = ctx.get(.name);  // Compile-time validated!
    const port = ctx.get(.port);
}
```

Inspired by modern CLI frameworks, built for Zig's strengths.

## Features

### CLI Framework (Type-Safe)

- **Compile-Time Validation**: All field access validated at compile time
- **Struct-Based Options**: Define CLI options as structs - auto-generate everything
- **Zero Runtime Overhead**: All type checking happens at compile time
- **IDE Autocomplete**: Full IntelliSense/LSP support for field names
- **Command Routing**: Support for nested subcommands with aliases
- **Auto-Generated Help**: Beautiful help text from struct definitions
- **Type Safety**: Enums, optionals, nested structs all supported
- **Middleware System**: Type-safe pre/post command hooks

### Interactive Prompts

- **State Machine**: Clean 5-state state machine (initial -> active <-> error -> submit/cancel)
- **Event-driven**: Fine-grained event system for prompt interactions
- **Terminal Detection**: Automatic Unicode/ASCII and color support detection
- **Multiple Prompt Types**:
  - Text input with validation and placeholders
  - Confirmation prompts
  - Select (single choice)
  - MultiSelect (multiple choices)
  - Password input with masking
  - Number input with range validation (integer/float)
  - Path selection with Tab autocomplete
  - Group prompts for multi-step workflows
  - Spinner for loading/activity indicators
  - Progress bars with multiple styles
  - Messages (intro, outro, note, log, cancel)
  - Box/panel rendering for organized output

### Terminal Features

- **ANSI Colors**: Full color support with automatic detection
- **Style Chaining**: Composable styling API (`.red().bold().underline()`)
- **Raw Mode**: Cross-platform terminal raw mode handling
- **Cursor Control**: Hide/show, save/restore cursor position
- **Unicode Support**: Graceful fallback to ASCII when needed
- **Keyboard Input**: Full keyboard event handling (arrows, enter, backspace, etc.)
- **Dimension Detection**: Automatic terminal width/height detection
- **Box Rendering**: Multiple box styles (single, double, rounded, ASCII)
- **Table Rendering**: Column alignment, auto-width, multiple border styles

### Configuration

- **Multiple Formats**: TOML, JSONC (JSON with Comments), JSON5
- **Auto-discovery**: Automatically find config files in standard locations
- **Type-safe Access**: Typed getters for strings, integers, floats, booleans
- **Nested Values**: Support for tables/objects and arrays
- **Flexible Syntax**: Comments, trailing commas, unquoted keys (format-dependent)

## Installation

Add zig-cli to your `build.zig`:

```zig
const zig_cli = b.dependency("zig-cli", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zig-cli", zig_cli.module("zig-cli"));
```

## Quick Start

### Basic CLI Application

```zig
const std = @import("std");
const cli = @import("zig-cli");

// 1. Define options as a struct - that's it!
const GreetOptions = struct {
    name: []const u8 = "World",  // With default value
    enthusiastic: bool = false,   // Boolean flag
};

// 2. Type-safe action function
fn greet(ctx: *cli.Context(GreetOptions)) !void {
    const io = std.Options.debug_io;
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(io, &buf);
    const stdout = &file_writer.interface;

    // Compile-time validated field access - no strings!
    const name = ctx.get(.name);
    const punct: []const u8 = if (ctx.get(.enthusiastic)) "!" else ".";

    try stdout.print("Hello, {s}{s}\n", .{ name, punct });
    try stdout.flush();
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // 3. Create command - options auto-generated!
    var cmd = try cli.Command(GreetOptions).init(allocator, "greet", "Greet someone");
    defer cmd.deinit();

    _ = cmd.setAction(greet);

    // 4. Parse args and execute
    var args_list = std.ArrayList([]const u8){};
    defer args_list.deinit(allocator);

    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    _ = args_iter.skip(); // skip program name
    while (args_iter.next()) |arg| {
        try args_list.append(allocator, arg);
    }

    var parser = cli.Parser.init(allocator);
    try parser.parse(cmd.getCommand(), args_list.items);
}
```

That's it! Run with: `myapp greet --name Alice --enthusiastic`

**Benefits:**

- Options auto-generated from struct fields
- Compile-time validation - typos caught by compiler
- Full IDE autocomplete support
- No string-based lookups
- Zero runtime overhead

### Interactive Prompts

```zig
const std = @import("std");
const prompt = @import("zig-cli").prompt;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Text prompt
    var text_prompt = prompt.TextPrompt.init(allocator, "What is your name?");
    defer text_prompt.deinit();
    const name = try text_prompt.prompt();
    defer allocator.free(name);

    // Confirm prompt
    var confirm_prompt = prompt.ConfirmPrompt.init(allocator, "Continue?");
    defer confirm_prompt.deinit();
    const confirmed = try confirm_prompt.prompt();

    _ = confirmed;

    // Select prompt
    const choices = [_]prompt.SelectPrompt.Choice{
        .{ .label = "Option 1", .value = "opt1" },
        .{ .label = "Option 2", .value = "opt2" },
    };
    var select_prompt = prompt.SelectPrompt.init(allocator, "Choose:", &choices);
    defer select_prompt.deinit();
    const selected = try select_prompt.prompt();
    defer allocator.free(selected);
}
```

## API Reference

### CLI Framework

#### Type-Safe Commands (Recommended)

Define your command options as a struct and get compile-time validation:

```zig
const GreetOptions = struct {
    name: []const u8,              // Required string
    age: ?u16 = null,              // Optional integer
    times: u8 = 1,                 // With default value
    verbose: bool = false,         // Boolean flag
    format: enum { text, json } = .text, // Enum support
};

fn greetAction(ctx: *cli.Context(GreetOptions)) !void {
    // Compile-time validated field access - no string lookups!
    const name = ctx.get(.name);      // Returns []const u8
    const age = ctx.get(.age);        // Returns ?u16
    const times = ctx.get(.times);    // Returns u8

    // Or parse entire struct at once
    const opts = try ctx.parse();

    _ = age;
    _ = times;
    std.debug.print("Hello, {s}!\n", .{opts.name});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Auto-generates CLI options from struct fields!
    var cmd = try cli.Command(GreetOptions).init(allocator, "greet", "Greet a user");
    defer cmd.deinit();

    _ = cmd.setAction(greetAction);

    var args_list = std.ArrayList([]const u8){};
    defer args_list.deinit(allocator);

    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    _ = args_iter.skip();
    while (args_iter.next()) |arg| {
        try args_list.append(allocator, arg);
    }

    var parser = cli.Parser.init(allocator);
    try parser.parse(cmd.getCommand(), args_list.items);
}
```

Benefits:

- **Compile-time validation** - field names validated at compile time
- **IDE autocomplete** - full IntelliSense support
- **Type safety** - no runtime string parsing or optionals
- **Auto-generation** - options automatically created from struct
- **Zero overhead** - comptime code generates efficient runtime

#### Low-Level Command API

For more control, use `BaseCommand` directly:

```zig
// Create a base command
const cmd = try cli.BaseCommand.init(allocator, "myapp", "Description");

// Add options manually
const option = cli.Option.init("name", "long-name", "Description", .string)
    .withShort('n')              // Short flag (-n)
    .withRequired(true)          // Make it required
    .withDefault("value");       // Set default value

_ = try cmd.addOption(option);
```

Option types:

- `.string` - String value
- `.int` - Integer value
- `.float` - Float value
- `.bool` - Boolean flag

#### Adding Arguments

```zig
const arg = cli.Argument.init("name", "Description", .string)
    .withRequired(true)          // Required argument
    .withVariadic(false);        // Accept multiple values

_ = try cmd.addArgument(arg);
```

#### Creating Subcommands

```zig
const subcmd = try cli.BaseCommand.init(allocator, "subcmd", "Subcommand description");

// Add aliases for the command
_ = try subcmd.addAlias("sub");
_ = try subcmd.addAlias("s");

const opt = cli.Option.init("opt", "option", "Option description", .string);
_ = try subcmd.addOption(opt);

_ = subcmd.setAction(myAction);
_ = try app.addCommand(subcmd);
```

Now you can call the subcommand with: `myapp subcmd`, `myapp sub`, or `myapp s`

#### Middleware

Add pre/post command hooks to your CLI:

```zig
var chain = cli.Middleware.MiddlewareChain.init(allocator);
defer chain.deinit();

// Add built-in middleware
try chain.use(cli.Middleware.Middleware.init("logging", cli.Middleware.loggingMiddleware));
try chain.use(cli.Middleware.Middleware.init("timing", cli.Middleware.timingMiddleware));
try chain.use(cli.Middleware.Middleware.init("validation", cli.Middleware.validationMiddleware));

// Custom middleware
fn authMiddleware(ctx: _cli.Middleware.MiddlewareContext) !bool {
    const is_authenticated = checkAuth();
    if (!is_authenticated) {
        try ctx.set("error", "Unauthorized");
        return false; // Stop chain
    }
    try ctx.set("user", "john@example.com");
    return true; // Continue
}

// Add with priority (lower runs first)
try chain.use(cli.Middleware.Middleware.init("auth", authMiddleware).withOrder(-10));

// Execute middleware chain before command
var middleware_ctx = cli.Middleware.MiddlewareContext.init(allocator, parse_context, command);
defer middleware_ctx.deinit();

if (try chain.execute(&middleware_ctx)) {
    // All middleware passed, execute command
    try command.executeAction(parse_context);
}
```

Built-in middleware:

- `loggingMiddleware` - Logs command execution
- `timingMiddleware` - Records start time
- `validationMiddleware` - Validates required options
- `environmentCheckMiddleware` - Checks environment variables

#### Command Actions (Low-Level)

```zig
fn myAction(ctx: _cli.BaseCommand.ParseContext) !void {
    // Get option value
    const value = ctx.getOption("name") orelse "default";

    // Check if option was provided
    if (ctx.hasOption("verbose")) {
        // Do something
    }

    // Get positional argument
    const arg = ctx.getArgument(0) orelse return error.MissingArgument;

    // Get argument count
    const count = ctx.getArgumentCount();

    _ = value;
    _ = arg;
    _ = count;
}
```

#### Runtime vs Typed API Comparison

```zig
// Runtime API (string-based, via BaseCommand)
const value = ctx.getOption("name");  // Returns ?[]const u8
if (value) |v| {
    const age_str = ctx.getOption("age") orelse "0";
    const age = try std.fmt.parseInt(u16, age_str, 10);
    _ = v;
    _ = age;
}

// Typed API (compile-time validated, via cli.Command(T))
const name = ctx.get(.name);  // Returns []const u8 directly
const age = ctx.get(.age);    // Returns u16, already parsed
//              ^^^^^ Compile-time validated enum field!
```

See `examples/typed.zig` for a complete working example.

#### Type-Safe Config

Load config files with compile-time schema validation:

```zig
const AppConfig = struct {
    database: struct {
        host: []const u8,
        port: u16,
        max_connections: u32 = 100,
    },
    log_level: enum { debug, info, warn, @"error" } = .info,
    debug: bool = false,
};

// Load with full type checking
var config = try cli.config.load(AppConfig, allocator, "config.toml");
defer config.deinit();

// Direct field access - no optionals, no string parsing!
std.debug.print("DB: {s}:{d}\n", .{
    config.value.database.host,
    config.value.database.port,
});
std.debug.print("Log Level: {s}\n", .{@tagName(config.value.log_level)});

// Auto-discovery also works
var discovered = try cli.config.discover(AppConfig, allocator, "myapp");
defer discovered.deinit();
```

Supported types:

- Primitives: `bool`, `i8`-`i64`, `u8`-`u64`, `f32`, `f64`
- Strings: `[]const u8`
- Enums: Any Zig enum
- Optionals: `?T` for optional fields
- Nested structs: Arbitrary depth
- Arrays: Fixed-size arrays

### Prompts

#### Text Prompt

```zig
var text = prompt.TextPrompt.init(allocator, "Enter value:");
defer text.deinit();

_ = text.withPlaceholder("placeholder text");
_ = text.withDefault("default value");
_ = text.withValidation(myValidator);

const value = try text.prompt();
defer allocator.free(value);
```

Custom validator:

```zig
fn myValidator(value: []const u8) ?[]const u8 {
    if (value.len < 3) {
        return "Value must be at least 3 characters";
    }
    return null;  // Valid
}
```

#### Confirm Prompt

```zig
var confirm = prompt.ConfirmPrompt.init(allocator, "Continue?");
defer confirm.deinit();

_ = confirm.withDefault(true);

const result = try confirm.prompt();  // Returns bool
```

#### Select Prompt

```zig
const choices = [_]prompt.SelectPrompt.Choice{
    .{ .label = "TypeScript", .value = "ts", .description = "JavaScript with types" },
    .{ .label = "Zig", .value = "zig", .description = "Systems programming" },
};

var select = prompt.SelectPrompt.init(allocator, "Choose a language:", &choices);
defer select.deinit();

const selected = try select.prompt();
defer allocator.free(selected);
```

#### MultiSelect Prompt

```zig
const choices = [_]prompt.MultiSelectPrompt.Choice{
    .{ .label = "Option 1", .value = "opt1" },
    .{ .label = "Option 2", .value = "opt2" },
};

var multi = try prompt.MultiSelectPrompt.init(allocator, "Select options:", &choices);
defer multi.deinit();

const selected = try multi.prompt();  // Returns [][]const u8
defer {
    for (selected) |item| allocator.free(item);
    allocator.free(selected);
}
```

#### Password Prompt

```zig
var password = prompt.PasswordPrompt.init(allocator, "Enter password:");
defer password.deinit();

_ = password.withMaskChar('_');
_ = password.withValidation(validatePassword);

const pwd = try password.prompt();
defer allocator.free(pwd);
```

#### Spinner Prompt

```zig
var spinner = prompt.SpinnerPrompt.init(allocator, "Loading data...");
try spinner.start();

// Do some work
_ = std.c.nanosleep(&.{ .sec = 2, .nsec = 0 }, null);

try spinner.stop("Data loaded successfully!");
```

#### Message Prompts

```zig
// Intro/Outro for CLI flows
try prompt.intro(allocator, "My CLI Application");
// ... your application logic ...
try prompt.outro(allocator, "All done! Thanks for using our CLI.");

// Notes and logs
try prompt.note(allocator, "Important", "This is additional information");
try prompt.log(allocator, .info, "Starting process...");
try prompt.log(allocator, .success, "Process completed!");
try prompt.log(allocator, .warning, "This is a warning");
try prompt.log(allocator, .error_level, "An error occurred");

// Cancel message
try prompt.cancel(allocator, "Operation was canceled");
```

#### Box Rendering

```zig
// Simple box
try prompt.box(allocator, "Title", "This is the content");

// Custom box with styling
var box = prompt.Box.init(allocator);
box = box.withStyle(.rounded);  // .single, .double, .rounded, .ascii
box = box.withPadding(2);
try box.render("My Box",
    \\Line 1 of content
    \\Line 2 of content
    \\Line 3 of content
);
```

#### Number Prompt

```zig
var num_prompt = prompt.NumberPrompt.init(allocator, "Enter port:", .integer);
defer num_prompt.deinit();

_ = num_prompt.withRange(1, 65535);  // Set min/max
_ = num_prompt.withDefault(8080);

const port = try num_prompt.prompt();  // Returns f64
const port_int = @as(u16, @intFromFloat(port));
```

Number types:

- `.integer` - Integer values
- `.float` - Floating-point values

#### Path Prompt

```zig
var path_prompt = prompt.PathPrompt.init(allocator, "Select file:", .file);
defer path_prompt.deinit();

_ = path_prompt.withMustExist(true);  // Must exist
_ = path_prompt.withDefault("./config.toml");

const path = try path_prompt.prompt();
defer allocator.free(path);

// Press Tab to autocomplete based on filesystem
```

Path types:

- `.file` - File selection
- `.directory` - Directory selection
- `.any` - File or directory

#### Group Prompts

```zig
const prompts = [_]prompt.GroupPrompt.PromptDef{
    .{ .text = .{ .key = "name", .message = "Your name?" } },
    .{ .number = .{ .key = "age", .message = "Your age?", .number_type = .integer } },
    .{ .confirm = .{ .key = "agree", .message = "Do you agree?" } },
    .{ .select = .{
        .key = "lang",
        .message = "Choose language:",
        .choices = &[_]prompt.SelectPrompt.Choice{
            .{ .label = "Zig", .value = "zig" },
            .{ .label = "TypeScript", .value = "ts" },
        },
    }},
};

var group = prompt.GroupPrompt.init(allocator, &prompts);
defer group.deinit();

try group.run();

// Access results by key
const name = group.getText("name");
const age = group.getNumber("age");
const agreed = group.getBool("agree");
const lang = group.getText("lang");
```

#### Progress Bar

```zig
var progress = prompt.ProgressBar.init(allocator, 100, "Processing files");
defer progress.deinit();

try progress.start();

for (0..100) |i| {
    // Do some work
    _ = std.c.nanosleep(&.{ .sec = 0, .nsec = 50 _ std.time.ns_per_ms }, null);
    try progress.update(i + 1);
}

try progress.finish();
```

Progress bar styles:

- `.bar` - Classic progress bar
- `.blocks` - Block characters
- `.dots` - Dots
- `.ascii` - ASCII fallback

#### Table Rendering

```zig
const columns = [_]prompt.Table.Column{
    .{ .header = "Name", .alignment = .left },
    .{ .header = "Age", .alignment = .right },
    .{ .header = "Status", .alignment = .center },
};

var table = prompt.Table.init(allocator, &columns);
defer table.deinit();

table = table.withStyle(.rounded);  // .simple, .rounded, .double, .minimal

try table.addRow(&[_][]const u8{ "Alice", "30", "Active" });
try table.addRow(&[_][]const u8{ "Bob", "25", "Inactive" });
try table.addRow(&[_][]const u8{ "Charlie", "35", "Active" });

try table.render();
```

#### Style Chaining

```zig
// Create styled text with chainable API
const styled = try prompt.style(allocator, "Error occurred")
    .red()
    .bold()
    .underline()
    .render();
defer allocator.free(styled);

try prompt.Terminal.init().write(styled);

// Available colors: black, red, green, yellow, blue, magenta, cyan, white
// Available styles: bold(), dim(), italic(), underline()
// Available backgrounds: bgRed(), bgGreen(), bgBlue(), etc.
```

### Configuration Files

zig-cli supports type-safe configuration loading from TOML, JSONC (JSON with Comments), and JSON5 files.

#### Loading Config

```zig
// 1. Define your config schema as a struct
const AppConfig = struct {
    database: struct {
        host: []const u8,
        port: u16,
    },
    log_level: enum { debug, info, warn, @"error" } = .info,
    debug: bool = false,
};

// 2. Load with full type checking
var config = try cli.config.load(AppConfig, allocator, "config.toml");
defer config.deinit();

// 3. Direct field access - type-safe!
std.debug.print("DB: {s}:{d}\n", .{
    config.value.database.host,
    config.value.database.port,
});

// Load from string
var config2 = try cli.config.loadFromString(AppConfig, allocator, toml_content, .toml);
defer config2.deinit();

// Auto-discover config file
var config3 = try cli.config.discover(AppConfig, allocator, "myapp");
defer config3.deinit();
// Searches for: myapp.toml, myapp.json5, myapp.jsonc
// In: ., ./.config, ~/.config/myapp
```

#### Untyped Config Access

For simple cases, use the raw `Config` type:

```zig
var raw_config = cli.config.Config.init(allocator);
defer raw_config.deinit();

try raw_config.loadFromFile("config.toml", .auto);

// Get typed values
if (raw_config.getString("name")) |name| {
    std.debug.print("Name: {s}\n", .{name});
}

if (raw_config.getInt("port")) |port| {
    std.debug.print("Port: {d}\n", .{port});
}

if (raw_config.getBool("debug")) |debug| {
    std.debug.print("Debug: {}\n", .{debug});
}
```

#### Supported Formats

**TOML:**

```toml
# config.toml
name = "myapp"
port = 8080

[database]
host = "localhost"
```

**JSONC (JSON with Comments):**

```jsonc
{
  // Comments are allowed
  "name": "myapp",
  "port": 8080,
  "database": {
    "host": "localhost"
  },  // trailing commas allowed
}
```

**JSON5:**

```json5
{
  // Unquoted keys
  name: 'myapp',  // single quotes
  port: 8080,
  permissions: 0x755,  // hex numbers
  ratio: .5,  // leading decimal
  maxValue: Infinity,  // special values
}
```

### Terminal & ANSI

#### Colors

```zig
const ansi = @import("zig-cli").prompt.Ansi;

const colored = try ansi.colorize(allocator, "text", .green);
defer allocator.free(colored);

// Convenience functions
const bold = try ansi.bold(allocator, "text");
const red = try ansi.red(allocator, "error");
const green = try ansi.green(allocator, "success");
```

#### Symbols

```zig
const symbols = ansi.Symbols.forTerminal(supports_unicode);

std.debug.print("{s} Success!\n", .{symbols.checkmark});
std.debug.print("{s} Error!\n", .{symbols.cross});
std.debug.print("{s} Loading...\n", .{symbols.spinner[0]});
```

## Examples

Check out the `examples/` directory for complete examples:

- `simple.zig` - Minimal typed CLI example
- `basic.zig` - Basic CLI with options and subcommands
- `typed.zig` - Type-safe API examples (compile-time validated)
- `advanced.zig` - Complex CLI with multiple commands and arguments
- `prompts.zig` - All prompt types with validation
- `showcase.zig` - Comprehensive feature demonstration
- `config.zig` - Configuration file examples (TOML, JSONC, JSON5)

Example config files are in `examples/configs/`:

- `example.toml` - TOML format example
- `example.jsonc` - JSONC format example
- `example.json5` - JSON5 format example

Build and run examples:

```bash
zig build examples          # Build all examples
zig build run-simple        # Run a specific example
zig build run-showcase      # Run the showcase
```

## Architecture

### CLI Framework

```
Command(T) (typed, compile-time validated)
├── BaseCommand (underlying command)
│   ├── Options (parsed from --flags)
│   ├── Arguments (positional)
│   └── Subcommands (nested)
├── Context(T) (typed parse context)
└── Parser (validation pipeline)
```

### Prompt System

```
PromptCore (state machine)
├── Terminal I/O
│   ├── Raw mode handling
│   ├── Keyboard input
│   └── ANSI output
├── State: initial -> active <-> error -> submit/cancel
└── Events: value, cursor, key, submit, cancel
```

## Design Principles

1. **Type Safety**: Leverage Zig's type system for compile-time safety
2. **Memory Ownership**: Clear allocation/deallocation patterns
3. **Error Handling**: Explicit error handling with Zig's error unions
4. **Cross-platform**: Works on macOS, Linux, and Windows
5. **Zero Dependencies**: Only uses Zig standard library
6. **Composable**: Mix and match CLI and prompt features

## Comparison with clapp

zig-cli is inspired by the TypeScript library clapp, bringing similar developer experience to Zig:

| Feature | clapp | zig-cli |
|---------|-------|---------|
| Builder Pattern | yes | yes |
| Subcommands | yes | yes |
| Command Aliases | yes | yes |
| Interactive Prompts | yes | yes |
| State Machine | yes | yes |
| Type Validation | yes | yes |
| ANSI Colors | yes | yes |
| Style Chaining | yes | yes |
| Spinner/Loading | yes | yes |
| Progress Bars | yes | yes |
| Box Rendering | yes | yes |
| Table Rendering | yes | yes |
| Message Prompts | yes | yes |
| Number Prompts | yes | yes |
| Path Prompts | yes | yes |
| Group Prompts | yes | yes |
| Terminal Detection | yes | yes |
| Dimension Detection | yes | yes |
| Config Files (TOML/JSONC/JSON5) | yes | yes |
| Middleware System | yes | yes |
| Language | TypeScript | Zig |
| Binary Size | ~50MB (with Node.js) | ~500KB |
| Startup Time | ~50-100ms | <1ms |

## Testing

```bash
zig build test
```

## Building

```bash
zig build              # Build the library
zig build test         # Run all tests
zig build examples     # Build all examples
```

## Community

For help, discussion about best practices, or any other conversation that would benefit from being searchable:

[Discussions on GitHub](https://github.com/zig-utils/zig-cli/discussions)

For casual chit-chat with others using this package:

[Join the zig-utils Discord Server](https://discord.gg/f7wBym6JF2)

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Roadmap

### Completed Features

- [x] Spinner/loading indicators
- [x] Box/panel rendering
- [x] Message prompts (intro, outro, note, log, cancel)
- [x] Terminal dimension detection
- [x] Command aliases
- [x] Config file support (TOML, JSONC, JSON5)
- [x] Auto-discovery of config files
- [x] Progress bars with multiple styles
- [x] Table rendering with column alignment
- [x] Style chaining (`.red().bold().underline()`)
- [x] Group prompts with result access
- [x] Number prompt with range validation
- [x] Path prompt with autocomplete
- [x] Middleware system for commands
- [x] Type-safe API with compile-time validation
  - [x] TypedCommand with auto-generated options from structs
  - [x] TypedConfig with schema validation
  - [x] TypedMiddleware with compile-time field checking

### Future Enhancements

- [ ] Tree rendering for hierarchical data
- [ ] Date/time prompts
- [ ] Shell completion generation (bash, zsh, fish)
- [ ] Better Windows terminal support
- [ ] Task prompts with status indicators
- [ ] Streaming output prompts
- [ ] Vim keybindings for prompts
- [ ] Multi-column layout support
