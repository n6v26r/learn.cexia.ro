const std = @import("std");

const notebooks = @import("notebooks/tree.zig");
const types = @import("notebooks/types.zig");

pub fn main(init: std.process.Init) !void {
    const root: std.Io.Dir = .cwd();
    try root.deleteTree(init.io, types.out_dir);
    try notebooks.generateAt(init.arena.allocator(), init.io, root, types.out_dir);
}
