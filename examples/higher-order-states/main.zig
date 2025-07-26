const std = @import("std");
const ps = @import("polystate");

pub fn Words(
    comptime Fsm: fn (State: type) type,
    comptime ParentContext: type,
    comptime ctx_field: std.meta.FieldEnum(ParentContext),
) type {
    return struct {
        pub fn IterateWords(
            comptime WordOperation: fn (Next: type) type,
            comptime NoWordsLeft: type,
        ) type {
            return union(enum) {
                to_inner: Fsm(IterateWordsInner(WordOperation(@This()), NoWordsLeft)),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    ctx.head = ctx.word_end;
                    return .to_inner;
                }
            };
        }

        pub fn IterateWordsInner(
            comptime FoundWord: type,
            comptime NoWordsLeft: type,
        ) type {
            return union(enum) {
                to_find_word: Fsm(FindWord(FoundWord)),
                to_no_words_left: Fsm(NoWordsLeft),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.word_end >= ctx.string.len) {
                        return .to_no_words_left;
                    } else {
                        return .to_find_word;
                    }
                }
            };
        }

        pub fn FindWord(comptime Next: type) type {
            return union(enum) {
                to_find_word_end: Fsm(FindWordEnd(Next)),
                no_transition: Fsm(@This()),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.head >= ctx.string.len) {
                        ctx.word_start = ctx.head;
                        ctx.word_end = ctx.head;
                        return .to_find_word_end;
                    }
                    switch (ctx.string[ctx.head]) {
                        ' ', '\t'...'\r' => {
                            ctx.head += 1;
                            return .no_transition;
                        },
                        else => {
                            ctx.word_start = ctx.head;
                            ctx.word_end = ctx.head;
                            return .to_find_word_end;
                        },
                    }
                }
            };
        }

        pub fn FindWordEnd(comptime Next: type) type {
            return union(enum) {
                to_next: Fsm(Next),
                no_transition: Fsm(@This()),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.word_end >= ctx.string.len) {
                        return .to_next;
                    }
                    switch (ctx.string[ctx.word_end]) {
                        ' ', '\t'...'\r' => return .to_next,
                        else => {
                            ctx.word_end += 1;
                            return .no_transition;
                        },
                    }
                }
            };
        }

        pub fn CharMutation(
            comptime Next: type,
            mutateChar: fn (char: u8) u8,
        ) type {
            return union(enum) {
                to_inner: Fsm(CharMutationInner(Next, mutateChar)),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    ctx.head = ctx.word_start;
                    return .to_inner;
                }
            };
        }

        pub fn CharMutationInner(
            comptime Next: type,
            mutateChar: fn (char: u8) u8,
        ) type {
            return union(enum) {
                to_next: Fsm(Next),
                no_transition: Fsm(@This()),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.head >= ctx.word_end) {
                        return .to_next;
                    } else {
                        ctx.string[ctx.head] = mutateChar(ctx.string[ctx.head]);
                        ctx.head += 1;
                        return .no_transition;
                    }
                }
            };
        }

        pub fn Reverse(comptime Next: type) type {
            return union(enum) {
                to_inner: Fsm(ReverseInner(Next)),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    ctx.tail = ctx.word_start;
                    ctx.head = ctx.word_end - 1;
                    return .to_inner;
                }
            };
        }

        pub fn ReverseInner(comptime Next: type) type {
            return union(enum) {
                to_next: Fsm(Next),
                no_transition: Fsm(@This()),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.tail >= ctx.head) {
                        return .to_next;
                    } else {
                        const temp = ctx.string[ctx.tail];
                        ctx.string[ctx.tail] = ctx.string[ctx.head];
                        ctx.string[ctx.head] = temp;
                        ctx.tail += 1;
                        ctx.head -= 1;
                        return .no_transition;
                    }
                }
            };
        }

        pub fn CharFilter(
            comptime Pass: type,
            comptime Fail: type,
            comptime predicate: fn (char: u8) bool,
        ) type {
            return union(enum) {
                to_inner: Fsm(CharFilterInner(Pass, Fail, predicate)),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    ctx.head = ctx.word_start;
                    return .to_inner;
                }
            };
        }

        pub fn CharFilterInner(
            comptime Pass: type,
            comptime Fail: type,
            comptime predicate: fn (char: u8) bool,
        ) type {
            return union(enum) {
                to_pass: Fsm(Pass),
                to_fail: Fsm(Fail),
                no_transition: Fsm(@This()),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.head >= ctx.word_end) {
                        return .to_fail;
                    }
                    if (predicate(ctx.string[ctx.head])) {
                        return .to_pass;
                    } else {
                        ctx.head += 1;
                        return .no_transition;
                    }
                }
            };
        }

        pub fn PalindromeFilter(
            comptime Pass: type,
            comptime Fail: type,
        ) type {
            return union(enum) {
                to_inner: Fsm(PalindromeFilterInner(Pass, Fail)),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    ctx.tail = ctx.word_start;
                    ctx.head = ctx.word_end - 1;
                    return .to_inner;
                }
            };
        }

        pub fn PalindromeFilterInner(
            comptime Pass: type,
            comptime Fail: type,
        ) type {
            return union(enum) {
                to_pass: Fsm(Pass),
                to_fail: Fsm(Fail),
                no_transition: Fsm(@This()),

                pub fn handler(parent_ctx: *ParentContext) @This() {
                    const ctx = ctxFromParent(parent_ctx);
                    if (ctx.tail >= ctx.head) {
                        return .to_pass;
                    } else if (ctx.string[ctx.tail] != ctx.string[ctx.head]) {
                        return .to_fail;
                    } else {
                        ctx.tail += 1;
                        ctx.head -= 1;
                        return .no_transition;
                    }
                }
            };
        }

        fn ctxFromParent(parent_ctx: *ParentContext) *WordsContext {
            return &@field(parent_ctx, @tagName(ctx_field));
        }
    };
}

