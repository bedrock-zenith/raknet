const std = @import("std");

const Reader = @import("../../common/cursor.zig").Reader;
const meta = @import("../../common/meta.zig");

const FRAGMENTED_BIT = 0x10;
pub const FrameHeader = struct {};

pub const CapsuleReliability = enum(u8) {
    Unreliable = 0,
    UnreliableSequenced = 1,
    Reliable = 2,
    ReliableOrdered = 3,
    ReliableSequenced = 4,
    UnreliableWithAckReceipt = 5,
    ReliableWithAckReceipt = 6,
    ReliableOrderedWithAckReceipt = 7,

    pub inline fn isReliable(reliability: CapsuleReliability) bool {
        return switch (reliability) {
            .Reliable => true,
            .ReliableOrdered => true,
            .ReliableSequenced => true,
            .ReliableWithAckReceipt => true,
            else => false,
        };
    }
    pub inline fn isSequenced(reliability: CapsuleReliability) bool {
        return switch (reliability) {
            .UnreliableSequenced => true,
            .ReliableSequenced => true,
            else => false,
        };
    }
    pub inline fn isSequencedOrdered(reliability: CapsuleReliability) bool {
        return switch (reliability) {
            .UnreliableSequenced => true,
            .ReliableOrdered => true,
            .ReliableSequenced => true,
            .ReliableOrderedWithAckReceipt => true,
            else => false,
        };
    }
    pub inline fn isOrdered(reliability: CapsuleReliability) bool {
        return switch (reliability) {
            .ReliableOrdered => true,
            .ReliableOrderedWithAckReceipt => true,
            else => false,
        };
    }
};

pub const CapsuleInfo = struct {
    reliability: CapsuleReliability,
    orderChannel: u8,
    fragment_data: ?struct {
        id: u16,
        count: u32,
        index: u32,
        // We can use it as linked list when building fragments together
        next: ?*CapsuleInfo = null,
    },
    orderingIndex: u32,
    reliableIndex: u32,
    sequenceIndex: u32,
    body: []const u8,

    pub fn read(self: *CapsuleInfo, reader: *Reader) !void {
        try reader.assert(3);
        const flags = reader.readByte();
        const reliability: CapsuleReliability = @enumFromInt((flags >> 5) & 0x7);
        self.reliability = reliability;

        const is_fragmented = (flags & FRAGMENTED_BIT != 0);
        // raknet being in bits is just lame
        const data_len = reader.readInt(u16, .big) >> 3;

        if (reliability.isReliable()) {
            try reader.assert(3);
            self.reliableIndex = meta.readU24LE(reader);
        }

        if (reliability.isSequenced()) {
            try reader.assert(3);
            self.sequenceIndex = meta.readU24LE(reader);
        }

        if (reliability.isSequencedOrdered()) {
            try reader.assert(4);
            self.orderingIndex = meta.readU24LE(reader);
            self.orderChannel = reader.readByte();
        }

        if (is_fragmented) {
            try reader.assert(4 + 2 + 4);
            self.fragment_data.? = .{
                .next = null,
                .count = reader.readInt(u32, .big),
                .id = reader.readInt(u16, .big),
                .index = reader.readInt(u32, .big),
            };
        }

        try reader.assert(data_len);
        self.body = reader.readSlice(data_len);
    }
};
