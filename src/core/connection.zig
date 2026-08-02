//  SPDX-License-Identifier: LGPL-3.0-or-later
//  ============================================================================
//   Zenith Raknet - Minecraft Bedrock Raknet
//   Copyright (C) 2026 Bedrock Zenith
//   https://github.com/bedrock-zenith/raknet
//  ============================================================================
//  
//  This file is part of Zenith Raknet.
//  
//  Zenith Raknet is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Lesser General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//  
//  Zenith Raknet is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU Lesser General Public License for more details.
//  
//  You should have received a copy of the GNU Lesser General Public License
//  along with Zenith Raknet. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Utils = @import("../24/root.zig").Utils;
const BitWindow = @import("../24/root.zig").BitWindow;
const Window = @import("../24/window.zig").Window;
const common = @import("../common/root.zig");
const Reader = common.Reader;
const Writer = common.Writer;
const binary = common.binary;
const CONSTANTS = @import("../constants.zig");
const raknet = @import("../protocol/root.zig");
const Segment = raknet.datagram.Segment;
const logger = @import("../root.zig").raknet_logger;
const ConnectionState = @import("connection-state.zig").ConnectionState;
const Endpoint = @import("endpoint.zig");
const FragmentBuilder = @import("fragment-builder.zig");
const PoolAllocator = @import("root.zig").FramePool;

const DatagramWindow = BitWindow(CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE);
const DatagramMemoryWindow = Window(?*raknet.datagram.DatagramMemory, CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE);
const ReliableWindow = BitWindow(CONSTANTS.UNACKNOWLEDGED_WINDOWS_SIZE * 4);
const CHANNELS_COUNT = 16;
const PARALLEL_FRAGMENT_BUILDERS = 32;
const RECEIVE_BUFFER = 128;
const DATAGRAM_ACKNOWLEDGE_TIMEOUT_TICKS = 3000;
const UPDATE_ACKNOWLEDGE_DELAY_TICKS = 30;
const FLUSH_WRITER_DELAY_TICKS = 5;

const Connection = @This();
io: std.Io,
mtu: u16,
guid: u64,
current_tick: usize,
rx_last_tick: usize,
tx_last_ack_tick: usize,
state: ConnectionState,
endpoint: Endpoint,
pool_allocator: *PoolAllocator,
gpa: Allocator,

rx_datagram_window: DatagramWindow,
rx_reliable_window: ReliableWindow,
rx_fragment_builder: [PARALLEL_FRAGMENT_BUILDERS]FragmentBuilder,
rx_channels: [CHANNELS_COUNT]Channel,
rx_received: std.Deque(*Segment),

tx_reliable_index: u32,
tx_fragment_index: u16,
tx_datagram_writer: ?*raknet.datagram.DatagramMemory,
tx_buffer_main: std.Deque(*raknet.datagram.DatagramMemory),
tx_buffer_urgent: std.Deque(*raknet.datagram.DatagramMemory),
tx_datagram_window: DatagramMemoryWindow,
tx_channels: [CHANNELS_COUNT]Channel,
tx_send: std.Deque([]u8),

pub fn init(
    self: *Connection,
    io: std.Io,
    pool: *PoolAllocator,
    gpa: Allocator,
    endpoint: Endpoint,
    connection_tick: usize,
    guid: u64,
    mtu: u16,
) Allocator.Error!void {
    self.* = .{
        .io = io,
        .guid = guid,
        .state = .Unconnected,
        .endpoint = endpoint,
        .pool_allocator = pool,
        .gpa = gpa,
        .mtu = mtu,
        .rx_last_tick = connection_tick,
        .current_tick = connection_tick,
        .tx_last_ack_tick = connection_tick,

        // rx
        .rx_datagram_window = .{},
        .rx_reliable_window = .{},
        .rx_fragment_builder = @splat(.empty),
        .rx_channels = @splat(.{}),

        // tx
        .tx_datagram_window = .{
            .buffer = @splat(null),
        },
        .tx_channels = @splat(.{}),
        .tx_reliable_index = 0,
        .tx_fragment_index = 0,
        .tx_datagram_writer = null,

        // post setup
        .rx_received = undefined,
        .tx_buffer_main = undefined,
        .tx_buffer_urgent = undefined,
        .tx_send = undefined,
    };
    self.rx_received = try .initCapacity(self.gpa, 512);
    errdefer self.rx_received.deinit(self.gpa);

    self.tx_buffer_main = try .initCapacity(self.gpa, 512);
    errdefer self.tx_buffer_main.deinit(self.gpa);

    self.tx_buffer_urgent = try .initCapacity(self.gpa, 512);
    errdefer self.tx_buffer_urgent.deinit(self.gpa);

    self.tx_send = try .initCapacity(self.gpa, 16);
    errdefer self.tx_send.deinit(self.gpa);
}

