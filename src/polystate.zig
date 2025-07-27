const std = @import("std");

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

pub const StateMap = struct {
    states: []const type,
    StateId: type,

    pub fn init(comptime FsmState: type) StateMap {
        @setEvalBranchQuota(200_000_000);

        comptime {
            const states = reachableStates(FsmState);
            return .{
                .states = states,
                .StateId = @Type(.{
                    .@"enum" = .{
                        .tag_type = std.math.IntFittingRange(0, states.len - 1),
                        .fields = inner: {
                            var fields: [states.len]std.builtin.Type.EnumField = undefined;

                            for (&fields, states, 0..) |*field, State, state_int| {
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
                }),
            };
        }
    }

    pub fn StateFromId(comptime self: StateMap, comptime state_id: self.StateId) type {
        return self.states[@intFromEnum(state_id)];
    }

    pub fn idFromState(comptime self: StateMap, comptime State: type) self.StateId {
        if (!@hasField(self.StateId, @typeName(State))) @compileError(std.fmt.comptimePrint(
            "Can't find State {s}",
            .{@typeName(State)},
        ));
        return @field(self.StateId, @typeName(State));
    }

    pub fn iterator(comptime self: StateMap) Iterator {
        return .{
            .state_map = self,
            .idx = 0,
        };
    }

    pub const Iterator = struct {
        state_map: StateMap,
        idx: usize,

        pub fn next(comptime self: *Iterator) ?type {
            if (self.idx < self.state_map.states.len) {
                defer self.idx += 1;
                return self.state_map.states[self.idx];
            }

            return null;
        }
    };
};

pub fn Runner(
    comptime is_inline: bool,
    comptime FsmState: type,
) type {
    return struct {
        pub const Context = FsmState.Context;
        pub const state_map: StateMap = .init(FsmState);
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

pub fn reachableStates(comptime FsmState: type) []const type {
    comptime {
        var states: []const type = &.{FsmState.State};
        var states_stack: []const type = &.{FsmState};
        var states_set: TypeSet(128) = .init;

        states_set.insert(FsmState.State);

        reachableStatesDepthFirstSearch(FsmState, &states, &states_stack, &states_set);

        return states;
    }
}

fn reachableStatesDepthFirstSearch(
    comptime FsmState: type,
    comptime states: *[]const type,
    comptime states_stack: *[]const type,
    comptime states_set: *TypeSet(128),
) void {
    @setEvalBranchQuota(20_000_000);

    comptime {
        if (states_stack.len == 0) {
            return;
        }

        const CurrentFsmState = states_stack.*[states_stack.len - 1];
        states_stack.* = states_stack.*[0 .. states_stack.len - 1];

        const CurrentState = CurrentFsmState.State;

        if (!std.mem.eql(u8, CurrentFsmState.name, FsmState.name)) {
            @compileError(std.fmt.comptimePrint(
                \\Inconsistent state machine names:
                \\You used a state from state machine [{s}] in state machine [{s}].
            , .{ CurrentFsmState.name, FsmState.name }));
        }

        switch (@typeInfo(CurrentState)) {
            .@"union" => |un| {
                for (un.fields) |field| {
                    const NextFsmState = field.type;
                    if (CurrentFsmState.mode != NextFsmState.mode) {
                        @compileError("The Modes of the two fsm_states are inconsistent!");
                    }

                    const NextState = NextFsmState.State;

                    if (!states_set.has(NextState)) {
                        states.* = states.* ++ &[_]type{NextState};
                        states_stack.* = states_stack.* ++ &[_]type{NextFsmState};
                        states_set.insert(NextState);

                        reachableStatesDepthFirstSearch(FsmState, states, states_stack, states_set);
                    }
                }
            },
            else => @compileError("Only support tagged union!"),
        }
    }
}

fn TypeSet(comptime bucket_count: usize) type {
    return struct {
        buckets: [bucket_count][]const type,

        const Self = @This();

        pub const init: Self = .{
            .buckets = @splat(&.{}),
        };

        pub fn insert(comptime self: *Self, comptime Type: type) void {
            comptime {
                const hash = std.hash_map.hashString(@typeName(Type));

                self.buckets[hash % bucket_count] = self.buckets[hash % bucket_count] ++ &[_]type{Type};
            }
        }

        pub fn has(comptime self: Self, comptime Type: type) bool {
            comptime {
                const hash = std.hash_map.hashString(@typeName(Type));

                return std.mem.indexOfScalar(type, self.buckets[hash % bucket_count], Type) != null;
            }
        }

        pub fn items(comptime self: Self) []const type {
            comptime {
                var res: []const type = &.{};

                for (&self.buckets) |bucket| {
                    res = res ++ bucket;
                }

                return res;
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
    var graph = try Graph.initWithFsm(allocator, StateA);
    defer graph.deinit();

    const ExampleRunner = Runner(true, StateA);

    try std.testing.expectEqual(
        graph.nodes.items.len,
        ExampleRunner.state_map.states.len,
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
    var graph = try Graph.initWithFsm(allocator, StateA);
    defer graph.deinit();

    const ExampleRunner = Runner(true, StateA);

    try std.testing.expectEqual(
        graph.nodes.items.len,
        ExampleRunner.state_map.states.len,
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
