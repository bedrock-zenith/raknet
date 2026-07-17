const std = @import("std");

const common = @import("../../common/root.zig");
const Reader = common.Reader;
const binary = common.binary;
const raknet = @import("../root.zig");
const Reliability = raknet.Reliability;

pub const BIT_MASK = 0b1000_0000;
const FRAGMENTED_BIT = 0x10;

pub const Capsule = struct {
    reliability: Reliability,
    orderChannel: u8,
    fragment_data: ?struct {
        id: u16,
        count: u32,
        index: u32,
    },
    orderingIndex: u32,
    reliableIndex: u32,
    sequenceIndex: u32,
    body: []const u8,
    // We can use it as linked list when building fragments together
    next: ?*Capsule = null,

    pub fn read(self: *Capsule, reader: *Reader) !void {
        try reader.assert(3);
        const flags = reader.readByte();
        const reliability: Reliability = @enumFromInt((flags >> 5) & 0x7);
        self.reliability = reliability;

        const is_fragmented = (flags & FRAGMENTED_BIT != 0);
        // raknet being in bits is just lame
        const data_len = reader.readInt(u16, .big) >> 3;

        if (reliability.isReliable()) {
            try reader.assert(3);
            self.reliableIndex = binary.readU24LE(reader);
        }

        if (reliability.isSequenced()) {
            try reader.assert(3);
            self.sequenceIndex = binary.readU24LE(reader);
        }

        if (reliability.isSequencedOrdered()) {
            try reader.assert(4);
            self.orderingIndex = binary.readU24LE(reader);
            self.orderChannel = reader.readByte();
        }

        if (is_fragmented) {
            try reader.assert(4 + 2 + 4);
            self.fragment_data.? = .{
                .count = reader.readInt(u32, .big),
                .id = reader.readInt(u16, .big),
                .index = reader.readInt(u32, .big),
            };
        }

        try reader.assert(data_len);
        self.body = reader.readSlice(data_len);
    }
};
