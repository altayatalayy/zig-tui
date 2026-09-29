//! Direct /dev/tty access: raw mode, the alternate screen, and size queries.
//! Linux-only; talks to the fd directly so stdout stays free for output.

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

pub const Size = struct {
    cols: usize,
    rows: usize,
};

pub fn open() !posix.fd_t {
    return try posix.openat(posix.AT.FDCWD, "/dev/tty", .{ .ACCMODE = .RDWR }, 0);
}

pub fn close(fd: posix.fd_t) void {
    _ = linux.close(fd);
}

pub const RawMode = struct {
    fd: posix.fd_t,
    orig: posix.termios,

    pub fn init(fd: posix.fd_t) !RawMode {
        const orig = try posix.tcgetattr(fd);
        try posix.tcsetattr(fd, .FLUSH, rawTermios(orig));
        return .{ .fd = fd, .orig = orig };
    }

    pub fn deinit(self: *RawMode) void {
        posix.tcsetattr(self.fd, .FLUSH, self.orig) catch {};
        self.* = undefined;
    }
};

pub const AltScreen = struct {
    fd: posix.fd_t,

    pub fn init(fd: posix.fd_t) !AltScreen {
        try writeAll(fd, "\x1b[?1049h");
        return .{ .fd = fd };
    }

    pub fn deinit(self: *AltScreen) void {
        writeAll(self.fd, "\x1b[?25h\x1b[?1049l") catch {};
        self.* = undefined;
    }
};

pub fn showCursor(fd: posix.fd_t) !void {
    try writeAll(fd, "\x1b[?25h");
}

pub fn hideCursor(fd: posix.fd_t) !void {
    try writeAll(fd, "\x1b[?25l");
}

/// Writer-based so it composes into a buffered frame; (x, y) are 0-based.
pub fn moveCursor(w: *std.Io.Writer, x: usize, y: usize) !void {
    try w.print("\x1b[{d};{d}H", .{ y + 1, x + 1 });
}

pub fn size(fd: posix.fd_t) !Size {
    var ws: posix.winsize = undefined;
    const rc = linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&ws));
    const sret: isize = @bitCast(rc);
    if (sret < 0) return error.InvalidTerminalSize;
    return .{ .cols = ws.col, .rows = ws.row };
}

pub fn writeAll(fd: posix.fd_t, bytes: []const u8) !void {
    var i: usize = 0;
    while (i < bytes.len) {
        const rc = linux.write(fd, bytes[i..].ptr, bytes.len - i);
        const n: isize = @bitCast(rc);
        if (n <= 0) return error.WriteFailed;
        i += @intCast(n);
    }
}

pub fn rawTermios(orig: posix.termios) posix.termios {
    var raw = orig;
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.INLCR = false;
    raw.iflag.IGNCR = false;
    raw.cc[@intFromEnum(posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;
    return raw;
}

test "rawTermios keeps Ctrl-J distinct from Enter" {
    var term: posix.termios = std.mem.zeroes(posix.termios);
    term.iflag.ICRNL = true;
    term.iflag.INLCR = true;
    term.iflag.IGNCR = true;
    term.iflag.IXON = true;

    const raw = rawTermios(term);
    try std.testing.expect(!raw.iflag.ICRNL);
    try std.testing.expect(!raw.iflag.INLCR);
    try std.testing.expect(!raw.iflag.IGNCR);
    try std.testing.expect(!raw.iflag.IXON);
}
