//! Cursor and scroll bookkeeping for a vertical list view.

const std = @import("std");

pub const Range = struct {
    start: usize,
    end: usize,
};

pub const Nav = struct {
    len: usize = 0,
    cursor: usize = 0,
    scroll: usize = 0,

    /// Call when the underlying items change; cursor and scroll reset.
    pub fn reset(self: *Nav, len: usize) void {
        self.* = .{ .len = len };
    }

    /// Moves the cursor by `delta`, wrapping at both ends.
    pub fn move(self: *Nav, delta: isize) void {
        if (self.len == 0) return;
        const n: isize = @intCast(self.len);
        const cur: isize = @intCast(self.cursor);
        self.cursor = @intCast(@mod(cur + delta, n));
    }

    pub fn keepCursorVisible(self: *Nav, visible_rows: usize) void {
        if (visible_rows == 0 or self.len == 0) {
            self.scroll = 0;
            return;
        }
        if (self.cursor < self.scroll) {
            self.scroll = self.cursor;
        } else if (self.cursor >= self.scroll + visible_rows) {
            self.scroll = self.cursor + 1 - visible_rows;
        }
        const max_scroll = self.len - @min(visible_rows, self.len);
        self.scroll = @min(self.scroll, max_scroll);
    }

    pub fn visibleRange(self: Nav, visible_rows: usize) Range {
        if (visible_rows == 0 or self.len == 0) return .{ .start = 0, .end = 0 };
        const start = @min(self.scroll, self.len);
        return .{ .start = start, .end = @min(start + visible_rows, self.len) };
    }
};

// --- tests ---

const testing = std.testing;

test "empty list ignores movement" {
    var nav: Nav = .{};
    nav.move(1);
    nav.move(-1);
    try testing.expectEqual(@as(usize, 0), nav.cursor);
}

test "cursor wraps both ways" {
    var nav: Nav = .{ .len = 3 };
    nav.move(-1);
    try testing.expectEqual(@as(usize, 2), nav.cursor);
    nav.move(1);
    try testing.expectEqual(@as(usize, 0), nav.cursor);
}

test "keepCursorVisible scrolls down and up" {
    var nav: Nav = .{ .len = 5 };

    nav.cursor = 4;
    nav.keepCursorVisible(3);
    try testing.expectEqual(@as(usize, 2), nav.scroll);

    nav.cursor = 1;
    nav.keepCursorVisible(3);
    try testing.expectEqual(@as(usize, 1), nav.scroll);
}

test "visible range is clamped to the list length" {
    var nav: Nav = .{ .len = 2, .scroll = 1 };
    const range = nav.visibleRange(10);
    try testing.expectEqual(@as(usize, 1), range.start);
    try testing.expectEqual(@as(usize, 2), range.end);
}

test "reset clears cursor and scroll" {
    var nav: Nav = .{ .len = 5, .cursor = 3, .scroll = 2 };
    nav.reset(2);
    try testing.expectEqual(@as(usize, 0), nav.cursor);
    try testing.expectEqual(@as(usize, 0), nav.scroll);
    try testing.expectEqual(@as(usize, 2), nav.len);
}
