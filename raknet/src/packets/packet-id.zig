// -------- Enums --------
pub const PacketId = enum(u8) {
    pub fn from(num: u8) PacketId {
        return @enumFromInt(num);
    }
    UnconnectedPing = 0x01,
    UnconnectedPingOpenConnections = 0x02,
    UnconnectedPong = 0x1c,
    ConnectedPing = 0x00,
    ConnectedPong = 0x03,
    OpenConnectionRequestOne = 0x05,
    OpenConnectionReply1 = 0x06,
    OpenConnectionRequest2 = 0x07,
    OpenConnectionReply2 = 0x08,
    ConnectionRequest = 0x09,
    RemoteSystemRequiresPublicKey = 0x0a,
    OurSystemRequiresSecurity = 0x0b,
    ConnectionAttemptFailed = 0x11,
    AlreadyConnected = 0x12,
    ConnectionRequestAccepted = 0x10,
    NewIncomingConnection = 0x13,
    DisconnectionNotification = 0x15,
    ConnectionLost = 0x16,
    IncompatibleProtocolVersion = 0x19,
    _, // This could be unknown packet-type from future versions
};
