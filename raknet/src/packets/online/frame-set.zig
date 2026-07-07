const std = @import("std");

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
};
