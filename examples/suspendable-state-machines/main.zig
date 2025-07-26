const std = @import("std");
const ps = @import("polystate");

pub const FindWord = union(enum) {
    to_check_word: CapsFsm(.current, CheckWord),
    exit: CapsFsm(.current, ps.Exit),
    no_transition: CapsFsm(.current, FindWord),

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
    to_find_word: CapsFsm(.current, FindWord),
    to_capitalize: CapsFsm(.next, Capitalize),
    exit: CapsFsm(.current, ps.Exit),
    no_transition: CapsFsm(.current, CheckWord),

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
    to_find_word: CapsFsm(.current, FindWord),
    exit: CapsFsm(.current, ps.Exit),
    no_transition: CapsFsm(.current, Capitalize),

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

pub fn CapsFsm(comptime method: ps.Method, comptime State: type) type {
    return ps.FSM("Underscore Capitalizer", .suspendable, Context, null, method, State);
}

pub const EnterFsmState = CapsFsm(.current, FindWord);

pub fn main() void {
    const Runner = ps.Runner(true, EnterFsmState);

    var string_backing =
        \\capitalize_me 
        \\DontCapitalizeMe 
        \\ineedcaps_  _IAlsoNeedCaps idontneedcaps
        \\_/\o_o/\_ <-- wide_eyed
    .*;
    const string: [:0]u8 = &string_backing;

    var ctx: Context = .init(string);

    std.debug.print("Without caps:\n{s}\n\n", .{string});

    var state_id = Runner.idFromState(EnterFsmState.State);

    while (Runner.runHandler(state_id, &ctx)) |new_state_id| {
        state_id = new_state_id;

        var word_len: usize = 0;
        while (ctx.word[word_len] != 0 and !std.ascii.isWhitespace(ctx.word[word_len])) {
            word_len += 1;
        }

        const word = ctx.word[0..word_len];

        std.debug.print("capitalizing word: {s}\n", .{word});
    }

    std.debug.print("\nWith caps:\n{s}\n", .{string});
}
