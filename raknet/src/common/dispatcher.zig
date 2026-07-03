pub const Context = ?*anyopaque;

pub fn Dispatcher(comptime event_data_type: type) type {
    return struct {
        pub const empty: @This() = .{
            .context = null,
            .callback = null,
        };

        pub const FnPtr = ?*const (fn (context: Context, event_data: event_data_type) void);
        pub const DataType = event_data_type;
        context: Context,
        callback: FnPtr,

        pub fn register(this: *@This(), context: Context, callback: FnPtr) void {
            this.context = context;
            this.callback = callback;
        }

        pub fn invoke(this: *const @This(), data: event_data_type) bool {
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
