const ClientSession = @import("root.zig").ClientSession;

pub const ListenerEvent = union(enum) {
    messaged: struct { session: *ClientSession, context: *const anyopaque, message: []const u8 },
    connected: struct { session: *ClientSession },
    disconnected: struct { session: *ClientSession },
};
