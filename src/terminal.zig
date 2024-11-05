const types = @import("types.zig");
const std = @import("std");
const termios = std.posix.termios;
const utils = @import("utils.zig");

pub const DELETE = "\x7f";
pub const BACKSPACE = "\x08";
pub const ENTER = "\x0d";
pub const ESC = "\x1B";
pub const CSI = ESC ++ "[";

const MODULE_NAME = "terminal";

var termios_backup: ?termios = null;
const stdin = std.io.getStdIn();

pub fn enterRawMode() void {
    if (termios_backup) |_| {
        return;
    }

    termios_backup = std.posix.tcgetattr(stdin.handle) catch utils.panicFromModule(
        MODULE_NAME,
        "Failed to get raw mode parameters.",
    );
    var raw = termios_backup.?;
    // Comments pasted from the source for easier googling
    raw.iflag.BRKINT = false; // No break
    raw.iflag.ICRNL = false; // No CR to NL
    raw.iflag.INPCK = false; // No parity check
    raw.iflag.ISTRIP = false; // No strip char
    raw.iflag.IXON = false; // No start/stop output control

    raw.oflag.OPOST = false; // Disable post processing

    raw.cflag.CSIZE = .CS8; // 8 bit chars

    raw.lflag.ECHO = false; // Echoing off
    raw.lflag.ICANON = false; // Canonical off
    raw.lflag.IEXTEN = false; // No extended function
    raw.lflag.ISIG = false; // No signal chars

    raw.cc[@intFromEnum(std.posix.V.MIN)] = 0; // Return each byte
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 1; // 100 ms timeout

    std.posix.tcsetattr(stdin.handle, std.posix.TCSA.FLUSH, raw) catch utils.panicFromModule(
        MODULE_NAME,
        "Failed to set raw mode parameters.",
    );
}

pub fn exitRawMode() void {
    const backup = termios_backup orelse return;
    std.posix.tcsetattr(stdin.handle, std.posix.TCSA.FLUSH, backup) catch utils.panicFromModule(
        MODULE_NAME,
        "Failed to reset raw mode parameters.",
    );
}

pub fn enterAlternativeScreen(writer: anytype) void {
    writeCommand(writer, CSI ++ "?1049h");
}

pub fn exitAlternativeScreen(writer: anytype) void {
    writeCommand(writer, CSI ++ "?1049l");
}

pub fn setForegroundColor(writer: anytype, color: types.Color) void {
    writer.print(CSI ++ "38;2;{d};{d};{d}m", .{ color.r, color.g, color.b }) catch utils.panicFromModule(
        MODULE_NAME,
        "Failed setting foreground color",
    );
}

pub fn setForegroundColorToDefault(writer: anytype) void {
    writeCommand(writer, CSI ++ "39m");
}

pub fn setBackgroundColor(writer: anytype, color: types.Color) void {
    writer.print(CSI ++ "48;2;{d};{d};{d}m", .{ color.r, color.g, color.b }) catch utils.panicFromModule(
        MODULE_NAME,
        "Failed setting background color",
    );
}

pub fn setBackgroundColorToDefault(writer: anytype) void {
    writeCommand(writer, CSI ++ "49m");
}

pub fn saveCursor(writer: anytype) void {
    writeCommand(writer, CSI ++ "s");
}

pub fn restoreCursor(writer: anytype) void {
    writeCommand(writer, CSI ++ "u");
}

pub fn hideCursor(writer: anytype) void {
    writeCommand(writer, CSI ++ "?25l");
}

pub fn showCursor(writer: anytype) void {
    writeCommand(writer, CSI ++ "?25h");
}

pub fn moveCursor(writer: anytype, position: types.Position) void {
    writer.print(CSI ++ "{d};{d}H", .{ position.row + 1, position.col + 1 }) catch utils.panicFromModule(
        MODULE_NAME,
        "Failed setting cursor position",
    );
}

pub fn moveCursorHome(writer: anytype) void {
    writeCommand(writer, CSI ++ "H");
}

pub fn queryCursorPosition(writer: anytype) void {
    writeCommand(writer, CSI ++ "6n");
}

pub fn resetStyle(writer: anytype) void {
    writeCommand(writer, CSI ++ "0m");
}

pub fn enableMouseSupport(writer: anytype) void {
    writeCommand(writer, CSI ++ "?1000h" ++ CSI ++ "?1003h" ++ CSI ++ "?1015h" ++ CSI ++ "?1006h");
}

pub fn disableMouseSupport(writer: anytype) void {
    writeCommand(writer, CSI ++ "?1000l" ++ CSI ++ "?1003l" ++ CSI ++ "?1015l" ++ CSI ++ "?1006l");
}

pub fn startSync(writer: anytype) void {
    writeCommand(writer, CSI ++ "? 2026 h");
}

pub fn endSync(writer: anytype) void {
    writeCommand(writer, CSI ++ "? 2026 l");
}

fn writeCommand(writer: anytype, comptime command: []const u8) void {
    writer.writeAll(command) catch utils.panicFromModule(MODULE_NAME, "Failed writing out command.");
}

// If we ever need this, this is the code.
// .ScreenSize => CSI ++ "14t",
