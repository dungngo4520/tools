const std = @import("std");
const fs = std.fs;

pub fn build(b: *std.Build) void {
    // Standard build options
    const target = b.standardTargetOptions(.{});
    // Default to ReleaseFast for production builds (can be overridden with -Doptimize=Debug)
    const optimize_opt = b.standardOptimizeOption(.{});
    const optimize = if (optimize_opt == .Debug) .ReleaseFast else optimize_opt;

    // Custom options
    const tool_opt = b.option([]const u8, "tool", "Tool to build ('all' or tool name)") orelse "all";

    const allocator = b.allocator;

    // Auto-discover tools by scanning the current directory
    var tools = std.ArrayListUnmanaged([]const u8){};
    defer tools.deinit(allocator);

    // Scan root directory for tool folders
    var root_dir = fs.cwd().openDir(".", .{ .iterate = true }) catch unreachable;
    defer root_dir.close();

    var iter = root_dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            const name = entry.name;

            // Skip hidden directories and build artifacts
            if (std.mem.startsWith(u8, name, ".") or
                std.mem.startsWith(u8, name, "zig-out") or
                std.mem.eql(u8, name, "dist"))
            {
                continue;
            }

            // Check if directory contains main.zig
            const main_path = b.fmt("{s}/main.zig", .{name});
            fs.cwd().access(main_path, .{}) catch continue;

            const tool_name_dup = allocator.dupe(u8, name) catch unreachable;
            tools.append(allocator, tool_name_dup) catch unreachable;
        }
    }

    // Build selected tools
    for (tools.items) |tool_name| {
        // Skip if specific tool requested and this isn't it
        if (!std.mem.eql(u8, tool_opt, "all") and !std.mem.eql(u8, tool_opt, tool_name)) {
            continue;
        }

        // Create executable
        const main_path = b.fmt("{s}/main.zig", .{tool_name});
        const root_module = b.addModule(tool_name, .{
            .root_source_file = b.path(main_path),
            .target = target,
            .optimize = optimize,
        });
        const exe = b.addExecutable(.{
            .name = tool_name,
            .root_module = root_module,
        });

        // Get target info to construct directory name
        const target_info = target.result;
        const arch_name = @tagName(target_info.cpu.arch);
        const os_name = @tagName(target_info.os.tag);
        const abi_name = @tagName(target_info.abi);

        // Construct target triple string for directory structure
        const target_triple = std.fmt.allocPrint(
            b.allocator,
            "{s}-{s}-{s}",
            .{ arch_name, os_name, abi_name },
        ) catch unreachable;
        defer b.allocator.free(target_triple);

        // Install to target-specific directory: zig-out/<target>/bin/
        // Note: .custom is relative to install prefix (zig-out), so we don't include it
        const install_dir_path = b.fmt("{s}/bin", .{target_triple});
        const target_install_step = b.addInstallFileWithDir(
            exe.getEmittedBin(),
            .{ .custom = install_dir_path },
            b.fmt("{s}", .{exe.out_filename}),
        );
        b.getInstallStep().dependOn(&target_install_step.step);
    }

    // Create a clean step that removes build artifacts
    const clean_step = b.step("clean", "Remove all build artifacts");
    const rm_zig_out = b.addRemoveDirTree(b.path("zig-out"));
    const rm_zig_cache = b.addRemoveDirTree(b.path(".zig-cache"));
    const rm_dist = b.addRemoveDirTree(b.path("dist"));
    clean_step.dependOn(&rm_zig_out.step);
    clean_step.dependOn(&rm_zig_cache.step);
    clean_step.dependOn(&rm_dist.step);
}
