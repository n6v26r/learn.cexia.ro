const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const Json = std.json.Value;
const Allocator = std.mem.Allocator;
const Writer = Io.Writer;

const markdown_mod = @import("markdown.zig");
const meta_mod = @import("meta.zig");
const output = @import("output.zig");
const result_mod = @import("result.zig");
const types = @import("types.zig");
const util = @import("util.zig");

pub fn notebook(alloc: Allocator, io: Io, root: Dir, out_dir: []const u8, rel: []const u8) !void {
    const source_path = try util.join(alloc, &.{ "site", rel });
    const notebook_bytes = try root.readFileAlloc(io, source_path, alloc, .unlimited);
    const parsed = try std.json.parseFromSlice(Json, alloc, notebook_bytes, .{});
    defer parsed.deinit();

    const dir = std.fs.path.dirname(rel) orelse "";
    const stem = std.fs.path.stem(std.fs.path.basename(rel));
    const page_path = try util.join(alloc, &.{ dir, stem });
    const asset_path = try util.join(alloc, &.{ out_dir, page_path });

    try root.createDirPath(io, asset_path);
    try root.copyFile(source_path, root, try util.join(alloc, &.{ asset_path, "notebook.ipynb" }), io, .{ .make_path = true });

    const cells = parsed.value.object.get("cells").?.array.items;
    const meta_name = try std.fmt.allocPrint(alloc, "{s}.smd", .{stem});
    const sidecar = try meta_mod.loadSmd(alloc, io, root, try util.join(alloc, &.{ "site", dir, meta_name }));
    var meta = sidecar.meta;
    var strip_title = false;
    var title: []const u8 = if (meta.title) |v| std.mem.trim(u8, v, " \t\r\n") else "";
    if (meta.title == null and cells.len > 0 and std.mem.eql(u8, cells[0].object.get("cell_type").?.string, "markdown")) {
        const source = cells[0].object.get("source").?;
        title = try markdown_mod.firstLineTitle(alloc, try util.sourceText(alloc, &source));
        strip_title = title.len > 0;
    }
    if (title.len == 0) title = try util.titleFromSlug(alloc, stem);

    const language_info = parsed.value.object.get("metadata").?.object.get("language_info").?;
    const language = language_info.object.get("name").?.string;
    const version = if (language_info.object.getPtr("version")) |v| v.string else null;
    try meta_mod.inferRuntime(alloc, &parsed.value, &meta.custom);

    var smd = Writer.Allocating.init(alloc);
    defer smd.deinit();
    if (meta.custom.result) |v| {
        const with_total = try result_mod.addTotal(alloc, v);
        meta.custom.result = try result_mod.addText(alloc, with_total, &meta.custom);
    }
    meta.custom.crumbs = try util.breadcrumbHtml(alloc, page_path);
    meta.custom.python = version;
    if (meta.custom.gpu) |v| {
        if (v.len == 0 or std.ascii.eqlIgnoreCase(v, "none")) meta.custom.gpu = null;
    }

    meta.title = title;
    if (meta.layout == null) meta.layout = "notebook.shtml";
    try meta_mod.writeFrontmatter(&smd.writer, meta);
    try smd.writer.writeAll(sidecar.body);
    if (!std.mem.endsWith(u8, sidecar.body, "\n")) try smd.writer.writeByte('\n');
    try smd.writer.writeByte('\n');

    for (cells, 0..) |cell, idx| {
        const obj = cell.object;
        const cell_type = obj.get("cell_type").?.string;
        const source = obj.get("source").?;
        var source_text = try util.sourceText(alloc, &source);

        if (std.mem.eql(u8, cell_type, "markdown")) {
            if (idx == 0 and strip_title) source_text = markdown_mod.dropFirstLine(source_text);
            if (std.mem.trim(u8, source_text, " \t\r\n").len == 0) continue;
            try smd.writer.print("[]($section.id('cell-{d:0>3}').attrs('nb-cell','nb-markdown'))\n\n", .{idx + 1});
            try smd.writer.print("{s}\n\n", .{try markdown_mod.cellText(alloc, io, root, cell, source_text, idx + 1, asset_path)});
            continue;
        }

        if (std.mem.eql(u8, cell_type, "code")) {
            try smd.writer.print("[]($section.id('cell-{d:0>3}').attrs('nb-cell','nb-code'))\n\n", .{idx + 1});
            try smd.writer.print("```{s}\n", .{language});
            try util.writeFenceBody(&smd.writer, std.mem.trimEnd(u8, source_text, "\r\n"));
            try smd.writer.writeAll("\n```\n\n");

            for (obj.get("outputs").?.array.items, 0..) |out, output_idx| {
                try output.render(alloc, io, root, &smd.writer, out, idx + 1, output_idx + 1, asset_path);
            }
            continue;
        }

        return error.UnsupportedNotebookCell;
    }

    try util.writeFile(root, io, try util.join(alloc, &.{ out_dir, dir, meta_name }), smd.written());
}

pub fn markdown(alloc: Allocator, io: Io, root: Dir, out_dir: []const u8, rel: []const u8) !void {
    const dir = std.fs.path.dirname(rel) orelse "";
    const stem = std.fs.path.stem(std.fs.path.basename(rel));
    const notebook_path = try util.join(alloc, &.{ "site", dir, try std.fmt.allocPrint(alloc, "{s}.ipynb", .{stem}) });
    var paired = root.openFile(io, notebook_path, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (paired) |*file| {
        file.close(io);
        return;
    }

    const source = try meta_mod.loadSmd(alloc, io, root, try util.join(alloc, &.{ "site", rel }));
    var meta = source.meta;
    var body = source.body;
    var title = if (meta.title) |value| std.mem.trim(u8, value, " \t\r\n") else "";
    if (title.len == 0) {
        title = try markdown_mod.firstLineTitle(alloc, body);
        if (title.len > 0) body = markdown_mod.dropFirstLine(body);
    }
    if (title.len == 0) title = try util.titleFromSlug(alloc, stem);

    const page_path = try util.join(alloc, &.{ dir, stem });
    meta.title = title;
    if (meta.layout == null) meta.layout = "markdown.shtml";
    meta.custom.crumbs = try util.breadcrumbHtml(alloc, page_path);

    var out = Writer.Allocating.init(alloc);
    defer out.deinit();
    try meta_mod.writeFrontmatter(&out.writer, meta);
    try out.writer.writeAll("[]($section.id('content'))\n\n");
    try out.writer.writeAll(try markdown_mod.bodyText(alloc, body));
    if (!std.mem.endsWith(u8, body, "\n")) try out.writer.writeByte('\n');
    try util.writeFile(root, io, try util.join(alloc, &.{ out_dir, dir, try std.fmt.allocPrint(alloc, "{s}.smd", .{stem}) }), out.written());
}