/// This function might and might not free segment data or segment it self
pub fn deinit(self: *Connection) void {
    const pool = self.pool_allocator;
    const gpa = self.gpa;

    var rx_received_iterator = self.rx_received.iterator();
    while (rx_received_iterator.next()) |segment| {
        destroySegment(pool, gpa, segment);
    }

    self.rx_received.deinit(self.gpa);

    // Do not deallocate anything that wasn't allocated in BaseConnection
    // Clean up any unprocessed fragments
    for (&self.rx_fragment_builder) |*v| {
        if (v.last == null) continue;
        var iterator = v.iterator();
        while (iterator.next()) |segment|
            destroySegment(pool, gpa, segment);
    }

    for (&self.rx_channels) |*channel| {
        if (channel.heap) |heap| {
            for (0..heap.len) |i| {
                const segment = heap.buffer[i];
                destroySegment(pool, gpa, segment.segment);
            }

            gpa.destroy(heap);
        }
    }

    // tx
    var tx_datagram_window_iterator = self.tx_datagram_window.iterator();
    while (tx_datagram_window_iterator.next()) |item| if (item) |window| {
        // debug purposes
        if (@import("builtin").mode == .Debug)
            for (0..window.segments_len) |i|
                std.debug.assert(window.segments[i].meta.alloc.data == .contained);

        pool.destroy(window);
    };

    inline for (.{ &self.tx_buffer_main, &self.tx_buffer_urgent }) |queue| {
        var iterator = queue.iterator();
        while (iterator.next()) |window|
            pool.destroy(window);

        queue.deinit(gpa);
    }

    if (self.tx_datagram_writer) |writer| {
        pool.destroy(writer);
        self.tx_datagram_writer = null;
    }

    while (self.tx_send.popFront()) |buffer|
        pool.destroy(buffer.ptr);

    self.tx_send.deinit(gpa);
}

pub const RxFragmentBuilderOutOfMemoryError = error{FragmentBuilderOutOfMemory};
pub const RxInvalidPacketError = error{InvalidPacket};
pub const RxError = error{ Unrecoverable, ChannelOutOfBounds } || RxInvalidPacketError || RxFragmentBuilderOutOfMemoryError;

pub fn tick(self: *Connection, tick_id: usize) Allocator.Error!void {
    self.current_tick = tick_id;

    if (tick_id > self.tx_last_ack_tick + UPDATE_ACKNOWLEDGE_DELAY_TICKS) {
        self.tx_last_ack_tick = tick_id;
        try self.txFlushAcknowlege();
    }

    if (self.tx_datagram_writer) |writer| {
        if (writer.segments_len > 0 and tick_id > writer.tick + FLUSH_WRITER_DELAY_TICKS) {
            _ = try txFlushWriter(self);
        }
    }

    _ = try txFlushWindow(self);
}

pub fn receive(self: *Connection, datagram: []const u8) (RxError || Allocator.Error)!void {
    self.rx_last_tick = self.current_tick;
    if (self.state == .Disconnected) {
        @branchHint(.cold);
        return;
    }

    if (datagram[0] & (raknet.datagram.ACKNOWLEDGE_BIT_MASK | raknet.datagram.NOT_ACKNOWLEDGE_BIT_MASK) != 0)
        return try rxAcknowledge(self, datagram);

    try rxDatagram(self, datagram);
}

