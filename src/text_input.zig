//! Single-line editing state for a search box or text field: an ASCII
//! buffer with a cursor, driven by `input.Key` events. Drawing lives in
//! `widget.TextBox`; writer-based UIs can render `window` themselves.

const std = @import("std");
const input = @import("input.zig");

pub const Edit = enum { none, moved, changed };

pub const TextInput = struct {
    buffer: std.ArrayList(u8) = .empty,
    /// Byte offset of the cursor; may equal `buffer.items.len` (append position).
    cursor: usize = 0,

    pub fn deinit(self: *TextInput, alloc: std.mem.Allocator) void {
        self.buffer.deinit(alloc);
        self.* = undefined;
    }

    pub fn text(self: *const TextInput) []const u8 {
        return self.buffer.items;
    }

    pub fn clear(self: *TextInput) void {
        self.buffer.clearRetainingCapacity();
        self.cursor = 0;
    }

    /// Applies an editing key. Keys the input does not handle return `.none`,
    /// so the caller can route every key here after its own bindings.
    pub fn handleKey(
        self: *TextInput,
        alloc: std.mem.Allocator,
        key: input.Key,
    ) std.mem.Allocator.Error!Edit {
        switch (key) {
            .char => |c| {
                try self.buffer.insert(alloc, self.cursor, c);
                self.cursor += 1;
                return .changed;
            },
            .backspace => {
                if (self.cursor == 0) return .none;
                self.cursor -= 1;
                _ = self.buffer.orderedRemove(self.cursor);
                return .changed;
            },
            .left => {
                if (self.cursor == 0) return .none;
                self.cursor -= 1;
                return .moved;
            },
            .right => {
                if (self.cursor >= self.buffer.items.len) return .none;
                self.cursor += 1;
                return .moved;
            },
            else => return .none,
        }
    }

    pub const Window = struct {
        text: []const u8,
        /// Cursor column relative to `text`; equals `text.len` when the
        /// cursor sits past the visible end.
        cursor: usize,
    };

    /// The slice that fits in `width` columns, scrolled so the cursor lands
    /// in column `width - 1` or earlier.
    pub fn window(self: *const TextInput, width: usize) Window {
        if (width == 0) return .{ .text = "", .cursor = 0 };
        const items = self.buffer.items;
        const start = if (self.cursor >= width) self.cursor - (width - 1) else 0;
        const end = @min(start + width, items.len);
        return .{ .text = items[start..end], .cursor = self.cursor - start };
    }
};

// --- tests ---

const testing = std.testing;

test "characters insert at the cursor" {
    const alloc = testing.allocator;
    var ti: TextInput = .{};
    defer ti.deinit(alloc);

    try testing.expectEqual(Edit.changed, try ti.handleKey(alloc, .{ .char = 'a' }));
    try testing.expectEqual(Edit.changed, try ti.handleKey(alloc, .{ .char = 'c' }));
    try testing.expectEqual(Edit.moved, try ti.handleKey(alloc, .left));
    try testing.expectEqual(Edit.changed, try ti.handleKey(alloc, .{ .char = 'b' }));
    try testing.expectEqualStrings("abc", ti.text());
    try testing.expectEqual(@as(usize, 2), ti.cursor);
}

test "backspace deletes before the cursor and stops at the start" {
    const alloc = testing.allocator;
    var ti: TextInput = .{};
    defer ti.deinit(alloc);

    _ = try ti.handleKey(alloc, .{ .char = 'a' });
    _ = try ti.handleKey(alloc, .{ .char = 'b' });
    _ = try ti.handleKey(alloc, .left);
    try testing.expectEqual(Edit.changed, try ti.handleKey(alloc, .backspace));
    try testing.expectEqualStrings("b", ti.text());
    try testing.expectEqual(Edit.none, try ti.handleKey(alloc, .backspace));
}

test "cursor movement is clamped to the buffer" {
    const alloc = testing.allocator;
    var ti: TextInput = .{};
    defer ti.deinit(alloc);

    try testing.expectEqual(Edit.none, try ti.handleKey(alloc, .left));
    try testing.expectEqual(Edit.none, try ti.handleKey(alloc, .right));
    _ = try ti.handleKey(alloc, .{ .char = 'x' });
    try testing.expectEqual(Edit.none, try ti.handleKey(alloc, .right));
}

test "unhandled keys are ignored" {
    const alloc = testing.allocator;
    var ti: TextInput = .{};
    defer ti.deinit(alloc);

    try testing.expectEqual(Edit.none, try ti.handleKey(alloc, .enter));
    try testing.expectEqual(Edit.none, try ti.handleKey(alloc, .up));
    try testing.expectEqual(Edit.none, try ti.handleKey(alloc, .cancel));
}

test "window scrolls to keep the cursor visible" {
    const alloc = testing.allocator;
    var ti: TextInput = .{};
    defer ti.deinit(alloc);
    for ("abcdef") |c| _ = try ti.handleKey(alloc, .{ .char = c });

    // Cursor past the end: the tail is shown with one column kept for it.
    var win = ti.window(5);
    try testing.expectEqualStrings("cdef", win.text);
    try testing.expectEqual(@as(usize, 4), win.cursor);

    // Cursor back inside the window: the text fills the full width.
    ti.cursor = 2;
    win = ti.window(5);
    try testing.expectEqualStrings("abcde", win.text);
    try testing.expectEqual(@as(usize, 2), win.cursor);

    win = ti.window(0);
    try testing.expectEqualStrings("", win.text);
}

test "clear resets text and cursor" {
    const alloc = testing.allocator;
    var ti: TextInput = .{};
    defer ti.deinit(alloc);
    _ = try ti.handleKey(alloc, .{ .char = 'a' });

    ti.clear();
    try testing.expectEqualStrings("", ti.text());
    try testing.expectEqual(@as(usize, 0), ti.cursor);
}
