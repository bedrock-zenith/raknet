const ClientConnection = @import("root.zig");

pub const ServerEvent = union {
    message: struct { connection: *ClientConnection, message: []const u8 },
    connection: struct { connection: *ClientConnection },
    disconnection: struct { connection: *ClientConnection },
};
