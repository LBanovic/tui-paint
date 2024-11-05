const std = @import("std");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub const COLOR_DEF_MAX_LENGTH = 6;

    pub fn parseColor(color_string: []const Cell) ?Color {
        if (color_string.len == 0) {
            return null;
        }
        var color: Color = .{ .r = 0, .b = 0, .g = 0 };
        for (0..COLOR_DEF_MAX_LENGTH) |i| {
            var value: u8 = 0;
            if (i < color_string.len) {
                const hex_code = color_string[i].grapheme[0];
                value = switch (hex_code) {
                    '0'...'9' => hex_code - '0',
                    'A'...'F' => hex_code - 'A' + 10,
                    'a'...'f' => hex_code - 'a' + 10,
                    else => unreachable, // we already check for validity
                };
            }
            if (i < 2) { // Red
                color.r = 16 * color.r + value;
            } else if (i < 4) { // Green
                color.g = 16 * color.g + value;
            } else { // Blue
                color.b = 16 * color.b + value;
            }
        }
        return color;
    }
};

pub const Cell = struct {
    pub const MAX_BYTES = 4;

    color_foreground: ?Color = null,
    color_background: ?Color = null,
    grapheme: [MAX_BYTES]u8 = .{ ' ', 0, 0, 0 },

    pub fn fromChar(char: u8) Cell {
        return .{ .grapheme = .{ char, 0, 0, 0 } };
    }

    /// performs no checking, validate outside of this function
    pub fn fromStrUnchecked(value: []const u8) Cell {
        var cell: Cell = .{};
        for (0..Cell.MAX_BYTES) |i| {
            cell.grapheme[i] = if (i < value.len) value[i] else 0;
        }
        return cell;
    }
};

pub const Dimensions = struct {
    height: usize,
    width: usize,
};

pub const Position = struct {
    row: usize,
    col: usize,

    pub inline fn toBufferIndex(position: Position, dimension: Dimensions) usize {
        return position.row * dimension.width + position.col;
    }

    pub inline fn isInBounds(position: Position, dimension: Dimensions) bool {
        return position.row < dimension.height and position.col < dimension.width;
    }

    pub fn addOffset(
        self: *const Position,
        offset: struct {
            offset_row: i64 = 0,
            offset_col: i64 = 0,
        },
    ) Position {
        const abs_offset_row = @abs(offset.offset_row);
        const abs_offset_col = @abs(offset.offset_col);
        return .{
            .row = if (offset.offset_row > 0) self.row +| abs_offset_row else self.row -| abs_offset_row,
            .col = if (offset.offset_col > 0) self.col +| abs_offset_col else self.col -| abs_offset_col,
        };
    }
};
