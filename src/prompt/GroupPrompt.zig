const std = @import("std");
const TextPrompt = @import("TextPrompt.zig");
const ConfirmPrompt = @import("ConfirmPrompt.zig");
const SelectPrompt = @import("SelectPrompt.zig");
const NumberPrompt = @import("NumberPrompt.zig");
const PasswordPrompt = @import("PasswordPrompt.zig");

const GroupPrompt = @This();

pub const PromptResult = union(enum) {
    text: []const u8,
    number: f64,
    boolean: bool,
    password: []const u8,

    pub fn deinit(self: *PromptResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .text, .password => |s| allocator.free(s),
            else => {},
        }
    }
};

pub const PromptDef = union(enum) {
    text: struct {
        key: []const u8,
        message: []const u8,
        placeholder: ?[]const u8 = null,
        default: ?[]const u8 = null,
    },
    number: struct {
        key: []const u8,
        message: []const u8,
        number_type: NumberPrompt.NumberType = .integer,
        min: ?f64 = null,
        max: ?f64 = null,
        default: ?f64 = null,
    },
    confirm: struct {
        key: []const u8,
        message: []const u8,
        default: bool = false,
    },
    select: struct {
        key: []const u8,
        message: []const u8,
        choices: []const SelectPrompt.Choice,
    },
    password: struct {
        key: []const u8,
        message: []const u8,
    },
};

allocator: std.mem.Allocator,
prompts: []const PromptDef,
results: std.StringHashMap(PromptResult),

pub fn init(allocator: std.mem.Allocator, prompts: []const PromptDef) GroupPrompt {
    return .{
        .allocator = allocator,
        .prompts = prompts,
        .results = std.StringHashMap(PromptResult).init(allocator),
    };
}

pub fn deinit(self: *GroupPrompt) void {
    var iter = self.results.iterator();
    while (iter.next()) |entry| {
        var result = entry.value_ptr.*;
        result.deinit(self.allocator);
    }
    self.results.deinit();
}

pub fn run(self: *GroupPrompt) !void {
    for (self.prompts) |prompt_def| {
        const result = try self.executePrompt(prompt_def);

        const key = switch (prompt_def) {
            .text => |t| t.key,
            .number => |n| n.key,
            .confirm => |c| c.key,
            .select => |s| s.key,
            .password => |p| p.key,
        };

        try self.results.put(key, result);
    }
}

fn executePrompt(self: *GroupPrompt, prompt_def: PromptDef) !PromptResult {
    return switch (prompt_def) {
        .text => |t| blk: {
            var prompt_obj = TextPrompt.init(self.allocator, t.message);
            defer prompt_obj.deinit();

            if (t.placeholder) |ph| {
                _ = prompt_obj.withPlaceholder(ph);
            }
            if (t.default) |d| {
                _ = prompt_obj.withDefault(d);
            }

            const result = try prompt_obj.prompt();
            break :blk PromptResult{ .text = result };
        },
        .number => |n| blk: {
            var prompt_obj = NumberPrompt.init(self.allocator, n.message, n.number_type);
            defer prompt_obj.deinit();

            if (n.min) |min| {
                _ = prompt_obj.withMin(min);
            }
            if (n.max) |max| {
                _ = prompt_obj.withMax(max);
            }
            if (n.default) |d| {
                _ = prompt_obj.withDefault(d);
            }

            const result = try prompt_obj.prompt();
            break :blk PromptResult{ .number = result };
        },
        .confirm => |c| blk: {
            var prompt_obj = ConfirmPrompt.init(self.allocator, c.message);
            defer prompt_obj.deinit();
            _ = prompt_obj.withDefault(c.default);

            const result = try prompt_obj.prompt();
            break :blk PromptResult{ .boolean = result };
        },
        .select => |s| blk: {
            var prompt_obj = SelectPrompt.init(self.allocator, s.message, s.choices);
            defer prompt_obj.deinit();

            const result = try prompt_obj.prompt();
            break :blk PromptResult{ .text = result };
        },
        .password => |p| blk: {
            var prompt_obj = PasswordPrompt.init(self.allocator, p.message);
            defer prompt_obj.deinit();

            const result = try prompt_obj.prompt();
            break :blk PromptResult{ .password = result };
        },
    };
}

pub fn getText(self: *GroupPrompt, key: []const u8) ?[]const u8 {
    const result = self.results.get(key) orelse return null;
    return switch (result) {
        .text => |t| t,
        else => null,
    };
}

pub fn getNumber(self: *GroupPrompt, key: []const u8) ?f64 {
    const result = self.results.get(key) orelse return null;
    return switch (result) {
        .number => |n| n,
        else => null,
    };
}

pub fn getBool(self: *GroupPrompt, key: []const u8) ?bool {
    const result = self.results.get(key) orelse return null;
    return switch (result) {
        .boolean => |b| b,
        else => null,
    };
}

pub fn getPassword(self: *GroupPrompt, key: []const u8) ?[]const u8 {
    const result = self.results.get(key) orelse return null;
    return switch (result) {
        .password => |p| p,
        else => null,
    };
}
