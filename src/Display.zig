const std = @import("std");
const terminal = @import("terminal.zig");
const events = @import("events.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

const assert = std.debug.assert;

const Position = types.Position;
const Dimensions = types.Dimensions;
const Cell = types.Cell;
const Color = types.Color;
const OutputBuffer = std.ArrayList(u8);
const UpdateSet = std.AutoHashMap(Position, void);

const Self = @This();

const MODULE_NAME = "Display";

pub const MAX_DISPLAY_DIMENSIONS: Dimensions = .{
    .height = 1080,
    .width = 1920,
};
var buffer = [_]Cell{.{}} ** (MAX_DISPLAY_DIMENSIONS.height * MAX_DISPLAY_DIMENSIONS.width);

viewport_dimensions: Dimensions,
output_buffer: OutputBuffer,
update_set: UpdateSet,
buffer: []Cell,

pub fn init(allocator: std.mem.Allocator, cursor_position: Position) Self {
    return Self{
        .viewport_dimensions = getDimensions(cursor_position),
        .output_buffer = OutputBuffer.init(allocator),
        .update_set = UpdateSet.init(allocator),
        .buffer = buffer[0..],
    };
}

pub fn deinit(self: *Self) void {
    self.output_buffer.deinit();
    self.update_set.deinit();
}

pub fn updateDimensions(self: *Self, position: Position) void {
    const previous_dimensions = self.viewport_dimensions;
    self.viewport_dimensions = getDimensions(position);

    const previous_area = previous_dimensions.width * previous_dimensions.height;
    const current_area = self.viewport_dimensions.height * self.viewport_dimensions.width;

    if (previous_area > current_area) {
        return;
    }

    // We zoomed out, rerender the new part of the viewport
    for (previous_dimensions.height..self.viewport_dimensions.height) |row| {
        for (0..self.viewport_dimensions.width) |col| {
            self.update_set.put(.{
                .row = row,
                .col = col,
            }, {}) catch utils.panicFromModule(
                MODULE_NAME,
                "OOM during updating the viewport after resize.",
            );
        }
    }

    for (0..self.viewport_dimensions.height) |row| {
        for (previous_dimensions.width..self.viewport_dimensions.width) |col| {
            self.update_set.put(.{
                .row = row,
                .col = col,
            }, {}) catch utils.panicFromModule(
                MODULE_NAME,
                "OOM during updating the viewport after resize.",
            );
        }
    }
}

pub fn drawCell(self: *Self, position: Position, cell: Cell) void {
    if (!position.isInBounds(MAX_DISPLAY_DIMENSIONS)) {
        return;
    }
    self.update_set.put(position, {}) catch utils.panicFromModule(
        MODULE_NAME,
        "OOM during updating a single cell",
    );
    self.buffer[position.toBufferIndex(MAX_DISPLAY_DIMENSIONS)] = cell;
}

pub fn drawMultipleCells(self: *Self, positions: []const Position, cells: []const Cell) void {
    assert(positions.len == cells.len);
    for (positions, cells) |position, cell| {
        if (position.isInBounds(MAX_DISPLAY_DIMENSIONS)) {
            self.update_set.put(position, {}) catch utils.panicFromModule(
                MODULE_NAME,
                "OOM during updating multiple cells",
            );
            self.buffer[position.toBufferIndex(MAX_DISPLAY_DIMENSIONS)] = cell;
        }
    }
}

pub fn getCellAtPosition(self: *Self, position: Position) types.Cell {
    assert(position.isInBounds(MAX_DISPLAY_DIMENSIONS));
    return self.buffer[position.toBufferIndex(MAX_DISPLAY_DIMENSIONS)];
}

pub fn render(self: *Self, writer: anytype) void {
    const buffer_writer = self.output_buffer.writer();

    terminal.startSync(buffer_writer);
    var iterator = self.update_set.iterator();
    while (iterator.next()) |entry| {
        const position = entry.key_ptr;
        if (!position.isInBounds(self.viewport_dimensions)) {
            continue;
        }
        const cell = self.buffer[position.toBufferIndex(MAX_DISPLAY_DIMENSIONS)];
        terminal.moveCursor(buffer_writer, position.*);
        displayCell(cell, buffer_writer);
    }
    terminal.moveCursorHome(buffer_writer);
    terminal.endSync(buffer_writer);

    writer.writeAll(self.output_buffer.items) catch utils.panicFromModule(
        MODULE_NAME,
        "Failed writing out display buffer",
    );
    self.output_buffer.clearRetainingCapacity();
    self.update_set.clearRetainingCapacity();
}

pub fn askForDimensions() void {
    // Move cursor somewhere obscene and check where it actually ends up
    const writer = std.io.getStdOut().writer();
    terminal.saveCursor(writer);
    terminal.moveCursor(writer, .{ .row = 5000, .col = 5000 });
    terminal.queryCursorPosition(writer);
    terminal.restoreCursor(writer);
}

fn getDimensions(cursor_position: Position) types.Dimensions {
    return types.Dimensions{
        // size of the screen is 1 more than position of the cursor
        .height = cursor_position.row + 1,
        .width = cursor_position.col + 1,
    };
}

fn displayCell(cell: types.Cell, writer: anytype) void {
    if (cell.color_foreground) |color| {
        terminal.setForegroundColor(writer, color);
    } else {
        terminal.setForegroundColorToDefault(writer);
    }
    if (cell.color_background) |color| {
        terminal.setBackgroundColor(writer, color);
    } else {
        terminal.setBackgroundColorToDefault(writer);
    }

    writer.writeAll(&cell.grapheme) catch utils.panicFromModule(MODULE_NAME, "Cannot write grapheme");
    terminal.resetStyle(writer);
}
