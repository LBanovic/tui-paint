const std = @import("std");
const draw_commands = @import("draw_commands.zig");
const types = @import("types.zig");
const events = @import("events.zig");
const Display = @import("Display.zig");
const Toolbar = @import("Toolbar.zig");
const utils = @import("utils.zig");

const assert = std.debug.assert;
const DrawCommandStack = draw_commands.DrawCommandStack;
const DrawCommand = draw_commands.DrawCommand;
const Position = types.Position;
const Cell = types.Cell;
const Dimensions = types.Dimensions;

const Allocator = std.mem.Allocator;

const Self = @This();
const MODULE_NAME = "Canvas";

allocator: Allocator,
command_stack: DrawCommandStack,
bottom_margin: usize,
display: *Display,
current_draw_command: DrawCommand,
resize_command: DrawCommand,
is_drawing: bool = false,

pub fn init(allocator: Allocator, display: *Display, bottom_margin: usize) Self {
    return .{
        .allocator = allocator,
        .command_stack = DrawCommandStack.init(allocator),
        .bottom_margin = bottom_margin,
        .current_draw_command = DrawCommand.init(allocator, display),
        .resize_command = DrawCommand.init(allocator, display),
        .display = display,
    };
}

pub fn deinit(self: *Self) void {
    for (self.command_stack.commands.items) |command| {
        command.deinit();
    }
    self.command_stack.deinit();
    self.resize_command.deinit();
    self.current_draw_command.deinit();
}

fn drawFreehand(self: *Self, position: Position, cell: Cell) bool {
    self.current_draw_command.undo();
    if (self.current_draw_command.numberOfCells() == 0) {
        self.current_draw_command.addCell(position, cell);
    } else {
        assert(std.meta.eql(self.current_draw_command.cells.getLast(), cell));
        const previous_position = self.current_draw_command.positions.getLast();
        self.bresenhamLine(previous_position, position, cell);
    }
    self.current_draw_command.do();
    return true;
}

fn drawStraightLine(self: *Self, position: Position, cell: Cell) bool {
    self.current_draw_command.undo();
    var previous_position: Position = undefined;
    if (self.current_draw_command.numberOfCells() == 0) {
        previous_position = position;
    } else {
        assert(std.meta.eql(self.current_draw_command.cells.getLast(), cell));

        // Leave only the first point
        self.current_draw_command.cells.shrinkAndFree(1);
        self.current_draw_command.previous_cells.shrinkAndFree(1);
        self.current_draw_command.positions.shrinkAndFree(1);

        previous_position = self.current_draw_command.positions.items[0];
    }
    self.bresenhamLine(previous_position, position, cell);
    self.current_draw_command.do();
    return true;
}

fn floodFillViewport(self: *Self, starting_position: Position, cell: Cell) void {
    const previous_cell = self.display.getCellAtPosition(starting_position);
    var seen = std.AutoHashMap(Position, void).init(self.allocator);
    defer seen.deinit();

    var unseen = std.ArrayList(Position).init(self.allocator);
    defer unseen.deinit();

    unseen.append(starting_position) catch utils.panicFromModule(
        MODULE_NAME,
        "OOM during flood fill",
    );
    while (unseen.items.len > 0) {
        const position = unseen.pop();

        seen.put(position, {}) catch utils.panicFromModule(
            MODULE_NAME,
            "OOM during flood fill",
        );
        const cell_at_position = self.display.getCellAtPosition(position);

        if (!std.meta.eql(cell_at_position, previous_cell)) continue;
        if (!position.isInBounds(self.getCurrentCanvasViewport())) continue;

        self.current_draw_command.addCell(position, cell);

        const next_positions = [_]Position{
            position.addOffset(.{ .offset_row = -1 }),
            position.addOffset(.{ .offset_col = -1 }),
            position.addOffset(.{ .offset_row = 1 }),
            position.addOffset(.{ .offset_col = 1 }),
        };

        for (next_positions) |next_position| {
            if (!seen.contains(next_position)) {
                unseen.append(next_position) catch utils.panicFromModule(
                    MODULE_NAME,
                    "OOM during flood fill",
                );
            }
        }
    }

    self.current_draw_command.do();
}

pub fn clear(self: *Self) void {
    const clear_cell: Cell = .{};
    for (self.display.buffer, 0..) |*item, index| {
        if (!std.meta.eql(item.*, clear_cell)) {
            const position = Position{
                .row = index / Display.MAX_DISPLAY_DIMENSIONS.width,
                .col = index % Display.MAX_DISPLAY_DIMENSIONS.width,
            };
            self.current_draw_command.addCell(position, clear_cell);
        }
    }
    self.current_draw_command.do();
    self.commitDraw();
}

fn bresenhamLine(self: *Self, start_position: Position, end_position: Position, cell: Cell) void {
    const start_row: i32 = @intCast(start_position.row);
    const start_col: i32 = @intCast(start_position.col);
    const end_row: i32 = @intCast(end_position.row);
    const end_col: i32 = @intCast(end_position.col);

    const d_row: i32 = -@as(i32, @intCast(@abs(end_row - start_row)));
    const d_col: i32 = @as(i32, @intCast(@abs(end_col - start_col)));

    const orientation_row: i32 = if (start_row < end_row) 1 else -1;
    const orientation_col: i32 = if (start_col < end_col) 1 else -1;

    var error_term = d_row + d_col;
    var update_term = 2 * error_term;

    var current_row = start_row;
    var current_col = start_col;

    while (true) {
        const position: Position = .{
            .row = @intCast(current_row),
            .col = @intCast(current_col),
        };
        if (!position.isInBounds(self.getCurrentCanvasViewport())) {
            return;
        }
        self.current_draw_command.addCell(position, cell);
        if (current_row == end_row and current_col == end_col) break;

        update_term = 2 * error_term;

        if (update_term >= d_row) {
            error_term += d_row;
            current_col += orientation_col;
        }
        if (update_term <= d_col) {
            error_term += d_col;
            current_row += orientation_row;
        }
    }
}

