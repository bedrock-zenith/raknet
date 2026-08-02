const AckRange = @This();

min: u32,
max: u32,

pub inline fn isSingle(self: AckRange) bool {
    return self.min == self.max;
}
