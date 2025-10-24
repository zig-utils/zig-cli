# zig-cli

A modern, feature-rich CLI library for Zig, inspired by popular frameworks like clapp. Build beautiful command-line applications and interactive prompts with ease.

## Features

### CLI Framework
- **Fluent API**: Chainable builder pattern for intuitive CLI construction
- **Command Routing**: Support for nested subcommands with aliases
- **Argument Parsing**: Robust parsing with validation pipeline
- **Type Safety**: Strong typing for options (string, int, float, bool)
- **Auto-generated Help**: Beautiful help text generation
- **Validation**: Built-in validation with custom validators
- **Command Aliases**: Support for command shortcuts and alternative names
- **Middleware System**: Pre/post command hooks with built-in middleware

### Interactive Prompts
- **State Machine**: Clean 5-state state machine (initial → active ↔ error → submit/cancel)
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

fn greetAction(ctx: *cli.Command.ParseContext) !void {
    const name = ctx.getOption("name") orelse "World";
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Hello, {s}!\n", .{name});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create CLI application
    var app = try cli.CLI.init(
        allocator,
        "myapp",
        "1.0.0",
        "My awesome CLI application"
    );
    defer app.deinit();

    // Add options
    const name_option = cli.Option.init("name", "name", "Your name", .string)
        .withShort('n')
        .withDefault("World");
    _ = try app.option(name_option);

    // Set action
    _ = app.action(greetAction);

    // Parse arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    try app.parse(args);
}
```

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

#### Creating a CLI Application

```zig
var app = try cli.CLI.init(allocator, "app-name", "1.0.0", "Description");
defer app.deinit();
```

#### Adding Options

```zig
const option = cli.Option.init("name", "long-name", "Description", .string)
    .withShort('n')              // Short flag (-n)
    .withRequired(true)          // Make it required
    .withDefault("value");       // Set default value

_ = try app.option(option);
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

_ = try app.argument(arg);
```

#### Creating Subcommands

```zig
const subcmd = try cli.Command.init(allocator, "subcmd", "Subcommand description");

// Add aliases for the command
_ = try subcmd.addAlias("sub");
_ = try subcmd.addAlias("s");

const opt = cli.Option.init("opt", "option", "Option description", .string);
_ = try subcmd.addOption(opt);

_ = subcmd.setAction(myAction);
_ = try app.command(subcmd);
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
fn authMiddleware(ctx: *cli.Middleware.MiddlewareContext) !bool {
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

#### Command Actions

```zig
fn myAction(ctx: *cli.Command.ParseContext) !void {
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
}
```

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
const choices = [_]prompt.SelectPrompt.Choice{
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

_ = password.withMaskChar('*');
_ = password.withValidation(validatePassword);

const pwd = try password.prompt();
defer allocator.free(pwd);
```

#### Spinner Prompt

```zig
var spinner = prompt.SpinnerPrompt.init(allocator, "Loading data...");
try spinner.start();

// Do some work
std.time.sleep(2 * std.time.ns_per_s);

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
    std.time.sleep(50 * std.time.ns_per_ms);
    try progress.update(i + 1);
}

try progress.finish();
```

Progress bar styles:
- `.bar` - Classic progress bar (█████░░░░░)
- `.blocks` - Block characters (▓▓▓▓▓░░░░░)
- `.dots` - Dots (⣿⣿⣿⣿⣿⡀⡀⡀⡀⡀)
- `.ascii` - ASCII fallback ([====------])

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

zig-cli supports loading configuration from TOML, JSONC (JSON with Comments), and JSON5 files.

#### Loading Config

```zig
// Load from file (auto-detects format)
var config = try cli.config.load(allocator, "config.toml");
defer config.deinit();

// Or load from string
var config2 = cli.config.Config.init(allocator);
defer config2.deinit();
try config2.loadFromString(content, .toml);  // or .jsonc, .json5

// Auto-discover config file
var config3 = try cli.config.discover(allocator, "myapp");
defer config3.deinit();
// Searches for: myapp.toml, myapp.json5, myapp.jsonc, myapp.json
// In: ., ./.config, ~/.config/myapp
```

#### Reading Values

```zig
// Get typed values
if (config.getString("name")) |name| {
    std.debug.print("Name: {s}\n", .{name});
}

if (config.getInt("port")) |port| {
    std.debug.print("Port: {d}\n", .{port});
}

if (config.getBool("debug")) |debug| {
    std.debug.print("Debug: {}\n", .{debug});
}

if (config.getFloat("timeout")) |timeout| {
    std.debug.print("Timeout: {d}s\n", .{timeout});
}

// Get raw value for complex types
if (config.get("database")) |db_value| {
    // Handle nested tables, arrays, etc.
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

- `basic.zig` - Basic CLI with options and subcommands
- `prompts.zig` - All prompt types with validation
- `advanced.zig` - Complex CLI with multiple commands and arguments
- `showcase.zig` - Comprehensive feature demonstration including all new prompts
- `config.zig` - Configuration file examples (TOML, JSONC, JSON5)

Example config files are in `examples/configs/`:
- `example.toml` - TOML format example
- `example.jsonc` - JSONC format example
- `example.json5` - JSON5 format example

Run examples with your own Zig project by importing zig-cli.

## Architecture

### CLI Framework
```
CLI
├── Command (root)
│   ├── Options (parsed from --flags)
│   ├── Arguments (positional)
│   └── Subcommands (nested)
└── Parser (validation pipeline)
```

### Prompt System
```
PromptCore (state machine)
├── Terminal I/O
│   ├── Raw mode handling
│   ├── Keyboard input
│   └── ANSI output
├── State: initial → active ↔ error → submit/cancel
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
| Builder Pattern | ✅ | ✅ |
| Subcommands | ✅ | ✅ |
| Command Aliases | ✅ | ✅ |
| Interactive Prompts | ✅ | ✅ |
| State Machine | ✅ | ✅ |
| Type Validation | ✅ | ✅ |
| ANSI Colors | ✅ | ✅ |
| Style Chaining | ✅ | ✅ |
| Spinner/Loading | ✅ | ✅ |
| Progress Bars | ✅ | ✅ |
| Box Rendering | ✅ | ✅ |
| Table Rendering | ✅ | ✅ |
| Message Prompts | ✅ | ✅ |
| Number Prompts | ✅ | ✅ |
| Path Prompts | ✅ | ✅ |
| Group Prompts | ✅ | ✅ |
| Terminal Detection | ✅ | ✅ |
| Dimension Detection | ✅ | ✅ |
| Config Files (TOML/JSONC/JSON5) | ✅ | ✅ |
| Middleware System | ✅ | ✅ |
| Language | TypeScript | Zig |
| Binary Size | ~50MB (with Node.js) | ~500KB |
| Startup Time | ~50-100ms | <1ms |

## Testing

```bash
zig build test
```

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Roadmap

### Completed Features ✅
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

### Future Enhancements
- [ ] Tree rendering for hierarchical data
- [ ] Date/time prompts
- [ ] Shell completion generation (bash, zsh, fish)
- [ ] Better Windows terminal support
- [ ] Task prompts with status indicators
- [ ] Streaming output prompts
- [ ] Vim keybindings for prompts
- [ ] Multi-column layout support
