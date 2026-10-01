const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const Json = std.json.Value;
const Allocator = std.mem.Allocator;
const Writer = Io.Writer;

const assets = @import("assets.zig");
const types = @import("types.zig");
const util = @import("util.zig");

pub fn firstLineTitle(alloc: Allocator, text: []const u8) ![]const u8 {
    const line_end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;

    var title = std.mem.trim(u8, text[0..line_end], " \t\r");
    while (title.len > 0 and title[0] == '#') title = title[1..];
    title = std.mem.trim(u8, title, " \t\r");

    var out = Writer.Allocating.init(alloc);
    defer out.deinit();
    var in_tag = false;
    for (title) |char| {
        if (char == '<') in_tag = true;
        if (!in_tag) try out.writer.writeByte(char);
        if (char == '>') in_tag = false;
    }
    return try alloc.dupe(u8, std.mem.trim(u8, out.written(), " \t\r"));
}

pub fn dropFirstLine(text: []const u8) []const u8 {
    const line_end = std.mem.indexOfScalar(u8, text, '\n') orelse return "";
    return text[line_end + 1 ..];
}

pub fn bodyText(alloc: Allocator, text: []const u8) ![]const u8 {
    return htmlBlocks(alloc, try math(alloc, text));
}

pub fn cellText(alloc: Allocator, io: Io, root: Dir, cell: Json, source: []const u8, idx: usize, asset_path: []const u8) ![]const u8 {
    var text = try stripTextFenceLanguage(alloc, source);
    text = try math(alloc, text);
    if (cell.object.getPtr("attachments")) |attachments| {
        var it = attachments.object.iterator();
        while (it.next()) |entry| {
            const safe = try util.slugify(alloc, std.fs.path.stem(entry.key_ptr.*));
            const mime, const ext = blk: {
                inline for (types.image_mimes) |image| {
                    if (entry.value_ptr.object.get(image.mime) != null) break :blk .{ image.mime, image.ext };
                }
                @panic("unsupported notebook image attachment");
            };
            const filename = try std.fmt.allocPrint(alloc, "cell-{d:0>3}-attachment-{s}.{s}", .{ idx, safe, ext });
            try assets.writeDataAsset(alloc, io, root, try util.join(alloc, &.{ asset_path, filename }), mime, entry.value_ptr.object.getPtr(mime).?);
            text = try attachmentImages(alloc, text, entry.key_ptr.*, filename);
        }
    }
    text = try inlineDataImages(alloc, io, root, text, idx, asset_path);
    return try htmlBlocks(alloc, text);
}

fn htmlBlocks(alloc: Allocator, text: []const u8) ![]const u8 {
    var out = Writer.Allocating.init(alloc);
    defer out.deinit();
    var lines = std.mem.splitScalar(u8, text, '\n');
    var fence_char: u8 = 0;
    var fence_len: usize = 0;
    var details_depth: usize = 0;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (fence_len == 0) {
            if (std.mem.eql(u8, trimmed, "<details>")) {
                details_depth += 1;
                continue;
            }
            if (details_depth > 0 and std.mem.eql(u8, trimmed, "</details>")) {
                details_depth -= 1;
                try out.writer.writeByte('\n');
                continue;
            }
        }
        for (0..details_depth) |_| try out.writer.writeAll("> ");
        if (fence_len == 0 and details_depth > 0 and std.mem.startsWith(u8, trimmed, "<summary>") and std.mem.endsWith(u8, trimmed, "</summary>")) {
            try out.writer.print("# [{s}]($block.collapsible(false))\n", .{trimmed[9 .. trimmed.len - 10]});
            continue;
        }
        if (fence_len == 0 and std.mem.startsWith(u8, trimmed, "<a id=\"") and std.mem.endsWith(u8, trimmed, "\"></a>")) {
            const id = trimmed[7 .. trimmed.len - 6];
            if (id.len > 0 and std.mem.indexOfNone(u8, id, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_") == null) {
                try out.writer.print("[]($section.id('{s}').attrs('nb-markdown'))\n", .{id});
                continue;
            }
        }
        if (trimmed.len > 0 and (trimmed[0] == '`' or trimmed[0] == '~')) {
            const run = std.mem.indexOfNone(u8, trimmed, trimmed[0..1]) orelse trimmed.len;
            if (fence_len == 0 and run >= 3) {
                fence_char = trimmed[0];
                fence_len = run;
            } else if (trimmed[0] == fence_char and run >= fence_len and run == trimmed.len) {
                fence_len = 0;
            }
        }

        const html_line = fence_len == 0 and
            line.len - std.mem.trimStart(u8, line, " ").len <= 3 and
            startsHtml(trimmed);
        if (html_line) {
            try out.writer.print("```=html\n{s}\n```", .{line});
        } else {
            try out.writer.writeAll(line);
        }
        if (lines.peek() != null) try out.writer.writeByte('\n');
    }
    return try alloc.dupe(u8, out.written());
}

fn startsHtml(line: []const u8) bool {
    if (std.mem.startsWith(u8, line, "<!--")) return true;
    if (line.len < 3 or line[0] != '<') return false;
    var i: usize = if (line[1] == '/') 2 else 1;
    if (i == line.len or !std.ascii.isAlphabetic(line[i])) return false;
    while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '-')) : (i += 1) {}
    return i < line.len and std.mem.indexOfScalar(u8, " \t\r/>", line[i]) != null;
}

