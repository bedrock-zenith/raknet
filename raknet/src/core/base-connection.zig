const std = @import("std");

const IndexableBitQueue = @import("../24/root.zig").IndexableBitQueue;
const IndexableQueue = @import("../24/root.zig").IndexableQueue;
const Indexable = @import("../24/root.zig").Indexable;
const common = @import("../common/root.zig");
const Reader = common.Reader;
const Writer = common.Writer;
const binary = common.binary;
const CONSTANTS = @import("../constants.zig");
const raknet = @import("../data/root.zig");
const ConnectionState = @import("connection-state.zig").ConnectionState;
const Endpoint = @import("endpoint.zig");
const FragmentBuilder = @import("fragment-builder.zig");
const PoolAllocator = @import("root.zig").FramePool;

const BaseConnection = @This();
const SequencedIndexableBitQueue = IndexableBitQueue(CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE);
const ReliabilityIndexableBitQueue = IndexableBitQueue(CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE * 4);
const ORDERED_CHANNELS_COUNT = 32;
const PARALLEL_FRAGMENT_REBUILDERS = 32;

io: *const std.Io,
endpoint: Endpoint,
guid: u64,
connection_state: ConnectionState = .Unconnected,
pool_allocator: *PoolAllocator,
incomingAcknowledgeQueue: SequencedIndexableBitQueue,
incomingFragments: [PARALLEL_FRAGMENT_REBUILDERS]FragmentBuilder,
incomingHighestSequenceIndexes: [ORDERED_CHANNELS_COUNT]u32,
incomingOrderingIndexes: [ORDERED_CHANNELS_COUNT]u32,
incomingReliabilityIndexBitSet: ReliabilityIndexableBitQueue,
incomingOrderChannels: [ORDERED_CHANNELS_COUNT]?*IndexableQueue(?*[]const u8, 2048, null),
// Store window for FrameSet that weren't acknowledged
memory_window: [CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE]?*const raknet.datagram.Capsule,

pub fn init(self: *BaseConnection, io: *const std.Io, endpoint: Endpoint, guid: u64, pool: *PoolAllocator) !void {
    self.* = .{
        .io = io,
        .guid = guid,
        .endpoint = endpoint,
        .connection_state = .Unconnected,
        .incomingAcknowledgeQueue = .{},
        .pool_allocator = pool,
        .incomingFragments = @splat(.empty),
        .memory_window = @splat(null),
        .incomingHighestSequenceIndexes = @splat(0),
        .incomingOrderChannels = @splat(null),
        .incomingOrderingIndexes = @splat(0),
        .incomingReliabilityIndexBitSet = .{},
    };

    //@memset(self.incomingFragments, .empty);
    //@memset(self.memory_window, null);
    //@memset(self.incomingOrderChannels, null);
}

pub fn deinit(self: *BaseConnection) void {
    self.connection_state = .Disconnected;
    // Do not deallocate anything that wasn't allocated in BaseConnection
    // Clean up any unprocessed fragments
    for (self.incomingFragments) |*v| {
        var iterator = v.iterator();
        while (iterator.next()) |c|
            self.pool_allocator.destroy(c);
    }
    for (self.memory_window) |window|
        if (window) |w|
            self.pool_allocator.destroy(w);
}

pub fn handle(self: *BaseConnection, buffer: []const u8) !void {
    @branchHint(.unlikely);
    if (self.connection_state == .Disconnected) return;

    // Ack
    if (buffer[0] & raknet.datagram.ACKNOWLEDGE_BIT_MASK != 0) {
        try handleAck(self, buffer);
        return;
    }

    // Nack
    if (buffer[0] & raknet.datagram.NOT_ACKNOWLEDGE_BIT_MASK != 0) {
        try handleAck(self, buffer);
        return;
    }

    try handleFrameSet(self, buffer);
}

fn handleAck(self: *BaseConnection, buffer: []const u8) !void {
    _ = self; // autofix

    var reader: Reader = .init(buffer, 1);

    const amountOfRanges: u16 = reader.readInt(u16, .big);

    for (0..amountOfRanges) |_| {
        const range = try binary.readRange(&reader);

        for (range.min..range.max + 1) |j| {
            _ = j; // autofix
            // TODO
        }
    }

    // Remove from memory_window
}

fn handleNack(self: *BaseConnection, buffer: []const u8) !void {
    _ = self; // autofix

    var reader: Reader = .init(buffer, 1);

    const amountOfRanges: u16 = reader.readInt(u16, .big);

    for (0..amountOfRanges) |_| {
        const range = try binary.readRange(reader);

        for (range.max..range.min) |j| {
            _ = j; // autofix
            // TODO
        }
    }
    // pop from memory_window, and resent
}

