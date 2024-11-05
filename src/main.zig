const std = @import("std");
const terminal = @import("terminal.zig");
const events = @import("events.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

const Display = @import("Display.zig");
const Canvas = @import("Canvas.zig");
const Toolbar = @import("Toolbar.zig");

const Event = events.Event;

const TOOLBAR_HEIGHT = 4;
const READ_BUFFER_SIZE = 256;
const MODULE_NAME = "main";

const stdin = std.io.getStdIn();
const writer = std.io.getStdOut().writer();
var canvas: Canvas = undefined;
var display: Display = undefined;
var toolbar: Toolbar = undefined;
var read_buffer: [READ_BUFFER_SIZE]u8 = undefined;
const starting_cell: types.Cell = types.Cell.fromChar('#');

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    setUp(allocator);
    defer tearDown();

    toolbar.draw();

    main_loop: while (true) {
        display.render(writer);
        toolbar.clear();
        const n_bytes = stdin.read(&read_buffer) catch 0;
        const read_input = read_buffer[0..n_bytes];
        var iterator = events.iterator(read_input);

        while (iterator.next()) |event| {
            // Assume canvas stopped drawing. If it's not true, drawing functions will update it.
            canvas.is_drawing = false;
            switch (toolbar.toolbar_mode) {
                .Normal => {
                    switch (event.keypress) {
                        .text => |value| {
                            if (std.mem.eql(u8, value, "q") and event.modifiers == 0) break :main_loop;
                            if (std.mem.eql(u8, value, "u") and event.modifiers == 0) canvas.command_stack.undo();
                            if (std.mem.eql(u8, value, "r") and event.modifiers == 0) canvas.command_stack.redo();
                            if (std.mem.eql(u8, value, "f") and event.modifiers == 0) terminal.disableMouseSupport(writer);
                            if (std.mem.eql(u8, value, "t") and event.modifiers == 0) terminal.enableMouseSupport(writer);
                            if (std.mem.eql(u8, value, "c") and event.modifiers == 0) canvas.clear();
                        },
                        .arrow_up, .arrow_down, .arrow_left, .arrow_right => {},
                        .resize => |pos| {
                            display.updateDimensions(pos);
                            canvas.resize();
                        },
                        .mouse_event => |mouse_event| {
                            // position of the mouse event is checked in the canvas and the toolbar
                            canvas.is_drawing = canvas.handleMouseEvent(
                                mouse_event,
                                event.modifiers,
                                &toolbar,
                            );
                            toolbar.handleMouseEvent(mouse_event);
                        },
                    }
                },
                .InsertSymbol, .InsertFgColor, .InsertBgColor => {
                    switch (event.keypress) {
                        .text => |value| {
                            // zig fmt: off
                            if (value.len == 1) {
                                switch (value[0]) {
                                    terminal.ESC[0] => if (event.modifiers == 0) toolbar.cancelInsert(),
                                    terminal.ENTER[0] => if (event.modifiers == 0) toolbar.commitInsert(),
                                    terminal.BACKSPACE[0] => if (event.modifiers == 0) toolbar.eraseLast(),
                                    terminal.DELETE[0] => if (event.modifiers == 0) toolbar.eraseLast(),
                                    else => toolbar.insertValue(value),
                                }
                            }
                            else toolbar.insertValue(value);
                            // zig fmt: off
                        },
                        else => {},
                    }
                },
            }
        }
        if (!canvas.is_drawing) canvas.commitDraw();
        toolbar.draw();
    }
}

fn setUp(allocator: std.mem.Allocator) void {
    terminal.enterRawMode();
    terminal.enterAlternativeScreen(writer);
    terminal.hideCursor(writer);
    terminal.enableMouseSupport(writer);

    Display.askForDimensions();

    var cursor_position: types.Position = undefined;
    outer: while (true) {
        const n_bytes = stdin.read(&read_buffer) catch 0;
        const read_input = read_buffer[0..n_bytes];
        if (read_input.len == 0) {
            continue;
        }
        var iterator = events.iterator(read_input);
        while (iterator.next()) |event| {
            switch (event.keypress) {
                .resize => |pos| {
                    cursor_position = pos;
                    break :outer;
                },
                else => continue,
            }
        }
    }

    display = Display.init(allocator, cursor_position);
    toolbar = Toolbar.init(allocator, starting_cell, &display, TOOLBAR_HEIGHT);
    canvas = Canvas.init(allocator, &display, toolbar.height);

    registerSigWinChHandler();
}

fn tearDown() void {
    terminal.exitRawMode();
    terminal.exitAlternativeScreen(writer);
    terminal.showCursor(writer);
    terminal.disableMouseSupport(writer);
    canvas.deinit();
    toolbar.deinit();
    display.deinit();
}

fn registerSigWinChHandler() void {
    std.posix.sigaction(
        std.posix.SIG.WINCH,
        &std.posix.Sigaction{
            .handler = .{ .handler = handleSigWinCh },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        },
        null,
    ) catch utils.panicFromModule(MODULE_NAME, "Failed registering sigwinch handler");
}

fn handleSigWinCh(_: c_int) callconv(.C) void {
    Display.askForDimensions();
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    display.deinit();
    tearDown();
    std.builtin.default_panic(msg, trace, ret_addr);
}
