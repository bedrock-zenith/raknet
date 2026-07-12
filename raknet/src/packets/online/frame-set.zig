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
    },
    orderingIndex: u32,
    reliableIndex: u32,
    sequenceIndex: u32,
    body: []const u8,

    pub fn read(self: *CapsuleInfo, reader: *Reader) !void {
        const flags = try reader.readByte();
        const reliability: CapsuleReliability = @enumFromInt((flags >> 5) & 0x7);
        self.reliability = reliability;

        const is_fragmented = (flags & FRAGMENTED_BIT != 0);
        // raknet being in bits is just lame
        const data_len = (try reader.readInt(u16, .big)) >> 3;

        if (reliability.isReliable())
            self.reliableIndex = try meta.readU24LE(reader);

        if (reliability.isSequenced())
            self.sequenceIndex = try meta.readU24LE(reader);

        if (reliability.isSequencedOrdered()) {
            self.orderingIndex = try meta.readU24LE(reader);
            self.orderChannel = try reader.readByte();
        }

        if (is_fragmented) {
            self.fragment_data.? = .{
                .count = try reader.readInt(u32, .big),
                .id = try reader.readInt(u16, .big),
                .index = try reader.readInt(u32, .big),
            };
        }

        self.body = try reader.readSlice(data_len);
    }
};
