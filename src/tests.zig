const std = @import("std");

test {
    std.testing.refAllDecls(@This());
}

comptime {
    // Once you have some tests, include them here
    // _ = @import("canvas.zig");
    _ = @import("events.zig");
}
