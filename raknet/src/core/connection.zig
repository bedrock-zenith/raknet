const std = @import("std");

const Utils = @import("../24/root.zig").Utils;
const BitWindow = @import("../24/root.zig").BitWindow;
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

const DatagramWindow = BitWindow(CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE);
const ReliableWindow = BitWindow(CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE * 4);
const CHANNELS_COUNT = 16;
const PARALLEL_FRAGMENT_BUILDERS = 32;
const RECEIVE_BUFFER = 128;

const Connection = @This();
io: *const std.Io,
guid: u64,
state: ConnectionState,
endpoint: Endpoint,
pool_allocator: *PoolAllocator,

rx_datagram_window: DatagramWindow,
rx_reliable_window: ReliableWindow,
rx_fragment_builder: [PARALLEL_FRAGMENT_BUILDERS]FragmentBuilder,
rx_channels: [CHANNELS_COUNT]Channel,
rx_received: std.Deque(*const raknet.datagram.Segment),

tx_memory: [CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE]?*const raknet.datagram.Segment,

pub fn init(self: *Connection, io: *const std.Io, endpoint: Endpoint, guid: u64, pool: *PoolAllocator) !void {
    self.* = .{
        .io = io,
        .guid = guid,
        .state = .Unconnected,
        .endpoint = endpoint,
        .pool_allocator = pool,
        .rx_datagram_window = .{},
        .rx_reliable_window = .{},
        .rx_fragment_builder = @splat(.empty),
        .rx_channels = @splat(.{}),
        .rx_received = undefined,
        .tx_memory = @splat(null),
    };
    self.rx_received = try .initCapacity(pool.backing_allocator, 512);
    errdefer self.rx_received.deinit(pool.backing_allocator);

    // const buffer = try pool.alloc(*const raknet.datagram.Segment);
    // // In case of failed initialization we free the allocated memory
    // errdefer pool.destroy(buffer);
    // self.send_queue = .initBuffer(buffer[0..]);
}

pub fn deinit(self: *Connection) void {
    self.connection_state = .Disconnected;

    var rx_received_iterator = self.rx_received.iterator();
    while (rx_received_iterator.next()) |segment| {
        freeSegment(self, segment);
    }

    self.rx_received.deinit(self.pool_allocator.backing_allocator);

    //self.pool_allocator.destroy(self.send_queue.buffer);

    // Do not deallocate anything that wasn't allocated in BaseConnection
    // Clean up any unprocessed fragments
    for (self.rx_fragment_builder) |*v| {
        if (v.last == null) continue;
        var iterator = v.iterator();
        while (iterator.next()) |segment|
            self.pool_allocator.destroy(segment);
    }

    for (self.tx_memory) |window|
        if (window) |segment|
            self.pool_allocator.destroy(segment);
}

pub fn receive(self: *Connection, datagram: []const u8) !void {
    if (self.state == .Disconnected) {
        @branchHint(.cold);
        return;
    }

    if (datagram[0] & raknet.datagram.ACKNOWLEDGE_BIT_MASK != 0) return;
    if (datagram[0] & raknet.datagram.NOT_ACKNOWLEDGE_BIT_MASK != 0) return;

    try rxDatagram(self, datagram);
}

