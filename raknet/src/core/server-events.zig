const ClientSession = @import("root.zig");

pub const ListenerEvent = union {
    message: struct { connection: *ClientSession, message: []const u8 },
    connection: struct { connection: *ClientSession },
    disconnection: struct { connection: *ClientSession },
};