pub const WordsContext = struct {
    string: []u8,
    head: usize,
    word_start: usize,
    word_end: usize,
    tail: usize,

    pub fn init(string: []u8) WordsContext {
        return .{
            .string = string,
            .head = 0,
            .word_start = 0,
            .word_end = 0,
            .tail = 0,
        };
    }
};

pub const Context = struct {
    string1_ctx: WordsContext,
    string2_ctx: WordsContext,

    pub fn init(string1: []u8, string2: []u8) Context {
        return .{
            .string1_ctx = .init(string1),
            .string2_ctx = .init(string2),
        };
    }
};

pub fn CapsFsm(comptime State: type) type {
    return ps.FSM("Word Processor", .not_suspendable, Context, null, {}, State);
}

const string1_states = struct {
    const W = Words(CapsFsm, Context, .string1_ctx);

    fn isUnderscore(char: u8) bool {
        return char == '_';
    }

    fn capitalize(char: u8) u8 {
        return std.ascii.toUpper(char);
    }

    pub fn UnderscoreFilter(comptime Pass: type, comptime Fail: type) type {
        return W.CharFilter(Pass, Fail, isUnderscore);
    }

    pub fn Capitalize(comptime Next: type) type {
        return W.CharMutation(Next, capitalize);
    }

    pub fn UnderscoreOrPalindromeFilter(comptime Pass: type, comptime Fail: type) type {
        return UnderscoreFilter(
            Pass,
            W.PalindromeFilter(Pass, Fail),
        );
    }

    pub fn CapitalizeUnderscoreOrPalindromeWord(comptime Next: type) type {
        return UnderscoreOrPalindromeFilter(
            Capitalize(Next),
            Next,
        );
    }

    pub fn CapitalizeUnderscoreOrPalindromeWords(comptime Next: type) type {
        return W.IterateWords(
            CapitalizeUnderscoreOrPalindromeWord,
            Next,
        );
    }
};

const string2_states = struct {
    const W = Words(CapsFsm, Context, .string2_ctx);

    fn isVowel(char: u8) bool {
        return switch (char) {
            'a', 'e', 'i', 'o', 'u', 'A', 'E', 'I', 'O', 'U' => true,
            else => false,
        };
    }

    pub fn VowelFilter(comptime Pass: type, comptime Fail: type) type {
        return W.CharFilter(Pass, Fail, isVowel);
    }

    pub fn ReverseWordWithVowel(comptime Next: type) type {
        return VowelFilter(
            W.Reverse(Next),
            Next,
        );
    }

    pub fn ReverseVowelWords(comptime Next: type) type {
        return W.IterateWords(
            ReverseWordWithVowel,
            Next,
        );
    }
};

pub const EnterFsmState = CapsFsm(
    string1_states.CapitalizeUnderscoreOrPalindromeWords(
        string2_states.ReverseVowelWords(ps.Exit),
    ),
);

pub fn main() !void {
    const Runner = ps.Runner(true, EnterFsmState);

    var string1_backing =
        \\capitalize_me 
        \\DontCapitalizeMe 
        \\ineedcaps_  _IAlsoNeedCaps idontneedcaps
        \\_/\o_o/\_ <-- wide_eyed
        \\tacocat 123Hello--olleH321
    .*;

    var string2_backing =
        \\apple gym cry
        \\elephant pfft sphinx
        \\amazing fly grr
    .*;

    var ctx: Context = .init(&string1_backing, &string2_backing);

    const starting_state_id = Runner.idFromState(EnterFsmState.State);

    std.debug.print("Before processing:\n", .{});
    std.debug.print("String 1: {s}\n", .{string1_backing});
    std.debug.print("String 2: {s}\n\n", .{string2_backing});

    Runner.runHandler(starting_state_id, &ctx);

    std.debug.print("After processing:\n", .{});
    std.debug.print("String 1: {s}\n", .{string1_backing});
    std.debug.print("String 2: {s}\n", .{string2_backing});
}