pub fn commitDraw(self: *Self) void {
    if (self.current_draw_command.positions.items.len == 0) {
        return;
    }
    self.command_stack.addCommand(self.current_draw_command);
    self.current_draw_command = DrawCommand.init(self.allocator, self.display);
}

pub fn resize(self: *Self) void {
    // clean up the remnants leaking out of the canvas viewport
    self.resize_command.undo();
    self.resize_command.clearRetainingCapacity();

    const current_canvas_viewport = self.getCurrentCanvasViewport();
    const current_display_viewport = self.display.viewport_dimensions;
    const cell: Cell = .{};
    for (current_canvas_viewport.height..current_display_viewport.height) |row| {
        for (0..current_display_viewport.width) |col| {
            self.resize_command.addCell(.{ .row = row, .col = col }, cell);
        }
    }
    self.resize_command.do();
}

pub fn getCurrentCanvasViewport(self: *Self) Dimensions {
    const viewport_dimensions = self.display.viewport_dimensions;
    assert(self.bottom_margin < self.display.viewport_dimensions.height);
    return .{
        .width = viewport_dimensions.width,
        .height = viewport_dimensions.height -| self.bottom_margin,
    };
}

const MouseAction = enum {
    draw_freehand,
    draw_straight_line,
    scoop_current_cell,
    scoop_foreground_color,
    scoop_background_color,
    scoop_grapheme,
    fill,
};

const MouseActionBinding = struct {
    event: events.MouseEvent,
    modifiers: events.Modifiers,
    mouse_action: MouseAction,
};

const POSITION_DONT_CARE: Position = .{ .row = 0, .col = 0 };

const MouseEventToAction = struct {
    pub fn getAction(event: events.MouseEvent, modifiers: events.Modifiers) ?MouseAction {
        for (action_map) |action_binding| {
            const action_event = action_binding.event;
            // zig fmt: off
            if (action_event.event_type == event.event_type and
                action_event.button == event.button and
                action_binding.modifiers == modifiers) {
                return action_binding.mouse_action;
            }
            // zig fmt: on
        }
        return null;
    }
    const action_map = [_]MouseActionBinding{
        .{
            .event = .{
                .button = .left,
                .event_type = .press,
                .position = POSITION_DONT_CARE,
            },
            .modifiers = 0,
            .mouse_action = .draw_freehand,
        },
        .{
            .event = .{
                .button = .left,
                .event_type = .drag,
                .position = POSITION_DONT_CARE,
            },
            .modifiers = 0,
            .mouse_action = .draw_freehand,
        },
        .{
            .event = .{
                .button = .left,
                .event_type = .press,
                .position = POSITION_DONT_CARE,
            },
            .modifiers = events.CTRL,
            .mouse_action = .draw_straight_line,
        },
        .{
            .event = .{
                .button = .left,
                .event_type = .drag,
                .position = POSITION_DONT_CARE,
            },
            .modifiers = events.CTRL,
            .mouse_action = .draw_straight_line,
        },
        .{
            .event = .{
                .button = .right,
                .event_type = .press,
                .position = POSITION_DONT_CARE,
            },
            .modifiers = 0,
            .mouse_action = .scoop_current_cell,
        },
        .{
            .event = .{
                .button = .right,
                .event_type = .press,
                .position = POSITION_DONT_CARE,
            },
            .modifiers = events.CTRL,
            .mouse_action = .scoop_foreground_color,
        },
        .{
            .event = .{
                .button = .right,
                .event_type = .press,
                .position = POSITION_DONT_CARE,
            },
            .modifiers = events.ALT,
            .mouse_action = .scoop_background_color,
        },
        .{
            .event = .{
                .button = .right,
                .event_type = .press,
                .position = POSITION_DONT_CARE,
            },
            .modifiers = events.ALT | events.CTRL,
            .mouse_action = .scoop_grapheme,
        },
        .{
            .event = .{
                .button = .middle,
                .event_type = .press,
                .position = POSITION_DONT_CARE,
            },
            .modifiers = 0,
            .mouse_action = .fill,
        },
    };
};

pub fn handleMouseEvent(self: *Self, event: events.MouseEvent, modifiers: events.Modifiers, toolbar: *Toolbar) bool {
    if (!event.position.isInBounds(self.getCurrentCanvasViewport())) {
        return false;
    }

    const binding = MouseEventToAction.getAction(event, modifiers) orelse return false;
    switch (binding) {
        .draw_freehand => return self.drawFreehand(event.position, toolbar.current_cell),
        .draw_straight_line => return self.drawStraightLine(event.position, toolbar.current_cell),
        .scoop_current_cell => {
            toolbar.current_cell = self.display.getCellAtPosition(event.position);
            toolbar.previous_cell = toolbar.current_cell;
        },
        .scoop_foreground_color => {
            toolbar.current_cell.color_foreground = self.display.getCellAtPosition(event.position).color_foreground;
            toolbar.previous_cell = toolbar.current_cell;
        },
        .scoop_background_color => {
            toolbar.current_cell.color_background = self.display.getCellAtPosition(event.position).color_background;
            toolbar.previous_cell = toolbar.current_cell;
        },
        .scoop_grapheme => {
            toolbar.current_cell.grapheme = self.display.getCellAtPosition(event.position).grapheme;
            toolbar.previous_cell = toolbar.current_cell;
        },
        .fill => self.floodFillViewport(event.position, toolbar.current_cell),
    }

    return false;
}
