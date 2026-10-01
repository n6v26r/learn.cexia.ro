const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const Allocator = std.mem.Allocator;
const Writer = Io.Writer;

const meta_mod = @import("meta.zig");
const render = @import("render.zig");
const types = @import("types.zig");
const util = @import("util.zig");

pub fn generate(b: *std.Build) !void {
    try generateAt(b.allocator, b.graph.io, b.root.root_dir.handle, types.out_dir);
}

pub fn generateAt(alloc: Allocator, io: Io, root: Dir, out_dir: []const u8) !void {
    try root.createDirPath(io, out_dir);

    try writeFolderPage(alloc, io, root, out_dir, "");

    var site_dir = try root.openDir(io, "site", .{ .iterate = true });
    defer site_dir.close(io);

    var walker = try site_dir.walk(alloc);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        const rel = try alloc.dupe(u8, entry.path);
        if (entry.kind == .directory) {
            try writeFolderPage(alloc, io, root, out_dir, rel);
        } else if (entry.kind == .file) {
            if (std.mem.endsWith(u8, rel, ".ipynb")) {
                try render.notebook(alloc, io, root, out_dir, rel);
            } else if (std.mem.endsWith(u8, rel, ".smd") and !std.mem.eql(u8, std.fs.path.basename(rel), "index.smd")) {
                try render.markdown(alloc, io, root, out_dir, rel);
            }
        }
    }
}

fn writeFolderPage(alloc: Allocator, io: Io, root: Dir, out_dir: []const u8, page: []const u8) !void {
    const smd = try meta_mod.loadSmd(alloc, io, root, try util.join(alloc, &.{ "site", page, "index.smd" }));
    var meta = smd.meta;
    var title = meta.title orelse "";
    if (title.len == 0) title = try util.titleFromSlug(alloc, std.fs.path.basename(page));

    var out = Writer.Allocating.init(alloc);
    defer out.deinit();
    meta.title = title;
    if (meta.layout == null) meta.layout = "folder.shtml";
    meta.custom.crumbs = try util.breadcrumbHtml(alloc, page);
    meta.custom.section = true;
    try meta_mod.writeFrontmatter(&out.writer, meta);

    try out.writer.writeAll(smd.body);
    if (!std.mem.endsWith(u8, smd.body, "\n")) try out.writer.writeByte('\n');
    try out.writer.writeByte('\n');

    try util.writeFile(root, io, try util.join(alloc, &.{ out_dir, page, "index.smd" }), out.written());
}
