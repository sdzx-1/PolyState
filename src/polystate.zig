const std = @import("std");
const Adler32 = std.hash.Adler32;
const AVL = @import("avl.zig").AVL;

pub const Graph = @import("Graph.zig");

pub const Exit = union(enum) {};

// FSM       : fn (type) type , Example
// State     : type           , A, B
// FsmState  : type           , Example(A), Example(B)

pub const Mode = enum {
    not_suspendable,
    suspendable,
};

pub const Method = enum {
    next,
    current,
};

pub fn FSM(
    comptime name_: []const u8,
    comptime mode_: Mode,
    comptime Context_: type,
    comptime enter_fn_: ?fn (*Context_, type) void, // enter_fn args type is State
    comptime transition_method_: if (mode_ == .not_suspendable) void else Method,
    comptime State_: type,
) type {
    return struct {
        pub const name = name_;
        pub const mode = mode_;
        pub const Context = Context_;
        pub const enter_fn = enter_fn_;
        pub const transition_method: Method = if (mode_ == .not_suspendable) .current else transition_method_;
        pub const State = State_;
    };
}

pub fn StateMap(comptime max_len: usize) type {
    return struct {
        root: i32 = -1,
        avl: AVL(max_len, struct { type, usize }) = .{}, // the type is State
        StateId: type,

        const Self = @This();

        pub fn init(comptime FsmState: type) Self {
            @setEvalBranchQuota(10_000_000);
            comptime {
                var res: Self = .{
                    .root = -1,
                    .avl = .{},
                    .StateId = undefined,
                };

                res.collect(FsmState);

                const state_count = res.avl.len;

                res.StateId = @Type(.{
                    .@"enum" = .{
                        .tag_type = std.math.IntFittingRange(0, state_count - 1),
                        .fields = inner: {
                            var fields: [state_count]std.builtin.Type.EnumField = undefined;

                            for (&fields, res.avl.nodes[0..state_count]) |*field, node| {
                                const State, const state_int = node.data;

                                field.* = .{
                                    .name = @typeName(State),
                                    .value = state_int,
                                };
                            }

                            const fields_const = fields;
                            break :inner &fields_const;
                        },
                        .decls = &.{},
                        .is_exhaustive = true,
                    },
                });

                return res;
            }
        }

        pub fn StateFromId(comptime self: *const Self, comptime state_id: self.StateId) type {
            return self.avl.nodes[@intFromEnum(state_id)].data[0];
        }

        pub fn idFromState(comptime self: *const Self, comptime State: type) self.StateId {
            if (!@hasField(self.StateId, @typeName(State))) @compileError(std.fmt.comptimePrint(
                "Can't find State {s}",
                .{@typeName(State)},
            ));
            return @field(self.StateId, @typeName(State));
        }

        pub fn iterator(comptime self: *const Self) Iterator {
            return .{
                .state_map = self,
                .idx = 0,
            };
        }

        pub const Iterator = struct {
            state_map: *const Self,
            idx: usize,

            pub fn next(comptime self: *Iterator) ?type {
                if (self.idx < self.state_map.avl.len) {
                    defer self.idx += 1;
                    return self.state_map.avl.nodes[self.idx].data[0];
                }

                return null;
            }
        };

        fn checkConsistency(comptime b: []const u8, comptime a: []const u8) void {
            if (comptime !std.mem.eql(u8, b, a)) {
                const error_str = std.fmt.comptimePrint(
                    \\The state machine name are inconsistent.
                    \\You used the state of state machine [{s}] in state machine [{s}]."
                , .{ b, a });
                @compileError(error_str);
            }
        }

        fn collect(comptime self: *Self, comptime FsmState: type) void {
            const State = FsmState.State;
            const state_hash = Adler32.hash(@typeName(State));
            const name = FsmState.name;
            if (self.avl.search(self.root, state_hash)) |_| {
                return;
            } else {
                const idx = self.avl.len;
                self.root = self.avl.insert(self.root, state_hash, .{ State, idx });
                switch (@typeInfo(State)) {
                    .@"union" => |un| {
                        inline for (un.fields) |field| {
                            const NextFsmState = field.type;
                            if (FsmState.mode != NextFsmState.mode) {
                                @compileError("The Modes of the two fsm_states are inconsistent!");
                            }
                            const new_name = NextFsmState.name;
                            checkConsistency(new_name, name);
                            self.collect(NextFsmState);
                        }
                    },
                    else => @compileError("Only support tagged union!"),
                }
            }
        }
    };
}

