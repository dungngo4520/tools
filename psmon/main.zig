const std = @import("std");
const builtin = @import("builtin");

const ProcessInfo = struct {
    pid: std.posix.pid_t,
    name: []const u8,
    cpu_percent: f64,
    memory_kb: u64,
    disk_read_bytes: ?u64,
    disk_write_bytes: ?u64,
    open_files: ?u64,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <process_name1> [process_name2] ...\n", .{args[0]});
        std.process.exit(1);
    }

    // Collect process names to search for
    var process_names = std.ArrayListUnmanaged([]const u8){};
    defer process_names.deinit(allocator);
    for (args[1..]) |arg| {
        try process_names.append(allocator, arg);
    }

    // Find all matching processes
    var processes = std.ArrayListUnmanaged(ProcessInfo){};
    defer {
        for (processes.items) |proc| {
            allocator.free(proc.name);
        }
        processes.deinit(allocator);
    }

    try findProcesses(allocator, process_names.items, &processes);

    if (processes.items.len == 0) {
        std.debug.print("No matching processes found.\n", .{});
        return;
    }

    // Print header with proper spacing (no tabs, use fixed widths)
    std.debug.print("{s:<20} {s:<8} {s:>10} {s:>12} {s:>12} {s:>12} {s:>12} {s:>10}\n", .{
        "PROCESS",
        "PID",
        "CPU %",
        "MEMORY",
        "DISK READ",
        "DISK WRITE",
        "NET READ",
        "OPEN FILES",
    });
    const separator = "----------------------------------------------------------------------------------------------------";
    std.debug.print("{s}\n", .{separator});

    // Print process information
    for (processes.items) |proc| {
        const disk_read_str = if (proc.disk_read_bytes) |bytes|
            formatBytes(allocator, bytes) catch "N/A"
        else
            "N/A";
        defer if (proc.disk_read_bytes != null) allocator.free(disk_read_str);

        const disk_write_str = if (proc.disk_write_bytes) |bytes|
            formatBytes(allocator, bytes) catch "N/A"
        else
            "N/A";
        defer if (proc.disk_write_bytes != null) allocator.free(disk_write_str);

        const open_files_str = if (proc.open_files) |count|
            try std.fmt.allocPrint(allocator, "{d}", .{count})
        else
            "N/A";
        defer if (proc.open_files != null) allocator.free(open_files_str);

        // Format CPU percentage with % sign
        const cpu_str = try std.fmt.allocPrint(allocator, "{d:.2}%", .{proc.cpu_percent});
        defer allocator.free(cpu_str);

        // Format memory in human-readable format (convert KB to bytes first)
        const memory_bytes = proc.memory_kb * 1024;
        const memory_str = formatBytes(allocator, memory_bytes) catch "N/A";
        defer if (!std.mem.eql(u8, memory_str, "N/A")) allocator.free(memory_str);

        std.debug.print("{s:<20} {d:<8} {s:>10} {s:>12} {s:>12} {s:>12} {s:>12} {s:>10}\n", .{
            proc.name,
            @as(u32, @intCast(proc.pid)), // Cast to unsigned for proper display
            cpu_str,
            memory_str,
            disk_read_str,
            disk_write_str,
            "N/A", // Network I/O not implemented yet
            open_files_str,
        });
    }
}

