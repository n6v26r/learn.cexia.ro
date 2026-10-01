const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const Json = std.json.Value;
const Allocator = std.mem.Allocator;
const Writer = Io.Writer;

pub fn sourceText(alloc: Allocator, value: *const Json) ![]const u8 {
    return switch (value.*) {
        .string => |s| s,
        .array => |array| blk: {
            var out = Writer.Allocating.init(alloc);
            defer out.deinit();
            for (array.items) |item| try out.writer.writeAll(item.string);
            break :blk try alloc.dupe(u8, out.written());
        },
        else => error.InvalidNotebook,
    };
}

pub fn join(alloc: Allocator, parts: []const []const u8) ![]const u8 {
    var out = Writer.Allocating.init(alloc);
    defer out.deinit();
    for (parts) |part| {
        if (part.len == 0) continue;
        if (out.written().len != 0) try out.writer.writeByte('/');
        try out.writer.writeAll(part);
    }
    return try alloc.dupe(u8, out.written());
}

pub fn breadcrumbHtml(alloc: Allocator, page: []const u8) ![]const u8 {
    var out = Writer.Allocating.init(alloc);
    defer out.deinit();
    try out.writer.writeAll("<a href=\"/\">~</a>");
    var start: usize = 0;
    while (start < page.len) {
        const end = std.mem.indexOfScalarPos(u8, page, start, '/') orelse page.len;
        try out.writer.print("<a href=\"/{s}/\">{s}</a>", .{ page[0..end], page[start..end] });
        start = end + 1;
    }
    return try alloc.dupe(u8, out.written());
}

pub fn titleFromSlug(alloc: Allocator, slug: []const u8) ![]const u8 {
    var out = Writer.Allocating.init(alloc);
    defer out.deinit();
    var upper = true;
    for (slug) |c| {
        if (c == '-' or c == '_') {
            try out.writer.writeByte(' ');
            upper = true;
        } else if (upper) {
            try out.writer.writeByte(std.ascii.toUpper(c));
            upper = false;
        } else {
            try out.writer.writeByte(c);
        }
    }
    return try alloc.dupe(u8, out.written());
}

pub fn slugify(alloc: Allocator, text: []const u8) ![]const u8 {
    var out = std.array_list.Managed(u8).init(alloc);
    var dash = false;
    for (text) |c| {
        const lower = std.ascii.toLower(c);
        if (std.ascii.isAlphanumeric(lower)) {
            try out.append(lower);
            dash = false;
        } else if (!dash) {
            try out.append('-');
            dash = true;
        }
    }
    while (out.items.len > 0 and out.items[out.items.len - 1] == '-') _ = out.pop();
    if (out.items.len == 0) try out.appendSlice("asset");
    return out.toOwnedSlice();
}

pub fn writeFenceBody(w: *Writer, value: []const u8) !void {
    var rest = value;
    while (std.mem.indexOf(u8, rest, "```")) |idx| {
        try w.writeAll(rest[0..idx]);
        try w.writeAll("``\\`");
        rest = rest[idx + 3 ..];
    }
    try w.writeAll(rest);
}

pub fn writeFile(root: Dir, io: Io, path: []const u8, data: []const u8) !void {
    var file = try root.createFileAtomic(io, path, .{ .make_path = true, .replace = true });
    defer file.deinit(io);
    try file.file.writeStreamingAll(io, data);
    try file.replace(io);
}
