//! Fixed-width cell rendering: truncation with an ellipsis, padding, and
//! per-character match highlighting.

const std = @import("std");
const style = @import("style.zig");

pub const ellipsis = "...";

/// Truncates `text` to `width`, replacing the overflow with an ellipsis.
pub fn writeTruncated(w: *std.Io.Writer, text: []const u8, width: usize, face: style.Face) !void {
    const kept = keptLen(text, width);
    if (kept > 0) try style.write(w, face, text[0..kept]);
    if (text.len > kept and width >= ellipsis.len) try style.write(w, face, ellipsis);
}

/// Truncates and right-pads to exactly `width` columns.
pub fn writeCell(w: *std.Io.Writer, text: []const u8, width: usize, face: style.Face) !void {
    try writeTruncated(w, text, width, face);
    try writePadding(w, renderedLen(text, width), width);
}

/// Like `writeCell`, but characters whose absolute position (`offset` + index)
/// appears in the sorted `positions` list get `highlight` instead of `base`.
pub fn writeHighlightedCell(
    w: *std.Io.Writer,
    text: []const u8,
    offset: usize,
    positions: []const usize,
    width: usize,
    base: style.Face,
    highlight: style.Face,
) !void {
    const kept = keptLen(text, width);
    try writeHighlighted(w, text[0..kept], offset, positions, base, highlight);
    if (text.len > kept and width >= ellipsis.len) {
        try style.write(w, base, ellipsis);
    }
    try writePadding(w, renderedLen(text, width), width);
}

pub fn writeHighlighted(
    w: *std.Io.Writer,
    text: []const u8,
    offset: usize,
    positions: []const usize,
    base: style.Face,
    highlight: style.Face,
) !void {
    var start: usize = 0;
    for (text, 0..) |_, i| {
        if (!hasPosition(positions, offset + i)) continue;
        if (start < i) try style.write(w, base, text[start..i]);
        try style.write(w, highlight, text[i .. i + 1]);
        start = i + 1;
    }
    if (start < text.len) try style.write(w, base, text[start..]);
}

pub fn writePadding(w: *std.Io.Writer, used: usize, width: usize) !void {
    var i: usize = used;
    while (i < width) : (i += 1) try w.writeByte(' ');
}

/// Repeats a (possibly multi-byte) rune `count` times; useful for rules.
pub fn writeRepeated(w: *std.Io.Writer, rune: []const u8, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) try w.writeAll(rune);
}

// Keep room for the ellipsis: when text overflows we drop the last chars and
// render "..." in their place so the cell still fits exactly within `width`.
fn keptLen(text: []const u8, width: usize) usize {
    if (text.len <= width) return text.len;
    return width -| ellipsis.len;
}

fn renderedLen(text: []const u8, width: usize) usize {
    if (width == 0) return 0;
    return @min(text.len, width);
}

fn hasPosition(positions: []const usize, pos: usize) bool {
    for (positions) |p| {
        if (p == pos) return true;
        if (p > pos) return false;
    }
    return false;
}

// --- tests ---

const testing = std.testing;

test "short text is padded to the cell width" {
    var buf: [32]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);

    try writeCell(&w, "ab", 5, .{});
    try testing.expectEqualStrings("ab   ", w.buffered());
}

test "long text is truncated with an ellipsis" {
    var buf: [32]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);

    try writeCell(&w, "abcdefgh", 6, .{});
    try testing.expectEqualStrings("abc...", w.buffered());
}

test "tiny widths drop the ellipsis instead of overflowing" {
    var buf: [32]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);

    try writeCell(&w, "abcdefgh", 2, .{});
    try testing.expectEqualStrings("", w.buffered());
}

test "highlight positions are offset-mapped" {
    var buf: [128]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);

    const highlight: style.Face = .{ .bold = true };
    try writeHighlighted(&w, "abc", 10, &.{11}, .{}, highlight);
    try testing.expectEqualStrings("a\x1b[1mb\x1b[0mc", w.buffered());
}

test "writeRepeated emits multi-byte runes" {
    var buf: [32]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);

    try writeRepeated(&w, "\xe2\x94\x80", 3);
    try testing.expectEqualStrings("\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80", w.buffered());
}
