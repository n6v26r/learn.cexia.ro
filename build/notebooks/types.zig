pub const out_dir = "zig-out/.site-content";
pub const staging_dir = "zig-out/.site-content-next";

pub const image_mimes = .{
    .{ .mime = "image/svg+xml", .ext = "svg" },
    .{ .mime = "image/png", .ext = "png" },
    .{ .mime = "image/jpeg", .ext = "jpg" },
};

pub const Date = union(enum) {
    date: []const u8,
};

pub const ResultValue = struct {
    score: ?f64 = null,
    metric: ?f64 = null,
    score_text: ?[]const u8 = null,
    metric_text: ?[]const u8 = null,
};

pub const SplitResult = struct {
    public: ResultValue,
    private: ResultValue,
};

pub const BoardResult = union(enum) {
    one: ResultValue,
    split: SplitResult,
};

pub const ResultEntry = union(enum) {
    one: ResultValue,
    split: SplitResult,
    total: BoardResult,
};

pub const Result = union(enum) {
    full: BoardResult,
    subtasks: []const ResultEntry,
};

pub const Custom = struct {
    crumbs: ?[]const u8 = null,
    section: ?bool = null,
    problem_url: ?[]const u8 = null,
    runtime: ?[]const u8 = null,
    cpu: ?[]const u8 = null,
    memory: ?[]const u8 = null,
    gpu: ?[]const u8 = null,
    python: ?[]const u8 = null,
    duration: ?[]const u8 = null,
    level: ?[]const u8 = null,
    result: ?Result = null,
    result_split: ?bool = null,
    result_has_score: ?bool = null,
    result_has_metric: ?bool = null,
};

pub const Meta = struct {
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    authors: ?[]const []const u8 = null,
    tags: ?[]const []const u8 = null,
    aliases: ?[]const []const u8 = null,
    date: Date = .{ .date = "" },
    layout: ?[]const u8 = null,
    custom: Custom = .{},
};

pub const Smd = struct {
    meta: Meta = .{},
    body: []const u8 = "",
};
