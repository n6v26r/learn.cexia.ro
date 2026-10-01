const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const Json = std.json.Value;
const Allocator = std.mem.Allocator;

const util = @import("util.zig");

pub fn writeDataAsset(alloc: Allocator, io: Io, root: Dir, path: []const u8, mime: []const u8, value: *const Json) !void {
    const text = try util.sourceText(alloc, value);
    if (std.mem.eql(u8, mime, "image/svg+xml")) {
        try util.writeFile(root, io, path, text);
        return;
    }
    try writeBase64Asset(alloc, io, root, path, text);
}

pub fn writeBase64Asset(alloc: Allocator, io: Io, root: Dir, path: []const u8, text: []const u8) !void {
    var cleaned = std.array_list.Managed(u8).init(alloc);
    for (text) |c| if (!std.ascii.isWhitespace(c)) try cleaned.append(c);
    const size = try std.base64.standard.Decoder.calcSizeForSlice(cleaned.items);
    const bytes = try alloc.alloc(u8, size);
    try std.base64.standard.Decoder.decode(bytes, cleaned.items);
    try util.writeFile(root, io, path, bytes);
}
