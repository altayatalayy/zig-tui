//! Widgets drawn onto a Surface: Block is the box-model container (margin,
//! border, title, padding — the `div` of this library), List and Table
//! render `list.Nav`-backed selections, and TextBox renders a
//! `text_input.TextInput`-backed single-line editor.

const std = @import("std");
const layout = @import("layout.zig");
const list = @import("list.zig");
const style = @import("style.zig");
const surface_mod = @import("surface.zig");
const table = @import("table.zig");
const text_input = @import("text_input.zig");

const Surface = surface_mod.Surface;

pub const Border = struct {
    horizontal: u21,
    vertical: u21,
    top_left: u21,
    top_right: u21,
    bottom_left: u21,
    bottom_right: u21,

    pub const line: Border = .{
        .horizontal = '─',
        .vertical = '│',
        .top_left = '┌',
        .top_right = '┐',
        .bottom_left = '└',
        .bottom_right = '┘',
    };

    pub const rounded: Border = .{
        .horizontal = '─',
        .vertical = '│',
        .top_left = '╭',
        .top_right = '╮',
        .bottom_left = '╰',
        .bottom_right = '╯',
    };

    pub const double: Border = .{
        .horizontal = '═',
        .vertical = '║',
        .top_left = '╔',
        .top_right = '╗',
        .bottom_left = '╚',
        .bottom_right = '╝',
    };
};

pub const Block = struct {
    border: ?Border = null,
    border_face: style.Face = .{},
    title: []const u8 = "",
    title_face: style.Face = .{},
    /// Background for the area inside the border (padding included).
    fill_face: ?style.Face = null,
    margin: layout.Insets = .{},
    padding: layout.Insets = .{},

    /// Draws margin, border, title, and fill; returns the content rectangle.
    /// A rectangle too small for the border degrades to no border.
    pub fn draw(self: Block, surface: *Surface, rect: layout.Rect) error{InvalidUtf8}!layout.Rect {
        const outer = rect.inset(self.margin);
        var inner = outer;

        if (self.border != null and outer.w >= 2 and outer.h >= 2) {
            drawBorder(surface, outer, self.border.?, self.border_face);
            if (self.title.len > 0 and outer.w > 4) {
                try surface.writeTruncated(outer.x + 2, outer.y, self.title, outer.w - 4, self.title_face);
            }
            inner = outer.inset(.all(1));
        }

        if (self.fill_face) |face| surface.fill(inner, ' ', face);
        return inner.inset(self.padding);
    }
};

fn drawBorder(surface: *Surface, rect: layout.Rect, border: Border, face: style.Face) void {
    const right = rect.x + rect.w - 1;
    const bottom = rect.y + rect.h - 1;

    var x = rect.x + 1;
    while (x < right) : (x += 1) {
        surface.set(x, rect.y, border.horizontal, face);
        surface.set(x, bottom, border.horizontal, face);
    }
    var y = rect.y + 1;
    while (y < bottom) : (y += 1) {
        surface.set(rect.x, y, border.vertical, face);
        surface.set(right, y, border.vertical, face);
    }
    surface.set(rect.x, rect.y, border.top_left, face);
    surface.set(right, rect.y, border.top_right, face);
    surface.set(rect.x, bottom, border.bottom_left, face);
    surface.set(right, bottom, border.bottom_right, face);
}

pub const List = struct {
    items: []const []const u8,
    /// Shared with the event loop; `draw` adjusts the scroll to the
    /// rectangle height. `nav.len` must match `items.len`.
    nav: *list.Nav,
    face: style.Face = .{},
    selected_face: style.Face = .{ .bold = true },
    /// Drawn in front of the selected row; other rows get blank space of the
    /// same width.
    marker: []const u8 = "▸ ",

    pub fn draw(self: List, surface: *Surface, rect: layout.Rect) error{InvalidUtf8}!void {
        std.debug.assert(self.items.len == self.nav.len);
        self.nav.keepCursorVisible(rect.h);

        const marker_cols = std.unicode.utf8CountCodepoints(self.marker) catch
            return error.InvalidUtf8;
        const text_x = rect.x + @min(marker_cols, rect.w);
        const text_w = rect.w -| marker_cols;

        const range = self.nav.visibleRange(rect.h);
        for (range.start..range.end, 0..) |index, row| {
            const y = rect.y + row;
            const selected = index == self.nav.cursor;
            if (selected) {
                _ = try surface.writeText(rect.x, y, self.marker, rect.w, self.selected_face);
            }
            const face = if (selected) self.selected_face else self.face;
            try surface.writeTruncated(text_x, y, self.items[index], text_w, face);
        }
    }
};

