//! SIGWINCH as a pollable fd, so resizes join the main poll loop.

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

pub const Resize = struct {
    fd: posix.fd_t,
    old_mask: posix.sigset_t,

    pub fn init() !Resize {
        var mask = posix.sigemptyset();
        posix.sigaddset(&mask, .WINCH);

        var old_mask: posix.sigset_t = undefined;
        posix.sigprocmask(posix.SIG.BLOCK, &mask, &old_mask);
        errdefer posix.sigprocmask(posix.SIG.SETMASK, &old_mask, null);

        const fd = try posix.signalfd(
            -1,
            &mask,
            linux.SFD.CLOEXEC | linux.SFD.NONBLOCK,
        );
        return .{ .fd = fd, .old_mask = old_mask };
    }

    pub fn deinit(self: *Resize) void {
        _ = linux.close(self.fd);
        posix.sigprocmask(posix.SIG.SETMASK, &self.old_mask, null);
        self.* = undefined;
    }

    /// Consumes all queued WINCH notifications; coalesced into one event.
    pub fn drain(self: *Resize) !void {
        var infos: [8]linux.signalfd_siginfo = undefined;
        const bytes = std.mem.asBytes(&infos);
        while (true) {
            const n = posix.read(self.fd, bytes) catch |err| switch (err) {
                error.WouldBlock => return,
                else => |e| return e,
            };
            if (n == 0) return;
        }
    }
};
