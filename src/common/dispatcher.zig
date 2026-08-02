pub const Context = ?*anyopaque;

pub fn Dispatcher(comptime EventData: type) type {
    return struct {
        pub const empty: @This() = .{
            .context = null,
            .callback = null,
        };

        pub const FnPtr = ?*const (fn (context: Context, event_data: EventData) void);
        pub const DataType = EventData;
        context: Context,
        callback: FnPtr,

        pub fn register(
            this: *@This(),
            comptime T: type,
            callback: ?*const (fn (context: T, event_data: EventData) void),
            context: T,
        ) void {
            this.context = @ptrCast(context);
            this.callback = @ptrCast(callback);
        }

        pub fn invoke(this: *const @This(), data: EventData) bool {
            if (this.callback) |fnc| {
                fnc(this.context, data);
                return true;
            }
            return false;
        }
    };
}

test "Dispatcher Test" {
    const Handler = Dispatcher(u32);
    var event: Handler = .empty;
    event.register(null, testFunc);
    _ = event.invoke(654);
}

fn testFunc(_: Context, value: u32) void {
    @import("std").testing.expectEqual(value, 654) catch unreachable;
}
