const ClientSession = @import("root.zig").ClientSession;

pub const ListenerEvent = union(enum) {
    message: struct { connection: *ClientSession, context: *const anyopaque, message: []const u8 },
    connection: struct { connection: *ClientSession },
    disconnection: struct { connection: *ClientSession },
};
