const std = @import("std");
const types = @import("types.zig");
const draw_commands = @import("draw_commands.zig");
const terminal = @import("terminal.zig");
const events = @import("events.zig");
const utils = @import("utils.zig");

const Display = @import("Display.zig");

const assert = std.debug.assert;
const Cell = types.Cell;
const Cells = types.Cells;
const Dimensions = types.Dimensions;
const Position = types.Position;
const Color = types.Color;
const DrawCommand = draw_commands.DrawCommand;

const MODULE_NAME = "Toolbar";

const ToolbarMode = enum {
    InsertFgColor,
    InsertBgColor,
    InsertSymbol,
    Normal,
};

pub const Label = struct {
    const Content = std.ArrayList(Cell);
    content: Content,
    start_position: Position = .{ .row = 0, .col = 0 },
    end_position: Position = .{ .row = 0, .col = 0 },
    color_foreground: ?Color = null,
    color_background: ?Color = null,

    pub fn init(allocator: std.mem.Allocator) Label {
        return .{ .content = Content.init(allocator) };
    }

    pub fn initFromAscii(allocator: std.mem.Allocator, ascii: []const u8) Label {
        return initFromAsciiWithColor(allocator, ascii, null, null);
    }

    pub fn initFromAsciiWithColor(
        allocator: std.mem.Allocator,
        ascii: []const u8,
        color_foreground: ?Color,
        color_background: ?Color,
    ) Label {
        var label: Label = .{
            .content = Content.init(allocator),
            .color_foreground = color_foreground,
            .color_background = color_background,
        };
        for (ascii) |char| {
            var cell = std.mem.zeroInit(Cell, .{});
            cell.grapheme[0] = char;
            label.content.append(cell) catch @panic("OOM at initFromAscii");
        }
        return label;
    }

    pub fn deinit(self: *Label) void {
        self.content.deinit();
    }

    pub fn draw(self: *Label, draw_command: *DrawCommand, start_position: Position) void {
        var curr_position = start_position;
        self.start_position = start_position;
        for (self.content.items) |cell| {
            draw_command.addCell(curr_position, Cell{
                .grapheme = cell.grapheme,
                .color_foreground = self.color_foreground,
                .color_background = self.color_background,
            });
            curr_position.col += 1;
        }
        self.end_position = curr_position;
    }
};

const Self = @This();

// --------- Styling options -----------------
const TEXT_COLOR: ?Color = null;

const SET_SYMBOL_BUTTON_BACKGROUND: Color = .{ .r = 80, .g = 80, .b = 0 };
const SET_SYMBOL_BUTTON_BACKGROUND_HOVER: Color = .{ .r = 180, .g = 180, .b = 0 };

const SET_COLOR_BUTTON_BACKGROUND: Color = .{ .r = 0, .g = 80, .b = 0 };
const SET_COLOR_BUTTON_BACKGROUND_HOVER: Color = .{ .r = 0, .g = 200, .b = 0 };

const RESET_COLOR_BUTTON_BACKGROUND: Color = .{ .r = 80, .g = 0, .b = 0 };
const RESET_COLOR_BUTTON_BACKGROUND_HOVER: Color = .{ .r = 255, .g = 0, .b = 0 };

const label_title_content = .{
    .text = "------------ tui-paint ----------------",
    .color_foreground = TEXT_COLOR,
    .color_background = null,
};
const label_symbol_content = .{
    .text = " set current grapheme >> ",
    .color_foreground = TEXT_COLOR,
    .color_background = SET_SYMBOL_BUTTON_BACKGROUND,
};
const label_foreground_color_content = .{
    .text = " set foreground color ",
    .color_foreground = TEXT_COLOR,
    .color_background = SET_COLOR_BUTTON_BACKGROUND,
};
const label_reset_foreground_color_content = .{
    .text = " reset foreground color ",
    .color_foreground = TEXT_COLOR,
    .color_background = RESET_COLOR_BUTTON_BACKGROUND,
};

const label_background_color_content = .{
    .text = " set background color ",
    .color_foreground = TEXT_COLOR,
    .color_background = SET_COLOR_BUTTON_BACKGROUND,
};
const label_reset_background_color_content = .{
    .text = " reset background color ",
    .color_foreground = TEXT_COLOR,
    .color_background = RESET_COLOR_BUTTON_BACKGROUND,
};

