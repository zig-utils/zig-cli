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
/// May be given more than once; every value is kept (`ParseContext.getOptionValues`).
repeatable: bool = false,

/// The spellings a bool option takes after `=`, case-insensitively: true, false, yes, no, on,
/// off, 1, 0 (clamscan-style `--flag=yes` as well as `--flag=true`). A bare `--flag` is true.
pub const bool_spellings = "true, false, yes, no, on, off, 1 or 0";

/// `text` as a bool option value, or null when it is none of `bool_spellings`.
pub fn parseBool(text: []const u8) ?bool {
    const yes = [_][]const u8{ "true", "yes", "on", "1" };
    const no = [_][]const u8{ "false", "no", "off", "0" };
    for (yes) |s| if (std.ascii.eqlIgnoreCase(text, s)) return true;
    for (no) |s| if (std.ascii.eqlIgnoreCase(text, s)) return false;
    return null;
}

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

pub fn withRepeatable(self: Option, repeatable: bool) Option {
    var opt = self;
    opt.repeatable = repeatable;
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
