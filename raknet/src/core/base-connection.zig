const std = @import("std");

const Reader = @import("../common/cursor.zig").Reader;
const Endpoint = @import("../common/endpoint.zig");
const meta = @import("../common/meta.zig");
const well_known = @import("./well-known.zig");
const ConnectionState = @import("connection-state.zig").ConnectionState;

const BaseConnection = @This();

endpoint: Endpoint,
guid: u64,
incomingMissingDatagram: [512]u1,
connection_state: ConnectionState,

pub fn handle(self: *BaseConnection, buffer: []const u8) !void {
    // Ack
    if (buffer[0] & well_known.ACK_DATAGRAM_BIT_MASK != 0) {
        try handleAck(self, buffer);
        return;
    }

    // Nack
    if (buffer[0] & well_known.NACK_DATAGRAM_BIT_MASK != 0) {
        try handleAck(self, buffer);
        return;
    }

    try handleFrameSet(self, buffer);
}
pub fn handleAck(self: *BaseConnection, buffer: []const u8) !void {
    _ = self; // autofix
    _ = buffer; // autofix
}

pub fn handleNack(self: *BaseConnection, buffer: []const u8) !void {
    _ = self; // autofix
    _ = buffer; // autofix
}

pub fn handleFrameSet(self: *BaseConnection, buffer: []const u8) !void {
    _ = self; // autofix

    var reader: Reader = .init(buffer, 1);

    const sequence_index: u32 = try meta.readU24LE(&reader);

    std.log.info("SequenceIndex: {}", .{sequence_index});
}