fn rxDatagram(self: *Connection, datagram: []const u8) !void {
    var reader: Reader = .init(datagram, 1);
    try reader.assert(3);
    const datagram_index: u32 = binary.readU24LE(&reader);

    std.log.info("---------------------------------", .{});
    std.log.info("datagram_index: {}, size: {}", .{ datagram_index, datagram.len });

    const last_datagram_index = Utils.fixed(self.rx_datagram_window.head -% 1);
    const distance = Utils.distance(last_datagram_index, datagram_index);

    // we have probably lost more packets than even client it self remembers
    // in that case we just notify disconnect, and remove this connection
    //
    // ref: BitWindow.reserve first assert
    if (distance > @as(i32, @bitCast(self.rx_datagram_window.available()))) {
        std.log.err("Capacity fail: ", .{});
        return error.Unrecoverable;
    }

    // late packets, late packets also covers old duplicates
    //
    // ref: BitWindow.@etValue first assert sequenceIndex >= tail
    if (distance < -@as(i32, @bitCast(self.rx_datagram_window.len))) {
        std.log.err("BitRingBuffer.@etValue first assert sequenceIndex >= tail, d: {}, {}, {}", .{
            distance,
            self.rx_datagram_window,
            -@as(i32, @bitCast(self.rx_datagram_window.len)),
        });

        // Maybe we can recover?
        return;
    }

    // duplicate packets that are yet not acknowledged
    //
    // ref: BitWindow.@etValue second assert datagram_index < head
    if (distance <= 0 and self.rx_datagram_window.getValue(datagram_index))
        return;

    // 2 -> 5, 2 packets lost
    //
    // This call already sets other bits to zero, meaning the packets were lost
    // ref: BitWindow.reserve second assert datagram_index >= head
    if (distance > 0)
        self.rx_datagram_window.reserve(datagram_index);

    // Set this datagram as received
    // ref: BitRingBuffer.@etValue second assert, head = datagram_index + 1 => datagram_index < head
    self.rx_datagram_window.setValue(datagram_index, true);

    // gets optimized away
    var segment: raknet.datagram.Segment = undefined;
    while (reader.remaining() > 0) {
        segment.read(&reader) catch continue;
        std.log.info("SEGMENT; Reliability: {}, data: {any}", .{ segment.delivery_policy, segment.body });
        rxSegment(self, &segment) catch |err| switch (err) {
            error.ChannelOutOfBounds => continue,
            else => return err,
        };
    }
}

fn rxFragment(self: *Connection, fragment: raknet.datagram.Segment.FragmentInfo, input_segment: *raknet.datagram.Segment) !?*raknet.datagram.Segment {
    const builder_index = fragment.id % PARALLEL_FRAGMENT_BUILDERS;

    const builder = &self.rx_fragment_builder[builder_index];
    if (builder.last) |last| {
        if (last.fragment.?.id != fragment.id) return error.FragmentBuilderOutOfMemory;
    }

    defer {
        if (fragment.count == builder.count) builder.* = .{};
    }

    errdefer {
        var iterator = builder.iterator();
        while (iterator.next()) |seg| {
            self.pool_allocator.destroy(seg);
        }
    }

    const segment = try cloneSegment(self, input_segment);
    _ = builder.append(segment);

    if (fragment.count == builder.count) {
        var iterator = builder.iterator();
        var buffer = try self.pool_allocator.backing_allocator.alloc(u8, builder.buffer_size);

        var offset: usize = 0;
        while (iterator.next()) |seg| {
            @memcpy(buffer[offset .. offset + seg.body.len], seg.body);
            offset += seg.body.len;
            if (seg != segment)
                self.pool_allocator.destroy(seg);
        }

        input_segment.* = segment.*;
        segment.body = buffer;
        return segment;
    }

    return null;
}

