const std = @import("std");

const BitRingBuffer = @import("../common/bit-ring-buffer.zig");
const Reader = @import("../common/cursor.zig").Reader;
const Endpoint = @import("../common/endpoint.zig");
const Index24Utils = @import("../common/index-24-utils.zig");
const meta = @import("../common/meta.zig");
const FrameSet = @import("../packets/online/root.zig").FrameSet;
const well_known = @import("./well-known.zig");
const ConnectionState = @import("connection-state.zig").ConnectionState;

const BaseConnection = @This();

endpoint: Endpoint,
guid: u64,
connection_state: ConnectionState = .Unconnected,
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

    const last_sequence_index = Index24Utils.fixed(self.incomingAcknowledgeQueue.head -% 1);
    const distance = Index24Utils.distance(last_sequence_index, sequence_index);

    // we have probably lost more packets than even client it self remembers
    // in that case we just notify disconnect, and remove this connection
    //
    // ref: BitRingBuffer.reserve first assert
    if (distance > self.incomingAcknowledgeQueue.capacity) {
        //TODO:
        return;
    }

    // late packets, late packets also covers old duplicates
    //
    // ref: BitRingBuffer.@etValue first assert sequenceIndex >= tail
    if (distance +% @as(i32, @bitCast(self.incomingAcknowledgeQueue.capacity)) < BitRingBuffer.RANGE) {
        return;
    }

    // duplicate packets that are yet not acknowledged
    //
    // ref: BitRingBuffer.@etValue second assert sequenceIndex < head
    if (distance <= 0)
        if (self.incomingAcknowledgeQueue.getValue(sequence_index))
            return;

    // 2 -> 5, 2 packets lost
    //
    // ref: BitRingBuffer.reserve second assert sIndex >= head
    if (distance > 0)
        // This call already sets other bits to zero, meaning the packets were lost
        self.incomingAcknowledgeQueue.reserve(sequence_index);

    // Set this frame-set as received
    //
    // ref: BitRingBuffer.@etValue second assert, head = sequenceIndex + 1 => sequenceIndex < head
    self.incomingAcknowledgeQueue.setValue(sequence_index, true);

    // gets optimized away
    var frame: FrameSet.CapsuleInfo = undefined;
    while (reader.getRemainingBytes().len > 0) {
        try frame.read(&reader);
        std.log.info("Reliability: {}, data: {any}", .{ frame.reliability, frame.body });
    }
}
