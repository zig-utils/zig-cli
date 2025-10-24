const std = @import("std");
const Command = @import("Command.zig");

const Help = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Help {
    return .{ .allocator = allocator };
}

pub fn generate(self: *Help, command: *Command, cli_name: []const u8, version: []const u8) !void {
    _ = self;
    const stdout = std.io.getStdOut().writer();

    // Header
    try stdout.print("\n{s} v{s}\n", .{ cli_name, version });
    try stdout.print("{s}\n\n", .{command.description});

    // Usage
    try stdout.print("USAGE:\n", .{});
    try stdout.print("  {s}", .{command.name});

    if (command.options.items.len > 0) {
        try stdout.print(" [OPTIONS]", .{});
    }

    if (command.subcommands.items.len > 0) {
        try stdout.print(" <COMMAND>", .{});
    }

    for (command.arguments.items) |arg| {
        if (arg.required) {
            try stdout.print(" <{s}>", .{arg.name});
        } else {
            try stdout.print(" [{s}]", .{arg.name});
        }
        if (arg.variadic) {
            try stdout.print("...", .{});
        }
    }
    try stdout.print("\n\n", .{});

    // Arguments
    if (command.arguments.items.len > 0) {
        try stdout.print("ARGUMENTS:\n", .{});
        for (command.arguments.items) |arg| {
            try stdout.print("  <{s}>", .{arg.name});
            if (arg.variadic) {
                try stdout.print("...", .{});
            }
            const padding = 20 -| (arg.name.len + 2 + if (arg.variadic) @as(usize, 3) else @as(usize, 0));
            try stdout.writeByteNTimes(' ', padding);
            try stdout.print("{s}", .{arg.description});
            if (!arg.required) {
                try stdout.print(" (optional)", .{});
            }
            try stdout.print("\n", .{});
        }
        try stdout.print("\n", .{});
    }

    // Options
    if (command.options.items.len > 0) {
        try stdout.print("OPTIONS:\n", .{});
        for (command.options.items) |opt| {
            var length: usize = 0;

            if (opt.short) |s| {
                try stdout.print("  -{c}, ", .{s});
                length += 6;
            } else {
                try stdout.print("      ", .{});
                length += 6;
            }

            try stdout.print("--{s}", .{opt.long});
            length += opt.long.len + 2;

            if (opt.option_type != .bool) {
                const type_name = switch (opt.option_type) {
                    .string => "<VALUE>",
                    .int => "<INT>",
                    .float => "<FLOAT>",
                    .bool => "",
                };
                try stdout.print(" {s}", .{type_name});
                length += type_name.len + 1;
            }

            const padding = 30 -| length;
            try stdout.writeByteNTimes(' ', padding);

            try stdout.print("{s}", .{opt.description});

            if (opt.required) {
                try stdout.print(" (required)", .{});
            } else if (opt.default_value) |default| {
                try stdout.print(" (default: {s})", .{default});
            }

            try stdout.print("\n", .{});
        }

        try stdout.print("  -h, --help", .{});
        try stdout.writeByteNTimes(' ', 20);
        try stdout.print("Print help\n", .{});
        try stdout.print("\n", .{});
    }

    // Commands
    if (command.subcommands.items.len > 0) {
        try stdout.print("COMMANDS:\n", .{});
        for (command.subcommands.items) |subcmd| {
            try stdout.print("  {s}", .{subcmd.name});
            const padding = 20 -| subcmd.name.len;
            try stdout.writeByteNTimes(' ', padding);
            try stdout.print("{s}\n", .{subcmd.description});
        }
        try stdout.print("\n", .{});
        try stdout.print("Run '{s} <COMMAND> --help' for more information on a command.\n\n", .{command.name});
    }
}
