//! Building blocks for full-screen terminal UIs: raw-mode tty access, key
//! and resize events, SGR styling, and a widget layer (layout rectangles
//! and breakpoints, a cell-grid Surface, Block, List, Table, and TextBox
//! widgets). Frames are composed on a Surface or directly into a
//! *std.Io.Writer and flushed to the tty fd in one write.

pub const tty = @import("tty.zig");
pub const input = @import("input.zig");
pub const signals = @import("signals.zig");
pub const events = @import("events.zig");
pub const style = @import("style.zig");
pub const text = @import("text.zig");
pub const text_input = @import("text_input.zig");
pub const list = @import("list.zig");
pub const table = @import("table.zig");
pub const layout = @import("layout.zig");
pub const surface = @import("surface.zig");
pub const widget = @import("widget.zig");

test {
    _ = tty;
    _ = input;
    _ = signals;
    _ = events;
    _ = style;
    _ = text;
    _ = text_input;
    _ = list;
    _ = table;
    _ = layout;
    _ = surface;
    _ = widget;
}
