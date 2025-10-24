const std = @import("std");
const builtin = @import("builtin");

const Terminal = @This();

pub const RawMode = struct {
    original_termios: if (builtin.os.tag != .windows) std.os.termios else void,

    pub fn enable() !RawMode {
        const stdin = std.io.getStdIn();
        if (builtin.os.tag == .windows) {
            // Windows terminal setup would go here
            return RawMode{ .original_termios = {} };
        } else {
            const original = try std.os.tcgetattr(stdin.handle);
            var raw = original;

            // Disable canonical mode and echo
            raw.lflag.ICANON = false;
            raw.lflag.ECHO = false;
            raw.lflag.ISIG = false;

            // Set read to return immediately
            raw.cc[@intFromEnum(std.os.linux.V.MIN)] = 0;
            raw.cc[@intFromEnum(std.os.linux.V.TIME)] = 1;

            try std.os.tcsetattr(stdin.handle, .FLUSH, raw);

            return RawMode{ .original_termios = original };
        }
    }

    pub fn disable(self: RawMode) void {
        if (builtin.os.tag == .windows) {
            return;
        }
        const stdin = std.io.getStdIn();
        std.os.tcsetattr(stdin.handle, .FLUSH, self.original_termios) catch {};
    }
};

pub const Key = enum {
    char,
    enter,
    escape,
    backspace,
    delete,
    tab,
    up,
    down,
    left,
    right,
    home,
    end,
    ctrl_c,
    ctrl_d,
    unknown,
};

pub const KeyPress = struct {
    key: Key,
    char: ?u8 = null,
};

stdin: std.fs.File,
stdout: std.fs.File,
supports_unicode: bool,
supports_color: bool,
width: usize,
height: usize,

pub fn init() Terminal {
    const supports_unicode = detectUnicodeSupport();
    const supports_color = detectColorSupport();
    const size = detectTerminalSize();

    return .{
        .stdin = std.io.getStdIn(),
        .stdout = std.io.getStdOut(),
        .supports_unicode = supports_unicode,
        .supports_color = supports_color,
        .width = size.width,
        .height = size.height,
    };
}

fn detectUnicodeSupport() bool {
    if (std.os.getenv("LANG")) |lang| {
        return std.mem.indexOf(u8, lang, "UTF-8") != null or
            std.mem.indexOf(u8, lang, "utf8") != null;
    }
    return false;
}

fn detectColorSupport() bool {
    if (std.os.getenv("NO_COLOR")) |_| {
        return false;
    }
    if (std.os.getenv("TERM")) |term| {
        return !std.mem.eql(u8, term, "dumb");
    }
    return true;
}

const TerminalSize = struct {
    width: usize,
    height: usize,
};

fn detectTerminalSize() TerminalSize {
    if (builtin.os.tag == .windows) {
        // Windows console API would go here
        return .{ .width = 80, .height = 24 };
    }

    // Try to get terminal size via ioctl
    const stdout = std.io.getStdOut();
    var winsize: std.os.linux.winsize = undefined;

    const result = std.os.linux.ioctl(stdout.handle, std.os.linux.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (result == 0 and winsize.ws_col > 0 and winsize.ws_row > 0) {
        return .{
            .width = winsize.ws_col,
            .height = winsize.ws_row,
        };
    }

    // Fallback to common defaults
    return .{ .width = 80, .height = 24 };
}

pub fn readKey(self: *Terminal) !?KeyPress {
    var buf: [8]u8 = undefined;
    const n = try self.stdin.read(&buf);

    if (n == 0) return null;

    // Handle escape sequences
    if (buf[0] == 27) { // ESC
        if (n == 1) return KeyPress{ .key = .escape };

        if (n >= 3 and buf[1] == '[') {
            return switch (buf[2]) {
                'A' => KeyPress{ .key = .up },
                'B' => KeyPress{ .key = .down },
                'C' => KeyPress{ .key = .right },
                'D' => KeyPress{ .key = .left },
                'H' => KeyPress{ .key = .home },
                'F' => KeyPress{ .key = .end },
                '3' => if (n >= 4 and buf[3] == '~') KeyPress{ .key = .delete } else KeyPress{ .key = .unknown },
                else => KeyPress{ .key = .unknown },
            };
        }

        return KeyPress{ .key = .unknown };
    }

    // Handle control characters
    return switch (buf[0]) {
        3 => KeyPress{ .key = .ctrl_c },
        4 => KeyPress{ .key = .ctrl_d },
        9 => KeyPress{ .key = .tab },
        10, 13 => KeyPress{ .key = .enter },
        127 => KeyPress{ .key = .backspace },
        32...126 => KeyPress{ .key = .char, .char = buf[0] },
        else => KeyPress{ .key = .unknown },
    };
}

pub fn write(self: *Terminal, text: []const u8) !void {
    try self.stdout.writeAll(text);
}

pub fn writeLine(self: *Terminal, text: []const u8) !void {
    try self.stdout.writeAll(text);
    try self.stdout.writeAll("\n");
}

pub fn clearScreen(self: *Terminal) !void {
    try self.write("\x1b[2J\x1b[H");
}

pub fn clearLine(self: *Terminal) !void {
    try self.write("\x1b[2K\r");
}

pub fn moveCursor(self: *Terminal, row: usize, col: usize) !void {
    var buf: [32]u8 = undefined;
    const seq = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ row, col });
    try self.write(seq);
}

pub fn hideCursor(self: *Terminal) !void {
    try self.write("\x1b[?25l");
}

pub fn showCursor(self: *Terminal) !void {
    try self.write("\x1b[?25h");
}

pub fn saveCursor(self: *Terminal) !void {
    try self.write("\x1b[s");
}

pub fn restoreCursor(self: *Terminal) !void {
    try self.write("\x1b[u");
}

pub fn flush(self: *Terminal) !void {
    // No buffering in our implementation, but keeping for API consistency
    _ = self;
}
