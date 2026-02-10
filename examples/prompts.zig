const std = @import("std");
const prompt = @import("zig-cli").prompt;

fn getIo() std.Io {
    return std.Options.debug_io;
}

fn validateEmail(value: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, value, "@") == null) {
        return "Please enter a valid email address";
    }
    return null;
}

fn validatePassword(value: []const u8) ?[]const u8 {
    if (value.len < 8) {
        return "Password must be at least 8 characters";
    }
    return null;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const io = getIo();
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(io, &buf);
    const stdout = &file_writer.interface;

    // Text prompt example
    try stdout.print("\n=== Text Prompt Example ===\n", .{});
    try stdout.flush();
    var text_prompt = prompt.TextPrompt.init(allocator, "What is your name?");
    defer text_prompt.deinit();
    _ = text_prompt.withPlaceholder("John Doe");

    const name = text_prompt.prompt() catch |err| {
        if (err == error.Canceled) {
            try stdout.print("Prompt canceled\n", .{});
            try stdout.flush();
            return;
        }
        return err;
    };
    defer allocator.free(name);
    try stdout.print("Hello, {s}!\n\n", .{name});
    try stdout.flush();

    // Email validation example
    try stdout.print("=== Email Validation Example ===\n", .{});
    try stdout.flush();
    var email_prompt = prompt.TextPrompt.init(allocator, "What is your email?");
    defer email_prompt.deinit();
    _ = email_prompt.withValidation(validateEmail);

    const email = email_prompt.prompt() catch |err| {
        if (err == error.Canceled) {
            try stdout.print("Prompt canceled\n", .{});
            try stdout.flush();
            return;
        }
        return err;
    };
    defer allocator.free(email);
    try stdout.print("Email: {s}\n\n", .{email});
    try stdout.flush();

    // Confirm prompt example
    try stdout.print("=== Confirm Prompt Example ===\n", .{});
    try stdout.flush();
    var confirm_prompt = prompt.ConfirmPrompt.init(allocator, "Do you want to continue?");
    defer confirm_prompt.deinit();
    _ = confirm_prompt.withDefault(true);

    const confirmed = confirm_prompt.prompt() catch |err| {
        if (err == error.Canceled) {
            try stdout.print("Prompt canceled\n", .{});
            try stdout.flush();
            return;
        }
        return err;
    };
    try stdout.print("Answer: {s}\n\n", .{if (confirmed) "Yes" else "No"});
    try stdout.flush();

    if (!confirmed) {
        try stdout.print("Goodbye!\n", .{});
        try stdout.flush();
        return;
    }

    // Select prompt example
    try stdout.print("=== Select Prompt Example ===\n", .{});
    try stdout.flush();
    const choices = [_]prompt.SelectPrompt.Choice{
        .{ .label = "TypeScript", .value = "ts", .description = "JavaScript with types" },
        .{ .label = "Zig", .value = "zig", .description = "A general-purpose programming language" },
        .{ .label = "Rust", .value = "rust", .description = "A language empowering everyone" },
        .{ .label = "Go", .value = "go", .description = "Build simple, secure, scalable systems" },
    };

    var select_prompt = prompt.SelectPrompt.init(allocator, "What is your favorite language?", &choices);
    defer select_prompt.deinit();

    const selected = select_prompt.prompt() catch |err| {
        if (err == error.Canceled) {
            try stdout.print("Prompt canceled\n", .{});
            try stdout.flush();
            return;
        }
        return err;
    };
    defer allocator.free(selected);
    try stdout.print("You selected: {s}\n\n", .{selected});
    try stdout.flush();

    // MultiSelect prompt example
    try stdout.print("=== MultiSelect Prompt Example ===\n", .{});
    try stdout.flush();
    const tech_choices = [_]prompt.MultiSelectPrompt.Choice{
        .{ .label = "Frontend", .value = "frontend", .description = "Build user interfaces" },
        .{ .label = "Backend", .value = "backend", .description = "Build server-side logic" },
        .{ .label = "DevOps", .value = "devops", .description = "Infrastructure and automation" },
        .{ .label = "Mobile", .value = "mobile", .description = "Build mobile apps" },
    };

    var multi_prompt = try prompt.MultiSelectPrompt.init(allocator, "What areas interest you?", &tech_choices);
    defer multi_prompt.deinit();

    const selected_items = multi_prompt.prompt() catch |err| {
        if (err == error.Canceled) {
            try stdout.print("Prompt canceled\n", .{});
            try stdout.flush();
            return;
        }
        return err;
    };
    defer {
        for (selected_items) |item| {
            allocator.free(item);
        }
        allocator.free(selected_items);
    }

    try stdout.print("You selected {d} items:\n", .{selected_items.len});
    for (selected_items) |item| {
        try stdout.print("  - {s}\n", .{item});
    }
    try stdout.print("\n", .{});
    try stdout.flush();

    // Password prompt example
    try stdout.print("=== Password Prompt Example ===\n", .{});
    try stdout.flush();
    var password_prompt = prompt.PasswordPrompt.init(allocator, "Enter your password:");
    defer password_prompt.deinit();
    _ = password_prompt.withValidation(validatePassword);

    const password = password_prompt.prompt() catch |err| {
        if (err == error.Canceled) {
            try stdout.print("Prompt canceled\n", .{});
            try stdout.flush();
            return;
        }
        return err;
    };
    defer allocator.free(password);
    try stdout.print("Password set successfully (length: {d})\n\n", .{password.len});

    try stdout.print("All prompts completed successfully!\n", .{});
    try stdout.flush();
}
