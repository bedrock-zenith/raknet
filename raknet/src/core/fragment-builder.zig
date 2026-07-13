const std = @import("std");

const CapsuleInfo = @import("../packets/online/frame-set.zig").CapsuleInfo;

count: u32 = 0,
buffer_size: u32 = 0,
first: ?*CapsuleInfo = null,
last: ?*CapsuleInfo = null,

pub fn append(self: *@This(), capsule: *CapsuleInfo) bool {
    var meta = &(capsule.fragment_data orelse return false);
    meta.next = null;

    // So the self.last is just an checkpoint in the linked list
    // where anything from first to last is contiguous fragments where next.index == this.index + 1;
    // that means any fragments after the last might not be contiguous,
    //
    // in case where first is still null, the self.last might hold dirty values
    if (meta.index == 0) {
        if (self.first != null) return false;
        self.first = capsule;
        meta.next = self.last;
        self.last = capsule;
    } else {
        var last_ptr: *?*CapsuleInfo = if (self.first) |_| &self.last.?.fragment_data.?.next else &self.last;
        var cursor: ?*CapsuleInfo = last_ptr.*;

        while (cursor) |ptr| {
            if (ptr.fragment_data.?.index == meta.index) return false;
            if (ptr.fragment_data.?.index > meta.index) break;

            last_ptr = &ptr.fragment_data.?.next;
            cursor = ptr.fragment_data.?.next;
        }

        capsule.fragment_data.?.next = cursor;
        last_ptr.* = capsule;
    }

    self.count += 1;
    self.buffer_size += capsule.body.len;

    if (self.first != null)
        while (self.last) |last| {
            if (last.fragment_data.?.next) |next_node| {
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
    cursor: ?*CapsuleInfo = null,
    pub inline fn next(this: *@This()) ?*CapsuleInfo {
        if (this.cursor) |c| {
            this.cursor = c.fragment_data.?.next;
            return c;
        }
        return null;
    }
} {
    return .{ .cursor = self.first };
}
