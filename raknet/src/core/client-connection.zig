pub const Endpoint = @import("../common/endpoint.zig");
const BaseConnection = @import("./base-connection.zig");

const ClientConnection = @This();
base_connection: BaseConnection,

pub fn init(endpoint: *const Endpoint, guid: u64) ClientConnection {
    return .{
        .base_connection = .{
            .endpoint = endpoint.*,
            .guid = guid,
            .incomingAcknowledgeQueue = .{},
            .connection_state = .Unconnected,
        },
    };
}

pub fn deinit(self: *ClientConnection) void {
    _ = self; // autofix
}
