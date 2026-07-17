const BaseConnection = @import("./base-connection.zig");
pub const Endpoint = @import("endpoint.zig");
const Server = @import("server.zig");

const ClientConnection = @This();
base_connection: BaseConnection,
listener: *Server,

pub fn init(self: *ClientConnection, endpoint: *const Endpoint, listener: *Server, guid: u64) !void {
    self.* = .{
        .listener = listener,
        .base_connection = undefined,
    };
    try self.base_connection.init(
        endpoint.*,
        guid,
        &listener.pool_allocator,
    );
}

pub fn deinit(self: *ClientConnection) void {
    self.base_connection.deinit();
}