test "details preserve Markdown through native collapsible blocks" {
    const source =
        "<details>\n" ++
        "<summary>Show answers</summary>\n\n" ++
        "1. First answer.\n" ++
        "2. Second answer.\n\n" ++
        "</details>";
    const expected =
        "> # [Show answers]($block.collapsible(false))\n> \n" ++
        "> 1. First answer.\n" ++
        "> 2. Second answer.\n> \n\n";

    const actual = try htmlBlocks(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

pub fn math(alloc: Allocator, text: []const u8) ![]const u8 {
    var out = Writer.Allocating.init(alloc);
    defer out.deinit();
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '\\' and i + 1 < text.len and text[i + 1] == '$') {
            try out.writer.writeAll(text[i .. i + 2]);
            i += 2;
            continue;
        }
        if (i + 1 < text.len and text[i] == '$' and text[i + 1] == '$') {
            var end = i + 2;
            while (end + 1 < text.len and !(text[end] == '$' and text[end + 1] == '$')) : (end += 1) {}
            if (end + 1 < text.len) {
                try out.writer.writeAll("\n```=mathtex\n");
                try out.writer.writeAll(std.mem.trim(u8, text[i + 2 .. end], "\n\r"));
                try out.writer.writeAll("\n```\n");
                i = end + 2;
                continue;
            }
        }
        if (text[i] == '$') {
            var end = i + 1;
            while (end < text.len and text[end] != '$') : (end += 1) {}
            if (end < text.len) {
                try out.writer.writeAll("[`");
                try out.writer.writeAll(text[i + 1 .. end]);
                try out.writer.writeAll("`]($mathtex)");
                i = end + 1;
                continue;
            }
        }
        try out.writer.writeByte(text[i]);
        i += 1;
    }
    return try alloc.dupe(u8, out.written());
}

fn attachmentImages(alloc: Allocator, text: []const u8, attachment: []const u8, filename: []const u8) ![]const u8 {
    const needle = try std.fmt.allocPrint(alloc, "](attachment:{s})", .{attachment});
    var out = Writer.Allocating.init(alloc);
    defer out.deinit();
    var rest = text;
    while (std.mem.indexOf(u8, rest, needle)) |close| {
        const start = std.mem.lastIndexOf(u8, rest[0..close], "![") orelse {
            try out.writer.writeAll(rest[0 .. close + needle.len]);
            rest = rest[close + needle.len ..];
            continue;
        };
        const before = std.mem.trimEnd(u8, rest[0..start], " \t");
        try imageDirective(&out.writer, before, filename);
        rest = std.mem.trimStart(u8, rest[close + needle.len ..], " \t");
        if (rest.len > 0) try out.writer.writeAll("\n\n");
    }
    try out.writer.writeAll(rest);
    return try alloc.dupe(u8, out.written());
}

fn inlineDataImages(alloc: Allocator, io: Io, root: Dir, text: []const u8, idx: usize, asset_path: []const u8) ![]const u8 {
    var out = Writer.Allocating.init(alloc);
    defer out.deinit();
    var rest = text;
    var nth: usize = 1;
    while (std.mem.indexOf(u8, rest, "](data:image/")) |close| {
        const start = std.mem.lastIndexOf(u8, rest[0..close], "![") orelse {
            try out.writer.writeAll(rest[0 .. close + 2]);
            rest = rest[close + 2 ..];
            continue;
        };
        const uri_start = close + 2;
        const uri_end = std.mem.indexOfScalarPos(u8, rest, uri_start, ')').?;
        const uri = rest[uri_start..uri_end];
        const comma = std.mem.indexOfScalar(u8, uri, ',').?;
        const semi = std.mem.indexOfScalar(u8, uri, ';').?;
        const mime = uri["data:".len..semi];
        const ext = blk: {
            inline for (types.image_mimes) |image| {
                if (std.mem.eql(u8, mime, image.mime)) break :blk image.ext;
            }
            @panic("unsupported inline image mime");
        };
        const filename = try std.fmt.allocPrint(alloc, "cell-{d:0>3}-inline-{d:0>2}.{s}", .{ idx, nth, ext });
        try assets.writeBase64Asset(alloc, io, root, try util.join(alloc, &.{ asset_path, filename }), uri[comma + 1 ..]);

        const before = std.mem.trimEnd(u8, rest[0..start], " \t");
        try imageDirective(&out.writer, before, filename);
        rest = std.mem.trimStart(u8, rest[uri_end + 1 ..], " \t");
        if (rest.len > 0) try out.writer.writeAll("\n\n");
        nth += 1;
    }
    try out.writer.writeAll(rest);
    return try alloc.dupe(u8, out.written());
}

fn imageDirective(w: *Writer, before: []const u8, filename: []const u8) !void {
    if (before.len > 0) try w.print("{s}\n\n", .{before});
    try w.print("[]($image.asset('{s}'))", .{filename});
}

fn stripTextFenceLanguage(alloc: Allocator, text: []const u8) ![]const u8 {
    var out = Writer.Allocating.init(alloc);
    defer out.deinit();
    var rest = text;
    while (rest.len > 0) {
        const line_end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
        const line = rest[0..line_end];
        const trimmed = std.mem.trim(u8, line, " \t\r");
        try out.writer.writeAll(if (std.mem.eql(u8, trimmed, "```text")) "```" else line);
        if (line_end == rest.len) break;
        try out.writer.writeByte('\n');
        rest = rest[line_end + 1 ..];
    }
    return try alloc.dupe(u8, out.written());
}