pub const Table = struct {
    columns: []const table.Column,
    /// One cell per column; `rows.len` must match `nav.len`.
    rows: []const []const []const u8,
    /// Shared with the event loop, like `List.nav`.
    nav: *list.Nav,
    gap: usize = 2,
    header_face: style.Face = .{ .bold = true },
    face: style.Face = .{},
    selected_face: style.Face = .{ .bold = true },

    pub const max_columns = 16;

    /// Draws a header row (when any column has one) and the visible rows,
    /// with widths fitted to the content via `table.fitWidths`.
    pub fn draw(self: Table, surface: *Surface, rect: layout.Rect) error{InvalidUtf8}!void {
        std.debug.assert(self.rows.len == self.nav.len);
        std.debug.assert(self.columns.len <= max_columns);
        if (rect.w == 0 or rect.h == 0) return;

        var content: [max_columns]usize = @splat(0);
        for (self.rows) |row| {
            std.debug.assert(row.len == self.columns.len);
            for (row, content[0..row.len]) |cell, *widest| {
                const cols = std.unicode.utf8CountCodepoints(cell) catch
                    return error.InvalidUtf8;
                widest.* = @max(widest.*, cols);
            }
        }
        var widths: [max_columns]usize = undefined;
        table.fitWidths(
            self.columns,
            content[0..self.columns.len],
            self.gap,
            rect.w,
            widths[0..self.columns.len],
        );

        var has_header = false;
        for (self.columns) |col| has_header = has_header or col.header.len > 0;

        var y = rect.y;
        if (has_header) {
            var x = rect.x;
            for (self.columns, widths[0..self.columns.len]) |col, width| {
                try surface.writeTruncated(x, y, col.header, width, self.header_face);
                x += width + self.gap;
            }
            y += 1;
        }

        const body_rows = rect.h - @intFromBool(has_header);
        self.nav.keepCursorVisible(body_rows);
        const range = self.nav.visibleRange(body_rows);
        for (range.start..range.end) |index| {
            const face = if (index == self.nav.cursor) self.selected_face else self.face;
            var x = rect.x;
            for (self.rows[index], widths[0..self.columns.len]) |cell, width| {
                try surface.writeTruncated(x, y, cell, width, face);
                x += width + self.gap;
            }
            y += 1;
        }
    }
};

pub const TextBox = struct {
    /// Shared with the event loop, like `List.nav`.
    input: *const text_input.TextInput,
    prompt: []const u8 = "> ",
    prompt_face: style.Face = .{},
    face: style.Face = .{},

    pub const Cursor = struct {
        x: usize,
        y: usize,
    };

    /// Draws the prompt and the visible slice of the input on the first row
    /// of `rect`. Returns where the terminal cursor belongs; emit it with
    /// `tty.moveCursor` after flushing the surface.
    pub fn draw(self: TextBox, surface: *Surface, rect: layout.Rect) error{InvalidUtf8}!Cursor {
        if (rect.w == 0 or rect.h == 0) return .{ .x = rect.x, .y = rect.y };

        const used = try surface.writeText(rect.x, rect.y, self.prompt, rect.w, self.prompt_face);
        const win = self.input.window(rect.w - used);
        _ = try surface.writeText(rect.x + used, rect.y, win.text, rect.w - used, self.face);

        return .{
            .x = @min(rect.x + used + win.cursor, rect.x + rect.w - 1),
            .y = rect.y,
        };
    }
};

// --- tests ---

const testing = std.testing;

test "block applies margin, border, and padding around the content" {
    var surface = try Surface.init(testing.allocator, .{ .cols = 12, .rows = 6 });
    defer surface.deinit();

    const block: Block = .{
        .border = .line,
        .title = "ti",
        .margin = .all(1),
        .padding = .symmetric(0, 1),
    };
    const content = try block.draw(&surface, surface.area());

    try testing.expectEqual(layout.Rect{ .x = 3, .y = 2, .w = 6, .h = 2 }, content);
    try testing.expectEqual(@as(u21, '┌'), surface.get(1, 1).rune);
    try testing.expectEqual(@as(u21, '┘'), surface.get(10, 4).rune);
    try testing.expectEqual(@as(u21, 't'), surface.get(3, 1).rune);
    try testing.expectEqual(@as(u21, ' '), surface.get(0, 0).rune);
}

