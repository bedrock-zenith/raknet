const std = @import("std");

const BitRingBuffer = @import("../common/bit-ring-buffer.zig");
const Reader = @import("../common/cursor.zig").Reader;
const Endpoint = @import("../common/endpoint.zig");
const Index24Utils = @import("../common/index-24-utils.zig");
const meta = @import("../common/meta.zig");
const well_known = @import("./well-known.zig");
const ConnectionState = @import("connection-state.zig").ConnectionState;

const BaseConnection = @This();

endpoint: Endpoint,
guid: u64,
connection_state: ConnectionState = .Unconnected,
incomingLastActiveSequenceIndex: u32 = @bitCast(-1),
incomingAcknowledgeQueue: BitRingBuffer,

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
    var reader: Reader = .init(buffer, 1);
    const sequence_index: u32 = try meta.readU24LE(&reader);
    std.log.info("SequenceIndex: {}", .{sequence_index});

    const distance = Index24Utils.getDistance(self.incomingLastActiveSequenceIndex, sequence_index);

    // we have probably lost more packets than even client it self remembers
    // in that case we just notify disconnect, and remove this connection
    if (distance > self.incomingAcknowledgeQueue.capacity) {
        //TODO:
        return;
    }

    // late packets, late packets also handles old duplicates
    if (Index24Utils.getDistance(self.incomingAcknowledgeQueue.tail, sequence_index) < 0) {
        return;
    }

    // duplicate packets that are yet not acknowledged
    if (distance <= 0)
        if (self.incomingAcknowledgeQueue.getValue(sequence_index))
            return;

    // 2 -> 5, 2 packets lost
    if (distance > 1) {
        // This call already sets other bits to zero, meaning the packets were lost
        self.incomingAcknowledgeQueue.reserve(sequence_index);
        self.incomingLastActiveSequenceIndex = sequence_index;
    }

    // Set this frame-set as received
    self.incomingAcknowledgeQueue.setValue(sequence_index, true);
}
