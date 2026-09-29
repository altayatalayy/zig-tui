//! Blocking event loop input: multiplexes key presses and terminal resizes.

const std = @import("std");
const posix = std.posix;
const input = @import("input.zig");
const signals = @import("signals.zig");

pub const Event = union(enum) {
    key: input.Key,
    resize,
};

/// Blocks until a key or resize arrives; returns null on tty EOF.
pub fn read(tty_fd: posix.fd_t, resize: *signals.Resize) !?Event {
    while (true) {
        var fds = [_]posix.pollfd{
            .{ .fd = tty_fd, .events = posix.POLL.IN, .revents = 0 },
            .{ .fd = resize.fd, .events = posix.POLL.IN, .revents = 0 },
        };

        _ = try posix.poll(&fds, -1);

        if (fds[1].revents & posix.POLL.IN != 0) {
            try resize.drain();
            return .resize;
        }

        if (fds[0].revents & posix.POLL.IN != 0) {
            const key = try input.readKey(tty_fd) orelse return null;
            return .{ .key = key };
        }
    }
}
