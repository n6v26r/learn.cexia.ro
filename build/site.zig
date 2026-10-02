const std = @import("std");
const builtin = @import("builtin");
const zine = @import("zine");

const katex_fonts = .{
    "KaTeX_AMS-Regular.woff2",
    "KaTeX_Caligraphic-Bold.woff2",
    "KaTeX_Caligraphic-Regular.woff2",
    "KaTeX_Fraktur-Bold.woff2",
    "KaTeX_Fraktur-Regular.woff2",
    "KaTeX_Main-BoldItalic.woff2",
    "KaTeX_Main-Bold.woff2",
    "KaTeX_Main-Italic.woff2",
    "KaTeX_Main-Regular.woff2",
    "KaTeX_Math-BoldItalic.woff2",
    "KaTeX_Math-Italic.woff2",
    "KaTeX_SansSerif-Bold.woff2",
    "KaTeX_SansSerif-Italic.woff2",
    "KaTeX_SansSerif-Regular.woff2",
    "KaTeX_Script-Regular.woff2",
    "KaTeX_Size1-Regular.woff2",
    "KaTeX_Size2-Regular.woff2",
    "KaTeX_Size3-Regular.woff2",
    "KaTeX_Size4-Regular.woff2",
    "KaTeX_Typewriter-Regular.woff2",
};

const Tools = struct {
    node: std.Build.LazyPath,
    npm: std.Build.LazyPath,
    python: std.Build.LazyPath,
};

const render_katex_script =
    \\const eqns = document.querySelectorAll("script[type='math/tex']");
    \\for (let i = eqns.length - 1; i >= 0; i--) {
    \\    const eqn = eqns[i];
    \\    const displayMode = eqn.closest("p") == null;
    \\    eqn.outerHTML = katex.renderToString(eqn.textContent, {
    \\        displayMode,
    \\        throwOnError: false,
    \\    });
    \\}
    \\
;

pub fn materializeAssets(b: *std.Build) *std.Build.Step {
    const assets = b.addUpdateSourceFiles();
    assets.step.name = "materialize assets";

    const katex = b.dependency("katex", .{});
    const katex_font_assets = b.dependency("font_katex", .{});
    assets.addCopyFileToSource(katex.path("dist/katex.min.css"), "assets/katex.min.css");
    assets.addCopyFileToSource(katex.path("dist/katex.min.js"), "assets/katex.min.js");
    inline for (katex_fonts) |font| {
        assets.addCopyFileToSource(katex_font_assets.path("dist/fonts/" ++ font), "assets/fonts/" ++ font);
    }
    assets.addBytesToSource(render_katex_script, "assets/render-katex.js");

    const lexend = b.dependency("font_lexend", .{});
    const maple = b.dependency("font_maple_mono", .{});
    const merriweather = b.dependency("font_merriweather", .{});

    assets.addCopyFileToSource(lexend.path("files/lexend-latin-400-normal.woff2"), "assets/fonts/Lexend-Regular.woff2");
    assets.addCopyFileToSource(lexend.path("files/lexend-latin-700-normal.woff2"), "assets/fonts/Lexend-Bold.woff2");
    assets.addCopyFileToSource(lexend.path("files/lexend-latin-ext-400-normal.woff2"), "assets/fonts/Lexend-Regular-LatinExt.woff2");
    assets.addCopyFileToSource(lexend.path("files/lexend-latin-ext-700-normal.woff2"), "assets/fonts/Lexend-Bold-LatinExt.woff2");
    assets.addCopyFileToSource(maple.path("MapleMono-NF-Regular.woff2"), "assets/fonts/MapleMono-NF-Regular.woff2");
    assets.addCopyFileToSource(merriweather.path("files/merriweather-latin-400-normal.woff2"), "assets/fonts/Merriweather-Regular.woff2");
    assets.addCopyFileToSource(merriweather.path("files/merriweather-latin-ext-400-normal.woff2"), "assets/fonts/Merriweather-Regular-LatinExt.woff2");

    return &assets.step;
}

