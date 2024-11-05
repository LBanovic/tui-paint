pub fn panicFromModule(comptime module_name: []const u8, comptime message: []const u8) noreturn {
    @panic(module_name ++ ": " ++ message);
}