const cursor = types.Cell.fromChar('_');
const hex_code_indicator = types.Cell.fromChar('#');
// --------------------------------------------

display: *Display,
current_cell: Cell,
previous_cell: Cell,
height: usize,
symbol_position: Position,
toolbar_mode: ToolbarMode,

current_draw_command: DrawCommand,
current_insert_command: DrawCommand,
insert_buffer: Label,

label_title: Label,
label_symbol: Label,
label_foreground_color: Label,
label_reset_foreground_color: Label,
label_background_color: Label,
label_reset_background_color: Label,

pub fn init(
    allocator: std.mem.Allocator,
    current_cell: Cell,
    display: *Display,
    height: usize,
) Self {
    return Self{
        .current_cell = current_cell,
        .previous_cell = current_cell,
        .current_draw_command = DrawCommand.init(allocator, display),
        .current_insert_command = DrawCommand.init(allocator, display),
        .display = display,
        .height = height,
        .symbol_position = .{ .row = 0, .col = 0 },
        .toolbar_mode = .Normal,
        .insert_buffer = Label.init(allocator),
        .label_title = Label.initFromAsciiWithColor(
            allocator,
            label_title_content.text,
            label_title_content.color_foreground,
            label_title_content.color_background,
        ),
        .label_symbol = Label.initFromAsciiWithColor(
            allocator,
            label_symbol_content.text,
            label_symbol_content.color_foreground,
            label_symbol_content.color_background,
        ),
        .label_foreground_color = Label.initFromAsciiWithColor(
            allocator,
            label_foreground_color_content.text,
            label_foreground_color_content.color_foreground,
            label_foreground_color_content.color_background,
        ),
        .label_background_color = Label.initFromAsciiWithColor(
            allocator,
            label_background_color_content.text,
            label_background_color_content.color_foreground,
            label_background_color_content.color_background,
        ),
        .label_reset_foreground_color = Label.initFromAsciiWithColor(
            allocator,
            label_reset_foreground_color_content.text,
            label_reset_foreground_color_content.color_foreground,
            label_reset_foreground_color_content.color_background,
        ),
        .label_reset_background_color = Label.initFromAsciiWithColor(
            allocator,
            label_reset_background_color_content.text,
            label_reset_background_color_content.color_foreground,
            label_reset_background_color_content.color_background,
        ),
    };
}

pub fn deinit(self: *Self) void {
    self.current_draw_command.deinit();
    self.current_insert_command.deinit();
    self.insert_buffer.deinit();
    self.label_title.deinit();
    self.label_symbol.deinit();
    self.label_foreground_color.deinit();
    self.label_background_color.deinit();
    self.label_reset_foreground_color.deinit();
    self.label_reset_background_color.deinit();
}

pub fn clear(self: *Self) void {
    self.current_draw_command.undo();
    self.current_draw_command.clearRetainingCapacity();
    self.current_insert_command.undo();
    self.current_insert_command.clearRetainingCapacity();
}

