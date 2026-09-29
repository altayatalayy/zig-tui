//! Rectangle math for composing full-screen layouts: insets for margins and
//! padding, constraint-based splitting in either direction, and responsive
//! breakpoints mapping the terminal size to a layout mode.

const std = @import("std");
const tty = @import("tty.zig");

pub const Mode = enum {
    too_small,
    compact,
    regular,
    wide,
};

/// Column breakpoints between the modes; the defaults suit a typical
/// multi-column picker. Sizes below the minimums are `.too_small`.
pub const Breakpoints = struct {
    min_cols: usize = 48,
    min_rows: usize = 10,
    regular_min: usize = 70,
    wide_min: usize = 110,

    pub fn mode(self: Breakpoints, size: tty.Size) Mode {
        if (size.cols < self.min_cols or size.rows < self.min_rows) return .too_small;
        if (size.cols < self.regular_min) return .compact;
        if (size.cols < self.wide_min) return .regular;
        return .wide;
    }
};

pub const Rect = struct {
    x: usize = 0,
    y: usize = 0,
    w: usize = 0,
    h: usize = 0,

    /// Shrinks the rectangle inward; the same operation implements both
    /// margins (inset before drawing) and padding (inset after).
    pub fn inset(self: Rect, insets: Insets) Rect {
        const left = @min(insets.left, self.w);
        const top = @min(insets.top, self.h);
        return .{
            .x = self.x + left,
            .y = self.y + top,
            .w = self.w - left -| insets.right,
            .h = self.h - top -| insets.bottom,
        };
    }
};

pub const Insets = struct {
    top: usize = 0,
    bottom: usize = 0,
    left: usize = 0,
    right: usize = 0,

    pub fn all(n: usize) Insets {
        return .{ .top = n, .bottom = n, .left = n, .right = n };
    }

    pub fn symmetric(vertical: usize, horizontal: usize) Insets {
        return .{ .top = vertical, .bottom = vertical, .left = horizontal, .right = horizontal };
    }
};

pub const Direction = enum { horizontal, vertical };

pub const Constraint = union(enum) {
    /// Exactly this many cells, clipped when the rectangle runs out.
    len: usize,
    /// A weighted share of the space left after every `len`.
    fill: usize,
};

/// Splits `rect` along `direction` into one sub-rectangle per constraint.
/// `constraints` must be an array (`[_]Constraint{...}`) so its length is
/// comptime-known; the values themselves may be runtime.
pub fn split(
    rect: Rect,
    direction: Direction,
    constraints: anytype,
) [constraints.len]Rect {
    const total = switch (direction) {
        .vertical => rect.h,
        .horizontal => rect.w,
    };

    var fixed: usize = 0;
    var weights: usize = 0;
    for (constraints) |constraint| switch (constraint) {
        .len => |len| fixed += len,
        .fill => |weight| weights += weight,
    };
    const flexible = total -| fixed;

    var out: [constraints.len]Rect = undefined;
    var pos: usize = 0;
    var used_weight: usize = 0;
    var granted: usize = 0;
    for (constraints, 0..) |constraint, i| {
        const want = switch (constraint) {
            .len => |len| len,
            // Cumulative shares so the fills together cover `flexible`
            // exactly, without rounding gaps.
            .fill => |weight| share: {
                used_weight += weight;
                const upto = if (weights == 0) 0 else flexible * used_weight / weights;
                defer granted = upto;
                break :share upto - granted;
            },
        };
        const size = @min(want, total - pos);
        out[i] = switch (direction) {
            .vertical => .{ .x = rect.x, .y = rect.y + pos, .w = rect.w, .h = size },
            .horizontal => .{ .x = rect.x + pos, .y = rect.y, .w = size, .h = rect.h },
        };
        pos += size;
    }
    return out;
}

// --- tests ---

const testing = std.testing;

test "breakpoints map sizes to modes" {
    const bp: Breakpoints = .{};
    try testing.expectEqual(Mode.too_small, bp.mode(.{ .cols = 47, .rows = 24 }));
    try testing.expectEqual(Mode.too_small, bp.mode(.{ .cols = 80, .rows = 9 }));
    try testing.expectEqual(Mode.compact, bp.mode(.{ .cols = 69, .rows = 10 }));
    try testing.expectEqual(Mode.regular, bp.mode(.{ .cols = 70, .rows = 10 }));
    try testing.expectEqual(Mode.regular, bp.mode(.{ .cols = 109, .rows = 10 }));
    try testing.expectEqual(Mode.wide, bp.mode(.{ .cols = 110, .rows = 10 }));
}

test "inset shrinks and clamps at zero" {
    const rect: Rect = .{ .x = 1, .y = 1, .w = 10, .h = 4 };

    const padded = rect.inset(.symmetric(1, 2));
    try testing.expectEqual(Rect{ .x = 3, .y = 2, .w = 6, .h = 2 }, padded);

    const collapsed = rect.inset(.all(10));
    try testing.expectEqual(@as(usize, 0), collapsed.w);
    try testing.expectEqual(@as(usize, 0), collapsed.h);
}

test "split mixes fixed lengths and fills" {
    const area: Rect = .{ .w = 20, .h = 10 };
    const rows = split(area, .vertical, [_]Constraint{ .{ .len = 2 }, .{ .fill = 1 }, .{ .len = 1 } });

    try testing.expectEqual(Rect{ .x = 0, .y = 0, .w = 20, .h = 2 }, rows[0]);
    try testing.expectEqual(Rect{ .x = 0, .y = 2, .w = 20, .h = 7 }, rows[1]);
    try testing.expectEqual(Rect{ .x = 0, .y = 9, .w = 20, .h = 1 }, rows[2]);
}

test "fill weights cover the flexible space exactly" {
    const area: Rect = .{ .w = 10, .h = 1 };
    const cols = split(area, .horizontal, [_]Constraint{ .{ .fill = 1 }, .{ .fill = 2 } });

    try testing.expectEqual(@as(usize, 3), cols[0].w);
    try testing.expectEqual(@as(usize, 7), cols[1].w);
    try testing.expectEqual(@as(usize, 3), cols[1].x);
}

test "split clips when constraints overflow the rectangle" {
    const area: Rect = .{ .w = 5, .h = 3 };
    const rows = split(area, .vertical, [_]Constraint{ .{ .len = 2 }, .{ .len = 4 }, .{ .fill = 1 } });

    try testing.expectEqual(@as(usize, 2), rows[0].h);
    try testing.expectEqual(@as(usize, 1), rows[1].h);
    try testing.expectEqual(@as(usize, 0), rows[2].h);
}
