//! Column model for tabular views: content-based width fitting shared by
//! `widget.Table` and writer-direct renderers.

const std = @import("std");

pub const Column = struct {
    header: []const u8 = "",
    min: usize = 0,
    max: usize = std.math.maxInt(usize),
};

/// Sizes columns left to right into `widths`: each column clamps its widest
/// cell (`content[i]`, with the header as a floor) to `[min, max]`, limited
/// so the columns to its right keep at least their minimums plus `gap`.
/// When `total` is too tight, widths fall below `min` (down to 0), earlier
/// columns first since they yield to the minimums of the rest.
pub fn fitWidths(
    columns: []const Column,
    content: []const usize,
    gap: usize,
    total: usize,
    widths: []usize,
) void {
    std.debug.assert(content.len == columns.len and widths.len == columns.len);

    var remaining = total;
    for (columns, content, widths, 0..) |col, cell, *width, i| {
        var reserved: usize = 0;
        for (columns[i + 1 ..]) |later| reserved += gap + later.min;

        const target = std.math.clamp(@max(cell, col.header.len), col.min, col.max);
        width.* = @min(target, remaining -| reserved);
        remaining -|= width.* + gap;
    }
}

// --- tests ---

const testing = std.testing;

test "columns fit content within their bounds" {
    const columns = [_]Column{
        .{ .header = "HOST", .max = 24 },
        .{ .header = "SESSION", .min = 12, .max = 36 },
    };
    var widths: [2]usize = undefined;

    // Content drives the width: long hosts cap at max, short sessions sit at min.
    fitWidths(&columns, &.{ 80, 5 }, 3, 77, &widths);
    try testing.expectEqualSlices(usize, &.{ 24, 12 }, &widths);

    // The header is a floor even when every cell is narrower.
    fitWidths(&columns, &.{ 2, 20 }, 3, 77, &widths);
    try testing.expectEqualSlices(usize, &.{ 4, 20 }, &widths);
}

test "early columns leave room for later minimums" {
    const columns = [_]Column{
        .{ .max = 40 },
        .{ .min = 10, .max = 20 },
    };
    var widths: [2]usize = undefined;

    fitWidths(&columns, &.{ 40, 15 }, 2, 30, &widths);
    try testing.expectEqualSlices(usize, &.{ 18, 10 }, &widths);
}

test "tight totals shrink early columns first" {
    const columns = [_]Column{
        .{ .min = 4 },
        .{ .min = 4 },
        .{ .min = 4 },
    };
    var widths: [3]usize = undefined;

    fitWidths(&columns, &.{ 8, 8, 8 }, 1, 12, &widths);
    try testing.expectEqualSlices(usize, &.{ 2, 4, 4 }, &widths);
}
