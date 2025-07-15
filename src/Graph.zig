const std = @import("std");
const ps = @import("polystate.zig");
const Mode = ps.Mode;
const Method = ps.Method;
const Adler32 = std.hash.Adler32;

arena: std.heap.ArenaAllocator,
name: []const u8,
nodes: std.ArrayListUnmanaged(Node),
edges: std.ArrayListUnmanaged(Edge),

const Graph = @This();

pub const Node = struct {
    name: []const u8,
    id: u32,
};

pub const Edge = struct {
    from: u32,
    to: u32,
    color: Color,
    label: []const u8,
};

pub const Color = enum {
    black,
    blue,
};

pub fn generateDot(
    self: @This(),
    writer: anytype,
) !void {
    try writer.writeAll(
        \\digraph fsm_state_graph {
        \\
    );

    { //state graph
        try writer.print(
            \\  subgraph cluster_transitions {{
            \\    label = "State transitions for {0s}";
            \\    labelloc = "t";
            \\    labeljust = "c";
            \\
        , .{self.name});

        for (self.edges.items) |edge| {
            try writer.print(
                \\    {d} -> {d} [label = "{s}"{s}];
                \\
            , .{
                edge.from,
                edge.to,
                edge.label,
                switch (edge.color) {
                    .black => "",
                    .blue =>
                    \\ color = "blue"
                    ,
                },
            });
        }

        try writer.writeAll(
            \\  }
            \\
        );
    }

    { //all_state

        try writer.print(
            \\  subgraph cluster_names {{
            \\    label = "State names for {0s}";
            \\    labelloc = "t";
            \\    labeljust = "c";
            \\    all_node [shape=plaintext, label=<
            \\      <TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
            \\
        ,
            .{self.name},
        );

        for (self.nodes.items) |node| {
            try writer.print(
                \\      <TR><TD ALIGN="LEFT"> {d} -- {s} </TD></TR>
                \\
            , .{ node.id, node.name });
        }

        try writer.writeAll(
            \\      </TABLE>
            \\    >]
            \\  }
            \\
        );
    }

    try writer.writeAll(
        \\}
        \\
    );
}

pub fn generateMermaid(
    self: @This(),
    writer: anytype,
) !void {
    try writer.writeAll(
        \\---
        \\config:
        \\  layout: elk
        \\  elk:
        \\    mergeEdges: false
        \\    nodePlacementStrategy: LINEAR_SEGMENTS
        \\  theme: 'base'
        \\  themeVariables:
        \\    primaryColor: 'white'
        \\    primaryTextColor: 'black'
        \\    primaryBorderColor: 'black'
        \\  flowchart:
        \\    padding: 32
        \\---
        \\flowchart TB
        \\
    );

    {
        try writer.print(
            \\  subgraph {s}_graph
            \\    linkStyle default stroke-width:2px
            \\
        , .{self.name});

        for (self.edges.items) |edge| {
            try writer.print(
                \\    {d} -- "{s}" --> {d}
                \\
            , .{ edge.from, edge.label, edge.to });
        }

        var blue_count: usize = 0;
        for (self.edges.items) |edge| {
            if (edge.color == .blue) {
                blue_count += 1;
            }
        }

        if (blue_count > 0) {
            try writer.writeAll(
                \\    linkStyle 
            );

            for (self.edges.items, 0..) |edge, i| {
                if (edge.color == .blue) {
                    try writer.print(
                        \\{d}{s}
                    , .{
                        i,
                        if (blue_count > 1) "," else "",
                    });

                    blue_count -= 1;
                }
            }

            try writer.writeAll(
                \\ stroke:blue
                \\
            );
        }

        for (self.nodes.items) |node| {
            try writer.print(
                \\    {0d}@{{ shape: circle }}
                \\
            , .{node.id});
        }

        try writer.writeAll(
            \\  end
            \\
        );
    }

    {
        try writer.print(
            \\  subgraph {s}_states
            \\    s["
            \\
        , .{self.name});

        for (self.nodes.items) |node| {
            try writer.print(
                \\    {d} -- {s}
                \\
            , .{ node.id, node.name });
        }
        try writer.writeAll(
            \\    "]
            \\
        );

        try writer.writeAll(
            \\    s@{ shape: text}
            \\    s:::aligned
            \\    classDef aligned text-align: left, white-space: nowrap
            \\  end
        );
    }
}

pub fn initWithFsm(allocator: std.mem.Allocator, comptime FsmState: type, comptime max_len: usize) !Graph {
    @setEvalBranchQuota(2000000);

    var arena: std.heap.ArenaAllocator = .init(allocator);
    errdefer arena.deinit();

    const arena_allocator = arena.allocator();

    var nodes: std.ArrayListUnmanaged(Node) = .empty;
    var edges: std.ArrayListUnmanaged(Edge) = .empty;

    const state_map: ps.StateMap(max_len) = comptime .init(FsmState);

    comptime var state_map_iterator = state_map.iterator();
    comptime var state_idx: u32 = 0;
    inline while (state_map_iterator.next()) |State| : (state_idx += 1) {
        try nodes.append(arena_allocator, .{
            .name = @typeName(State),
            .id = state_idx,
        });

        switch (@typeInfo(State)) {
            .@"union" => |un| {
                inline for (un.fields) |field| {
                    const NextFsmState = field.type;
                    const NextState = NextFsmState.State;

                    const next_state_idx: u32 = @intFromEnum(state_map.idFromState(NextState));

                    try edges.append(arena_allocator, .{
                        .from = state_idx,
                        .to = next_state_idx,
                        .color = switch (NextFsmState.transition_method) {
                            .current => .black,
                            .next => .blue,
                        },
                        .label = field.name,
                    });
                }
            },
            else => @compileError("Only support tagged union!"),
        }
    }

    try deduplicateNameSubstrings(arena_allocator, &nodes);

    return .{
        .arena = arena,
        .edges = edges,
        .name = FsmState.name,
        .nodes = nodes,
    };
}

// Somewhat inefficient, consider optimizing later.
fn deduplicateNameSubstrings(arena_allocator: std.mem.Allocator, nodes: *std.ArrayListUnmanaged(Node)) !void {
    var new_nodes: std.ArrayListUnmanaged(Node) = try .initCapacity(arena_allocator, nodes.items.len);
    new_nodes.expandToCapacity();

    std.mem.sort(Node, nodes.items, {}, struct {
        pub fn lessThan(_: void, lhs: Node, rhs: Node) bool {
            return lhs.name.len > rhs.name.len;
        }
    }.lessThan);

    for (nodes.items, new_nodes.items) |node, *new_node| {
        new_node.* = node;

        for (nodes.items) |other_node| {
            if (node.id != other_node.id) {
                new_node.name = try std.mem.replaceOwned(
                    u8,
                    arena_allocator,
                    new_node.name,
                    other_node.name,
                    try std.fmt.allocPrint(arena_allocator, "{{{}}}", .{other_node.id}),
                );
            }
        }
    }

    nodes.* = new_nodes;

    std.mem.sort(Node, nodes.items, {}, struct {
        pub fn lessThan(_: void, lhs: Node, rhs: Node) bool {
            return lhs.id < rhs.id;
        }
    }.lessThan);
}

pub fn deinit(self: *Graph) void {
    self.arena.deinit();
}