fn rxSegment(self: *Connection, data: *raknet.datagram.Segment) !void {
    var segment = data;

    // f*ck it, just ignore this sus connection behavior
    if (segment.delivery_policy.hasEpochOrSnapshot() and segment.channel.id > CHANNELS_COUNT)
        return error.ChannelOutOfBounds;

    ////////// RELIABILITY SHI //////////

    if (segment.delivery_policy.isReliable()) {
        const hole = Utils.distance(self.rx_reliable_window.head, segment.reliable_index);

        // We are missing too many packets to recover the connection
        // or we got old packet thats too old
        if (hole > @as(i32, @bitCast(self.rx_reliable_window.available())) or
            // Head is not inclusive, and hole is relative to head, assertion (index >= window.tail)
            hole < -%@as(i32, @bitCast(self.rx_reliable_window.len)))
            return error.Unrecoverable;

        // reserve enough space
        if (hole >= 0)
            self.rx_reliable_window.reserve(segment.reliable_index);

        // check for duplicates
        if (self.rx_reliable_window.getValue(segment.reliable_index)) return;

        self.rx_reliable_window.setValue(segment.reliable_index, true);

        // We got packet as expected
        if (hole == 0) {
            @branchHint(.likely);
            self.rx_reliable_window.head = Utils.fixed(self.rx_reliable_window.head + 1);
            self.rx_reliable_window.tail = Utils.fixed(self.rx_reliable_window.tail + 1);
        }

        // clean and slice the window
        // we check if first range is bit set true
        // in that case we can safely move the tail
        else if (segment.reliable_index == self.rx_reliable_window.tail) {
            var iterator = self.rx_reliable_window.iterator();
            if (iterator.next()) |range|
                if (range.bit) {
                    const size = Utils.distance(range.tail, range.head);
                    self.rx_reliable_window.tail = Utils.fixed(self.rx_reliable_window.tail +% @as(u32, @bitCast(size)));
                    self.rx_reliable_window.len -%= @bitCast(size);
                };
        }
    }

    ////////// FRAGMENT SHI //////////

    if (segment.fragment) |fragment| {
        segment = try rxFragment(self, fragment, segment) orelse return;
    }

    ////////// EPOCH & SNAPSHOT SHI //////////

    if (segment.delivery_policy.hasEpochOrSnapshot()) {
        var channel = &self.rx_channels[segment.channel.id];
        const epoch_distance = Utils.distance(channel.epoch_index, segment.channel.epoch_index);
        if (epoch_distance == 0) {
            // old epoch new snapshot
            if (segment.delivery_policy.hasSnapshot()) {
                if (Utils.distance(channel.snapshot_index, segment.channel.snapshot_index) < 0)
                    // Old snapshots are ignored
                    return;

                channel.snapshot_index = Utils.fixed(segment.channel.snapshot_index +% 1);

                try rxFinalize(self, segment);
                return;
            }

            try rxFinalize(self, segment);

            // next epoch
            channel.epoch_index = Utils.fixed(channel.epoch_index +% 1);
            channel.snapshot_index = 0;

            // flush the heap
            const heap = channel.heap orelse return;
            var last_snapshot_id: u32 = 0;
            while (heap.peek()) |element| {
                if (element.epoch_id == channel.epoch_index) {
                    _ = heap.pop();

                    if (element.snapshot_id < last_snapshot_id) continue;

                    last_snapshot_id = element.snapshot_id;

                    try rxFinalize(self, segment);
                }
                break;
            }

            return;
        }

        // push future epoch to the heap until its properly resolved
        else if (epoch_distance > 0) {
            const heap = channel.heap orelse return_heap: {
                const new_heap = try self.pool_allocator.create(EpochMinHeap);
                new_heap.* = .{};
                break :return_heap new_heap;
            };

            // reallocate to heap
            const allocated = if (segment != data) segment else try cloneSegment(self, segment);
            _ = heap.push(.{ .epoch_id = segment.channel.epoch_index, .snapshot_id = segment.channel.snapshot_index, .segment = allocated });
            return;
        }

        // old epoch that was already resolved
        else return;
    }

    ////////// UNRELIABLE SHI //////////

    try rxFinalize(self, segment);
}

fn rxFinalize(self: *Connection, segment: *const raknet.datagram.Segment) !void {
    _ = self; // autofix
    std.log.info("todo: received {any}", .{segment.body});
}

fn freeSegment(self: *const Connection, segment: *const raknet.datagram.Segment) !void {
    if (segment.fragment) |_|
        self.pool_allocator.backing_allocator.destroy(segment.body.ptr);

    self.pool_allocator.destroy(segment);
}

fn cloneSegment(self: *const Connection, segment: *const raknet.datagram.Segment) !*raknet.datagram.Segment {
    var allocated_segment = try self.pool_allocator.create(raknet.datagram.Segment);
    allocated_segment.* = segment.*;

    const bytes = self.pool_allocator.remaining(raknet.datagram.Segment, allocated_segment)[0..segment.body.len];
    allocated_segment.body = bytes;
    @memcpy(bytes, segment.body);

    return allocated_segment;
}

const EpochMinHeapElement = struct {
    epoch_id: u32 = 0,
    snapshot_id: u32 = 0,
    segment: *raknet.datagram.Segment,

    pub fn compare(a: @This(), b: @This()) bool {
        if (a.epoch_id == b.epoch_id) return a.snapshot_id > b.snapshot_id;
        return a.epoch_id < b.epoch_id;
    }
};

const EpochMinHeap = @import("../24/root.zig").HeapArray(EpochMinHeapElement, 127, EpochMinHeapElement.compare);

