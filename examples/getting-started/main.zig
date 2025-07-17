const std = @import("std");
const ps = @import("polystate");

pub const FindWord = union(enum) {
    to_check_word: CapsFsm(CheckWord),
    exit: CapsFsm(ps.Exit),
    no_transition: CapsFsm(FindWord),

    pub fn handler(ctx: *Context) FindWord {
        switch (ctx.string[0]) {
            0 => return .exit,
            ' ', '\t'...'\r' => {
                ctx.string += 1;
                return .no_transition;
            },
            else => {
                ctx.word = ctx.string;
                return .to_check_word;
            },
        }
    }
};

pub const CheckWord = union(enum) {
    to_find_word: CapsFsm(FindWord),
    to_capitalize: CapsFsm(Capitalize),
    exit: CapsFsm(ps.Exit),
    no_transition: CapsFsm(CheckWord),

    pub fn handler(ctx: *Context) CheckWord {
        switch (ctx.string[0]) {
            0 => return .exit,
            ' ', '\t'...'\r' => {
                ctx.string += 1;
                return .to_find_word;
            },
            '_' => {
                ctx.string = ctx.word;
                return .to_capitalize;
            },
            else => {
                ctx.string += 1;
                return .no_transition;
            },
        }
    }
};

pub const Capitalize = union(enum) {
    to_find_word: CapsFsm(FindWord),
    exit: CapsFsm(ps.Exit),
    no_transition: CapsFsm(Capitalize),

    pub fn handler(ctx: *Context) Capitalize {
        switch (ctx.string[0]) {
            0 => return .exit,
            ' ', '\t'...'\r' => {
                ctx.string += 1;
                return .to_find_word;
            },
            else => {
                ctx.string[0] = std.ascii.toUpper(ctx.string[0]);
                ctx.string += 1;
                return .no_transition;
            },
        }
    }
};

pub const Context = struct {
    string: [*:0]u8,
    word: [*:0]u8,

    pub fn init(string: [:0]u8) Context {
        return .{
            .string = string.ptr,
            .word = string.ptr,
        };
    }
};

pub fn CapsFsm(comptime State: type) type {
    return ps.FSM("Underscore Capitalizer", .not_suspendable, Context, null, {}, State);
}

pub const EnterFsmState = CapsFsm(FindWord);

pub fn main() void {
    const Runner = ps.Runner(99, true, EnterFsmState);

    var string_backing =
        \\capitalize_me 
        \\DontCapitalizeMe 
        \\ineedcaps_  _IAlsoNeedCaps idontneedcaps
        \\_/\o_o/\_ <-- wide_eyed
    .*;
    const string: [:0]u8 = &string_backing;

    var ctx: Context = .init(string);

    const starting_state_id = Runner.idFromState(EnterFsmState.State);

    std.debug.print("Without caps:\n{s}\n\n", .{string});

    Runner.runHandler(starting_state_id, &ctx);

    std.debug.print("With caps:\n{s}\n", .{string});
}
