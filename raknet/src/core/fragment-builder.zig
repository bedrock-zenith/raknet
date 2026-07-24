const std = @import("std");

const Segment = @import("../protocol/root.zig").datagram.Segment;

count: u32 = 0,
buffer_size: u32 = 0,
first: ?*Segment = null,
last: ?*Segment = null,
pub const empty: @This() = .{};

pub fn isEmpty(self: *const @This()) bool {
    return self.last == null;
}

pub fn append(self: *@This(), segment: *Segment) bool {
    const meta = &(segment.fragment orelse return false);
    segment.meta.next = null;

    // So the self.last is just an checkpoint in the linked list
    // where anything from first to last is contiguous fragments where next.index == this.index + 1;
    // that means any fragments after the last might not be contiguous,
    //
    // in case where first is still null, the self.last might hold dirty values
    if (meta.index == 0) {
        if (self.first != null) return false;
        self.first = segment;
        segment.meta.next = self.last;
        self.last = segment;
    } else {
        var last_ptr: *?*Segment = if (self.first) |_| &self.last.?.meta.next else &self.last;
        var cursor: ?*Segment = last_ptr.*;

        while (cursor) |ptr| {
            if (ptr.fragment.?.index == meta.index) return false;
            if (ptr.fragment.?.index > meta.index) break;

            last_ptr = &ptr.meta.next;
            cursor = ptr.meta.next;
        }

        segment.meta.next = cursor;
        last_ptr.* = segment;
    }

    self.count += 1;
    self.buffer_size += @intCast(segment.body.len);

    if (self.first != null)
        while (self.last) |last| {
            if (last.meta.next) |next_node| {
                if (last.fragment.?.index + 1 == next_node.fragment.?.index) {
                    self.last = next_node;
                    continue;
                }
            }
            break;
        };

    return true;
}

pub inline fn iterator(self: *@This()) struct {
    cursor: ?*Segment = null,
    pub inline fn next(this: *@This()) ?*Segment {
        if (this.cursor) |c| {
            this.cursor = c.meta.next;
            return c;
        }
        return null;
    }
} {
    return .{ .cursor = self.first orelse self.last };
}

pub inline fn reset(self: *@This()) void {
    self.* = .empty;
}