fn rxAcknowledge(self: *Connection, datagram: []const u8) (RxInvalidPacketError || Allocator.Error)!void {
    var reader: Reader = .init(datagram, 1);
    reader.assert(3) catch return error.InvalidPacket;
    const is_nack = datagram[0] & raknet.datagram.NOT_ACKNOWLEDGE_BIT_MASK != 0;

    const count: u16 = reader.readInt(u16, .big);

    for (0..count) |_| {
        const range = binary.readRange(&reader) catch return error.InvalidPacket;
        var offset = range.min;
        const distance = Utils.distance(range.min, range.max);
        if (distance < 0) continue;
        if (distance > 1024) return error.InvalidPacket;

        for (0..@intCast(distance + 1)) |_| {
            const index = offset;
            offset = Utils.fixed(offset + 1);
            if (self.tx_datagram_window.includes(index)) {
                const ptr = index % self.tx_datagram_window.buffer.len;

                const datagram_element = self.tx_datagram_window.buffer[ptr] orelse continue;

                self.tx_datagram_window.buffer[ptr] = null;

                if (is_nack) {
                    try self.tx_buffer_urgent.pushBack(self.gpa, datagram_element);
                } else {
                    self.pool_allocator.destroy(datagram_element);
                }
            }
        }
    }

    try txCleanDatagramWindow(self);
}

fn txCleanDatagramWindow(self: *Connection) Allocator.Error!void {
    while (self.tx_datagram_window.len > 0) {
        const datagram = self.tx_datagram_window.peek() orelse {
            _ = self.tx_datagram_window.pop();
            continue;
        };

        if (self.current_tick < datagram.tick + DATAGRAM_ACKNOWLEDGE_TIMEOUT_TICKS) break;

        _ = self.tx_datagram_window.pop();
        try self.tx_buffer_urgent.pushBack(self.gpa, datagram);
    }
}

