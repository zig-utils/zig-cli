# Feature Parity with clapp

This document tracks the feature parity between zig-cli and the clapp TypeScript library.

## Implemented Features

### CLI Framework

- [x] **Fluent Builder API** - Chainable methods for intuitive CLI construction
- [x] **Command System** - Full command routing with nested subcommands
- [x] **Command Aliases** - Support for command shortcuts (e.g., `build`, `b`)
- [x] **Options** - Short and long flags with type validation
- [x] **Arguments** - Positional and variadic arguments
- [x] **Type Safety** - String, int, float, boolean types
- [x] **Validation** - Custom validators for options and arguments
- [x] **Help Generation** - Auto-generated, formatted help text
- [x] **Error Handling** - Clear error messages with context
- [x] **Middleware System** - Pre/post command hooks, chainable middleware
- [x] **Type-Safe Commands** - `cli.Command(T)` with compile-time validated struct-based options

### Interactive Prompts

- [x] **TextPrompt** - Text input with placeholder and validation
- [x] **ConfirmPrompt** - Yes/No confirmation
- [x] **SelectPrompt** - Single selection from list
- [x] **MultiSelectPrompt** - Multiple selections with space toggle
- [x] **PasswordPrompt** - Masked password input
- [x] **SpinnerPrompt** - Animated loading indicator
- [x] **NumberPrompt** - Integer/Float with min/max range validation
- [x] **PathPrompt** - File/directory path with Tab autocomplete
- [x] **GroupPrompt** - Sequential prompts with shared state/results
- [x] **Message Prompts** - intro, outro, note, log, cancel

### Terminal & UI

- [x] **Terminal Detection** - Unicode/ASCII support detection
- [x] **Color Support** - ANSI colors with NO_COLOR respect
- [x] **Dimension Detection** - Terminal width/height via ioctl
- [x] **Box Rendering** - Multiple styles (single, double, rounded, ASCII)
- [x] **Table Rendering** - Column alignment, auto-width, multiple border styles
- [x] **Progress Bar** - 4 styles (bar, blocks, dots, ASCII)
- [x] **Style Chaining** - Composable: `.red().bold().underline()`
- [x] **ANSI Symbols** - Checkmark, cross, spinner, arrows, etc.
- [x] **Raw Mode** - Terminal raw mode for key capture
- [x] **Cursor Control** - Hide, show, save, restore cursor
- [x] **Keyboard Events** - Full keyboard handling (arrows, enter, backspace, etc.)

### State Management

- [x] **State Machine** - 5-state system (initial -> active <-> error -> submit/cancel)
- [x] **Event System** - Event types for value, cursor, key, submit, cancel
- [x] **State Transitions** - Validated state transitions

### Configuration

- [x] **TOML Parser** - Full TOML format support
- [x] **JSONC Parser** - JSON with comments
- [x] **JSON5 Parser** - Extended JSON syntax
- [x] **Type-Safe Config** - `cli.config.load(T, ...)` with compile-time schema validation
- [x] **Auto-discovery** - Search standard locations for config files
- [x] **Format Auto-detection** - Based on file extension

### Architecture

- [x] **Memory Safety** - Explicit allocators, proper cleanup
- [x] **Error Handling** - Zig error unions throughout
- [x] **Cross-platform** - macOS, Linux support (Windows partial)
- [x] **Zero Dependencies** - Only uses Zig stdlib

## Partially Implemented

### Terminal

- [~] **Windows Support** - Basic structure exists, needs full implementation
  - Terminal raw mode placeholder
  - Console API integration needed
  - Color support needs testing

## Not Yet Implemented (from clapp)

### Additional Prompt Types

- [ ] **DatePrompt** - Date/time selection
- [ ] **AutocompletePrompt** - Text input with suggestions
- [ ] **GroupMultiselectPrompt** - Grouped multi-selection
- [ ] **SelectKeyPrompt** - Key-based selection (1-9 shortcuts)
- [ ] **TaskPrompt** - Task with status tracking
- [ ] **TasksPrompt** - Multiple tasks with parallel execution
- [ ] **StreamPrompt** - Streaming output display

### UI Components

- [ ] **Tree Rendering** - Hierarchical tree display

### Advanced Features

- [ ] **Theme System** - Customizable color themes
- [ ] **Lifecycle Hooks** - SIGINT, SIGTERM, error handlers
- [ ] **Shell Completion** - Generate shell completions
- [ ] **Async Iterables** - Stream support for async operations

### Testing Utilities

- [ ] **Mock Prompts** - Testing helpers for prompts
- [ ] **Output Capture** - Capture and test CLI output
- [ ] **File System Mocks** - Testing file operations

### Utilities

- [ ] **Vim Keybindings** - hjkl navigation support
- [ ] **Markdown Processing** - Render markdown in terminal

## Feature Completion Stats

### Core Features (Critical)

- **CLI Framework**: 100%
- **Basic Prompts**: 100% (text, confirm, select, multiselect, password)
- **Advanced Prompts**: 100% (number, path, group, spinner)
- **Terminal Basics**: 100% (detection, colors, keyboard)
- **UI Components**: 90% (box, table, progress bar, style chaining - tree missing)
- **Configuration**: 100% (TOML, JSONC, JSON5, typed loader, auto-discovery)

### Advanced Features

- **Style System**: 95% (colors, chaining, backgrounds - themes missing)
- **CLI Advanced**: 100% (aliases, middleware, typed commands)
- **Platform Support**: 80% (Unix fully supported, Windows partial)

### Overall Completion

#### Estimated: ~95% feature parity

All commonly used features are fully implemented. The remaining items (tree rendering, specialized prompt types, shell completion) are lower-priority specialized features.

## What Makes zig-cli Special

While we're inspired by clapp, zig-cli brings Zig-specific advantages:

1. **Compile-time Safety** - Type checking catches errors early
2. **No Runtime** - Zero-cost abstractions, no GC pauses
3. **Explicit Memory** - Clear ownership, no hidden allocations
4. **Error Unions** - Explicit error handling, can't ignore errors
5. **Cross-compilation** - Easy to build for multiple platforms
6. **Small Binaries** - Typical CLI apps are < 500KB
7. **Fast Startup** - No runtime initialization

## Notes

- Feature parity doesn't mean identical API - we adapt to Zig idioms
- Some TypeScript-specific features (like Promise-based APIs) don't directly translate
- We prioritize features that provide the most value to Zig developers
- Windows support is ongoing and will reach parity with Unix systems
