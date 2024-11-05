const std = @import("std");
const types = @import("types.zig");
const Display = @import("Display.zig");
const utils = @import("utils.zig");

const MODULE_NAME = "draw_commands";

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Position = types.Position;
const Cell = types.Cell;

const PositionBuffer = std.ArrayList(Position);
const CellBuffer = std.ArrayList(Cell);
const DrawCommands = std.ArrayList(DrawCommand);

pub const DrawCommand = struct {
    const Self = @This();
    positions: PositionBuffer,
    cells: CellBuffer,
    previous_cells: CellBuffer,
    display: *Display,

    pub fn init(allocator: Allocator, display: *Display) Self {
        return .{
            .positions = PositionBuffer.init(allocator),
            .cells = CellBuffer.init(allocator),
            .previous_cells = CellBuffer.init(allocator),
            .display = display,
        };
    }

    pub fn deinit(self: *const Self) void {
        self.positions.deinit();
        self.cells.deinit();
        self.previous_cells.deinit();
    }

    pub fn numberOfCells(self: *const Self) usize {
        assert(self.positions.items.len == self.cells.items.len and self.cells.items.len == self.previous_cells.items.len);
        return self.positions.items.len;
    }

    pub fn addCell(self: *Self, position: Position, cell: Cell) void {
        self.positions.append(position) catch utils.panicFromModule(
            MODULE_NAME,
            "OOM when appending a cell to draw command",
        );
        self.cells.append(cell) catch utils.panicFromModule(
            MODULE_NAME,
            "OOM when appending a cell to draw command",
        );
        const previous_cell = self.display.getCellAtPosition(position);
        self.previous_cells.append(previous_cell) catch utils.panicFromModule(
            MODULE_NAME,
            "OOM when appending a cell to draw command",
        );
    }

    pub fn clearRetainingCapacity(self: *Self) void {
        self.cells.clearRetainingCapacity();
        self.previous_cells.clearRetainingCapacity();
        self.positions.clearRetainingCapacity();
    }

    pub fn do(self: *const Self) void {
        self.display.drawMultipleCells(self.positions.items, self.cells.items);
    }

    pub fn undo(self: *const Self) void {
        self.display.drawMultipleCells(self.positions.items, self.previous_cells.items);
    }
};

pub const DrawCommandStack = struct {
    const Self = @This();

    commands: DrawCommands,
    stack_head_pointer: usize,

    pub fn init(allocator: Allocator) Self {
        return .{ .commands = DrawCommands.init(allocator), .stack_head_pointer = 0 };
    }

    pub fn deinit(self: *Self) void {
        self.commands.deinit();
    }

    pub fn undo(self: *Self) void {
        assert(self.stack_head_pointer <= self.commands.items.len);
        if (self.stack_head_pointer == 0) return;

        self.stack_head_pointer -= 1;
        const command = self.commands.items[self.stack_head_pointer];
        command.undo();
    }

    pub fn redo(self: *Self) void {
        assert(self.stack_head_pointer <= self.commands.items.len);
        if (self.stack_head_pointer == self.commands.items.len) return;

        const command = self.commands.items[self.stack_head_pointer];
        self.stack_head_pointer += 1;
        command.do();
    }

    pub fn addCommand(self: *Self, command: DrawCommand) void {
        while (self.commands.items.len > self.stack_head_pointer) {
            const top_command = self.commands.pop();
            top_command.deinit();
        }
        self.commands.append(command) catch utils.panicFromModule(
            MODULE_NAME,
            "OOM when appending a command to command stack",
        );
        self.stack_head_pointer += 1;
    }
};
