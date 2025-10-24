const std = @import("std");

pub const State = enum {
    initial,
    active,
    error_state,
    submit,
    cancel,

    pub fn canTransitionTo(self: State, next: State) bool {
        return switch (self) {
            .initial => next == .active,
            .active => next == .error_state or next == .submit or next == .cancel,
            .error_state => next == .active or next == .submit or next == .cancel,
            .submit, .cancel => false, // Terminal states
        };
    }
};

pub const Event = union(enum) {
    value: []const u8,
    cursor: usize,
    key: KeyEvent,
    submit: void,
    cancel: void,
    error_event: []const u8,

    pub const KeyEvent = struct {
        key: u8,
        is_ctrl: bool = false,
        is_alt: bool = false,
    };
};

pub const EventHandler = *const fn (event: Event) void;

pub const StateTransition = struct {
    from: State,
    to: State,
    timestamp: i64,

    pub fn init(from: State, to: State) StateTransition {
        return .{
            .from = from,
            .to = to,
            .timestamp = std.time.timestamp(),
        };
    }
};
