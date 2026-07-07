pub const ConnectionState = enum(u8) {
    Unconnected = 0,
    Connecting = 1,
    Connected = 2,
    Disconnected = 3,
};