pub fn Runner(
    comptime max_len: usize,
    comptime is_inline: bool,
    comptime FsmState: type,
) type {
    return struct {
        pub const Context = FsmState.Context;
        pub const state_map: StateMap(max_len) = .init(FsmState);
        pub const StateId = state_map.StateId;
        pub const RetType =
            switch (FsmState.mode) {
                .suspendable => ?StateId,
                .not_suspendable => void,
            };

        pub fn idFromState(comptime State: type) StateId {
            return state_map.idFromState(State);
        }

        pub fn StateFromId(comptime state_id: StateId) type {
            return state_map.StateFromId(state_id);
        }

        pub fn runHandler(curr_id: StateId, ctx: *Context) RetType {
            @setEvalBranchQuota(10_000_000);
            sw: switch (curr_id) {
                inline else => |state_id| {
                    // Remove when https://github.com/ziglang/zig/issues/24323 is fixed:
                    {
                        var runtime_false = false;
                        _ = &runtime_false;
                        if (runtime_false) continue :sw @enumFromInt(0);
                    }

                    const State = StateFromId(state_id);

                    if (State == Exit) {
                        return switch (FsmState.mode) {
                            .suspendable => null,
                            .not_suspendable => {},
                        };
                    }

                    if (FsmState.enter_fn) |fun| fun(ctx, State);

                    const handle_res = @call(
                        if (is_inline) .always_inline else .auto,
                        State.handler,
                        .{ctx},
                    );
                    switch (handle_res) {
                        inline else => |new_fsm_state_wit| {
                            const NewFsmState = @TypeOf(new_fsm_state_wit);
                            const new_id = comptime idFromState(NewFsmState.State);

                            switch (NewFsmState.transition_method) {
                                .next => return new_id,
                                .current => continue :sw new_id,
                            }
                        },
                    }
                },
            }
        }
    };
}

test "polystate suspendable" {
    const Context = struct {
        a: i32,
        b: i32,
        max_a: i32,
    };

    const Tmp = struct {
        pub fn Example(meth: Method, Current: type) type {
            return FSM("Example", .suspendable, Context, null, meth, Current);
        }

        pub const A = union(enum) {
            // zig fmt: off
            exit : Example(.next, Exit),
            to_B : Example(.next, B),
            to_B1: Example(.current, B),
            // zig fmt: on

            pub fn handler(ctx: *Context) @This() {
                if (ctx.a >= ctx.max_a) return .exit;
                ctx.a += 1;
                if (@mod(ctx.a, 2) == 0) return .to_B1;
                return .to_B;
            }
        };

        pub const B = union(enum) {
            to_A: Example(.next, A),

            pub fn handler(ctx: *Context) @This() {
                ctx.b += 1;
                return .to_A;
            }
        };
    };

    const StateA = Tmp.Example(.next, Tmp.A);

    const allocator = std.testing.allocator;
    var graph = try Graph.initWithFsm(allocator, StateA, 20);
    defer graph.deinit();

    const ExampleRunner = Runner(20, true, StateA);

    try std.testing.expectEqual(
        graph.nodes.items.len,
        ExampleRunner.state_map.avl.len,
    );

    // rand
    var prng = std.Random.DefaultPrng.init(@intCast(std.testing.random_seed));
    const rand = prng.random();

    for (0..500) |_| {
        const max_a: i32 = rand.intRangeAtMost(i32, 0, 10_000);

        var ctx: Context = .{ .a = 0, .b = 0, .max_a = max_a };
        var curr_id: ?ExampleRunner.StateId = ExampleRunner.idFromState(Tmp.A);
        while (curr_id) |id| {
            curr_id = ExampleRunner.runHandler(id, &ctx);
        }

        try std.testing.expectEqual(max_a, ctx.a);
        try std.testing.expectEqual(max_a, ctx.b);
    }
}

test "polystate not_suspendable" {
    const Context = struct {
        a: i32,
        b: i32,
        max_a: i32,
    };

    const Tmp = struct {
        pub fn Example(Current: type) type {
            return FSM("Example", .not_suspendable, Context, null, {}, Current);
        }

        pub const A = union(enum) {
            // zig fmt: off
            exit : Example(Exit),
            to_B : Example(B),
            to_B1: Example(B),
            // zig fmt: on

            pub fn handler(ctx: *Context) @This() {
                if (ctx.a >= ctx.max_a) return .exit;
                ctx.a += 1;
                if (@mod(ctx.a, 2) == 0) return .to_B1;
                return .to_B;
            }
        };

        pub const B = union(enum) {
            to_A: Example(A),

            pub fn handler(ctx: *Context) @This() {
                ctx.b += 1;
                return .to_A;
            }
        };
    };

    const StateA = Tmp.Example(Tmp.A);

    const allocator = std.testing.allocator;
    var graph = try Graph.initWithFsm(allocator, StateA, 20);
    defer graph.deinit();

    const ExampleRunner = Runner(20, true, StateA);

    try std.testing.expectEqual(
        graph.nodes.items.len,
        ExampleRunner.state_map.avl.len,
    );

    // rand
    var prng = std.Random.DefaultPrng.init(@intCast(std.testing.random_seed));
    const rand = prng.random();

    for (0..500) |_| {
        const max_a: i32 = rand.intRangeAtMost(i32, 0, 10_000);

        var ctx: Context = .{ .a = 0, .b = 0, .max_a = max_a };
        const curr_id: ExampleRunner.StateId = ExampleRunner.idFromState(Tmp.A);
        ExampleRunner.runHandler(curr_id, &ctx);

        try std.testing.expectEqual(max_a, ctx.a);
        try std.testing.expectEqual(max_a, ctx.b);
    }
}