fn rxDatagram(self: *Connection, datagram: []const u8) (RxError || Allocator.Error)!void {
    var reader: Reader = .init(datagram, 1);
    reader.assert(3) catch return error.InvalidPacket;
    const datagram_index: u32 = binary.readU24LE(&reader);

    const last_datagram_index = Utils.fixed(self.rx_datagram_window.head -% 1);
    const distance = Utils.distance(last_datagram_index, datagram_index);

    // we have probably lost more packets than even client it self remembers
    // in that case we just notify disconnect, and remove this connection
    //
    // ref: BitWindow.reserve first assert
    if (distance > @as(i32, @bitCast(self.rx_datagram_window.available()))) {
        logger.err("Capacity fail: ", .{});
        return error.Unrecoverable;
    }

    // late packets, late packets also covers old duplicates
    //
    // ref: BitWindow.@etValue first assert sequenceIndex >= tail
    if (distance < -@as(i32, @bitCast(self.rx_datagram_window.len))) {
        logger.err("BitRingBuffer.@etValue first assert sequenceIndex >= tail, d: {}, {}, {}", .{
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
    var segment: Segment = undefined;
    while (reader.remaining() > 0) {
        segment.read(&reader) catch return error.InvalidPacket;
        segment.meta.alloc = .{ .data = .borrowed, .self = .borrowed };
        rxSegment(self, &segment) catch |err| switch (err) {
            error.ChannelOutOfBounds => continue,
            else => return err,
        };
    }
}

fn rxSegment(self: *Connection, input: *const Segment) (RxError || Allocator.Error)!void {

    // f*ck it, just ignore this sus connection behavior
    if (input.delivery_policy.hasEpochOrSnapshot() and input.channel.id > CHANNELS_COUNT)
        return error.ChannelOutOfBounds;

    ////////// RELIABILITY SHI //////////

    if (input.delivery_policy.isReliable()) {
        const hole = Utils.distance(self.rx_reliable_window.head, input.reliable_index);

        // We are missing too many packets to recover the connection
        if (hole > @as(i32, @bitCast(self.rx_reliable_window.available())))
            return error.Unrecoverable;

        // or we got old packet thats too old, we don't really care about that one
        if (hole < -%@as(i32, @bitCast(self.rx_reliable_window.len)))
            return;

        // reserve enough space
        if (hole >= 0)
            self.rx_reliable_window.reserve(input.reliable_index);

        // check for duplicates
        if (self.rx_reliable_window.getValue(input.reliable_index)) return;

        self.rx_reliable_window.setValue(input.reliable_index, true);

        // We got packet as expected
        if (hole == 0) {
            @branchHint(.likely);
            self.rx_reliable_window.head = Utils.fixed(self.rx_reliable_window.head + 1);
            self.rx_reliable_window.tail = Utils.fixed(self.rx_reliable_window.tail + 1);
        }

        // clean and slice the window
        // we check if first range is bit set true
        // in that case we can safely move the tail
        else if (input.reliable_index == self.rx_reliable_window.tail) {
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

    var segment: *Segment = undefined;
    if (input.fragment) |fragment| {
        segment = try rxFragment(self, fragment, input) orelse return;
    } else segment = try allocSegment(self, input);

    ////////// EPOCH & SNAPSHOT SHI //////////

    if (segment.delivery_policy.hasEpochOrSnapshot()) {
        var channel = &self.rx_channels[segment.channel.id];
        const epoch_distance = Utils.distance(channel.epoch_index, segment.channel.epoch_index);
        if (epoch_distance == 0) {
            // old epoch new snapshot
            if (segment.delivery_policy.hasSnapshot()) {
                if (Utils.distance(channel.snapshot_index, segment.channel.snapshot_index) < 0) {
                    destroySegment(self.pool_allocator, self.gpa, segment);
                    // Old snapshots are ignored
                    return;
                }

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

                    try rxFinalize(self, element.segment);
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
                channel.heap = new_heap;
                break :return_heap new_heap;
            };

            _ = heap.push(.{
                .epoch_id = segment.channel.epoch_index,
                .snapshot_id = segment.channel.snapshot_index,
                .segment = segment,
            });

            return;
        }

        // old epoch that was already resolved
        // should be already discarded by reliability
        // but its good to cover the worse scenarios
        else {
            destroySegment(self.pool_allocator, self.gpa, segment);
            return;
        }
    }

    ////////// UNRELIABLE SHI //////////

    try rxFinalize(self, segment);
}

fn rxFragment(self: *Connection, fragment: Segment.FragmentInfo, input_segment: *const Segment) (RxFragmentBuilderOutOfMemoryError || Allocator.Error)!?*Segment {
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

    const segment = try allocSegment(self, input_segment);
    _ = builder.append(segment);

    if (fragment.count == builder.count) {
        var iterator = builder.iterator();
        var buffer = try self.gpa.alloc(u8, builder.buffer_size);

        var offset: usize = 0;
        while (iterator.next()) |seg| {
            @memcpy(buffer[offset .. offset + seg.body.len], seg.body);
            offset += seg.body.len;
            if (seg != segment)
                self.pool_allocator.destroy(seg);
        }

        // we assert from lines above that body is self_contained as segment was allocated
        segment.body = buffer;
        segment.meta.alloc.data = .allocated;
        return segment;
    }

    return null;
}

fn rxFinalize(self: *Connection, segment: *Segment) Allocator.Error!void {
    std.debug.assert(segment.meta.alloc.self == .allocated);
    try self.rx_received.pushBack(self.gpa, segment);
}

/// This function might and might not free segment data or segment it self
pub fn destroySegment(pool_allocator: *PoolAllocator, gpa_allocator: std.mem.Allocator, segment: *Segment) void {
    switch (segment.meta.alloc.data) {
        .allocated => gpa_allocator.free(segment.body),
        .borrowed, .contained => {},
    }

    switch (segment.meta.alloc.self) {
        .allocated => pool_allocator.destroy(segment),
        .borrowed, .contained => {},
    }
}

fn allocSegment(self: *const Connection, segment: *const Segment) Allocator.Error!*Segment {
    var allocated_segment = try self.pool_allocator.create(Segment);
    allocated_segment.* = segment.*;

    const bytes = self.pool_allocator.remaining(Segment, allocated_segment)[0..segment.body.len];
    allocated_segment.body = bytes;
    @memcpy(bytes, segment.body);
    allocated_segment.meta.alloc = .{ .data = .contained, .self = .allocated };
    return allocated_segment;
}

/// This method does not borrow the data buffer, after this method is called you are free to use data again
pub fn send(self: *Connection, data: []const u8) Allocator.Error!void {
    // Parameters candidates shi
    const channel_id = 0;
    const delivery_policy: raknet.DeliveryPolicy = .ReliableOrdered;

    const DHS = raknet.datagram.DATAGRAM_HEADER_SIZE;
    const space: usize = @intCast(self.mtu - CONSTANTS.UDP_HEADER_SIZE);
    const header: usize = DHS + Segment.headerSize(delivery_policy, false);

    var channel = &self.tx_channels[channel_id];

    var segment: Segment = .{
        .delivery_policy = delivery_policy,
        .channel = .{
            .id = channel_id,
            .epoch_index = channel.epoch_index,
            .snapshot_index = channel.snapshot_index,
        },
        .fragment = null,
        .body = data,

        // Unused
        .meta = .{
            .alloc = .{
                // stack-allocated, we don't want to be freed or lost
                .self = .borrowed,
                // its data are literally borrowed
                .data = .borrowed,
            },
        },
        .reliable_index = undefined,
    };

    if (delivery_policy.hasSnapshot()) {
        channel.snapshot_index = Utils.fixed(channel.snapshot_index +% 1);
    } else if (delivery_policy.hasEpoch()) {
        channel.epoch_index = Utils.fixed(channel.epoch_index +% 1);
        channel.snapshot_index = 0;
    }

    if (header + data.len <= space) {
        if (delivery_policy.isReliable()) {
            segment.reliable_index = self.tx_reliable_index;
            self.tx_reliable_index = Utils.fixed(self.tx_reliable_index +% 1);
        }

        try txQueue(self, &segment);
        return;
    }

    // is reliable required for fragments
    std.debug.assert(segment.delivery_policy.isReliable());

    const max_chunk_size = self.mtu - DHS - Segment.headerSize(delivery_policy, true);
    // @divCeil
    const fragment_count = @divFloor(data.len - 1, max_chunk_size) + 1;
    segment.fragment = .{
        .id = self.tx_fragment_index,
        .count = @intCast(fragment_count),
        .index = 0,
    };

    self.tx_fragment_index +%= 1;

    for (0..fragment_count) |index| {
        if (delivery_policy.isReliable()) {
            segment.reliable_index = self.tx_reliable_index;
            self.tx_reliable_index = Utils.fixed(self.tx_reliable_index +% 1);
        }

        segment.fragment.?.index = @intCast(index);

        const offset = max_chunk_size * index;
        const offset_end = @min(max_chunk_size * (index +% 1), data.len);
        segment.body = data[offset..offset_end];

        try txQueue(self, &segment);
    }
}

fn txQueue(self: *Connection, segment: *const Segment) Allocator.Error!void {
    var tx_writer = self.tx_datagram_writer orelse alloc: {
        const new = try allocDatagramMemory(self);
        self.tx_datagram_writer = new;
        break :alloc new;
    };

    if (tx_writer.segments_len >= tx_writer.segments.len) {
        tx_writer = try txFlushWriter(self);
    }

    if (tx_writer.offset + segment.body.len >= tx_writer.buffer.len) {
        tx_writer = try txFlushWriter(self);
    }

    const index = tx_writer.segments_len;
    tx_writer.segments[index] = segment.*;
    tx_writer.segments_len = index +% 1;

    const new_buffer = tx_writer.buffer[tx_writer.offset..][0..segment.body.len];
    @memcpy(new_buffer, segment.body);
    tx_writer.segments[index].body = new_buffer;
    // both data and segments are part of the same memory block inside the datagram_memory structure
    tx_writer.segments[index].meta.alloc = .{ .data = .contained, .self = .contained };
    tx_writer.offset +%= new_buffer.len;

    if (tx_writer.segments_len >= tx_writer.segments.len)
        _ = try txFlushWriter(self);
}

fn txFlushWriter(self: *Connection) Allocator.Error!*raknet.datagram.DatagramMemory {
    var tx_writer = self.tx_datagram_writer orelse {
        const txw = try allocDatagramMemory(self);
        self.tx_datagram_writer = txw;
        return txw;
    };

    if (tx_writer.segments_len == 0)
        return tx_writer;

    try self.tx_buffer_main.pushBack(self.gpa, tx_writer);
    tx_writer = try allocDatagramMemory(self);
    self.tx_datagram_writer = tx_writer;
    return tx_writer;
}

fn txFlushWindow(self: *Connection) Allocator.Error!bool {
    var flushed = false;
    while (self.tx_datagram_window.available() != 0) {
        var reliable_only = false;

        // first flush the ack/nack shi
        var data_memory: *raknet.datagram.DatagramMemory = undefined;
        if (self.tx_buffer_urgent.popFront()) |data| {
            data_memory = data;
            reliable_only = true;
        } else if (self.tx_buffer_main.popFront()) |data| {
            data_memory = data;
        } else break;

        errdefer self.pool_allocator.destroy(data_memory);

        if (try txRawSend(self, data_memory, self.tx_datagram_window.head, reliable_only)) {
            data_memory.tick = self.current_tick;
            _ = self.tx_datagram_window.push(data_memory);
        } else {
            self.pool_allocator.destroy(data_memory);
        }

        flushed = true;
    }

    return flushed;
}

/// Returns true if state changed
pub fn txFlush(self: *Connection) Allocator.Error!bool {
    _ = try txFlushWriter(self);
    _ = try txFlushWindow(self);
}

/// Force send last packet before connection is destroyed
pub fn txHarakiry(self: *Connection, data: []const u8) Allocator.Error!void {
    var datagram: raknet.datagram.DatagramMemory = .{
        .buffer = undefined,
        .offset = 0,
        .segments_len = 1,
        .segments = undefined,
    };

    datagram.segments[0] = .{
        .delivery_policy = .Reliable,
        .reliable_index = self.tx_reliable_index,
        .body = data,
        .fragment = null,
        .channel = undefined,
    };

    self.tx_reliable_index +%= 1;
    self.state = .Harakiry;
    _ = try txRawSend(self, &datagram, self.tx_datagram_window.head, false);
}

fn txRawSend(self: *Connection, datagram: *const raknet.datagram.DatagramMemory, datagram_index: u32, reliable_only: bool) Allocator.Error!bool {
    const buffer: *[2048]u8 = try self.pool_allocator.rent();
    var writer: Writer = .init(buffer, 0);

    writer.writeByte(raknet.datagram.DATAGRAM_BIT_MASK | 4);
    binary.writeU24LE(&writer, datagram_index);

    for (0..datagram.segments_len) |i| {
        const segment = &datagram.segments[i];

        if (reliable_only and !segment.delivery_policy.isReliable())
            continue;

        // We assert the this method is called after framing is done anyway
        segment.write(&writer) catch unreachable;
    }

    // no data to send
    if (writer.pointer == raknet.datagram.DATAGRAM_HEADER_SIZE) return false;

    try self.tx_send.pushBack(self.gpa, writer.getProcessedBytes());
    // try self.endpoint.send(self.io.*, writer.getProcessedBytes());

    return true;
}

fn allocDatagramMemory(self: *Connection) Allocator.Error!*raknet.datagram.DatagramMemory {
    var writer = try self.pool_allocator.create(raknet.datagram.DatagramMemory);
    writer.clear();
    writer.tick = self.current_tick;

    return writer;
}

pub fn txFlushAcknowlege(self: *Connection) Allocator.Error!void {
    const AckMeta = struct {
        ack: bool,
        buffer: []u8 = undefined,
        writer: Writer = undefined,
        count: usize = 0,
        pub inline fn reinitialize(this: *@This(), pool: *PoolAllocator) !void {
            this.buffer = try pool.rent();
            this.writer = .init(this.buffer, 3);
            this.count = 0;
        }
        pub inline fn finalize(this: *@This()) []u8 {
            const buf = this.writer.getProcessedBytes();
            this.writer.pointer = 0;
            this.writer.writeByte(if (this.ack) raknet.datagram.ACKNOWLEDGE_PACKED_ID else raknet.datagram.NOT_ACKNOWLEDGE_PACKED_ID);
            this.writer.writeInt(u16, @intCast(this.count), .big);
            return buf;
        }
    };

    var ack: AckMeta = .{ .ack = true, .buffer = &.{} };
    try ack.reinitialize(self.pool_allocator);
    errdefer {
        if (ack.buffer.len > 0) self.pool_allocator.destroy(ack.buffer.ptr);
    }

    var nack: AckMeta = .{ .ack = false };
    try nack.reinitialize(self.pool_allocator);
    errdefer {
        if (nack.buffer.len > 0) self.pool_allocator.destroy(nack.buffer.ptr);
    }

    var iterator = self.rx_datagram_window.iterator();
    var next = iterator.next();

    state: switch (enum { Next, Finalize, Flush }.Next) {
        .Next => if (next) |range| {
            const meta: *AckMeta = if (range.bit) &ack else &nack;
            meta.count +%= 1;

            // try to write and flush if it doesn't fit the buffers
            binary.writeRange(&meta.writer, .{
                .min = range.tail,
                .max = range.head -% 1,
            }) catch continue :state .Flush;

            next = iterator.next();
            continue :state .Next;
        } else continue :state .Finalize,
        .Flush => {
            const meta: *AckMeta = if (ack.writer.remaining() <= 7) &ack else &nack;
            const buff = meta.finalize();
            try self.tx_send.pushBack(self.gpa, buff);
            try meta.reinitialize(self.pool_allocator);
            continue :state .Next;
        },
        .Finalize => {
            inline for (.{ &ack, &nack }) |meta| {
                const buff = meta.finalize();
                if (buff.len > 3) {
                    try self.tx_send.pushBack(self.gpa, buff);
                    meta.buffer = &.{};
                } else {
                    self.pool_allocator.destroy(meta.buffer.ptr);
                    meta.buffer = &.{};
                }
            }
        },
    }

    // var iterator = self.rx_datagram_window.iterator();
    // var next = iterator.next();
    // while (next) {
    //     const ack_buffer: *[1024]u8 = try self.pool_allocator.rent();
    //     errdefer self.pool_allocator.destroy(ack_buffer);
    //     const nack_buffer: *[1024]u8 = try self.pool_allocator.rent();
    //     errdefer self.pool_allocator.deinit(nack_buffer);

    //     var ack_writer: Writer = .init(ack_buffer, 0);
    //     var ack_count: usize = 0;
    //     ack_writer.writeByte(raknet.datagram.ACKNOWLEDGE_PACKED_ID);
    //     ack_writer.skip(2);

    //     var nack_writer: Writer = .init(nack_buffer, 0);
    //     var nack_count: usize = 0;
    //     nack_writer.writeByte(raknet.datagram.NOT_ACKNOWLEDGE_PACKED_ID);
    //     nack_writer.skip(2);

    //     while (next) |range| {
    //         const writer: *Writer = if (range.bit) &ack_writer else &nack_writer;
    //         const counter: *usize = if (range.bit) &ack_count else &nack_count;
    //         counter.* = counter.* + 1;

    //         // try to write and break if it doesn't fit the buffers
    //         binary.writeRange(writer, .{
    //             .min = range.tail,
    //             .max = range.head -% 1,
    //         }) catch break;

    //         next = iterator.next();
    //     }

    //     const ack: []u8 = ack_writer.getProcessedBytes();
    //     const nack: []u8 = nack_writer.getProcessedBytes();
    //     ack_writer.pointer = 1;
    //     ack_writer.writeInt(u16, @intCast(ack_count), .big);
    //     nack_writer.pointer = 1;
    //     nack_writer.writeInt(u16, @intCast(nack_count), .big);

    //     if (ack.len > 3) {
    //         self.tx_send.pushBack(self.gpa_allocator, ack) catch self.pool_allocator.destroy(ack.ptr);
    //     } else {
    //         self.pool_allocator.destroy(ack.ptr);
    //     }

    //     if (nack.len > 3) {
    //         self.tx_send.pushBack(self.gpa_allocator, nack) catch self.pool_allocator.destroy(nack.ptr);
    //     } else {
    //         self.pool_allocator.destroy(nack.ptr);
    //     }
    // }

    self.rx_datagram_window.clear();
}

const EpochMinHeapElement = struct {
    epoch_id: u32 = 0,
    snapshot_id: u32 = 0,
    segment: *Segment,

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