pub fn release(b: *std.Build, assets: *std.Build.Step) void {
    const tools = hostTools(b);

    const node_packages = run(b, tools.node);
    node_packages.addFileArg(tools.npm);
    node_packages.addArgs(&.{
        "ci",
        "--ignore-scripts",
        "--no-audit",
        "--no-fund",
        "--update-notifier=false",
        "--userconfig",
        "zig-out/.npm-userconfig",
        "--globalconfig",
        "zig-out/.npm-globalconfig",
        "--cache",
        "zig-out/.npm-cache",
    });
    node_packages.setEnvironmentVariable("HOME", "zig-out/.home");
    node_packages.setEnvironmentVariable("NO_UPDATE_NOTIFIER", "1");
    node_packages.setEnvironmentVariable("NPM_CONFIG_UPDATE_NOTIFIER", "false");
    node_packages.setName("install node packages");
    node_packages.has_side_effects = true;

    const python_packages = run(b, tools.python);
    python_packages.addArgs(&.{
        "-m",
        "pip",
        "--isolated",
        "install",
        "--upgrade",
        "--disable-pip-version-check",
        "--no-input",
        "--only-binary=:all:",
        "--cache-dir",
        "zig-out/.pip-cache",
        "--target",
        "zig-out/python-packages",
        "-r",
        "requirements-build.txt",
    });
    python_packages.setEnvironmentVariable("HOME", "zig-out/.home");
    python_packages.setEnvironmentVariable("PYTHONNOUSERSITE", "1");
    python_packages.setName("install python packages");
    python_packages.has_side_effects = true;

    const raw_release = zine.website(b, .{
        .output_path = ".zine-release-raw",
        .force = true,
    });
    raw_release.step.dependOn(assets);

    const render_katex = run(b, tools.node);
    render_katex.addArgs(&.{ "ssg/render-katex.js", "zig-out/.zine-release-raw", "--release" });
    render_katex.setName("render katex");
    render_katex.has_side_effects = true;
    render_katex.step.dependOn(&raw_release.step);

    const subset_fonts = run(b, tools.python);
    subset_fonts.addArgs(&.{ "-B", "ssg/subset-fonts.py" });
    subset_fonts.setName("subset fonts");
    subset_fonts.has_side_effects = true;
    subset_fonts.setEnvironmentVariable("PYTHONPATH", "zig-out/python-packages");
    subset_fonts.setEnvironmentVariable("PYTHONNOUSERSITE", "1");
    subset_fonts.step.dependOn(&render_katex.step);
    subset_fonts.step.dependOn(&python_packages.step);

    const cache_bust = run(b, tools.python);
    cache_bust.addArgs(&.{ "-B", "ssg/cache-bust.py" });
    cache_bust.setName("cache bust assets");
    cache_bust.has_side_effects = true;
    cache_bust.setEnvironmentVariable("PYTHONNOUSERSITE", "1");
    cache_bust.step.dependOn(&subset_fonts.step);

    const minify = run(b, tools.node);
    minify.addArgs(&.{ "ssg/minify.mjs", "zig-out/release" });
    minify.setName("minify release");
    minify.has_side_effects = true;
    minify.step.dependOn(&cache_bust.step);
    minify.step.dependOn(&node_packages.step);

    b.step("release", "Build a minified, cache-busted release site").dependOn(&minify.step);
}

fn hostTools(b: *std.Build) Tools {
    if (builtin.os.tag != .linux or builtin.cpu.arch != .x86_64) {
        @panic("pinned helper toolchain is linux x86_64 only");
    }

    const node = b.dependency("node_linux_x64", .{});
    const python = b.dependency("python_linux_x64", .{});

    return .{
        .node = node.path("bin/node"),
        .npm = node.path("lib/node_modules/npm/bin/npm-cli.js"),
        .python = python.path("bin/python3"),
    };
}

fn run(b: *std.Build, exe: std.Build.LazyPath) *std.Build.Step.Run {
    const cmd = std.Build.Step.Run.create(b, "run helper");
    cmd.addFileArg(exe);
    cmd.setCwd(b.path("."));
    cmd.expectExitCode(0);
    return cmd;
}
