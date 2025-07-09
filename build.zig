const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const polystate = b.addModule("root", .{
        .root_source_file = b.path("src/polystate.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addStaticLibrary(.{
        .name = "polystate",
        .root_module = polystate,
    });

    b.installArtifact(lib);

    const mod_tests = b.addTest(.{
        .root_module = polystate,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

pub const GraphMode = enum {
    graphviz,
    mermaid,
};

pub fn generateGraph(
    b: *std.Build,
    module_name: []const u8,
    module: *std.Build.Module,
    graph_mode: GraphMode,
    polystate: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
) void {
    const options = b.addOptions();
    const writer = options.contents.writer();
    writer.print(
        \\const std = @import("std");
        \\const ps = @import("polystate");
        \\const Target = @import("{s}");
        \\pub fn main() !void {{
        \\  var gpa_instance = std.heap.GeneralPurposeAllocator(.{{}}){{}};
        \\  const gpa = gpa_instance.allocator();
        \\  var graph = try ps.Graph.initWithFsm(gpa, Target.EnterFsmState, 1_000_000);
        \\  defer graph.deinit();
        \\  const writer = std.io.getStdOut().writer();
        \\  try graph.{s}(writer);
        \\}}
    , .{ module_name, switch (graph_mode) {
        .graphviz => "generateDot",
        .mermaid => "generateMermaid",
    } }) catch @panic("OOM");

    const opt_mod = b.createModule(.{
        .root_source_file = options.getOutput(),
        .target = target,
        .imports = &.{
            .{ .name = "polystate", .module = polystate.module("root") },
            .{ .name = b.allocator.dupe(u8, module_name) catch @panic("OOM"), .module = module },
        },
    });

    const gen_exe_name = std.mem.concat(b.allocator, u8, &.{ "_generate_dot_for_", module_name }) catch @panic("OOM");
    const opt_exe = b.addExecutable(.{
        .name = gen_exe_name,
        .root_module = opt_mod,
    });
    const run = b.addRunArtifact(opt_exe);
    const dot_file = run.captureStdOut();

    const output_name = std.mem.concat(b.allocator, u8, &.{ module_name, switch (graph_mode) {
        .graphviz => ".dot",
        .mermaid => ".mmd",
    } }) catch @panic("OOM");
    const install_dot_file = b.addInstallFile(dot_file, output_name);
    b.getInstallStep().dependOn(&install_dot_file.step);
}