test "block without room for a border degrades to the plain rectangle" {
    var surface = try Surface.init(testing.allocator, .{ .cols = 4, .rows = 1 });
    defer surface.deinit();

    const block: Block = .{ .border = .line };
    const content = try block.draw(&surface, surface.area());
    try testing.expectEqual(layout.Rect{ .x = 0, .y = 0, .w = 4, .h = 1 }, content);
}

test "textbox draws prompt and text and reports the cursor position" {
    var surface = try Surface.init(testing.allocator, .{ .cols = 8, .rows = 1 });
    defer surface.deinit();

    var ti: text_input.TextInput = .{};
    defer ti.deinit(testing.allocator);
    for ("hi") |c| _ = try ti.handleKey(testing.allocator, .{ .char = c });

    const box: TextBox = .{ .input = &ti };
    const cursor = try box.draw(&surface, surface.area());

    try testing.expectEqual(@as(u21, '>'), surface.get(0, 0).rune);
    try testing.expectEqual(@as(u21, 'h'), surface.get(2, 0).rune);
    try testing.expectEqual(TextBox.Cursor{ .x = 4, .y = 0 }, cursor);
}

test "textbox scrolls long input and clamps the cursor to the rectangle" {
    var surface = try Surface.init(testing.allocator, .{ .cols = 6, .rows = 1 });
    defer surface.deinit();

    var ti: text_input.TextInput = .{};
    defer ti.deinit(testing.allocator);
    for ("abcdefgh") |c| _ = try ti.handleKey(testing.allocator, .{ .char = c });

    const box: TextBox = .{ .input = &ti };
    const cursor = try box.draw(&surface, surface.area());

    // 4 columns remain after "> "; the tail "fgh" shows with one kept for the cursor.
    try testing.expectEqual(@as(u21, 'f'), surface.get(2, 0).rune);
    try testing.expectEqual(@as(u21, 'h'), surface.get(4, 0).rune);
    try testing.expectEqual(TextBox.Cursor{ .x = 5, .y = 0 }, cursor);
}

test "table draws fitted headers and scrolls to the selected row" {
    var surface = try Surface.init(testing.allocator, .{ .cols = 14, .rows = 3 });
    defer surface.deinit();

    const columns = [_]table.Column{
        .{ .header = "ID", .max = 4 },
        .{ .header = "NAME", .min = 3 },
    };
    const rows = [_][]const []const u8{
        &.{ "1", "alpha" },
        &.{ "2", "beta" },
        &.{ "3", "gamma" },
    };
    var nav: list.Nav = .{ .len = rows.len, .cursor = 2 };
    const widget: Table = .{ .columns = &columns, .rows = &rows, .nav = &nav };

    try widget.draw(&surface, surface.area());

    // Header, then the last two rows: the cursor sits on "gamma".
    try testing.expectEqual(@as(u21, 'I'), surface.get(0, 0).rune);
    try testing.expectEqual(@as(u21, 'N'), surface.get(4, 0).rune);
    try testing.expectEqual(@as(u21, 'b'), surface.get(4, 1).rune);
    try testing.expectEqual(@as(u21, 'g'), surface.get(4, 2).rune);
    try testing.expect(surface.get(4, 2).face.bold);
    try testing.expect(!surface.get(4, 1).face.bold);
}

test "list draws the marker on the selected row and scrolls" {
    var surface = try Surface.init(testing.allocator, .{ .cols = 8, .rows = 2 });
    defer surface.deinit();

    const items = [_][]const u8{ "one", "two", "three", "four" };
    var nav: list.Nav = .{ .len = items.len, .cursor = 2 };
    const widget: List = .{ .items = &items, .nav = &nav, .marker = "> " };

    try widget.draw(&surface, surface.area());

    // Rows 1 and 2 are visible; the cursor row carries the marker and face.
    try testing.expectEqual(@as(u21, 't'), surface.get(2, 0).rune);
    try testing.expectEqual(@as(u21, '>'), surface.get(0, 1).rune);
    try testing.expectEqual(@as(u21, 't'), surface.get(2, 1).rune);
    try testing.expect(surface.get(2, 1).face.bold);
    try testing.expect(!surface.get(2, 0).face.bold);
}
