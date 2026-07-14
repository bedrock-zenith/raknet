const std = @import("std");

const BitRingBuffer = @import("../common/bit-ring-buffer.zig");
const Reader = @import("../common/cursor.zig").Reader;
const Endpoint = @import("../common/endpoint.zig");
const Index24Utils = @import("../common/index-24-utils.zig");
const meta = @import("../common/meta.zig");
const PoolAllocator = @import("../common/pool-allocator.zig");
const FrameSet = @import("../packets/online/root.zig").FrameSet;
const FragmentBuilder = @import("./fragment-builder.zig");
const well_known = @import("./well-known.zig");
const ConnectionState = @import("connection-state.zig").ConnectionState;

const BaseConnection = @This();

endpoint: Endpoint,
guid: u64,
connection_state: ConnectionState = .Unconnected,
incomingAcknowledgeQueue: BitRingBuffer,
pool_allocator: *PoolAllocator,
fragments: [64]FragmentBuilder,
// Store window for FrameSet that weren't acknowledged
memory_window: [well_known.UNACKNOWLEDGED_WINDOWS_SIZE]?*const FrameSet.CapsuleInfo,

pub fn init(self: *BaseConnection, endpoint: Endpoint, guid: u64, pool: *PoolAllocator) !BaseConnection {
    self.* = .{
        .guid = guid,
        .endpoint = endpoint,
        .connection_state = .Unconnected,
        .incomingAcknowledgeQueue = .{},
        .pool_allocator = pool,
        .fragments = undefined,
        .memory_window = undefined,
    };
    @memset(self.fragments, .empty);
    @memset(self.memory_window, null);
}

pub fn deinit(self: *BaseConnection) void {
    // Do not deallocate anything that wasn't allocated in BaseConnection
    // Clean up any unprocessed fragments
    for (self.fragments) |*v| {
        var iterator = v.iterator();
        while (iterator.next()) |c|
            self.pool_allocator.destroy(c);
    }
    for (self.memory_window) |window|
        if (window) |w|
            self.pool_allocator.destroy(w);
}

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
    // Remove from memory_window
}

pub fn handleNack(self: *BaseConnection, buffer: []const u8) !void {
    _ = self; // autofix
    _ = buffer; // autofix
    // pop from memory_window, and resent
}

pub fn handleFrameSet(self: *BaseConnection, buffer: []const u8) !void {
    var reader: Reader = .init(buffer, 1);
    try reader.assert(3);
    const sequence_index: u32 = meta.readU24LE(&reader);
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
    var capsule: FrameSet.CapsuleInfo = undefined;
    while (reader.remaining() > 0) {
        try capsule.read(&reader);

        std.log.info("CAPSULE; Reliability: {}, data: {any}", .{ capsule.reliability, capsule.body });
        if (capsule.fragment_data) |_|
            handleFragment(self, capsule)
        else
            handleFrame(self, capsule);
    }
}

pub fn handleFragment(self: *BaseConnection, capsule: FrameSet.CapsuleInfo) void {
    _ = capsule; // autofix
    _ = self; // autofix

    // Rebuild and call handleFrame as well
}

pub fn handleFrame(self: *BaseConnection, capsule: FrameSet.CapsuleInfo) void {
    _ = self; // autofix
    _ = capsule; // autofix
}
