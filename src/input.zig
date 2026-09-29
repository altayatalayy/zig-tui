//! Key decoding for a raw-mode tty.

const std = @import("std");
const posix = std.posix;

pub const Key = union(enum) {
    char: u8,
    enter,
    backspace,
    up,
    down,
    left,
    right,
    cancel,
};

/// Blocks until a byte arrives; returns null on EOF (tty closed).
pub fn readKey(fd: posix.fd_t) !?Key {
    while (true) {
        const b = try readByte(fd) orelse return null;
        if (b == 0x1b) return try readEscape(fd);
        if (keyFromByte(b)) |key| return key;
    }
}

pub fn keyFromByte(b: u8) ?Key {
    return switch (b) {
        '\r' => .enter,
        0x7f, 0x08 => .backspace,
        0x03 => .cancel, // Ctrl-C
        0x0e, 0x0a => .down, // Ctrl-N, Ctrl-J
        0x10, 0x0b => .up, // Ctrl-P, Ctrl-K
        0x02 => .left, // Ctrl-B
        0x06 => .right, // Ctrl-F
        else => if (b >= 0x20 and b < 0x7f) Key{ .char = b } else null,
    };
}

/// Decodes a complete buffered byte sequence. A lone escape, or an unknown
/// escape sequence, maps to cancel.
pub fn decodeSequence(bytes: []const u8) ?Key {
    if (bytes.len == 0) return null;
    if (bytes[0] != 0x1b) return keyFromByte(bytes[0]);
    if (bytes.len == 1) return .cancel;
    if (bytes.len >= 3 and bytes[1] == '[') return keyFromCsi(bytes[2]);
    return .cancel;
}

fn keyFromCsi(final: u8) Key {
    return switch (final) {
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        else => .cancel,
    };
}

fn readEscape(fd: posix.fd_t) !Key {
    if (!(try pollReadable(fd, 50))) return .cancel;
    if ((try readByte(fd)) != '[') return .cancel;
    return keyFromCsi((try readByte(fd)) orelse return .cancel);
}

fn readByte(fd: posix.fd_t) !?u8 {
    var b: [1]u8 = undefined;
    const n = try posix.read(fd, &b);
    return if (n == 1) b[0] else null;
}

fn pollReadable(fd: posix.fd_t, timeout_ms: i32) !bool {
    var fds = [_]posix.pollfd{.{ .fd = fd, .events = posix.POLL.IN, .revents = 0 }};
    const n = try posix.poll(&fds, timeout_ms);
    return n > 0 and fds[0].revents & posix.POLL.IN != 0;
}

fn expectTag(expected: std.meta.Tag(Key), key: ?Key) !void {
    try std.testing.expect(key != null);
    try std.testing.expectEqual(expected, std.meta.activeTag(key.?));
}

test "raw bytes map to keys" {
    try expectTag(.enter, keyFromByte('\r'));
    try expectTag(.down, keyFromByte(0x0a));
    try expectTag(.up, keyFromByte(0x0b));
    try expectTag(.left, keyFromByte(0x02));
    try expectTag(.right, keyFromByte(0x06));
    try expectTag(.cancel, keyFromByte(0x03));
    try expectTag(.backspace, keyFromByte(0x7f));
    try expectTag(.backspace, keyFromByte(0x08));

    const q = keyFromByte('q') orelse return error.ExpectedChar;
    try std.testing.expectEqual(@as(u8, 'q'), q.char);
}

test "escape arrow sequences map to movement" {
    try expectTag(.up, decodeSequence("\x1b[A"));
    try expectTag(.down, decodeSequence("\x1b[B"));
    try expectTag(.right, decodeSequence("\x1b[C"));
    try expectTag(.left, decodeSequence("\x1b[D"));
    try expectTag(.cancel, decodeSequence("\x1b"));
    try expectTag(.cancel, decodeSequence("\x1b[Z"));
}