fn handleFrameSet(self: *BaseConnection, buffer: []const u8) !void {
    var reader: Reader = .init(buffer, 1);
    try reader.assert(3);
    const sequence_index: u32 = binary.readU24LE(&reader);
    std.log.info("---------------------------------", .{});
    std.log.info("SequenceIndex: {}, size: {}", .{ sequence_index, buffer.len });

    const last_sequence_index = Indexable.fixed(self.incomingAcknowledgeQueue.head -% 1);
    const distance = Indexable.distance(last_sequence_index, sequence_index);

    // we have probably lost more packets than even client it self remembers
    // in that case we just notify disconnect, and remove this connection
    //
    // ref: BitRingBuffer.reserve first assert
    if (distance > self.incomingAcknowledgeQueue.capacity) {
        std.log.err("Capacity fail: ", .{});
        //TODO:
        return;
    }

    // late packets, late packets also covers old duplicates
    //
    // ref: BitRingBuffer.@etValue first assert sequenceIndex >= tail
    if (distance < @as(i32, @bitCast(self.incomingAcknowledgeQueue.capacity -% SequencedIndexableBitQueue.RANGE))) {
        std.log.err("BitRingBuffer.@etValue first assert sequenceIndex >= tail, d: {}, {}, {}", .{
            distance,
            self.incomingAcknowledgeQueue,
            @as(i32, @bitCast(self.incomingAcknowledgeQueue.capacity -% SequencedIndexableBitQueue.RANGE)),
        });
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
    var capsule: raknet.datagram.Capsule = undefined;
    while (reader.remaining() > 0) {
        capsule.read(&reader) catch continue;
        std.log.info("CAPSULE; Reliability: {}, data: {any}", .{ capsule.reliability, capsule.body });
        handleFrame(self, &capsule) catch continue;
    }

    try updateAcknowledge(self);
}

fn handleFrame(self: *BaseConnection, capsule: *raknet.datagram.Capsule) !void {
    std.log.info("Reliability: {}", .{capsule.reliability});
    // f*ck it, just ignore this sus connection behavior
    if (capsule.reliability.isSequencedOrdered() and capsule.orderChannel > ORDERED_CHANNELS_COUNT)
        return error.RakNetOrderChannelOutOfBounds;

    std.log.info("ReliabilityIndex: {}", .{capsule.reliableIndex});

    if (capsule.reliability.isReliable()) {
        const hole = Indexable.distance(capsule.reliableIndex, self.incomingReliabilityIndexBitSet.head);

        // We are missing too many packets to recover the connection
        // or we got old packet thats too old
        if (hole > self.incomingReliabilityIndexBitSet.capacity or hole < (self.incomingReliabilityIndexBitSet.capacity -% ReliabilityIndexableBitQueue.RANGE))
            return;

        // reserve the space
        if (hole >= 0)
            self.incomingReliabilityIndexBitSet.reserve(capsule.reliableIndex)
            // duplicate
        else if (self.incomingReliabilityIndexBitSet.getValue(capsule.reliableIndex)) {
            return;
        }

        self.incomingReliabilityIndexBitSet.setValue(capsule.reliableIndex, true);
        // We got packet as expected
        if (hole == 0) {
            @branchHint(.likely);
            self.incomingReliabilityIndexBitSet.head += 1;
            self.incomingReliabilityIndexBitSet.tail += 1;
        } else if (capsule.reliableIndex == self.incomingReliabilityIndexBitSet.tail) {
            var iterator = self.incomingReliabilityIndexBitSet.iterator();
            // We check if first range is bit set true in that case we can safely move the tail
            if (iterator.next()) |range|
                if (range.bit) {
                    const size = Indexable.distance(range.tail, range.head);
                    self.incomingReliabilityIndexBitSet.tail +%= @bitCast(size);
                    self.incomingReliabilityIndexBitSet.capacity +%= @bitCast(size);
                };
        }
    }

    // The fragment was consumed so we leave early
    var ref = capsule;
    if (reassemble(self, &ref))
        return;

    const allocated = ref != capsule;
    _ = allocated; // autofix

    if (ref.reliability.isSequencedOrdered()) {
        const order_distance = Indexable.distance(self.incomingOrderingIndexes[ref.orderChannel], ref.orderingIndex);
        if (order_distance == 0) {
            if (ref.reliability.isSequenced()) {
                // basically discard any older packets
                if (Indexable.distance(self.incomingOrderingIndexes[ref.orderChannel], ref.orderingIndex) >= 0) {
                    self.incomingHighestSequenceIndexes[ref.orderChannel] = ref.sequenceIndex + 1;
                    //TODO: Push packet to receive queue
                }
                return;
            }

            //ref: Source\ReliabilityLayer.cpp:1372
            self.incomingOrderingIndexes[ref.orderChannel] = Indexable.fixed(ref.orderingIndex + 1);
            self.incomingHighestSequenceIndexes[ref.orderChannel] = 0;

            // Handle the packet
            // HandlePayload(data);
            // while (_incomingOutOfOrderBuffers.Remove(++index, out FragmentInfo info))
            // {
            //     HandlePayload(info.RentedBuffer.Span);
            //     info.RentedBuffer.Dispose();
            // }

            // // Update the queue
            // self.incomingOrderingIndexes[frame.OrderChannel] = (int)(index & 0b00000111_11111111_11111111_11111111);
        } else if (order_distance > 0) {
            // if (!_incomingOutOfOrderBuffers.TryAdd((uint)frame.OrderFrameIndex | ((uint)frame.OrderChannel << 27), new(frame, RentedBuffer.From(data))))
            //     throw new Exception("Unexpected existance of Unordered memory buffer");
        }
    }

    if (ref.reliability.isSequenced()) {
        if (Indexable.distance(self.incomingOrderingIndexes[ref.orderChannel], ref.orderingIndex) < 0)
            return;

        if (ref.sequenceIndex < self.incomingHighestSequenceIndexes[ref.orderChannel] or
            ref.orderingIndex < self.incomingOrderingIndexes[ref.orderChannel])
            return;

        self.incomingHighestSequenceIndexes[ref.orderChannel] = ref.sequenceIndex + 1;
        //HandlePayload(data);
        return;
    }
}

fn reassemble(self: *BaseConnection, ptr: **raknet.datagram.Capsule) bool {
    const capsule = ptr.*;
    const index: usize = @as(usize, @intCast(capsule.fragment_data.?.id)) % self.incomingFragments.len;
    var ref = &self.incomingFragments[index];
    if (ref.last) |l| {
        if (l.fragment_data.?.id != capsule.fragment_data.?.id)
            std.debug.panic("TODO: fragments array buffer overflow, should we close the connection??", .{});
    }

    if (!ref.append(capsule)) unreachable;
    if (ref.count == capsule.fragment_data.?.count) {
        std.debug.panic("TODO: build the fragments together and forward it??", .{});
        // + cleanup
    }

    // Rebuild and call handleFrame as well
    return false;
}

// This part reads the buffer to separated one, maybe we should move it only to places we need it
// var capsule: *FrameSet.CapsuleInfo = self.pool_allocator.create(FrameSet.CapsuleInfo);
// const body = self.pool_allocator.remaining(FrameSet.CapsuleInfo, capsule)[0..capsule.body.len];
// @memcpy(body, capsule.body);
// capsule.body = body;

fn updateAcknowledge(self: *BaseConnection) !void {
    var ack_buffer: [1024]u8 = undefined;
    var nack_buffer: [1024]u8 = undefined;

    var ack_writer: Writer = .init(&ack_buffer, 0);
    var ack_count: usize = 0;
    ack_writer.writeByte(raknet.datagram.ACKNOWLEDGE_PACKED_ID);
    ack_writer.skip(2);

    var nack_writer: Writer = .init(&nack_buffer, 0);
    var nack_count: usize = 0;
    nack_writer.writeByte(raknet.datagram.NOT_ACKNOWLEDGE_PACKED_ID);
    nack_writer.skip(2);

    var iterator = self.incomingAcknowledgeQueue.iterator();
    while (iterator.next()) |range| {
        const writer: *Writer = if (range.bit) &ack_writer else &nack_writer;
        const counter: *usize = if (range.bit) &ack_count else &nack_count;
        counter.* = counter.* + 1;
        try binary.writeRange(writer, .{
            .min = range.tail,
            .max = range.head -% 1,
        });
    }

    const ack = ack_writer.getProcessedBytes();
    const nack = nack_writer.getProcessedBytes();
    ack_writer.pointer = 1;
    ack_writer.writeInt(u16, @intCast(ack_count), .big);
    nack_writer.pointer = 1;
    nack_writer.writeInt(u16, @intCast(nack_count), .big);
    if (ack.len > 3)
        try self.endpoint.source.send(self.io.*, &self.endpoint.address, ack);
    if (nack.len > 3)
        try self.endpoint.source.send(self.io.*, &self.endpoint.address, nack);

    self.incomingAcknowledgeQueue.clear();
}