// Max 127 unordered packets
comptime {
    if (@sizeOf(EpochMinHeap) > PoolAllocator.PAGE_SIZE)
        @compileError("MinHeap doesn't fits the pool allocator");
}

const Channel = struct {
    epoch_index: u32 = 0,
    snapshot_index: u32 = 0,
    heap: ?*EpochMinHeap = null,
};

// const SequencedIndexableBitQueue = BitWindow(CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE);
// const ReliabilityIndexableBitQueue = BitWindow(CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE * 4);
// const ORDERED_CHANNELS_COUNT = 32;
// const PARALLEL_FRAGMENT_REBUILDERS = 32;
// const DQueue = std.Deque(*const raknet.datagram.Segment);
// const EpochMinHeapElement = struct {
//     epoch_id: u32 = 0,
//     snapshot_id: u32 = 0,
//     capsule: *raknet.datagram.Segment,
//     pub fn compare(a: @This(), b: @This()) bool {
//         if (a.epoch_id == b.epoch_id) return a.snapshot_id > b.snapshot_id;
//         return a.epoch_id < b.epoch_id;
//     }
// };

// const MinHeap = @import("../24/root.zig").HeapArray(EpochMinHeapElement, 127, EpochMinHeapElement.compare);

// // Max 127 unordered packets
// comptime {
//     if (@sizeOf(MinHeap) > PoolAllocator.PAGE_SIZE)
//         @compileError("MinHeap doesn't fits the pool allocator");
// }

// const Connection = @This();

// io: *const std.Io,
// endpoint: Endpoint,
// guid: u64,
// connection_state: ConnectionState = .Unconnected,
// pool_allocator: *PoolAllocator,
// incoming_acknowledge_queue: SequencedIndexableBitQueue,
// incoming_fragments: [PARALLEL_FRAGMENT_REBUILDERS]FragmentBuilder,
// incoming_highest_sequence_indexes: [ORDERED_CHANNELS_COUNT]u32,
// incoming_ordering_indexes: [ORDERED_CHANNELS_COUNT]u32,
// incoming_reliability_index_bit_set: ReliabilityIndexableBitQueue,
// incoming_order_channels: [ORDERED_CHANNELS_COUNT]?*MinHeap,

// // Store window for FrameSet that weren't acknowledged
// memory_window: [CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE]?*const raknet.datagram.Segment,
// send_queue: DQueue,
// outgoing_sequence_index: u32 = 0,

// pub fn init(self: *Connection, io: *const std.Io, endpoint: Endpoint, guid: u64, pool: *PoolAllocator) !void {
//     self.* = .{
//         .io = io,
//         .guid = guid,
//         .endpoint = endpoint,
//         .connection_state = .Unconnected,
//         .incoming_acknowledge_queue = .{},
//         .pool_allocator = pool,
//         .incoming_fragments = @splat(.empty),
//         .memory_window = @splat(null),
//         .incoming_highest_sequence_indexes = @splat(0),
//         .incoming_order_channels = @splat(null),
//         .incoming_ordering_indexes = @splat(0),
//         .incoming_reliability_index_bit_set = .{},
//         .send_queue = undefined,
//     };

//     const buffer = try pool.alloc(*const raknet.datagram.Segment);
//     // In case of failed initialization we free the allocated memory
//     errdefer pool.destroy(buffer);
//     self.send_queue = .initBuffer(buffer[0..]);
// }

// pub fn deinit(self: *Connection) void {
//     self.connection_state = .Disconnected;
//     self.pool_allocator.destroy(self.send_queue.buffer);

//     // Do not deallocate anything that wasn't allocated in BaseConnection
//     // Clean up any unprocessed fragments
//     for (self.incoming_fragments) |*v| {
//         var iterator = v.iterator();
//         while (iterator.next()) |c|
//             self.pool_allocator.destroy(c);
//     }
//     for (self.memory_window) |window|
//         if (window) |w|
//             self.pool_allocator.destroy(w);
// }

// pub fn handle(self: *Connection, buffer: []const u8) !void {
//     if (self.connection_state == .Disconnected) {
//         @branchHint(.cold);
//         return;
//     }

