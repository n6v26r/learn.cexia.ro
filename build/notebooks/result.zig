const std = @import("std");

const Allocator = std.mem.Allocator;

const types = @import("types.zig");

pub fn addTotal(alloc: Allocator, result: types.Result) !types.Result {
    const items = switch (result) {
        .full => return result,
        .subtasks => |v| v,
    };

    var split = false;
    var public: ?f64 = null;
    var private: ?f64 = null;
    for (items) |item| switch (item) {
        .one => |v| if (v.score) |score| {
            public = (public orelse 0) + score;
            private = (private orelse 0) + score;
        },
        .split => |v| {
            split = true;
            if (v.public.score) |score| public = (public orelse 0) + score;
            if (v.private.score) |score| private = (private orelse 0) + score;
        },
        .total => return result,
    };
    if (public == null and private == null) return result;

    const out = try alloc.alloc(types.ResultEntry, items.len + 1);
    @memcpy(out[0..items.len], items);
    out[items.len] = .{ .total = if (split) .{ .split = .{
        .public = .{ .score = public },
        .private = .{ .score = private },
    } } else .{ .one = .{ .score = public } } };
    return .{ .subtasks = out };
}

pub fn addText(alloc: Allocator, result: types.Result, custom: *types.Custom) !types.Result {
    return switch (result) {
        .full => |v| .{ .full = try boardText(alloc, v, custom) },
        .subtasks => |items| blk: {
            const out = try alloc.alloc(types.ResultEntry, items.len);
            for (items, out) |item, *dst| dst.* = switch (item) {
                .one => |v| .{ .one = try valueText(alloc, v, custom) },
                .split => |v| .{ .split = try splitText(alloc, v, custom) },
                .total => |v| .{ .total = try boardText(alloc, v, custom) },
            };
            break :blk .{ .subtasks = out };
        },
    };
}

fn boardText(alloc: Allocator, board: types.BoardResult, custom: *types.Custom) !types.BoardResult {
    return switch (board) {
        .one => |v| .{ .one = try valueText(alloc, v, custom) },
        .split => |v| .{ .split = try splitText(alloc, v, custom) },
    };
}

fn splitText(alloc: Allocator, split: types.SplitResult, custom: *types.Custom) !types.SplitResult {
    custom.result_split = true;
    return .{
        .public = try valueText(alloc, split.public, custom),
        .private = try valueText(alloc, split.private, custom),
    };
}

fn valueText(alloc: Allocator, value: types.ResultValue, custom: *types.Custom) !types.ResultValue {
    var out = value;
    out.score_text = null;
    out.metric_text = null;
    if (value.score) |score| {
        custom.result_has_score = true;
        out.score_text = try number(alloc, score);
    }
    if (value.metric) |metric| {
        custom.result_has_metric = true;
        out.metric_text = try number(alloc, metric);
    }
    return out;
}

fn number(alloc: Allocator, value: f64) ![]const u8 {
    const text = try std.fmt.allocPrint(alloc, "{d:.12}", .{value});
    return std.mem.trimEnd(u8, std.mem.trimEnd(u8, text, "0"), ".");
}
