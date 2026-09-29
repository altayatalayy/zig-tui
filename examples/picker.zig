//! Full-screen picker built from the widget layer: a bordered Block holding
//! a TextBox search line and a List of the matching items. Type to filter,
//! arrows / Ctrl-J / Ctrl-K move, Enter picks, Esc / Ctrl-C cancels.
//! Prints the pick to stdout.

const std = @import("std");
const tui = @import("tui");

const items = [_][]const u8{
    "build the cli library",
    "build the tui library",
    "build the template engine",
    "wire them together",
    "ship it",
};

const accent = tui.style.rgb(0xc4, 0xa7, 0xe7);
const muted = tui.style.rgb(0x6e, 0x6a, 0x86);

pub fn main(init: std.process.Init) !void {
    const picked = try pick(init.gpa) orelse {
        std.log.info("cancelled", .{});
        return;
    };

    var out_buf: [256]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &out_buf);
    try stdout.interface.print("{s}\n", .{picked});
    try stdout.interface.flush();
}

fn pick(alloc: std.mem.Allocator) !?[]const u8 {
    const fd = try tui.tty.open();
    defer tui.tty.close(fd);

    var raw = try tui.tty.RawMode.init(fd);
    defer raw.deinit();

    var alt = try tui.tty.AltScreen.init(fd);
    defer alt.deinit();

    var resize = try tui.signals.Resize.init();
    defer resize.deinit();

    var surface = try tui.surface.Surface.init(alloc, try tui.tty.size(fd));
    defer surface.deinit();

    var query: tui.text_input.TextInput = .{};
    defer query.deinit(alloc);

    var shown_buf: [items.len][]const u8 = undefined;
    var shown = refilter("", &shown_buf);
    var nav: tui.list.Nav = .{ .len = shown.len };

    while (true) {
        try draw(alloc, fd, &surface, &query, shown, &nav);

        const ev = (try tui.events.read(fd, &resize)) orelse return null;
        switch (ev) {
            .resize => try surface.resize(try tui.tty.size(fd)),
            .key => |key| switch (key) {
                .cancel => return null,
                .up => nav.move(-1),
                .down => nav.move(1),
                .enter => if (shown.len > 0) return shown[nav.cursor],
                .char, .backspace, .left, .right => {
                    if (try query.handleKey(alloc, key) == .changed) {
                        shown = refilter(query.text(), &shown_buf);
                        nav.reset(shown.len);
                    }
                },
            },
        }
    }
}

fn refilter(query: []const u8, buf: *[items.len][]const u8) [][]const u8 {
    var n: usize = 0;
    for (items) |item| {
        if (std.ascii.indexOfIgnoreCase(item, query) != null) {
            buf[n] = item;
            n += 1;
        }
    }
    return buf[0..n];
}

fn draw(
    alloc: std.mem.Allocator,
    fd: std.posix.fd_t,
    surface: *tui.surface.Surface,
    query: *const tui.text_input.TextInput,
    shown: []const []const u8,
    nav: *tui.list.Nav,
) !void {
    surface.clear();

    const block: tui.widget.Block = .{
        .border = .rounded,
        .border_face = .{ .fg = muted },
        .title = " pick a task ",
        .title_face = .{ .fg = accent, .bold = true },
        .margin = .all(1),
        .padding = .symmetric(0, 1),
    };
    const content = try block.draw(surface, surface.area());
    const rows = tui.layout.split(content, .vertical, [_]tui.layout.Constraint{
        .{ .len = 1 }, // search box
        .{ .len = 1 }, // blank separator
        .{ .fill = 1 }, // list
    });

    const search: tui.widget.TextBox = .{
        .input = query,
        .prompt_face = .{ .fg = accent, .bold = true },
    };
    const cursor = try search.draw(surface, rows[0]);

    const task_list: tui.widget.List = .{
        .items = shown,
        .nav = nav,
        .selected_face = .{ .fg = accent, .bold = true },
    };
    try task_list.draw(surface, rows[2]);

    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    try aw.writer.writeAll("\x1b[?25l");
    try surface.flush(&aw.writer);
    try tui.tty.moveCursor(&aw.writer, cursor.x, cursor.y);
    try aw.writer.writeAll("\x1b[?25h");
    try tui.tty.writeAll(fd, aw.writer.buffered());
}
