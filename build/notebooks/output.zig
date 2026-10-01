const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const Json = std.json.Value;
const Allocator = std.mem.Allocator;
const Writer = Io.Writer;

const assets = @import("assets.zig");
const markdown = @import("markdown.zig");
const types = @import("types.zig");
const util = @import("util.zig");

const ansi_fg = [_][]const u8{ "ansi-black", "ansi-red", "ansi-green", "ansi-yellow", "ansi-blue", "ansi-magenta", "ansi-cyan", "ansi-white" };
const ansi_bg = [_][]const u8{ "ansi-bg-black", "ansi-bg-red", "ansi-bg-green", "ansi-bg-yellow", "ansi-bg-blue", "ansi-bg-magenta", "ansi-bg-cyan", "ansi-bg-white" };

pub fn render(alloc: Allocator, io: Io, root: Dir, w: *Writer, output: Json, cell: usize, nth: usize, asset_path: []const u8) !void {
    const obj = output.object;
    const output_type = obj.get("output_type").?.string;

    if (std.mem.eql(u8, output_type, "stream")) {
        const text = obj.get("text").?;
        return writePlain(w, try util.sourceText(alloc, &text));
    }

    if (std.mem.eql(u8, output_type, "error")) {
        const traceback = obj.get("traceback").?;
        try w.writeAll("```=html\n<pre class=\"nb-error\"><code>");
        try writeAnsiHtml(w, std.mem.trimEnd(u8, try util.sourceText(alloc, &traceback), "\r\n"));
        try w.writeAll("</code></pre>\n```\n\n");
        return;
    }

    if (!std.mem.eql(u8, output_type, "display_data") and !std.mem.eql(u8, output_type, "execute_result")) return error.UnsupportedNotebookOutput;

    const data = obj.get("data").?;
    if (data.object.getPtr("text/html")) |html| {
        try w.writeAll("```=html\n");
        try w.writeAll(try notebookHtml(alloc, try util.sourceText(alloc, html)));
        try w.writeAll("\n```\n\n");
        return;
    }

    inline for (types.image_mimes) |image| {
        if (data.object.getPtr(image.mime)) |value| {
            const filename = try std.fmt.allocPrint(alloc, "cell-{d:0>3}-output-{d:0>2}.{s}", .{ cell, nth, image.ext });
            try assets.writeDataAsset(alloc, io, root, try util.join(alloc, &.{ asset_path, filename }), image.mime, value);
            try w.print("[]($image.asset('{s}'))\n\n", .{filename});
            return;
        }
    }

    if (data.object.getPtr("text/markdown")) |md| return w.print("{s}\n\n", .{try markdown.math(alloc, try util.sourceText(alloc, md))});
    if (data.object.getPtr("text/plain")) |plain| return writePlain(w, try util.sourceText(alloc, plain));
    return error.UnsupportedNotebookMime;
}

fn writePlain(w: *Writer, text: []const u8) !void {
    try w.writeAll("```\n");
    try util.writeFenceBody(w, std.mem.trimEnd(u8, text, "\r\n"));
    try w.writeAll("\n```\n\n");
}

fn notebookHtml(alloc: Allocator, html: []const u8) ![]const u8 {
    var out = Writer.Allocating.init(alloc);
    defer out.deinit();

    var rest = html;
    while (rest.len > 0) {
        const style_start = std.mem.indexOf(u8, rest, "<style");
        const border_start = std.mem.indexOf(u8, rest, " border=\"");

        if (style_start != null and (border_start == null or style_start.? < border_start.?)) {
            try out.writer.writeAll(rest[0..style_start.?]);
            const style_end = std.mem.indexOf(u8, rest[style_start.?..], "</style>") orelse break;
            rest = rest[style_start.? + style_end + "</style>".len ..];
            continue;
        }

        if (border_start) |start| {
            try out.writer.writeAll(rest[0..start]);
            var end = start + " border=\"".len;
            while (end < rest.len and rest[end] != '"') : (end += 1) {}
            if (end == rest.len) {
                try out.writer.writeAll(rest[start..]);
                break;
            }
            rest = rest[end + 1 ..];
            continue;
        }

        try out.writer.writeAll(rest);
        break;
    }

    return try alloc.dupe(u8, out.written());
}

fn writeAnsiHtml(w: *Writer, text: []const u8) !void {
    var class: []const u8 = "";
    var bg_class: []const u8 = "";
    var bold = false;
    var dim = false;
    var span_open = false;
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == 0x1b and i + 1 < text.len and text[i + 1] == '[') {
            var end = i + 2;
            while (end < text.len and (text[end] < 0x40 or text[end] > 0x7e)) : (end += 1) {}
            if (end < text.len) {
                if (text[end] == 'm') {
                    if (span_open) try w.writeAll("</span>");
                    applyAnsi(&class, &bg_class, &bold, &dim, text[i + 2 .. end]);
                    span_open = class.len > 0 or bg_class.len > 0 or bold or dim;
                    if (span_open) try openAnsiSpan(w, class, bg_class, bold, dim);
                }
                i = end + 1;
                continue;
            }
        }

        switch (text[i]) {
            '&' => try w.writeAll("&amp;"),
            '<' => try w.writeAll("&lt;"),
            '>' => try w.writeAll("&gt;"),
            '"' => try w.writeAll("&quot;"),
            else => try w.writeByte(text[i]),
        }
        i += 1;
    }
    if (span_open) try w.writeAll("</span>");
}

fn openAnsiSpan(w: *Writer, class: []const u8, bg_class: []const u8, bold: bool, dim: bool) !void {
    try w.writeAll("<span class=\"");
    var spaced = false;
    const classes = [_][]const u8{ class, bg_class, if (bold) "ansi-bold" else "", if (dim) "ansi-dim" else "" };
    for (classes) |name| {
        if (name.len == 0) continue;
        if (spaced) try w.writeByte(' ');
        try w.writeAll(name);
        spaced = true;
    }
    try w.writeAll("\">");
}

fn applyAnsi(class: *[]const u8, bg_class: *[]const u8, bold: *bool, dim: *bool, params: []const u8) void {
    var it = std.mem.splitScalar(u8, params, ';');
    while (it.next()) |param| {
        const code = if (param.len == 0) 0 else std.fmt.parseInt(u16, param, 10) catch continue;
        switch (code) {
            0 => {
                class.* = "";
                bg_class.* = "";
                bold.* = false;
                dim.* = false;
            },
            1 => bold.* = true,
            2 => dim.* = true,
            22 => {
                bold.* = false;
                dim.* = false;
            },
            30...37 => class.* = ansi_fg[@intCast(code - 30)],
            90...97 => class.* = ansi_fg[@intCast(code - 90)],
            39 => class.* = "",
            40...47 => bg_class.* = ansi_bg[@intCast(code - 40)],
            100...107 => bg_class.* = ansi_bg[@intCast(code - 100)],
            49 => bg_class.* = "",
            else => {},
        }
    }
}
