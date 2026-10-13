# zig-tui

Small Zig 0.17 terminal UI primitives. Linux-only.

- `tty` — raw mode, alternate screen, size queries, cursor control
- `events` / `input` / `signals` — blocking key + resize event loop
- `style` / `text` — truecolor SGR faces and fixed-width cell rendering for a `*std.Io.Writer`
- `layout` — rectangle math, constraint-based splitting, and responsive `Breakpoints` → `Mode` (too_small/compact/regular/wide)
- `table` — column model with content-based width fitting, usable from writer-direct renderers too
- `surface` — cell-grid frame composition, flushed in one write
- `widget` — `Block` (border/margin/padding container), `List` and `Table` (backed by `list.Nav`), `TextBox` (backed by `text_input.TextInput`)

Import the module as `tui`; see `examples/picker.zig` (`zig build example`).
