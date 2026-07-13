pub const Endpoint = @import("../common/endpoint.zig");
const BaseConnection = @import("./base-connection.zig");
const Listener = @import("./listener.zig");

const ClientConnection = @This();
base_connection: BaseConnection,
listener: *Listener,

pub fn init(endpoint: *const Endpoint, listener: *Listener, guid: u64) !ClientConnection {
    return .{
        .listener = listener,
        .base_connection = try .init(
            endpoint.*,
            guid,
            &listener.pool_allocator,
        ),
    };
}

pub fn deinit(self: *ClientConnection) void {
    self.base_connection.deinit();
}
