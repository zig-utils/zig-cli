const std = @import("std");
const Command = @import("Command.zig");

pub const MiddlewareContext = struct {
    parse_context: *Command.ParseContext,
    command: *Command,
    allocator: std.mem.Allocator,
    data: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, parse_context: *Command.ParseContext, command: *Command) MiddlewareContext {
        return .{
            .parse_context = parse_context,
            .command = command,
            .allocator = allocator,
            .data = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *MiddlewareContext) void {
        self.data.deinit();
    }

    pub fn set(self: *MiddlewareContext, key: []const u8, value: []const u8) !void {
        try self.data.put(key, value);
    }

    pub fn get(self: *MiddlewareContext, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }
};

pub const MiddlewareFn = *const fn (ctx: *MiddlewareContext) anyerror!bool;

pub const Middleware = struct {
    name: []const u8,
    handler: MiddlewareFn,
    order: i32, // Lower runs first

    pub fn init(name: []const u8, handler: MiddlewareFn) Middleware {
        return .{
            .name = name,
            .handler = handler,
            .order = 0,
        };
    }

    pub fn withOrder(self: Middleware, order: i32) Middleware {
        var result = self;
        result.order = order;
        return result;
    }
};

pub const MiddlewareChain = struct {
    allocator: std.mem.Allocator,
    middlewares: std.ArrayList(Middleware),

    pub fn init(allocator: std.mem.Allocator) MiddlewareChain {
        return .{
            .allocator = allocator,
            .middlewares = std.ArrayList(Middleware).init(allocator),
        };
    }

    pub fn deinit(self: *MiddlewareChain) void {
        self.middlewares.deinit();
    }

    pub fn use(self: *MiddlewareChain, middleware: Middleware) !void {
        try self.middlewares.append(middleware);

        // Sort by order
        std.mem.sort(Middleware, self.middlewares.items, {}, compareMiddleware);
    }

    pub fn execute(self: *MiddlewareChain, ctx: *MiddlewareContext) !bool {
        for (self.middlewares.items) |middleware| {
            const should_continue = try middleware.handler(ctx);
            if (!should_continue) {
                return false; // Middleware chain stopped
            }
        }
        return true;
    }

    fn compareMiddleware(_: void, a: Middleware, b: Middleware) bool {
        return a.order < b.order;
    }
};

// Built-in middleware

/// Logging middleware
pub fn loggingMiddleware(ctx: *MiddlewareContext) !bool {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("[LOG] Executing command: {s}\n", .{ctx.command.name});
    return true;
}

/// Timing middleware
pub fn timingMiddleware(ctx: *MiddlewareContext) !bool {
    const start = std.time.milliTimestamp();
    try ctx.set("start_time", try std.fmt.allocPrint(ctx.allocator, "{d}", .{start}));
    return true;
}

/// Validation middleware
pub fn validationMiddleware(ctx: *MiddlewareContext) !bool {
    // Check if all required options are present
    for (ctx.command.options.items) |opt| {
        if (opt.required and !ctx.parse_context.hasOption(opt.name)) {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("Error: Missing required option '--{s}'\n", .{opt.long});
            return false;
        }
    }
    return true;
}

/// Environment check middleware
pub fn environmentCheckMiddleware(ctx: *MiddlewareContext) !bool {
    // Example: Check if running in CI
    if (std.os.getenv("CI")) |_| {
        try ctx.set("ci_mode", "true");
    }
    return true;
}
