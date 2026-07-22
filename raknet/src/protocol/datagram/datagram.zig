const std = @import("std");

const common = @import("../../common/root.zig");
const Reader = common.Reader;
const Writer = common.Writer;
const binary = common.binary;
const CONSTANTS = @import("../../constants.zig");
const raknet = @import("../root.zig");
const DeliveryPolicy = raknet.DeliveryPolicy;

pub const DATAGRAM_HEADER_SIZE = 4; // packet id + datagram id u24le
pub const BIT_MASK = 0b1000_0000;
const FRAGMENTED_BIT = 0x10;

pub const Segment = struct {
    pub const MetaInfo = struct {
        next: ?*Segment = null,
        alloc: enum { Unknown, Borrowed, SelfContained, External, Stack } = .Unknown,
    };

    pub const FragmentInfo = struct {
        id: u16 = 0,
        count: u32 = 0,
        index: u32 = 0,
    };

    pub const ChannelInfo = struct {
        id: u8 = 0,
        epoch_index: u32 = 0,
        snapshot_index: u32 = 0,
    };

    delivery_policy: DeliveryPolicy,
    reliable_index: u32,
    fragment: ?FragmentInfo = null,
    channel: ChannelInfo,
    body: []const u8,
    // We can use it as linked list when building fragments together
    meta: MetaInfo = .{},

    pub fn read(self: *Segment, reader: *Reader) !void {
        try reader.assert(3);
        const flags = reader.readByte();
        const delivery_policy: DeliveryPolicy = @enumFromInt((flags >> 5) & 0x7);
        self.delivery_policy = delivery_policy;

        const is_fragmented = (flags & FRAGMENTED_BIT != 0);
        // raknet being in bits is just lame
        const data_len = reader.readInt(u16, .big) >> 3;

        if (delivery_policy.isReliable()) {
            try reader.assert(3);
            self.reliable_index = binary.readU24LE(reader);
        }

        if (delivery_policy.hasSnapshot()) {
            try reader.assert(3);
            self.channel.snapshot_index = binary.readU24LE(reader);
        }

        if (delivery_policy.hasEpochOrSnapshot()) {
            try reader.assert(4);
            self.channel.epoch_index = binary.readU24LE(reader);
            self.channel.id = reader.readByte();
        }

        if (is_fragmented) {
            try reader.assert(4 + 2 + 4);
            self.fragment.? = .{
                .count = reader.readInt(u32, .big),
                .id = reader.readInt(u16, .big),
                .index = reader.readInt(u32, .big),
            };
        } else self.fragment = null;

        try reader.assert(data_len);
        self.body = reader.readSlice(data_len);
    }

    pub fn write(self: *const Segment, writer: *Writer) !void {
        var flags: u8 = 0;
        flags |= @intFromEnum(self.delivery_policy) << 5;
        if (self.fragment != null) flags |= FRAGMENTED_BIT;

        try writer.assert(3);
        writer.writeByte(flags);

        // raknet being in bits is just lame
        writer.writeInt(u16, @intCast(self.body.len << 3), .big);

        if (self.delivery_policy.isReliable()) {
            try writer.assert(3);
            binary.writeU24LE(writer, self.reliable_index);
        }

        if (self.delivery_policy.hasSnapshot()) {
            try writer.assert(3);
            binary.writeU24LE(writer, self.channel.snapshot_index);
        }

        if (self.delivery_policy.hasEpochOrSnapshot()) {
            try writer.assert(4);
            binary.writeU24LE(writer, self.channel.epoch_index);
            writer.writeByte(self.channel.id);
        }

        if (self.fragment != null) {
            try writer.assert(4 + 2 + 4);
            writer.writeInt(u32, self.fragment.?.count, .big);
            writer.writeInt(u16, self.fragment.?.id, .big);
            writer.writeInt(u32, self.fragment.?.index, .big);
        }

        try writer.assert(self.body.len);
        writer.append(self.body);
    }

    pub inline fn headerSize(delivery_policy: DeliveryPolicy, is_fragmented: bool) usize {
        var total_size: usize = 0;

        total_size += 3;

        if (delivery_policy.isReliable()) {
            total_size += 3;
        }

        if (delivery_policy.hasSnapshot()) {
            total_size += 3;
        }

        if (delivery_policy.hasEpochOrSnapshot()) {
            total_size += 4;
        }

        if (is_fragmented) {
            total_size += 10;
        }

        return total_size;
    }
};

pub const DatagramMemory = struct {
    segments_len: usize = 0,
    offset: usize = 0,
    tick: usize = 0,
    segments: [8]Segment = undefined,
    buffer: [CONSTANTS.MAX_MTU_SIZE]u8,

    pub fn clear(self: *@This()) void {
        self.segments_len = 0;
        self.offset = 0;
    }
};

comptime {
    if (@sizeOf(DatagramMemory) > CONSTANTS.MAX_MTU_FRAME_SIZE)
        @compileError("Architecture fail, DatagramMemory has to fit in single frame");
}
