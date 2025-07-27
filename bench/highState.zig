const std = @import("std");
const ps = @import("polystate");

pub fn main() void {
    const ExampleRunner = ps.Runner(true, EnterFsmState);
    var ctx: Context = .{};
    ExampleRunner.runHandler(ExampleRunner.idFromState(EnterFsmState.State), &ctx);
}

const Context = struct {};

pub fn Example(Current: type) type {
    return ps.FSM("Example", .not_suspendable, Context, null, {}, Current);
}

pub fn Dummy(comptime Next: type, comptime int: comptime_int) type {
    return union(enum) {
        to_next0: Example(Next),
        to_next1: Example(Next),
        to_next2: Example(Next),
        to_next3: Example(Next),
        to_next4: Example(Next),
        to_next5: Example(Next),

        pub const int_decl = int;

        pub fn handler(_: *Context) @This() {
            return .to_next0;
        }
    };
}

pub fn Nested(comptime int: comptime_int) type {
    @setEvalBranchQuota(2000000);

    comptime {
        var State = ps.Exit;
        for (0..200) |_| {
            State = Dummy(State, int);
        }
        return State;
    }
}

pub const EnterFsmState = Example(union(enum) {
    to_1: Example(Nested(1)),
    to_2: Example(Nested(2)),
    to_3: Example(Nested(3)),
    to_4: Example(Nested(4)),
    to_5: Example(Nested(5)),
    to_6: Example(Nested(6)),
    to_7: Example(Nested(7)),
    to_8: Example(Nested(8)),
    to_9: Example(Nested(9)),
    to_10: Example(Nested(10)),
    to_11: Example(Nested(11)),
    to_12: Example(Nested(12)),
    to_13: Example(Nested(13)),
    to_14: Example(Nested(14)),
    to_15: Example(Nested(15)),
    to_16: Example(Nested(16)),
    to_17: Example(Nested(17)),
    to_18: Example(Nested(18)),
    to_19: Example(Nested(19)),
    to_20: Example(Nested(20)),

    pub fn handler(_: *Context) @This() {
        return .to_1;
    }
});
