# zig-cli

A modern, feature-rich CLI library for Zig, inspired by popular frameworks like clapp. Build beautiful command-line applications and interactive prompts with ease.

## Features

### CLI Framework
- **Fluent API**: Chainable builder pattern for intuitive CLI construction
- **Command Routing**: Support for nested subcommands
- **Argument Parsing**: Robust parsing with validation pipeline
- **Type Safety**: Strong typing for options (string, int, float, bool)
- **Auto-generated Help**: Beautiful help text generation
- **Validation**: Built-in validation with custom validators

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

### Terminal Features
- **ANSI Colors**: Full color support with automatic detection
- **Raw Mode**: Cross-platform terminal raw mode handling
- **Cursor Control**: Hide/show, save/restore cursor position
- **Unicode Support**: Graceful fallback to ASCII when needed
- **Keyboard Input**: Full keyboard event handling (arrows, enter, backspace, etc.)

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

const opt = cli.Option.init("opt", "option", "Option description", .string);
_ = try subcmd.addOption(opt);

_ = subcmd.setAction(myAction);
_ = try app.command(subcmd);
```

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

Run examples:
```bash
zig build example -- --help
zig build example -- --name Alice --count 3
zig build example -- info
```

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
| Interactive Prompts | ✅ | ✅ |
| State Machine | ✅ | ✅ |
| Type Validation | ✅ | ✅ |
| ANSI Colors | ✅ | ✅ |
| Language | TypeScript | Zig |

## Testing

```bash
zig build test
```

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Roadmap

- [ ] Spinner/progress indicators
- [ ] Table/tree rendering
- [ ] Config file support
- [ ] Shell completion generation
- [ ] More prompt types (number, date, autocomplete)
- [ ] Middleware system for commands
- [ ] Better Windows terminal support
