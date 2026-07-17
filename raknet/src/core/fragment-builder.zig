const std = @import("std");

const Capsule = @import("../data/root.zig").datagram.Capsule;

count: u32 = 0,
buffer_size: u32 = 0,
first: ?*Capsule = null,
last: ?*Capsule = null,
pub const empty: @This() = .{};

pub fn append(self: *@This(), capsule: *Capsule) bool {
    const meta = &(capsule.fragment_data orelse return false);
    capsule.next = null;

    // So the self.last is just an checkpoint in the linked list
    // where anything from first to last is contiguous fragments where next.index == this.index + 1;
    // that means any fragments after the last might not be contiguous,
    //
    // in case where first is still null, the self.last might hold dirty values
    if (meta.index == 0) {
        if (self.first != null) return false;
        self.first = capsule;
        capsule.next = self.last;
        self.last = capsule;
    } else {
        var last_ptr: *?*Capsule = if (self.first) |_| &self.last.?.next else &self.last;
        var cursor: ?*Capsule = last_ptr.*;

        while (cursor) |ptr| {
            if (ptr.fragment_data.?.index == meta.index) return false;
            if (ptr.fragment_data.?.index > meta.index) break;

            last_ptr = &ptr.next;
            cursor = ptr.next;
        }

        capsule.next = cursor;
        last_ptr.* = capsule;
    }

    self.count += 1;
    self.buffer_size += @intCast(capsule.body.len);

    if (self.first != null)
        while (self.last) |last| {
            if (last.next) |next_node| {
                if (last.fragment_data.?.index + 1 == next_node.fragment_data.?.index) {
                    self.last = next_node;
                    continue;
                }
            }
            break;
        };

    return true;
}

pub inline fn iterator(self: *@This()) struct {
    cursor: ?*Capsule = null,
    pub inline fn next(this: *@This()) ?*Capsule {
        if (this.cursor) |c| {
            this.cursor = c.fragment_data.?.next;
            return c;
        }
        return null;
    }
} {
    return .{ .cursor = self.first };
}

pub inline fn reset(self: *@This()) void {
    self.* = .empty;
}
