const std = @import("std");
const Command = @import("Command.zig");
const Option = @import("Option.zig");
const Argument = @import("Argument.zig");

const Parser = @This();

pub const ParseError = error{
    UnknownOption,
    UnknownCommand,
    MissingRequiredOption,
    MissingRequiredArgument,
    InvalidOptionValue,
    MissingOptionValue,
    TooManyArguments,
};

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Parser {
    return .{ .allocator = allocator };
}

pub fn parse(self: *Parser, command: *Command, args: []const []const u8) !void {
    if (args.len == 0) {
        if (command.action) |action| {
            var context = Command.ParseContext.init(self.allocator, command.name);
            defer context.deinit();
            try action(&context);
        }
        return;
    }

    // Check for subcommand
    if (command.findSubcommand(args[0])) |subcmd| {
        return self.parse(subcmd, args[1..]);
    }

    var context = Command.ParseContext.init(self.allocator, command.name);
    defer context.deinit();

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        // Check if it's an option
        if (arg.len > 0 and arg[0] == '-') {
            if (command.findOption(arg)) |opt| {
                if (opt.option_type == .bool) {
                    // Boolean flag, no value needed
                    try context.options.put(opt.name, "true");
                } else {
                    // Next arg should be the value
                    i += 1;
                    if (i >= args.len) {
                        std.debug.print("Error: Option '{s}' requires a value\n", .{arg});
                        return ParseError.MissingOptionValue;
                    }
                    const value = args[i];

                    // Validate the value type
                    try self.validateOptionValue(opt.*, value);
                    try context.options.put(opt.name, value);
                }
            } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                // Help flag - will be handled by CLI
                try context.options.put("help", "true");
            } else {
                std.debug.print("Error: Unknown option '{s}'\n", .{arg});
                return ParseError.UnknownOption;
            }
        } else {
            // It's a positional argument
            try context.arguments.append(arg);
        }
    }

    // Validate required options
    for (command.options.items) |opt| {
        if (opt.required and !context.hasOption(opt.name)) {
            if (opt.default_value) |default| {
                try context.options.put(opt.name, default);
            } else {
                std.debug.print("Error: Missing required option '--{s}'\n", .{opt.long});
                return ParseError.MissingRequiredOption;
            }
        } else if (!context.hasOption(opt.name) and opt.default_value != null) {
            try context.options.put(opt.name, opt.default_value.?);
        }
    }

    // Validate required arguments
    var required_count: usize = 0;
    for (command.arguments.items) |arg_def| {
        if (arg_def.required) {
            required_count += 1;
        }
    }

    if (context.getArgumentCount() < required_count) {
        std.debug.print("Error: Missing required arguments\n", .{});
        return ParseError.MissingRequiredArgument;
    }

    // Check for too many arguments (unless last one is variadic)
    const has_variadic = if (command.arguments.items.len > 0)
        command.arguments.items[command.arguments.items.len - 1].variadic
    else
        false;

    if (!has_variadic and context.getArgumentCount() > command.arguments.items.len) {
        std.debug.print("Error: Too many arguments provided\n", .{});
        return ParseError.TooManyArguments;
    }

    // Execute command action
    if (context.hasOption("help")) {
        // Help will be handled by CLI
        return;
    }

    if (command.action) |action| {
        try action(&context);
    }
}

fn validateOptionValue(self: *Parser, option: Option, value: []const u8) !void {
    _ = self;
    switch (option.option_type) {
        .string => {}, // Always valid
        .int => {
            _ = std.fmt.parseInt(i64, value, 10) catch {
                std.debug.print("Error: Option '--{s}' expects an integer value\n", .{option.long});
                return ParseError.InvalidOptionValue;
            };
        },
        .float => {
            _ = std.fmt.parseFloat(f64, value) catch {
                std.debug.print("Error: Option '--{s}' expects a float value\n", .{option.long});
                return ParseError.InvalidOptionValue;
            };
        },
        .bool => {}, // Already handled
    }
}
