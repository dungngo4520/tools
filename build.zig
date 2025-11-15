const std = @import("std");
const fs = std.fs;
const build_config = @import("build.config.zig");

pub fn build(b: *std.Build) void {
    const optimize_opt = b.standardOptimizeOption(.{});
    const optimize = if (optimize_opt == .Debug) .ReleaseFast else optimize_opt;

    const tool_opt = b.option([]const u8, "tool", "Tool to build ('all' or tool name)") orelse "all";
    const build_all = b.option(bool, "all-targets", "Build for all targets") orelse false;

    const allocator = b.allocator;

    const clean_step = b.step("clean", "Remove all build artifacts");
    const rm_zig_out = b.addRemoveDirTree(b.path("zig-out"));
    const rm_zig_cache = b.addRemoveDirTree(b.path(".zig-cache"));
    clean_step.dependOn(&rm_zig_out.step);
    clean_step.dependOn(&rm_zig_cache.step);

    if (build_all) {
        inline for (build_config.targets) |target_str| {
            const target = b.resolveTargetQuery(parseTargetTriple(target_str));
            buildForTarget(b, target, optimize, tool_opt, allocator);
        }
        return;
    } else {
        const target = b.standardTargetOptions(.{});
        buildForTarget(b, target, optimize, tool_opt, allocator);
    }
}

fn parseTargetTriple(triple: []const u8) std.Target.Query {
    var query: std.Target.Query = .{};
    var parts = std.mem.splitSequence(u8, triple, "-");

    if (parts.next()) |arch_str| {
        query.cpu_arch = std.meta.stringToEnum(std.Target.Cpu.Arch, arch_str);
    }

    if (parts.next()) |os_str| {
        query.os_tag = std.meta.stringToEnum(std.Target.Os.Tag, os_str);
    }

    if (parts.next()) |abi_str| {
        query.abi = std.meta.stringToEnum(std.Target.Abi, abi_str);
    }

    return query;
}

fn buildForTarget(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    tool_opt: []const u8,
    allocator: std.mem.Allocator,
) void {
    var libraries: std.StringHashMap(*std.Build.Module) = std.StringHashMap(*std.Build.Module).init(allocator);
    defer libraries.deinit();

    inline for (std.meta.fields(@TypeOf(build_config.libraries))) |field| {
        const lib_name = field.name;
        const lib_path = @field(build_config.libraries, lib_name);

        const lib_module = b.addModule(lib_name, .{
            .root_source_file = b.path(lib_path),
            .target = target,
            .optimize = optimize,
        });

        libraries.put(lib_name, lib_module) catch @panic("Failed to add library module");
    }

    inline for (build_config.tool_dirs) |tool_dir| {
        buildToolIfNeeded(b, target, optimize, tool_dir, tool_opt, &libraries);
    }
}

fn buildToolIfNeeded(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    tool_name: []const u8,
    tool_opt: []const u8,
    libraries: *std.StringHashMap(*std.Build.Module),
) void {
    if (!std.mem.eql(u8, tool_opt, "all") and !std.mem.eql(u8, tool_opt, tool_name)) {
        return;
    }

    const main_path = b.fmt("{s}/main.zig", .{tool_name});
    fs.cwd().access(main_path, .{}) catch return;

    buildTool(b, target, optimize, tool_name, libraries);
}

fn buildTool(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    tool_name: []const u8,
    libraries: *std.StringHashMap(*std.Build.Module),
) void {
    const main_path = b.fmt("{s}/main.zig", .{tool_name});
    const root_module = b.addModule(tool_name, .{
        .root_source_file = b.path(main_path),
        .target = target,
        .optimize = optimize,
    });

    var lib_iter = libraries.iterator();
    while (lib_iter.next()) |entry| {
        root_module.addImport(entry.key_ptr.*, entry.value_ptr.*);
    }

    const exe = b.addExecutable(.{
        .name = tool_name,
        .root_module = root_module,
    });

    const target_info = target.result;
    const arch_name = @tagName(target_info.cpu.arch);
    const os_name = @tagName(target_info.os.tag);
    const abi_name = @tagName(target_info.abi);

    const target_triple = b.fmt("{s}-{s}-{s}", .{ arch_name, os_name, abi_name });

    const install_dir_path = b.fmt("{s}/bin", .{target_triple});
    const target_install_step = b.addInstallFileWithDir(
        exe.getEmittedBin(),
        .{ .custom = install_dir_path },
        b.fmt("{s}", .{exe.out_filename}),
    );
    b.getInstallStep().dependOn(&target_install_step.step);
}