pub fn draw(self: *Self) void {
    var current_position: Position = .{
        .row = self.display.viewport_dimensions.height - self.height,
        .col = 0,
    };
    self.label_title.draw(&self.current_draw_command, current_position);

    current_position = .{ .row = self.label_title.end_position.row + 1, .col = 0 };
    self.label_symbol.draw(&self.current_draw_command, current_position);
    self.symbol_position = self.label_symbol.end_position.addOffset(.{ .offset_col = 1 });
    self.current_draw_command.addCell(self.symbol_position, self.current_cell);

    current_position = .{ .row = self.label_symbol.end_position.row + 1, .col = 0 };
    self.label_foreground_color.draw(&self.current_draw_command, current_position);

    current_position = .{ .row = self.label_foreground_color.end_position.row + 1, .col = 0 };
    self.label_background_color.draw(&self.current_draw_command, current_position);

    switch (self.toolbar_mode) {
        .InsertSymbol => {
            const insert_position = self.symbol_position.addOffset(.{ .offset_col = 2 });
            self.insert_buffer.color_foreground = null;
            self.insert_buffer.draw(&self.current_draw_command, insert_position);
            self.current_insert_command.addCell(self.insert_buffer.end_position, cursor);
        },
        .InsertFgColor => {
            const insert_position = self.label_foreground_color.end_position.addOffset(.{ .offset_col = 2 });
            self.insert_buffer.color_foreground = self.current_cell.color_foreground;
            self.insert_buffer.draw(&self.current_insert_command, insert_position);

            self.current_insert_command.addCell(self.insert_buffer.end_position, cursor);
            self.current_insert_command.addCell(
                self.insert_buffer.start_position.addOffset(.{ .offset_col = -1 }),
                hex_code_indicator,
            );
        },
        .InsertBgColor => {
            const insert_position = self.label_background_color.end_position.addOffset(.{ .offset_col = 2 });
            self.insert_buffer.color_foreground = self.current_cell.color_background;
            self.insert_buffer.draw(&self.current_insert_command, insert_position);

            self.current_insert_command.addCell(self.insert_buffer.end_position, cursor);
            self.current_insert_command.addCell(
                self.insert_buffer.start_position.addOffset(.{ .offset_col = -1 }),
                hex_code_indicator,
            );
        },
        .Normal => {
            const reset_fg_position = self.label_foreground_color.end_position.addOffset(.{ .offset_col = 2 });
            self.label_reset_foreground_color.draw(&self.current_insert_command, reset_fg_position);

            const reset_bg_position = self.label_background_color.end_position.addOffset(.{ .offset_col = 2 });
            self.label_reset_background_color.draw(&self.current_insert_command, reset_bg_position);
        },
    }
    self.current_draw_command.do();
    self.current_insert_command.do();
}

fn drawLabel(draw_command: *DrawCommand, start_position: Position, label: *Label, color: ?types.Color) void {
    var curr_position = start_position;
    label.start_position = start_position;
    for (label.content.items) |cell| {
        draw_command.addCell(curr_position, Cell{ .grapheme = cell.grapheme, .color_foreground = color });
        curr_position.col += 1;
    }
    label.end_position = curr_position;
}

pub fn handleMouseEvent(self: *Self, event: events.MouseEvent) void {
    self.reset_label_colors();
    const position = event.position;

    if (isPositionOnLabel(&self.label_symbol, position)) {
        if (event.event_type == .press and event.button == .left) {
            self.toolbar_mode = .InsertSymbol;
        }
        updateLabelLook(&self.label_symbol, SET_SYMBOL_BUTTON_BACKGROUND_HOVER, event);
        return;
    }
    if (isPositionOnLabel(&self.label_foreground_color, position)) {
        if (event.event_type == .press and event.button == .left) {
            self.toolbar_mode = .InsertFgColor;
        }
        updateLabelLook(&self.label_foreground_color, SET_COLOR_BUTTON_BACKGROUND_HOVER, event);
        return;
    }
    if (isPositionOnLabel(&self.label_background_color, position)) {
        if (event.event_type == .press and event.button == .left) {
            self.toolbar_mode = .InsertBgColor;
        }
        updateLabelLook(&self.label_background_color, SET_COLOR_BUTTON_BACKGROUND_HOVER, event);
        return;
    }
    if (isPositionOnLabel(&self.label_reset_foreground_color, position)) {
        if (event.event_type == .press and event.button == .left) {
            self.current_cell.color_foreground = null;
            self.previous_cell.color_foreground = null;
        }
        updateLabelLook(&self.label_reset_foreground_color, RESET_COLOR_BUTTON_BACKGROUND_HOVER, event);
        return;
    }
    if (isPositionOnLabel(&self.label_reset_background_color, position)) {
        if (event.event_type == .press and event.button == .left) {
            self.current_cell.color_background = null;
            self.previous_cell.color_background = null;
        }
        updateLabelLook(&self.label_reset_background_color, RESET_COLOR_BUTTON_BACKGROUND_HOVER, event);
        return;
    }
}

