const std = @import("std");
const Io = std.Io;
const raknet = @import("raknet");

pub fn main(_: std.process.Init) !void {
    _ = raknet.add(12, 12);
}