//     // Ack
//     if (buffer[0] & raknet.datagram.ACKNOWLEDGE_BIT_MASK != 0) {
//         try handleAck(self, buffer);
//         return;
//     }

//     // Nack
//     if (buffer[0] & raknet.datagram.NOT_ACKNOWLEDGE_BIT_MASK != 0) {
//         try handleAck(self, buffer);
//         return;
//     }

//     try handleFrameSet(self, buffer);
// }

// fn handleAck(self: *Connection, buffer: []const u8) !void {
//     _ = self; // autofix

//     var reader: Reader = .init(buffer, 1);

//     const amountOfRanges: u16 = reader.readInt(u16, .big);

//     for (0..amountOfRanges) |_| {
//         const range = try binary.readRange(&reader);

//         for (range.min..range.max + 1) |j| {
//             _ = j; // autofix
//             // TODO
//         }
//     }

//     // Remove from memory_window
// }

// fn handleNack(self: *Connection, buffer: []const u8) !void {
//     _ = self; // autofix

//     var reader: Reader = .init(buffer, 1);

//     const amountOfRanges: u16 = reader.readInt(u16, .big);

//     for (0..amountOfRanges) |_| {
//         const range = try binary.readRange(reader);

//         for (range.max..range.min) |j| {
//             _ = j; // autofix
//             // TODO
//         }
//     }
//     // pop from memory_window, and resent
// }

// fn handleFrameSet(self: *Connection, buffer: []const u8) !void {
//     var reader: Reader = .init(buffer, 1);
//     try reader.assert(3);
//     const sequence_index: u32 = binary.readU24LE(&reader);
//     std.log.info("---------------------------------", .{});
//     std.log.info("SequenceIndex: {}, size: {}", .{ sequence_index, buffer.len });

//     const last_sequence_index = Utils.fixed(self.incoming_acknowledge_queue.head -% 1);
//     const distance = Utils.distance(last_sequence_index, sequence_index);

//     // we have probably lost more packets than even client it self remembers
//     // in that case we just notify disconnect, and remove this connection
//     //
//     // ref: BitRingBuffer.reserve first assert
//     if (distance + @as(i32, @bitCast(self.incoming_acknowledge_queue.len)) > SequencedIndexableBitQueue.RANGE) {
//         std.log.err("Capacity fail: ", .{});
//         //TODO:
//         return;
//     }

//     // late packets, late packets also covers old duplicates
//     //
//     // ref: BitRingBuffer.@etValue first assert sequenceIndex >= tail
//     if (distance < -@as(i32, @bitCast(self.incoming_acknowledge_queue.len))) {
//         std.log.err("BitRingBuffer.@etValue first assert sequenceIndex >= tail, d: {}, {}, {}", .{
//             distance,
//             self.incoming_acknowledge_queue,
//             -@as(i32, @bitCast(self.incoming_acknowledge_queue.len)),
//         });
//         return;
//     }

//     // duplicate packets that are yet not acknowledged
//     //
//     // ref: BitRingBuffer.@etValue second assert sequenceIndex < head
//     if (distance <= 0)
//         if (self.incoming_acknowledge_queue.getValue(sequence_index))
//             return;

//     // 2 -> 5, 2 packets lost
//     //
//     // ref: BitRingBuffer.reserve second assert sIndex >= head
//     if (distance > 0)
//         // This call already sets other bits to zero, meaning the packets were lost
//         self.incoming_acknowledge_queue.reserve(sequence_index);

//     // Set this frame-set as received
//     //
//     // ref: BitRingBuffer.@etValue second assert, head = sequenceIndex + 1 => sequenceIndex < head
//     self.incoming_acknowledge_queue.setValue(sequence_index, true);

//     // gets optimized away
//     var capsule: raknet.datagram.Segment = undefined;
//     while (reader.remaining() > 0) {
//         capsule.read(&reader) catch continue;
//         std.log.info("CAPSULE; Reliability: {}, data: {any}", .{ capsule.delivery_policy, capsule.body });
//         handleFrame(self, &capsule) catch continue;
//     }

//     try updateAcknowledge(self);
// }

