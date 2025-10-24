const std = @import("std");
const cli = @import("zig-cli");
const prompt = cli.prompt;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Display intro
    try prompt.intro(allocator, "zig-cli Feature Showcase");

    // Show terminal dimensions
    const terminal = prompt.Terminal.init();
    var buf: [100]u8 = undefined;
    const dims = try std.fmt.bufPrint(&buf, "Terminal: {d}x{d}", .{ terminal.width, terminal.height });
    try prompt.note(allocator, "Detected terminal size:", dims);

    // Demonstrate box rendering
    try prompt.box(allocator, "Welcome",
        \\This is a box with multiple lines.
        \\It automatically wraps content.
        \\Perfect for displaying information!
    );

    // Info log
    try prompt.log(allocator, .info, "Starting feature demonstrations...");

    // Text prompt with validation
    try prompt.note(allocator, "Text Input Demo", "with validation");
    var text_prompt = prompt.TextPrompt.init(allocator, "Enter your name (min 3 chars):");
    defer text_prompt.deinit();
    _ = text_prompt.withPlaceholder("John Doe");
    _ = text_prompt.withValidation(validateName);

    const name = text_prompt.prompt() catch |err| {
        if (err == error.Canceled) {
            try prompt.cancel(allocator, "Operation canceled by user");
            return;
        }
        return err;
    };
    defer allocator.free(name);

    var greeting_buf: [200]u8 = undefined;
    const greeting = try std.fmt.bufPrint(&greeting_buf, "Hello, {s}!", .{name});
    try prompt.log(allocator, .success, greeting);

    // Confirm prompt
    try prompt.note(allocator, "Confirmation Demo", null);
    var confirm_prompt = prompt.ConfirmPrompt.init(allocator, "Do you want to continue?");
    defer confirm_prompt.deinit();
    _ = confirm_prompt.withDefault(true);

    const confirmed = try confirm_prompt.prompt();
    if (!confirmed) {
        try prompt.cancel(allocator, "User chose not to continue");
        return;
    }

    // Select prompt
    try prompt.note(allocator, "Selection Demo", "choose your favorite");
    const lang_choices = [_]prompt.SelectPrompt.Choice{
        .{ .label = "Zig", .value = "zig", .description = "Fast, safe, and simple" },
        .{ .label = "Rust", .value = "rust", .description = "Memory safety without GC" },
        .{ .label = "Go", .value = "go", .description = "Simple and productive" },
        .{ .label = "TypeScript", .value = "ts", .description = "JavaScript with types" },
    };

    var select_prompt = prompt.SelectPrompt.init(allocator, "Favorite language?", &lang_choices);
    defer select_prompt.deinit();

    const selected = try select_prompt.prompt();
    defer allocator.free(selected);

    var selected_buf: [200]u8 = undefined;
    const selected_msg = try std.fmt.bufPrint(&selected_buf, "You selected: {s}", .{selected});
    try prompt.log(allocator, .success, selected_msg);

    // MultiSelect prompt
    try prompt.note(allocator, "Multi-Selection Demo", "space to toggle, enter to confirm");
    const feature_choices = [_]prompt.SelectPrompt.Choice{
        .{ .label = "CLI Framework", .value = "cli", .description = "Command-line parsing" },
        .{ .label = "Interactive Prompts", .value = "prompts", .description = "User input" },
        .{ .label = "ANSI Colors", .value = "colors", .description = "Terminal styling" },
        .{ .label = "Box Rendering", .value = "boxes", .description = "UI elements" },
    };

    var multi_prompt = try prompt.MultiSelectPrompt.init(allocator, "Which features interest you?", &feature_choices);
    defer multi_prompt.deinit();

    const selected_features = try multi_prompt.prompt();
    defer {
        for (selected_features) |item| allocator.free(item);
        allocator.free(selected_features);
    }

    var count_buf: [100]u8 = undefined;
    const count_msg = try std.fmt.bufPrint(&count_buf, "Selected {d} features", .{selected_features.len});
    try prompt.log(allocator, .success, count_msg);

    // Password prompt
    try prompt.note(allocator, "Password Demo", "min 8 characters");
    var password_prompt = prompt.PasswordPrompt.init(allocator, "Enter a password:");
    defer password_prompt.deinit();
    _ = password_prompt.withValidation(validatePassword);

    const password = try password_prompt.prompt();
    defer allocator.free(password);

    var pwd_buf: [100]u8 = undefined;
    const pwd_msg = try std.fmt.bufPrint(&pwd_buf, "Password set ({d} chars)", .{password.len});
    try prompt.log(allocator, .success, pwd_msg);

    // Spinner demo
    try prompt.note(allocator, "Spinner Demo", "simulating work...");
    var spinner = prompt.SpinnerPrompt.init(allocator, "Processing data...");
    try spinner.start();

    // Simulate some work
    std.time.sleep(2 * std.time.ns_per_s);

    try spinner.stop("Processing complete!");

    // Warning and error examples
    try prompt.log(allocator, .warning, "This is a warning message");
    try prompt.log(allocator, .error_level, "This is an error message (just for demo)");

    // Final box with summary
    try prompt.box(allocator, "Summary",
        \\All features demonstrated successfully!
        \\
        \\✓ Text input with validation
        \\✓ Confirmation prompts
        \\✓ Select & MultiSelect
        \\✓ Password input
        \\✓ Spinner/loading
        \\✓ Box rendering
        \\✓ Logging & messages
        \\✓ Terminal detection
    );

    // Display outro
    try prompt.outro(allocator, "Showcase complete! Thanks for trying zig-cli.");
}

fn validateName(value: []const u8) ?[]const u8 {
    if (value.len < 3) {
        return "Name must be at least 3 characters";
    }
    return null;
}

fn validatePassword(value: []const u8) ?[]const u8 {
    if (value.len < 8) {
        return "Password must be at least 8 characters";
    }
    return null;
}
