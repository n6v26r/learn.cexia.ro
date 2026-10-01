const std = @import("std");
const zine = @import("zine");

const notebooks = @import("build/notebooks/tree.zig");
const notebook_types = @import("build/notebooks/types.zig");
const site = @import("build/site.zig");

pub fn build(b: *std.Build) void {
    const serve_host = b.option([]const u8, "serve-host", "Host used by `zig build serve`") orelse "localhost";
    const serve_port = b.option(u16, "serve-port", "Port used by `zig build serve`") orelse 1991;

    setupClean(b);

    const io = b.graph.io;
    const root = b.root.root_dir.handle;
    const generated_dirs: []const []const u8 = &.{ "zig-out/dist", "zig-out/.zine-release-raw", "zig-out/release", notebook_types.out_dir, notebook_types.staging_dir };
    for (generated_dirs) |path| {
        root.deleteTree(io, path) catch |err| std.debug.panic("failed to clean {s}: {s}", .{ path, @errorName(err) });
    }

    notebooks.generate(b) catch |err| std.debug.panic("failed to generate notebooks: {s}", .{@errorName(err)});
    const assets = site.materializeAssets(b);

    const website = zine.website(b, .{
        .output_path = "dist",
        .force = true,
    });
    website.step.dependOn(assets);
    b.getInstallStep().dependOn(&website.step);

    const serve = b.step("serve", "Start the Zine dev server");
    const watcher = b.addExecutable(.{
        .name = "site-watcher",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/watch.zig"),
            .target = b.graph.host,
        }),
    });
    const ziggy_impl = b.dependency("ziggy", .{
        .target = b.graph.host,
        .optimize = .Debug,
    }).module("ziggy");
    const ziggy = b.createModule(.{
        .root_source_file = b.path("build/ziggy.zig"),
        .imports = &.{.{ .name = "ziggy_impl", .module = ziggy_impl }},
    });
    watcher.root_module.addImport("ziggy", ziggy);
    const zine_dep = b.dependencyFromBuildZig(zine, .{
        .optimize = .ReleaseFast,
        .scope = @as([]const []const u8, &.{}),
        .@"no-git-version" = true,
    });
    const run_watcher = b.addRunArtifact(watcher);
    run_watcher.addArtifactArg(zine_dep.artifact("zine"));
    run_watcher.addArgs(&.{ "--host", serve_host });
    run_watcher.addArg(b.fmt("--port={d}", .{serve_port}));
    run_watcher.step.dependOn(assets);
    serve.dependOn(&run_watcher.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/watch.zig"),
            .target = b.graph.host,
        }),
    });
    tests.root_module.addImport("ziggy", ziggy);
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run project tests").dependOn(&run_tests.step);

    site.release(b, assets);
}

fn setupClean(b: *std.Build) void {
    const clean = b.addSystemCommand(&.{
        "rm",                  "-rf",
        ".smd.ziggy-schema",   ".zine.ziggy-schema",
        "assets/fonts",        "assets/katex.min.css",
        "assets/katex.min.js", "assets/render-katex.js",
        "node_modules",        "ssg/__pycache__",
        "zig-out",             "zig-pkg",
    });
    clean.setName("clean generated files");
    clean.has_side_effects = true;
    clean.expectExitCode(0);
    clean.setCwd(b.path("."));

    b.step("clean", "Remove generated build artifacts").dependOn(&clean.step);
}
