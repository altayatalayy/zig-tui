//! An in-memory cell grid for composing frames: widgets draw into
//! rectangles, then `flush` emits the whole frame as one escape-sequence
//! stream. One cell holds one codepoint; wide glyphs are not measured.

const std = @import("std");
const layout = @import("layout.zig");
const style = @import("style.zig");
const tty = @import("tty.zig");

pub const Cell = struct {
    rune: u21 = ' ',
    face: style.Face = .{},
};

pub const Surface = struct {
    alloc: std.mem.Allocator,
    cells: []Cell,
    cols: usize,
    rows: usize,

    pub fn init(alloc: std.mem.Allocator, size: tty.Size) std.mem.Allocator.Error!Surface {
        const cells = try alloc.alloc(Cell, size.cols * size.rows);
        @memset(cells, .{});
        return .{ .alloc = alloc, .cells = cells, .cols = size.cols, .rows = size.rows };
    }

    pub fn deinit(self: *Surface) void {
        self.alloc.free(self.cells);
        self.* = undefined;
    }

    pub fn resize(self: *Surface, size: tty.Size) std.mem.Allocator.Error!void {
        const cells = try self.alloc.alloc(Cell, size.cols * size.rows);
        self.alloc.free(self.cells);
        self.cells = cells;
        self.cols = size.cols;
        self.rows = size.rows;
        self.clear();
    }

    pub fn area(self: Surface) layout.Rect {
        return .{ .w = self.cols, .h = self.rows };
    }

    pub fn clear(self: *Surface) void {
        @memset(self.cells, .{});
    }

    /// Out-of-bounds writes are silently dropped; clipping at the edges is
    /// the normal way widgets handle small terminals.
    pub fn set(self: *Surface, x: usize, y: usize, rune: u21, face: style.Face) void {
        if (x >= self.cols or y >= self.rows) return;
        self.cells[y * self.cols + x] = .{ .rune = rune, .face = face };
    }

    pub fn get(self: Surface, x: usize, y: usize) Cell {
        std.debug.assert(x < self.cols and y < self.rows);
        return self.cells[y * self.cols + x];
    }

    pub fn fill(self: *Surface, rect: layout.Rect, rune: u21, face: style.Face) void {
        const x_end = @min(rect.x + rect.w, self.cols);
        const y_end = @min(rect.y + rect.h, self.rows);
        var y = rect.y;
        while (y < y_end) : (y += 1) {
            var x = rect.x;
            while (x < x_end) : (x += 1) {
                self.cells[y * self.cols + x] = .{ .rune = rune, .face = face };
            }
        }
    }

    /// Writes `text` starting at (x, y), clipped to `max` columns and the
    /// surface edge. Returns the number of columns written.
    pub fn writeText(
        self: *Surface,
        x: usize,
        y: usize,
        text: []const u8,
        max: usize,
        face: style.Face,
    ) error{InvalidUtf8}!usize {
        if (y >= self.rows or x >= self.cols) return 0;
        const limit = @min(max, self.cols - x);

        const view = std.unicode.Utf8View.init(text) catch return error.InvalidUtf8;
        var it = view.iterator();
        var used: usize = 0;
        while (used < limit) : (used += 1) {
            const rune = it.nextCodepoint() orelse break;
            self.cells[y * self.cols + x + used] = .{ .rune = rune, .face = face };
        }
        return used;
    }

    /// Like `writeText`, but text wider than `max` is cut and the last
    /// columns become the ellipsis. Widths below 3 render nothing,
    /// mirroring `text.writeCell`.
    pub fn writeTruncated(
        self: *Surface,
        x: usize,
        y: usize,
        text: []const u8,
        max: usize,
        face: style.Face,
    ) error{InvalidUtf8}!void {
        const runes = std.unicode.utf8CountCodepoints(text) catch return error.InvalidUtf8;
        if (runes <= max) {
            _ = try self.writeText(x, y, text, max, face);
            return;
        }
        if (max < ellipsis.len) return;
        const used = try self.writeText(x, y, text, max - ellipsis.len, face);
        for (0..ellipsis.len) |i| self.set(x + used + i, y, '.', face);
    }

    /// Emits the frame: cursor home, every row in full, faces switched only
    /// where they change. The caller owns cursor visibility.
    pub fn flush(self: Surface, w: *std.Io.Writer) !void {
        try w.writeAll("\x1b[H\x1b[0m");
        var current: style.Face = .{};
        for (0..self.rows) |y| {
            if (y > 0) try w.writeAll("\r\n");
            for (self.cells[y * self.cols ..][0..self.cols]) |cell| {
                if (!std.meta.eql(cell.face, current)) {
                    if (!current.isPlain()) try style.reset(w);
                    try style.apply(w, cell.face);
                    current = cell.face;
                }
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cell.rune, &buf) catch return error.InvalidRune;
                try w.writeAll(buf[0..n]);
            }
        }
        if (!current.isPlain()) try style.reset(w);
    }
};

const ellipsis = @import("text.zig").ellipsis;

// --- tests ---

const testing = std.testing;

fn testSurface(cols: usize, rows: usize) !Surface {
    return Surface.init(testing.allocator, .{ .cols = cols, .rows = rows });
}

test "writeText clips at the surface edge and the column budget" {
    var surface = try testSurface(5, 1);
    defer surface.deinit();

    try testing.expectEqual(@as(usize, 2), try surface.writeText(0, 0, "abcdef", 2, .{}));
    try testing.expectEqual(@as(usize, 2), try surface.writeText(3, 0, "xyz", 10, .{}));
    try testing.expectEqual(@as(usize, 0), try surface.writeText(0, 5, "off", 10, .{}));
    try testing.expectEqual(@as(u21, 'x'), surface.get(3, 0).rune);
}

test "writeTruncated cuts long text with dots" {
    var surface = try testSurface(10, 1);
    defer surface.deinit();

    try surface.writeTruncated(0, 0, "abcdefgh", 6, .{});
    try testing.expectEqual(@as(u21, 'c'), surface.get(2, 0).rune);
    try testing.expectEqual(@as(u21, '.'), surface.get(3, 0).rune);
    try testing.expectEqual(@as(u21, '.'), surface.get(5, 0).rune);
    try testing.expectEqual(@as(u21, ' '), surface.get(6, 0).rune);
}

test "flush emits rows with minimal face switches" {
    var surface = try testSurface(3, 2);
    defer surface.deinit();
    _ = try surface.writeText(0, 0, "hi", 3, .{ .bold = true });
    _ = try surface.writeText(0, 1, "yo", 3, .{});

    var buf: [128]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try surface.flush(&w);
    try testing.expectEqualStrings("\x1b[H\x1b[0m\x1b[1mhi\x1b[0m \r\nyo ", w.buffered());
}

test "resize clears to the new size" {
    var surface = try testSurface(2, 2);
    defer surface.deinit();
    _ = try surface.writeText(0, 0, "ab", 2, .{});

    try surface.resize(.{ .cols = 3, .rows = 1 });
    try testing.expectEqual(@as(usize, 3), surface.cols);
    try testing.expectEqual(@as(u21, ' '), surface.get(0, 0).rune);
}
