const std = @import("std");

const common = @import("../../common/root.zig");
const Reader = common.Reader;
const binary = common.binary;
const raknet = @import("../root.zig");
const DeliveryPolicy = raknet.DeliveryPolicy;

pub const BIT_MASK = 0b1000_0000;
const FRAGMENTED_BIT = 0x10;

pub const Segment = struct {
    delivery_policy: DeliveryPolicy,
    reliable_index: u32,
    fragment: ?struct {
        id: u16,
        count: u32,
        index: u32,
    },
    channel: struct {
        id: u8,
        epoch_index: u32,
        snapshot_index: u32,
    },
    body: []const u8,
    // We can use it as linked list when building fragments together
    next: ?*Segment = null,

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

        if (delivery_policy.isSequenced()) {
            try reader.assert(3);
            self.channel.snapshot_index = binary.readU24LE(reader);
        }

        if (delivery_policy.isSequencedOrdered()) {
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
        }

        try reader.assert(data_len);
        self.body = reader.readSlice(data_len);
    }
};
