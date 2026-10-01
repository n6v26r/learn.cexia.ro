const std = @import("std");

const notebooks = @import("notebooks/tree.zig");
const types = @import("notebooks/types.zig");

const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const Io = std.Io;
const Digest = [std.crypto.hash.Blake3.digest_length]u8;

const Entry = struct {
    path: []const u8,
    kind: std.Io.File.Kind,
};

const Watcher = struct {
    io: Io,
    gpa: Allocator,
    root: Dir,
    stop: std.atomic.Value(bool) = .init(false),
};

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingZineExecutable;

    var child = try std.process.spawn(init.io, .{
        .argv = args[1..],
        .environ_map = init.environ_map,
    });

    var watcher: Watcher = .{
        .io = init.io,
        .gpa = init.gpa,
        .root = .cwd(),
    };
    const thread = try std.Thread.spawn(.{}, watch, .{&watcher});

    const term = try child.wait(init.io);
    watcher.stop.store(true, .release);
    thread.join();

    return switch (term) {
        .exited => |code| code,
        else => 1,
    };
}

fn watch(watcher: *Watcher) void {
    var arena = std.heap.ArenaAllocator.init(watcher.gpa);
    defer arena.deinit();

    var previous = hashTree(arena.allocator(), watcher.io, watcher.root, "site") catch |err| {
        std.debug.print("watch: unable to hash site/: {s}\n", .{@errorName(err)});
        return;
    };

    while (!watcher.stop.load(.acquire)) {
        std.Io.sleep(watcher.io, .fromMilliseconds(250), .awake) catch return;
        _ = arena.reset(.retain_capacity);

        const current = hashTree(arena.allocator(), watcher.io, watcher.root, "site") catch |err| {
            std.debug.print("watch: unable to hash site/: {s}\n", .{@errorName(err)});
            continue;
        };
        if (std.mem.eql(u8, &previous, &current)) continue;
        previous = current;

        _ = arena.reset(.retain_capacity);
        rebuild(arena.allocator(), watcher.io, watcher.root) catch |err| {
            std.debug.print("watch: rebuild failed: {s}\n", .{@errorName(err)});
            continue;
        };
        std.debug.print("watch: rebuilt site/\n", .{});
    }
}

fn rebuild(alloc: Allocator, io: Io, root: Dir) !void {
    try root.deleteTree(io, types.staging_dir);
    defer root.deleteTree(io, types.staging_dir) catch {};

    try notebooks.generateAt(alloc, io, root, types.staging_dir);
    try clearDirectory(alloc, io, root, types.out_dir);
    try copyTree(alloc, io, root, types.staging_dir, types.out_dir);
}

fn clearDirectory(alloc: Allocator, io: Io, root: Dir, path: []const u8) !void {
    var dir = try root.createDirPathOpen(io, path, .{ .open_options = .{ .iterate = true } });
    defer dir.close(io);

    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(alloc);
    var it = dir.iterate();
    while (try it.next(io)) |entry| try names.append(alloc, try alloc.dupe(u8, entry.name));
    for (names.items) |name| try dir.deleteTree(io, name);
}

fn copyTree(alloc: Allocator, io: Io, root: Dir, source: []const u8, destination: []const u8) !void {
    var dir = try root.openDir(io, source, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(alloc);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        const dest = try std.fs.path.join(alloc, &.{ destination, entry.path });
        switch (entry.kind) {
            .directory => try root.createDirPath(io, dest),
            .file => {
                const src = try std.fs.path.join(alloc, &.{ source, entry.path });
                try root.copyFile(src, root, dest, io, .{ .make_path = true });
            },
            else => {},
        }
    }
}

fn hashTree(alloc: Allocator, io: Io, root: Dir, path: []const u8) !Digest {
    var dir = try root.openDir(io, path, .{ .iterate = true });
    defer dir.close(io);

    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(alloc);
    var walker = try dir.walk(alloc);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        try entries.append(alloc, .{
            .path = try alloc.dupe(u8, entry.path),
            .kind = entry.kind,
        });
    }
    std.mem.sort(Entry, entries.items, {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    var hash: std.crypto.hash.Blake3 = .init(.{});
    for (entries.items) |entry| {
        hash.update(@tagName(entry.kind));
        hash.update(&.{0});
        hash.update(entry.path);
        hash.update(&.{0});
        if (entry.kind == .file) {
            const file_path = try std.fs.path.join(alloc, &.{ path, entry.path });
            hash.update(try root.readFileAlloc(io, file_path, alloc, .unlimited));
        }
        hash.update(&.{0xff});
    }

    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

test "tree hash covers contents, names, and directories" {
    const io = std.testing.io;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "site/empty");
    try tmp.dir.writeFile(io, .{ .sub_path = "site/lesson.smd", .data = "one" });
    const initial = try hashTree(alloc, io, tmp.dir, "site");
    try std.testing.expectEqual(initial, try hashTree(alloc, io, tmp.dir, "site"));

    try tmp.dir.writeFile(io, .{ .sub_path = "site/lesson.smd", .data = "two" });
    const edited = try hashTree(alloc, io, tmp.dir, "site");
    try std.testing.expect(!std.mem.eql(u8, &initial, &edited));

    try tmp.dir.rename("site/lesson.smd", tmp.dir, "site/renamed.smd", io);
    const renamed = try hashTree(alloc, io, tmp.dir, "site");
    try std.testing.expect(!std.mem.eql(u8, &edited, &renamed));

    try tmp.dir.createDirPath(io, "site/nested/deeper");
    const nested = try hashTree(alloc, io, tmp.dir, "site");
    try std.testing.expect(!std.mem.eql(u8, &renamed, &nested));

    try tmp.dir.rename("site/empty", tmp.dir, "site/renamed-empty", io);
    const directory_renamed = try hashTree(alloc, io, tmp.dir, "site");
    try std.testing.expect(!std.mem.eql(u8, &nested, &directory_renamed));

    try tmp.dir.writeFile(io, .{ .sub_path = "site/added.smd", .data = "added" });
    const added = try hashTree(alloc, io, tmp.dir, "site");
    try std.testing.expect(!std.mem.eql(u8, &directory_renamed, &added));

    try tmp.dir.deleteFile(io, "site/added.smd");
    const file_removed = try hashTree(alloc, io, tmp.dir, "site");
    try std.testing.expect(!std.mem.eql(u8, &added, &file_removed));

    try tmp.dir.deleteTree(io, "site/nested");
    const removed = try hashTree(alloc, io, tmp.dir, "site");
    try std.testing.expect(!std.mem.eql(u8, &file_removed, &removed));
}
