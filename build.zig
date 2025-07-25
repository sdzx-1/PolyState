const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const polystate = b.addModule("root", .{
        .root_source_file = b.path("src/polystate.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_tests = b.addTest(.{
        .root_module = polystate,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    addExampleGraphsStep(b, target, polystate);
}

fn addExampleGraphsStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    polystate_mod: *std.Build.Module,
) void {
    const graph_step = b.step("example-graphs", "Generate SVG graphs for the README examples");

    const examples_dir_name = "examples";

    const graph_install_path = b.build_root.handle.realpathAlloc(b.allocator, examples_dir_name) catch |err| std.debug.panic("{}", .{err});

    const graph_install_path_relative = std.fs.path.relative(b.allocator, b.install_path, graph_install_path) catch |err| std.debug.panic("{}", .{err});

    const graph_install_dir: std.Build.InstallDir = .{ .custom = graph_install_path_relative };

    var examples_dir = b.build_root.handle.openDir(examples_dir_name, .{ .iterate = true }) catch |err| std.debug.panic("{}", .{err});
    defer examples_dir.close();

    var iterator = examples_dir.iterate();

    while (iterator.next() catch |err| std.debug.panic("{}", .{err})) |entry| {
        if (entry.kind == .directory) {
            const example_name = b.allocator.dupe(u8, entry.name) catch @panic("OOM");
            const mod = b.addModule(
                example_name,
                .{
                    .root_source_file = b.path(b.pathJoin(&.{ examples_dir_name, example_name, "main.zig" })),

                    .target = target,
                    .imports = &.{
                        .{
                            .name = "polystate",
                            .module = polystate_mod,
                        },
                    },
                },
            );

            addGraphToStep(b, graph_step, mod, target, polystate_mod, graph_install_dir, example_name);
        }
    }
}

fn addGraphToStep(
    b: *std.Build,
    step: *std.Build.Step,
    mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    polystate: *std.Build.Module,
    install_dir: std.Build.InstallDir,
    dst_rel_path: []const u8,
) void {
    const graph_file = addGraphFile(b, "graph", mod, 100, .graphviz, polystate, target);

    const dot_cmd = b.addSystemCommand(&.{"dot"});

    dot_cmd.addArg("-Tsvg");

    dot_cmd.addFileArg(graph_file);

    const graph_svg = dot_cmd.captureStdOut();

    const install_graph_svg = b.addInstallFileWithDir(graph_svg, install_dir, b.pathJoin(&.{ dst_rel_path, "graph.svg" }));

    step.dependOn(&install_graph_svg.step);
}

pub const GraphMode = enum {
    graphviz,
    mermaid,
    json,
};

pub fn addGraphFile(
    b: *std.Build,
    module_name: []const u8,
    module: *std.Build.Module,
    max_len: usize,
    graph_mode: GraphMode,
    polystate: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) std.Build.LazyPath {
    const options = b.addOptions();
    const writer = options.contents.writer();
    writer.print(
        \\const std = @import("std");
        \\const ps = @import("polystate");
        \\const Target = @import("{s}");
        \\pub fn main() !void {{
        \\  var gpa_instance = std.heap.GeneralPurposeAllocator(.{{}}){{}};
        \\  const gpa = gpa_instance.allocator();
        \\  var graph = try ps.Graph.initWithFsm(gpa, Target.EnterFsmState, {d});
        \\  defer graph.deinit();
        \\  const writer = std.io.getStdOut().writer();
        \\  try graph.{s}(writer);
        \\}}
    , .{ module_name, max_len, switch (graph_mode) {
        .graphviz => "generateDot",
        .mermaid => "generateMermaid",
        .json => "generateJson",
    } }) catch @panic("OOM");

    const opt_mod = b.createModule(.{
        .root_source_file = options.getOutput(),
        .target = target,
        .imports = &.{
            .{ .name = "polystate", .module = polystate },
            .{ .name = b.allocator.dupe(u8, module_name) catch @panic("OOM"), .module = module },
        },
    });

    const gen_exe_name = std.mem.concat(b.allocator, u8, &.{ "_generate_graph_for_", module_name }) catch @panic("OOM");
    const opt_exe = b.addExecutable(.{
        .name = gen_exe_name,
        .root_module = opt_mod,
    });
    const run = b.addRunArtifact(opt_exe);
    return run.captureStdOut();
}

pub fn addInstallGraphFile(
    b: *std.Build,
    module_name: []const u8,
    module: *std.Build.Module,
    max_len: usize,
    graph_mode: GraphMode,
    polystate: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    install_dir: std.Build.InstallDir,
) *std.Build.Step.InstallFile {
    const dot_file = addGraphFile(b, module_name, module, max_len, graph_mode, polystate, target);

    const output_name = std.mem.concat(b.allocator, u8, &.{ module_name, switch (graph_mode) {
        .graphviz => ".dot",
        .mermaid => ".mmd",
        .json => ".json",
    } }) catch @panic("OOM");
    return b.addInstallFileWithDir(dot_file, install_dir, output_name);
}
