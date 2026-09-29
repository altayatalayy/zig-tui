//! Truecolor SGR styling for a *std.Io.Writer.

const std = @import("std");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const Face = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    bold: bool = false,

    pub fn isPlain(self: Face) bool {
        return self.fg == null and self.bg == null and !self.bold;
    }
};

pub fn rgb(r: u8, g: u8, b: u8) Color {
    return .{ .r = r, .g = g, .b = b };
}

pub fn apply(w: *std.Io.Writer, face: Face) !void {
    if (face.bold) try w.writeAll("\x1b[1m");
    if (face.fg) |fg| try w.print("\x1b[38;2;{d};{d};{d}m", .{ fg.r, fg.g, fg.b });
    if (face.bg) |bg| try w.print("\x1b[48;2;{d};{d};{d}m", .{ bg.r, bg.g, bg.b });
}

pub fn reset(w: *std.Io.Writer) !void {
    try w.writeAll("\x1b[0m");
}

/// Writes `bytes` wrapped in apply/reset; a plain face skips the escapes.
pub fn write(w: *std.Io.Writer, face: Face, bytes: []const u8) !void {
    if (face.isPlain()) {
        try w.writeAll(bytes);
        return;
    }
    try apply(w, face);
    try w.writeAll(bytes);
    try reset(w);
}

test "face with no background does not emit a background escape" {
    var buf: [64]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);

    try write(&w, .{ .fg = rgb(0x9c, 0xcf, 0xd8) }, ">");
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "48;2") == null);
}

test "face emits background only when one is set" {
    var buf: [64]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);

    try write(&w, .{ .bg = rgb(0x1f, 0x1d, 0x2e) }, " ");
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "48;2") != null);
}

test "plain face writes bytes without escapes" {
    var buf: [64]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);

    try write(&w, .{}, "plain");
    try std.testing.expectEqualStrings("plain", w.buffered());
}
