const std = @import("std");

const Argument = @This();

pub const ArgumentType = enum {
    string,
    int,
    float,
};

name: []const u8,
description: []const u8,
arg_type: ArgumentType,
required: bool = true,
variadic: bool = false,

pub fn init(name: []const u8, description: []const u8, arg_type: ArgumentType) Argument {
    return .{
        .name = name,
        .description = description,
        .arg_type = arg_type,
    };
}

pub fn withRequired(self: Argument, required: bool) Argument {
    var arg = self;
    arg.required = required;
    return arg;
}

pub fn withVariadic(self: Argument, variadic: bool) Argument {
    var arg = self;
    arg.variadic = variadic;
    return arg;
}