// fn handleFrame(self: *Connection, capsule: *raknet.datagram.Segment) !void {
//     // f*ck it, just ignore this sus connection behavior
//     if (capsule.delivery_policy.isSequencedOrdered() and capsule.channel > ORDERED_CHANNELS_COUNT)
//         return error.ChannelOutOfBounds;

//     if (capsule.delivery_policy.isReliable()) {
//         const hole = Utils.distance(capsule.reliableIndex, self.incoming_reliability_index_bit_set.head);

//         // We are missing too many packets to recover the connection
//         // or we got old packet thats too old
//         if (hole + @as(i32, @bitCast(self.incoming_reliability_index_bit_set.len)) > ReliabilityIndexableBitQueue.RANGE or hole < -%@as(i32, @bitCast(self.incoming_reliability_index_bit_set.len)))
//             return error.Unrecoverable;

//         // reserve the space
//         if (hole >= 0) {
//             self.incoming_reliability_index_bit_set.reserve(capsule.reliableIndex);
//         } else if (self.incoming_reliability_index_bit_set.getValue(capsule.reliableIndex)) {
//             // duplicate
//             return error.Duplicate;
//         }
//         self.incoming_reliability_index_bit_set.setValue(capsule.reliableIndex, true);

//         // We got packet as expected
//         if (hole == 0) {
//             @branchHint(.likely);
//             self.incoming_reliability_index_bit_set.head += 1;
//             self.incoming_reliability_index_bit_set.tail += 1;
//         } else if (capsule.reliableIndex == self.incoming_reliability_index_bit_set.tail) {
//             var iterator = self.incoming_reliability_index_bit_set.iterator();
//             // We check if first range is bit set true in that case we can safely move the tail
//             if (iterator.next()) |range|
//                 if (range.bit) {
//                     const size = Utils.distance(range.tail, range.head);
//                     self.incoming_reliability_index_bit_set.tail +%= @bitCast(size);
//                     self.incoming_reliability_index_bit_set.len -%= @bitCast(size);
//                 };
//         }
//     }

//     // The fragment was consumed so we leave early
//     var ref = capsule;
//     if (reassemble(self, &ref))
//         return;

//     const allocated = ref != capsule;
//     _ = allocated; // autofix

//     //////////////////// MY OWN SEPARATOR FOR SEQUENCE/ORDERED SHIT /////////////////////////////////
//     const order_distance = Utils.distance(self.incoming_ordering_indexes[ref.orderChannel], ref.orderingIndex);
//     if (ref.reliability.isSequencedOrdered()) {

//         //ref: Source\ReliabilityLayer.cpp:1282
//         if (order_distance == 0) {
//             if (ref.reliability.isSequenced()) {
//                 // Do we have this implemented? check
//                 // basically discard any older packets
//                 if (Utils.distance(self.incoming_ordering_indexes[ref.orderChannel], ref.orderingIndex) >= 0) {
//                     self.incoming_highest_sequence_indexes[ref.orderChannel] = ref.sequenceIndex + 1;
//                     //TODO: Push packet to receive queue
//                 }
//                 return;
//             }

//             // 128  2048

//             //ref: Source\ReliabilityLayer.cpp:1372
//             self.incoming_ordering_indexes[ref.orderChannel] = Utils.fixed(ref.orderingIndex + 1);
//             self.incoming_highest_sequence_indexes[ref.orderChannel] = 0;

//             const heap = self.incoming_order_channels[ref.orderChannel] orelse try self.pool_allocator.create(MinHeap);
//             while (heap.peek()) |compound| {
//                 if (compound.epoch_id == self.incoming_ordering_indexes[ref.orderChannel]) {
//                     const data = heap.pop();
//                     _ = data; // autofix
//                     // TODO: push data to the send queue and deallocate
//                     //ref: Source\ReliabilityLayer.cpp:1416
//                     if (ref.reliability == .ReliableOrdered) {
//                         self.incoming_ordering_indexes[ref.orderChannel] = Utils.fixed(ref.orderingIndex + 1);
//                     } else {
//                         self.incoming_highest_sequence_indexes[ref.orderChannel] = ref.sequenceIndex;
//                     }
//                 } else break;
//             }
//         } else if (order_distance > 0) {
//             const heap = self.incoming_order_channels[ref.orderChannel] orelse try self.pool_allocator.create(MinHeap);

