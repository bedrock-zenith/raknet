pub const index = @import("24/root.zig");
pub const common = @import("common/root.zig");
pub const constants = @import("constants.zig");
pub const core = @import("core/root.zig");
pub const data = @import("data/root.zig");

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