fn reset_label_colors(self: *Self) void {
    self.label_symbol.color_background = SET_SYMBOL_BUTTON_BACKGROUND;
    self.label_foreground_color.color_background = SET_COLOR_BUTTON_BACKGROUND;
    self.label_background_color.color_background = SET_COLOR_BUTTON_BACKGROUND;
    self.label_reset_foreground_color.color_background = RESET_COLOR_BUTTON_BACKGROUND;
    self.label_reset_background_color.color_background = RESET_COLOR_BUTTON_BACKGROUND;
}

fn updateLabelLook(label: *Label, hover_color: Color, event: events.MouseEvent) void {
    switch (event.event_type) {
        .move, .release => label.color_background = hover_color,
        .drag, .press => {},
    }
}

fn isPositionOnLabel(label: *const Label, position: Position) bool {
    // zig fmt: off
    return position.row == label.end_position.row 
        and (label.start_position.col <= position.col and position.col <= label.end_position.col);
    // zig fmt: on
}

pub fn cancelInsert(self: *Self) void {
    self.toolbar_mode = .Normal;
    self.insert_buffer.content.clearRetainingCapacity();
    self.current_cell = self.previous_cell;
}

pub fn commitInsert(self: *Self) void {
    self.toolbar_mode = .Normal;
    self.insert_buffer.content.clearRetainingCapacity();
    self.previous_cell = self.current_cell;
}

pub fn eraseLast(self: *Self) void {
    if (self.insert_buffer.content.items.len > 0) {
        _ = self.insert_buffer.content.pop();
    }
    self.updateFromInsert(self.insert_buffer.content.items);
}

pub fn insertValue(self: *Self, value: []const u8) void {
    if (!self.checkValueValid(value)) {
        return;
    }

    switch (self.toolbar_mode) {
        .Normal => utils.panicFromModule(MODULE_NAME, "Trying to insert in Normal mode - this shouldn't happen"),
        .InsertSymbol => {
            const cell = types.Cell.fromStrUnchecked(value);
            self.insert_buffer.content.append(cell) catch utils.panicFromModule(
                MODULE_NAME,
                "OOM when appending to insert",
            );
        },
        .InsertFgColor, .InsertBgColor => {
            std.debug.assert(value.len == 1);
            const cell = types.Cell.fromChar(value[0]);
            if (self.insert_buffer.content.items.len < Color.COLOR_DEF_MAX_LENGTH) {
                self.insert_buffer.content.append(cell) catch utils.panicFromModule(
                    MODULE_NAME,
                    "OOM when appending to insert",
                );
            }
        },
    }
    self.updateFromInsert(self.insert_buffer.content.items);
}

fn checkValueValid(self: *Self, value: []const u8) bool {
    switch (self.toolbar_mode) {
        .Normal => unreachable,
        .InsertFgColor, .InsertBgColor => return value.len == 1 and switch (value[0]) {
            '0'...'9', 'A'...'F', 'a'...'f' => true,
            else => false,
        },
        .InsertSymbol => {
            const is_nbytes_ok = value.len <= types.Cell.MAX_BYTES and value.len > 0;
            const input_buffer_len = self.insert_buffer.content.items.len;
            const input_buffer_empty = input_buffer_len == 0;
            // check first byte to figure out the number of codepoints
            // we only allow a single codepoint
            // table taken from: https://en.wikipedia.org/wiki/UTF-8#Description
            const bytes_in_codepoint: usize = switch (value[0]) {
                0b00000000...0b01111111 => 1,
                0b11000000...0b11011111 => 2,
                0b11100000...0b11101111 => 3,
                0b11110000...0b11110111 => 4,
                else => return false,
            };
            return is_nbytes_ok and value.len == bytes_in_codepoint and input_buffer_empty;
        },
    }
}

fn updateFromInsert(self: *Self, insert_buffer: []const types.Cell) void {
    switch (self.toolbar_mode) {
        .Normal => unreachable,
        .InsertSymbol => {
            if (insert_buffer.len == 0) {
                self.current_cell.grapheme = self.previous_cell.grapheme;
                return;
            }
            std.debug.assert(insert_buffer.len == 1);
            self.current_cell.grapheme = self.insert_buffer.content.items[0].grapheme;
        },
        .InsertFgColor => self.current_cell.color_foreground = Color.parseColor(insert_buffer),
        .InsertBgColor => self.current_cell.color_background = Color.parseColor(insert_buffer),
    }
}