//             if (heap.len >= heap.buffer.len) {
//                 return error.HeapOutOfMemory;
//             }

//             // We need to allocate and safe the buffer
//             var new_capsule = try self.pool_allocator.create(raknet.datagram.Segment);
//             new_capsule.* = ref.*;
//             new_capsule.body = self.pool_allocator.remaining(raknet.datagram.Segment, new_capsule)[0..ref.body.len];
//             _ = heap.push(.{ .epoch_id = ref.orderingIndex, .snapshot_id = ref.sequenceIndex, .capsule = new_capsule });
//             // datas are buffer up but not ready for processing
//             return;
//         }
//     }

//     if (ref.reliability.isSequenced()) {
//         if (Utils.distance(self.incoming_ordering_indexes[ref.orderChannel], ref.orderingIndex) < 0)
//             return;

//         if (ref.sequenceIndex < self.incoming_highest_sequence_indexes[ref.orderChannel] or
//             ref.orderingIndex < self.incoming_ordering_indexes[ref.orderChannel])
//             return;

//         self.incoming_highest_sequence_indexes[ref.orderChannel] = ref.sequenceIndex + 1;
//         //HandlePayload(data);
//         return;
//     }
// }

// fn reassemble(self: *Connection, ptr: **raknet.datagram.Segment) bool {
//     const capsule = ptr.*;
//     const index: usize = @as(usize, @intCast(capsule.fragment_data.?.id)) % self.incoming_fragments.len;
//     var ref = &self.incoming_fragments[index];
//     if (ref.last) |l| {
//         if (l.fragment_data.?.id != capsule.fragment_data.?.id)
//             std.debug.panic("TODO: fragments array buffer overflow, should we close the connection??", .{});
//     }

//     if (!ref.append(capsule)) unreachable;
//     if (ref.count == capsule.fragment_data.?.count) {
//         std.debug.panic("TODO: build the fragments together and forward it??", .{});
//         // + cleanup
//     }

//     // Rebuild and call handleFrame as well
//     return false;
// }

// // This part reads the buffer to separated one, maybe we should move it only to places we need it
// // var capsule: *FrameSet.CapsuleInfo = self.pool_allocator.create(FrameSet.CapsuleInfo);
// // const body = self.pool_allocator.remaining(FrameSet.CapsuleInfo, capsule)[0..capsule.body.len];
// // @memcpy(body, capsule.body);
// // capsule.body = body;

// fn updateAcknowledge(self: *Connection) !void {
//     var ack_buffer: [1024]u8 = undefined;
//     var nack_buffer: [1024]u8 = undefined;

//     var ack_writer: Writer = .init(&ack_buffer, 0);
//     var ack_count: usize = 0;
//     ack_writer.writeByte(raknet.datagram.ACKNOWLEDGE_PACKED_ID);
//     ack_writer.skip(2);

//     var nack_writer: Writer = .init(&nack_buffer, 0);
//     var nack_count: usize = 0;
//     nack_writer.writeByte(raknet.datagram.NOT_ACKNOWLEDGE_PACKED_ID);
//     nack_writer.skip(2);

//     var iterator = self.incoming_acknowledge_queue.iterator();
//     while (iterator.next()) |range| {
//         const writer: *Writer = if (range.bit) &ack_writer else &nack_writer;
//         const counter: *usize = if (range.bit) &ack_count else &nack_count;
//         counter.* = counter.* + 1;
//         try binary.writeRange(writer, .{
//             .min = range.tail,
//             .max = range.head -% 1,
//         });
//     }

//     const ack = ack_writer.getProcessedBytes();
//     const nack = nack_writer.getProcessedBytes();
//     ack_writer.pointer = 1;
//     ack_writer.writeInt(u16, @intCast(ack_count), .big);
//     nack_writer.pointer = 1;
//     nack_writer.writeInt(u16, @intCast(nack_count), .big);
//     if (ack.len > 3)
//         try self.endpoint.source.send(self.io.*, &self.endpoint.address, ack);
//     if (nack.len > 3)
//         try self.endpoint.source.send(self.io.*, &self.endpoint.address, nack);

//     self.incoming_acknowledge_queue.clear();
// }
