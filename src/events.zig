const std = @import("std");
const terminal = @import("terminal.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

const expect = std.testing.expect;

const MODULE_NAME = "events";

pub const SHIFT: u3 = 0b001;
pub const ALT: u3 = 0b010;
pub const CTRL: u3 = 0b100;

pub const Modifiers = u3;

pub const Event = struct {
    keypress: Keypress,
    modifiers: Modifiers = 0,
};

const KeyType = enum {
    text,
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    resize,
    mouse_event,
};

pub const Keypress = union(KeyType) {
    text: []const u8,
    arrow_up: void,
    arrow_down: void,
    arrow_left: void,
    arrow_right: void,
    resize: types.Position,
    mouse_event: MouseEvent,
};

pub const MouseEvent = struct {
    button: enum { left, middle, right, none },
    event_type: enum { press, release, drag, move },
    position: types.Position,
};

const ControlSequences = struct {
    const Pair = struct { template: []const u8, key_type: KeyType };
    const template_to_key_type = [_]Pair{
        .{ .template = terminal.CSI ++ "<$;$;$M", .key_type = .mouse_event },
        .{ .template = terminal.CSI ++ "<$;$;$m", .key_type = .mouse_event },
        .{ .template = terminal.CSI ++ "$;$R", .key_type = .resize },
        .{ .template = terminal.CSI ++ "1;$A", .key_type = .arrow_up },
        .{ .template = terminal.CSI ++ "1;$B", .key_type = .arrow_down },
        .{ .template = terminal.CSI ++ "1;$C", .key_type = .arrow_right },
        .{ .template = terminal.CSI ++ "1;$D", .key_type = .arrow_left },
        .{ .template = terminal.CSI ++ "A", .key_type = .arrow_up },
        .{ .template = terminal.CSI ++ "B", .key_type = .arrow_down },
        .{ .template = terminal.CSI ++ "C", .key_type = .arrow_right },
        .{ .template = terminal.CSI ++ "D", .key_type = .arrow_left },
    };

    // We want to ensure that the longest ones get matched first.
    comptime {
        for (1..template_to_key_type.len) |i| {
            if (template_to_key_type[i].template.len > template_to_key_type[i - 1].template.len) {
                @compileError("Control sequence templates not sorted by length in descending order.");
            }
        }
    }

    pub fn getKeyType(input: []const u8) ?struct { key_type: KeyType, match_len: usize } {
        for (template_to_key_type) |template_key_type_pair| {
            const match_result = prefixMatchesTemplate(input, template_key_type_pair.template);
            switch (match_result) {
                .match => |len| return .{
                    .key_type = template_key_type_pair.key_type,
                    .match_len = len,
                },
                .no_match => {},
            }
        }
        return null;
    }
};
/// Parses a string into an event.
///
/// Modifiers are registered only for mouse events, arrows, and single ASCII letters.
/// Due to weird responses I get from the terminal when playing with inputs,
/// modifiers are ignored for other characters.
const EventIterator = struct {
    const Self = @This();

    input_buffer: []u8,

    pub fn next(self: *Self) ?Event {
        if (self.input_buffer.len == 0) {
            return null;
        }
        if (ControlSequences.getKeyType(self.input_buffer)) |match| {
            // snip off CSI
            const matched_slice = self.input_buffer[terminal.CSI.len..match.match_len];
            const event = switch (match.key_type) {
                .arrow_up, .arrow_down, .arrow_left, .arrow_right => parseArrowKey(matched_slice),
                .resize => parseCursorPosition(matched_slice),
                .mouse_event => parseMouseInput(matched_slice),
                .text => {
                    utils.panicFromModule(
                        MODULE_NAME,
                        "Found text after matching CSI sequence - should not happen",
                    );
                },
            };
            self.input_buffer = self.input_buffer[match.match_len..];
            return event;
        } else if (prefixMatchesTemplate(self.input_buffer, terminal.CSI) == .match) {
            // unhandled CSI, throw everything away
            return null;
        } else {
            const index = std.mem.indexOf(u8, self.input_buffer, terminal.CSI) orelse self.input_buffer.len;
            const event = parseSingleLetterAndModifier(self.input_buffer[0..index]);
            self.input_buffer = self.input_buffer[index..];
            return event;
        }
    }

    fn parseArrowKey(buffer: []const u8) Event {
        var modifiers: Modifiers = 0;
        if (buffer.len > 1) { // has modifiers
            // input looks like CSI 1; mod letter
            const modifier_key = buffer[2];
            modifiers = switch (modifier_key) {
                '2' => SHIFT,
                '3' => ALT,
                '4' => SHIFT | ALT,
                '5' => CTRL,
                '6' => CTRL | SHIFT,
                '7' => CTRL | ALT,
                '8' => CTRL | ALT | SHIFT,
                else => unreachable,
            };
        }

        const keypress: Keypress = switch (buffer[buffer.len - 1]) {
            'A' => .arrow_up,
            'B' => .arrow_down,
            'C' => .arrow_right,
            'D' => .arrow_left,
            else => unreachable,
        };

        return .{ .keypress = keypress, .modifiers = modifiers };
    }

    fn parseCursorPosition(buffer: []const u8) Event {
        // buffer should look like col ; row ; R]
        var split_iterator = std.mem.splitAny(u8, buffer, ";R");
        const row = std.fmt.parseInt(usize, split_iterator.next().?, 10) catch utils.panicFromModule(
            MODULE_NAME,
            "Cannot parse cursor position",
        );
        const col = std.fmt.parseInt(usize, split_iterator.next().?, 10) catch utils.panicFromModule(
            MODULE_NAME,
            "Cannot parse cursor position",
        );
        // information from terminal is 1-based, we use 0-based
        return Event{
            .keypress = .{
                .resize = .{
                    .row = row - 1,
                    .col = col - 1,
                },
            },
            .modifiers = 0,
        };
    }

    fn parseMouseInput(buffer: []const u8) Event {
        // buffer should look like < code;col;row;{m|M|nothing}
        // slice off '<'
        const valid_slice = buffer[1..];
        var split_iterator = std.mem.splitAny(u8, valid_slice, ";mM");

        const code = std.fmt.parseInt(u64, split_iterator.next().?, 10) catch utils.panicFromModule(
            MODULE_NAME,
            "Cannot parse mouse code",
        );
        const x = std.fmt.parseInt(u64, split_iterator.next().?, 10) catch utils.panicFromModule(
            MODULE_NAME,
            "Cannot parse mouse position",
        );
        const y = std.fmt.parseInt(u64, split_iterator.next().?, 10) catch utils.panicFromModule(
            MODULE_NAME,
            "Cannot parse mouse position",
        );
        const last_char = valid_slice[valid_slice.len - 1];

        // information from terminal is 1-based, we use 0-based
        const position = types.Position{ .row = y - 1, .col = x - 1 };

        // To figure out the modifiers, we need to check bits 2, 3, and 4.
        // 2 set => shift
        // 3 set => alt
        // 4 set => ctrl
        // Once we shift it, we have the same order of bits as in
        // constants defined in modifiers
        // No need to check the actual bits, just truncate it
        const modifiers: Modifiers = @truncate(code >> 2);

        // We need to reset the bits corresponding to modifiers
        // This will reduce the value in the code
        // So we just need to figure out what's that in hex
        const code_adapted = code & 0xFFFFFFE3;

        // last part - once we reduce `code` by the amount added by modifiers,
        // we check the actual value. 0-2 are normal buttons, 32-34 are drag motions
        // and 35 is just mouse move
        const keypress: Keypress = .{
            .mouse_event = .{
                .button = switch (code_adapted) {
                    0, 32 => .left,
                    1, 33 => .middle,
                    2, 34 => .right,
                    35 => .none,
                    else => .none, // Treat everything unhandled as no buttons pressed
                },
                .event_type = switch (code_adapted) {
                    0...2 => switch (last_char) {
                        'm' => .release,
                        'M' => .press,
                        else => unreachable,
                    },
                    32...34 => .drag,
                    35 => .move,
                    else => .move, // Treat everything unhandled as mouse move
                },
                .position = position,
            },
        };

        return .{ .keypress = keypress, .modifiers = modifiers };
    }

    fn parseSingleLetterAndModifier(buffer: []u8) Event {
        var modifiers: Modifiers = 0;
        var char_slice = buffer;
        if (buffer[0] == 27) {
            // ALT is pressed, which results in an array prepended with 27
            // The rest is the same for handling
            if (buffer.len > 1) {
                char_slice = char_slice[1..];
                modifiers |= ALT;
            }
        }
        switch (char_slice[0]) {
            // CTRL pressed with a-z
            // This is commented out since it collides with control characters
            // like backspace and enter
            // If there is a better way, I'll put this back
            // 1...26 => |*value| {
            //     event.modifiers |= CTRL;
            //     value.* += 96; // keep the value lowercase
            // },
            65...90 => {
                // These are uppercase letters, i.e. shift is pressed
                modifiers |= SHIFT;
                // value.* += 32; // keep the value lowercase
            },
            97...122 => {
                // simple lowercase letter
            },
            else => {}, // ignore everything else
        }
        const keypress: Keypress = .{ .text = char_slice };
        return .{ .keypress = keypress, .modifiers = modifiers };
    }
};

pub fn iterator(input_buffer: []u8) EventIterator {
    return .{ .input_buffer = input_buffer };
}

const MatchResult = union(enum) {
    match: usize,
    no_match: void,
};

/// very simple template pattern:
/// - $ matches a number, or verbatim
/// - everything else is matched verbatim
fn prefixMatchesTemplate(string: []const u8, template: []const u8) MatchResult {
    if (string.len < template.len) {
        return .no_match;
    }
    var template_index: usize = 0;
    var string_index: usize = 0;
    var matched_number: bool = false;
    while (template_index < template.len) : (string_index += 1) {
        if (string_index == string.len) {
            break;
        }

        const template_char = template[template_index];
        const string_char = string[string_index];
        if (template_char == string_char) {
            template_index += 1;
            continue;
        }
        if (template_char != string_char) {
            if (template_char != '$') {
                return .no_match;
            }
            switch (string_char) {
                '0'...'9' => matched_number = true,
                '$' => template_index += 1,
                else => {
                    if (matched_number) {
                        // we ended with the number,
                        // so we need to go back in the string
                        template_index += 1;
                        string_index -= 1;
                        matched_number = false;
                    } else {
                        return .no_match;
                    }
                },
            }
        }
    }

    return .{ .match = string_index };
}

test "match strings" {
    var result: MatchResult = undefined;

    result = prefixMatchesTemplate("a", "#");
    try expect(result == .no_match);

    result = prefixMatchesTemplate("4", "$");
    try expect(std.meta.eql(result, .{ .match = 1 }));

    result = prefixMatchesTemplate("$", "$");
    try expect(std.meta.eql(result, .{ .match = 1 }));

    result = prefixMatchesTemplate("", "$");
    try expect(result == .no_match);

    result = prefixMatchesTemplate("123", "$");
    try expect(std.meta.eql(result, .{ .match = 3 }));

    result = prefixMatchesTemplate("a123b", "a$b");
    try expect(std.meta.eql(result, .{ .match = 5 }));

    result = prefixMatchesTemplate("a123b", "$b");
    try expect(result == .no_match);

    result = prefixMatchesTemplate("a123", "a$");
    try expect(std.meta.eql(result, .{ .match = 4 }));

    result = prefixMatchesTemplate("a123", "a$$");
    try expect(std.meta.eql(result, .{ .match = 4 }));

    result = prefixMatchesTemplate("a123b456", "a$b$");
    try expect(std.meta.eql(result, .{ .match = 8 }));

    result = prefixMatchesTemplate("a1b46c", "a$b$");
    try expect(std.meta.eql(result, .{ .match = 5 }));

    result = prefixMatchesTemplate("a1b$46c", "a$b$");
    try expect(std.meta.eql(result, .{ .match = 4 }));
}
