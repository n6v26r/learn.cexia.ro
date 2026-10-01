const std = @import("std");
const ziggy = @import("ziggy").ziggy;

const Io = std.Io;
const Dir = Io.Dir;
const Json = std.json.Value;
const Allocator = std.mem.Allocator;

const types = @import("types.zig");

pub fn loadSmd(alloc: Allocator, io: Io, root: Dir, path: []const u8) !types.Smd {
    const bytes = root.readFileAlloc(io, path, alloc, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    if (!std.mem.startsWith(u8, bytes, "---\n")) return .{ .body = bytes };

    const end = std.mem.indexOf(u8, bytes[4..], "\n---\n") orelse return error.InvalidSmdMeta;
    const source = try alloc.dupeSentinel(u8, bytes[4 .. 4 + end], 0);
    var parse_meta: ziggy.Deserializer.Meta = .init;
    return .{
        .meta = try ziggy.deserializeLeaky(types.Meta, alloc, source, &parse_meta, .{}),
        .body = bytes[4 + end + "\n---\n".len ..],
    };
}

pub fn writeFrontmatter(w: *Io.Writer, page: types.Meta) !void {
    try w.writeAll("---\n");
    try ziggy.serialize(page, .{ .whitespace = .space_4, .emit_null_fields = false }, w);
    try w.writeAll("\n---\n\n");
}

pub fn inferRuntime(alloc: Allocator, notebook: *const Json, custom: *types.Custom) !void {
    if (custom.runtime != null) return;

    var total_ms: i128 = 0;
    var found = false;
    for (notebook.object.get("cells").?.array.items) |cell| {
        const metadata = cell.object.get("metadata").?;

        if (metadata.object.getPtr("ExecuteTime")) |execute_time| {
            const start = execute_time.object.get("start_time").?.string;
            const end = execute_time.object.get("end_time").?.string;
            total_ms += (try timestampMs(end)) - (try timestampMs(start));
            found = true;
            continue;
        }

        if (metadata.object.getPtr("execution")) |execution| {
            const start = if (execution.object.getPtr("iopub.status.busy")) |v| v.string else execution.object.get("iopub.execute_input").?.string;
            const end = if (execution.object.getPtr("iopub.status.idle")) |v| v.string else execution.object.get("shell.execute_reply").?.string;
            total_ms += (try timestampMs(end)) - (try timestampMs(start));
            found = true;
        }
    }

    if (found) custom.runtime = try formatDuration(alloc, total_ms);
}

fn timestampMs(s: []const u8) !i128 {
    const year = try std.fmt.parseInt(u16, s[0..4], 10);
    const month = try std.fmt.parseInt(u4, s[5..7], 10);
    const day = try std.fmt.parseInt(u5, s[8..10], 10);
    const hour = try std.fmt.parseInt(u6, s[11..13], 10);
    const minute = try std.fmt.parseInt(u6, s[14..16], 10);
    const second = try std.fmt.parseInt(u6, s[17..19], 10);

    var days: i128 = 0;
    var y: u16 = 1970;
    while (y < year) : (y += 1) days += std.time.epoch.getDaysInYear(y);

    var m: u4 = 1;
    while (m < month) : (m += 1) days += std.time.epoch.getDaysInMonth(year, @enumFromInt(m));

    var ms = (((days + day - 1) * 24 + hour) * 60 + minute) * 60_000 + @as(i128, second) * 1000;
    var i: usize = 19;
    if (i < s.len and s[i] == '.') {
        i += 1;
        var place: i128 = 100;
        while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {
            if (place > 0) {
                ms += @as(i128, s[i] - '0') * place;
                place = @divTrunc(place, 10);
            }
        }
    }
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        const sign: i128 = if (s[i] == '+') 1 else -1;
        const offset_hours = try std.fmt.parseInt(i128, s[i + 1 .. i + 3], 10);
        const offset_minutes = try std.fmt.parseInt(i128, s[i + 4 .. i + 6], 10);
        ms -= sign * (offset_hours * 60 + offset_minutes) * 60_000;
    }
    return ms;
}

fn formatDuration(alloc: Allocator, ms: i128) ![]const u8 {
    const total_seconds: u64 = @intCast(@divTrunc(ms + 500, 1000));
    const seconds = total_seconds % 60;
    const minutes = (total_seconds / 60) % 60;
    const hours = total_seconds / 3600;
    return std.fmt.allocPrint(alloc, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hours, minutes, seconds });
}
