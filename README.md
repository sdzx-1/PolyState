# Polystate

**Build type-safe finite state machines with higher-order states.**

With Polystate, you can write 'state functions' that produce entirely new states, whose transitions are decided by a set of parameters. This enables composition: constructing states using other states, or even other state functions.

## Adding Polystate to your project

Download and add Polystate as a dependency by running the following command in your project root:
```shell
zig fetch --save git+https://github.com/sdzx-1/polystate.git
```

Then, retrieve the dependency in your build.zig:
```zig
const polystate = b.dependency("polystate", .{
    .target = target,
    .optimize = optimize,
});
```

Finally, add the dependency's module to your module's imports:
```zig
exe_mod.addImport("polystate", polystate.module("root"));
```

You should now be able to import Polystate in your module's code:
```zig
const ps = @import("polystate");
```

## The basics

Let's build a state machine that completes a simple task: capitalize all words in a string that contain an underscore.

Our state machine will contain three states: `FindWord`, `CheckWord`, and `Capitalize`:
- `FindWord` finds the start of a word. `FindWord` transitions to `CheckWord` if it finds the start of a word.
- `CheckWord` checks if an underscore exists in the word. `CheckWord` transitions to `Capitalize` if an underscore is found, or transitions back to `FindWord` if no underscore is found.
- `Capitalize` capitalizes the word. `Capitalize` transitions back to `FindWord` once the word is capitalized.

Here's our state machine implemented with Polystate:
```zig
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

pub fn main() void {
    const StartingFsmState = CapsFsm(FindWord);

    const Runner = ps.Runner(99, true, StartingFsmState);

    var string_backing =
        \\capitalize_me 
        \\DontCapitalizeMe 
        \\ineedcaps_  _IAlsoNeedCaps idontneedcaps
        \\_/\o_o/\_ <-- wide_eyed
    .*;
    const string: [:0]u8 = &string_backing;

    var ctx: Context = .init(string);

    const starting_state_id = Runner.idFromState(StartingFsmState.State);

    std.debug.print("Without caps:\n{s}\n\n", .{string});

    Runner.runHandler(starting_state_id, &ctx);

    std.debug.print("With caps:\n{s}\n", .{string});
}
```

As you can see, each of our states is represented by a tagged union. These unions have two main components: their fields and their `handler` function.

Rules for the fields:
- Each field represents one of the state's transitions.
- The type of a field describes the transition, primarily what the transitioned-to state will be.
- Field types must be generated by `ps.FSM`, which wraps state union types and attaches additional information about the transition and its state machine.
- For a single state machine's transitions, `ps.FSM` must always be given the same name, mode, and context type. In our case, we ensure this by wrapping `ps.FSM` with `CapsFsm`. In `CapsFsm`, the name is set to `"Underscore Capitalizer"`, the mode is set to `not_suspendable`, and the context type is set to `Context`.

Rules for the `handler` function:
- `handler` executes the state's logic and determines which transition to take.
- `handler` takes a context parameter (`ctx`), which points to mutable data that is shared across all states.
- `handler` returns a transition (one of the state's union fields).

Once we have defined the states of our state machine, we make a runner using `ps.Runner`. Just like our state's transition types, the starting state we pass into `ps.Runner` must be generated using `ps.FSM`, which we accomplish using our `CapsFsm` wrapper: `CapsFsm(FindWord)`. Since our FSM's mode is set to `not_suspendable`, calling `runHandler` on our runner will run the state machine until completion (when the special `ps.Exit` state is reached). 

`runHandler` also requires the 'state ID' of the state you want to start at. A runner provides both the `StateId` type and functions to convert between states and their ID. We use this to get the starting state ID: `Runner.idFromState(StartingFsmState.State)`.

It may seem odd that we call `idFromState` with `StartingFsmState.State` instead of `StartingFsmState`, but this is because `StartingFsmState` is the wrapper type produced by `ps.FSM`, whereas `StartingFsmState.State` is the underlying state (`FindWord`). That's why we call it `StartingFsmState` instead of `StartingState`: the 'FSM' naming convention helps us remember that it's a wrapped state, and that we need to use its `State` declaration if we want the state it is wrapping.

## Suspendable state machines
In our previous example, our state machine's mode was `not_suspendable`. What if we set it to `suspendable`? Well, this would allow us to 'suspend' the execution of our state machine, run code outside of the state machine, and then resume the execution of our state machine.

However, `suspendable` adds an additional requirement to your state transitions: they must tell the state machine whether or not to suspend after transitioning.

This is our capitalization state machine, updated such that every time a word is chosen to be capitalized, we suspend execution and print the chosen word:
```zig
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

pub fn main() void {
    const StartingFsmState = CapsFsm(.current, FindWord);

    const Runner = ps.Runner(99, true, StartingFsmState);

    var string_backing =
        \\capitalize_me 
        \\DontCapitalizeMe 
        \\ineedcaps_  _IAlsoNeedCaps idontneedcaps
        \\_/\o_o/\_ <-- wide_eyed
    .*;
    const string: [:0]u8 = &string_backing;

    var ctx: Context = .init(string);

    std.debug.print("Without caps:\n{s}\n\n", .{string});

    var state_id = Runner.idFromState(StartingFsmState.State);

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
```

We've updated our `CapsFsm` wrapper to take an additional parameter of type `ps.Method`, which has two possible values: `current` and `next`.

- If a transition has the method `current`, the state machine will continue execution after transitioning.
- If a transition has the method `next`, the state machine will suspend execution after transitioning.

A transition's `ps.Method` basically answers the following question: "Should I set this new state as my current state and keep going (`current`), or save this new state for the next execution (`next`)?".

In addition to updating our state transitions with `current` or `next`, we also need to change how we use `runHandler`.

Before, since our state machine was `not_suspendable`, `runHandler` didn't return anything and only needed to be called once. Now, since our state machine is `suspendable`, `runHandler` only runs the state machine until it is suspended, and returns the ID of the state it was suspended on.

So, we now call `runHandler` in a loop, passing in the current state ID and using the result as the new state ID. We continue this until `runHandler` returns `null`, indicating that the state machine has completed (reached ps.Exit).

## Higher-order states and composability
If you've read the previous sections where we cover the basics of Polystate, you may feel like it's a bit overkill to use a library instead of just implementing your FSM manually. After all, it can seem like Polystate does little more than provide a convenient framework for structuring state machines.

This changes when you start using higher-order states.

A higher-order state is a function that takes states as parameters and returns a new state, AKA a 'state function'. Since states are represented as types (specifically, tagged unions), a state function is no different than any other Zig generic: a type-returning function that takes types as parameters.

While being simple at their core, higher-order states allow endless ways to construct, compose, and re-use transition logic among your states. Consider the following example:

<< TODO: finish README >>