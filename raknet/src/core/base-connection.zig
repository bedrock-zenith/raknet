const Endpoint = @import("../common/endpoint.zig");

const UnacknownledgedWindowsSize = 512;
endpoint: Endpoint,
guid: u64,
incomingMissingDatagram: [512]u1,
