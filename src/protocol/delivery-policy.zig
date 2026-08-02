pub const DeliveryPolicy = enum(u8) {
    Unreliable = 0,
    UnreliableSequenced = 1,
    Reliable = 2,
    ReliableOrdered = 3,
    ReliableSequenced = 4,
    UnreliableWithAckReceipt = 5,
    ReliableWithAckReceipt = 6,
    ReliableOrderedWithAckReceipt = 7,

    pub inline fn isReliable(reliability: DeliveryPolicy) bool {
        return switch (reliability) {
            .Reliable => true,
            .ReliableOrdered => true,
            .ReliableSequenced => true,
            .ReliableWithAckReceipt => true,
            else => false,
        };
    }
    pub inline fn hasSnapshot(reliability: DeliveryPolicy) bool {
        return switch (reliability) {
            .UnreliableSequenced => true,
            .ReliableSequenced => true,
            else => false,
        };
    }
    pub inline fn hasEpochOrSnapshot(reliability: DeliveryPolicy) bool {
        return switch (reliability) {
            .UnreliableSequenced => true,
            .ReliableOrdered => true,
            .ReliableSequenced => true,
            .ReliableOrderedWithAckReceipt => true,
            else => false,
        };
    }
    pub inline fn hasEpoch(reliability: DeliveryPolicy) bool {
        return switch (reliability) {
            .ReliableOrdered => true,
            .ReliableOrderedWithAckReceipt => true,
            else => false,
        };
    }
};