fn findProcesses(allocator: std.mem.Allocator, process_names: []const []const u8, out: *std.ArrayListUnmanaged(ProcessInfo)) !void {
    var proc_dir = try std.fs.cwd().openDir("/proc", .{ .iterate = true });
    defer proc_dir.close();

    var iter = proc_dir.iterate();
    while (try iter.next()) |entry| {
        // Check if entry is a directory with numeric name (PID)
        const pid = std.fmt.parseInt(std.posix.pid_t, entry.name, 10) catch continue;

        // Read process name from /proc/[pid]/comm
        const comm_path = try std.fmt.allocPrint(allocator, "{d}/comm", .{pid});
        defer allocator.free(comm_path);

        const comm_file = proc_dir.openFile(comm_path, .{}) catch continue;
        defer comm_file.close();

        var comm_buf: [256]u8 = undefined;
        const comm_len = comm_file.readAll(&comm_buf) catch continue;
        var comm = comm_buf[0..comm_len];
        // Remove trailing newline
        if (comm.len > 0 and comm[comm.len - 1] == '\n') {
            comm = comm[0 .. comm.len - 1];
        }

        // Check if process name matches any of the search terms
        var matches = false;
        for (process_names) |search_name| {
            if (std.mem.indexOf(u8, comm, search_name) != null) {
                matches = true;
                break;
            }
        }

        if (!matches) continue;

        // Read process stats
        const stat_path = try std.fmt.allocPrint(allocator, "{d}/stat", .{pid});
        defer allocator.free(stat_path);

        const stat_file = proc_dir.openFile(stat_path, .{}) catch continue;
        defer stat_file.close();

        var stat_buf: [4096]u8 = undefined;
        const stat_len = stat_file.readAll(&stat_buf) catch continue;
        const stat_line = stat_buf[0..stat_len];

        // Parse /proc/[pid]/stat
        // Format: pid (comm) state ppid ... utime stime ... starttime ... rss ...
        // The comm field is in parentheses and may contain spaces, so we need to find it
        var stat_rest = stat_line;
        // Skip pid (first token before space)
        if (std.mem.indexOf(u8, stat_rest, " ")) |space_idx| {
            stat_rest = stat_rest[space_idx + 1 ..];
        } else continue;

        // Find the closing parenthesis of comm field
        if (std.mem.indexOf(u8, stat_rest, ")")) |paren_idx| {
            stat_rest = stat_rest[paren_idx + 2 ..]; // Skip ") "
        } else continue;

        // Now tokenize the rest
        var tokens = std.mem.tokenizeScalar(u8, stat_rest, ' ');
        _ = tokens.next(); // state
        _ = tokens.next(); // ppid

        // Skip to utime (field 14, 0-indexed)
        var i: usize = 0;
        while (i < 9) : (i += 1) {
            _ = tokens.next();
        }
        const utime_str = tokens.next() orelse continue;
        const stime_str = tokens.next() orelse continue;

        // Skip to starttime (field 22, 0-indexed)
        i = 0;
        while (i < 6) : (i += 1) {
            _ = tokens.next();
        }
        const starttime_str = tokens.next() orelse continue;

        // Skip to rss (field 24)
        // After starttime (22): vsize (23), then rss (24)
        _ = tokens.next(); // vsize (field 23)
        const rss_str = tokens.next() orelse continue; // rss (field 24)

        const utime = try std.fmt.parseInt(u64, utime_str, 10);
        const stime = try std.fmt.parseInt(u64, stime_str, 10);
        const starttime = try std.fmt.parseInt(u64, starttime_str, 10);
        const rss = try std.fmt.parseInt(u64, rss_str, 10);

        // Memory in KB (rss is in pages, typically 4KB per page on Linux)
        // Use u128 for calculation to avoid overflow, then cast back to u64
        const page_size: u64 = 4096;
        const memory_bytes = @as(u128, rss) * @as(u128, page_size);
        const memory_kb_128 = memory_bytes / 1024;
        // Safely cast to u64, saturate at max if needed
        const memory_kb = if (memory_kb_128 > std.math.maxInt(u64))
            std.math.maxInt(u64)
        else
            @as(u64, @intCast(memory_kb_128));

        // Calculate CPU percentage
        // Read system uptime to calculate process elapsed time
        var cpu_percent: f64 = 0.0;
        if (std.fs.cwd().openFile("/proc/uptime", .{})) |uptime_file| {
            defer uptime_file.close();
            var uptime_buf: [64]u8 = undefined;
            if (uptime_file.readAll(&uptime_buf)) |uptime_len| {
                if (uptime_len > 0) {
                    var uptime_tokens = std.mem.tokenizeScalar(u8, uptime_buf[0..uptime_len], ' ');
                    const uptime_sec_str = uptime_tokens.next() orelse "";
                    const uptime_sec = std.fmt.parseFloat(f64, uptime_sec_str) catch 0.0;

                    // Get clock ticks per second (standard value is 100 on Linux)
                    const clock_ticks_per_sec: u64 = 100;
                    const total_cpu_time = @as(f64, @floatFromInt(utime + stime)) / @as(f64, @floatFromInt(clock_ticks_per_sec));
                    const process_start_sec = @as(f64, @floatFromInt(starttime)) / @as(f64, @floatFromInt(clock_ticks_per_sec));
                    const process_elapsed_sec = uptime_sec - process_start_sec;

                    if (process_elapsed_sec > 0) {
                        // CPU percentage = (CPU time / elapsed time) * 100
                        // For multi-core systems, this can exceed 100%
                        cpu_percent = (total_cpu_time / process_elapsed_sec) * 100.0;
                    }
                }
            } else |_| {
                // Error reading uptime - skip CPU calculation
            }
        } else |_| {
            // Cannot open /proc/uptime - skip CPU calculation
        }

        // Read I/O stats (optional)
        const io_path = try std.fmt.allocPrint(allocator, "{d}/io", .{pid});
        defer allocator.free(io_path);

        var disk_read_bytes: ?u64 = null;
        var disk_write_bytes: ?u64 = null;

        if (proc_dir.openFile(io_path, .{})) |io_file| {
            defer io_file.close();
            var io_buf: [2048]u8 = undefined;
            if (io_file.readAll(&io_buf)) |io_len| {
                const io_content = io_buf[0..io_len];
                var io_lines = std.mem.tokenizeScalar(u8, io_content, '\n');
                while (io_lines.next()) |line| {
                    if (std.mem.startsWith(u8, line, "read_bytes:")) {
                        var io_tokens = std.mem.tokenizeScalar(u8, line, ' ');
                        _ = io_tokens.next(); // "read_bytes:"
                        if (io_tokens.next()) |val| {
                            disk_read_bytes = std.fmt.parseInt(u64, val, 10) catch null;
                        }
                    } else if (std.mem.startsWith(u8, line, "write_bytes:")) {
                        var io_tokens = std.mem.tokenizeScalar(u8, line, ' ');
                        _ = io_tokens.next(); // "write_bytes:"
                        if (io_tokens.next()) |val| {
                            disk_write_bytes = std.fmt.parseInt(u64, val, 10) catch null;
                        }
                    }
                }
            } else |_| {
                // Permission denied or other error - skip I/O stats for this process
            }
        } else |_| {
            // File doesn't exist or permission denied - that's okay
        }

        // Count open file descriptors (optional)
        var open_files: ?u64 = null;
        const fd_path = try std.fmt.allocPrint(allocator, "{d}/fd", .{pid});
        defer allocator.free(fd_path);

        if (proc_dir.openDir(fd_path, .{ .iterate = true })) |fd_dir_result| {
            var fd_dir = fd_dir_result;
            defer fd_dir.close();
            var fd_iter = fd_dir.iterate();
            var count: u64 = 0;
            while (try fd_iter.next()) |_| {
                count += 1;
            }
            open_files = count;
        } else |_| {
            // Directory doesn't exist or permission denied - that's okay
        }

        const name_dup = try allocator.dupe(u8, comm);
        try out.append(allocator, ProcessInfo{
            .pid = pid,
            .name = name_dup,
            .cpu_percent = cpu_percent,
            .memory_kb = memory_kb,
            .disk_read_bytes = disk_read_bytes,
            .disk_write_bytes = disk_write_bytes,
            .open_files = open_files,
        });
    }
}

fn formatBytes(allocator: std.mem.Allocator, bytes: u64) ![]const u8 {
    const kb = bytes / 1024;
    const mb = kb / 1024;
    const gb = mb / 1024;

    if (gb > 0) {
        return try std.fmt.allocPrint(allocator, "{d}.{d} GB", .{ gb, (mb % 1024) / 100 });
    } else if (mb > 0) {
        return try std.fmt.allocPrint(allocator, "{d}.{d} MB", .{ mb, (kb % 1024) / 100 });
    } else if (kb > 0) {
        return try std.fmt.allocPrint(allocator, "{d} KB", .{kb});
    } else {
        return try std.fmt.allocPrint(allocator, "{d} B", .{bytes});
    }
}
