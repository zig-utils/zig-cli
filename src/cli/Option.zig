const std = @import("std");

const Option = @This();

pub const OptionType = enum {
    string,
    int,
    float,
    bool,
};

name: []const u8,
short: ?u8 = null,
long: []const u8,
description: []const u8,
option_type: OptionType,
required: bool = false,
default_value: ?[]const u8 = null,

pub fn init(name: []const u8, long: []const u8, description: []const u8, option_type: OptionType) Option {
    return .{
        .name = name,
        .long = long,
        .description = description,
        .option_type = option_type,
    };
}

pub fn withShort(self: Option, short: u8) Option {
    var opt = self;
    opt.short = short;
    return opt;
}

pub fn withRequired(self: Option, required: bool) Option {
    var opt = self;
    opt.required = required;
    return opt;
}

pub fn withDefault(self: Option, default_value: []const u8) Option {
    var opt = self;
    opt.default_value = default_value;
    return opt;
}

pub fn matches(self: Option, arg: []const u8) bool {
    if (arg.len >= 2 and arg[0] == '-') {
        if (arg[1] == '-') {
            // Long option
            return std.mem.eql(u8, arg[2..], self.long);
        } else if (self.short) |s| {
            // Short option
            return arg.len == 2 and arg[1] == s;
        }
    }
    return false;
}
