const std = @import("std");
const builtin = @import("builtin");

const ProcessInfo = struct {
    pid: u32, // Use u32 for cross-platform compatibility
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
            proc.pid,
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
    switch (builtin.target.os.tag) {
        .linux => try findProcessesLinux(allocator, process_names, out),
        .windows => try findProcessesWindows(allocator, process_names, out),
        .macos => try findProcessesMacOS(allocator, process_names, out),
        else => {
            std.debug.print("Error: Unsupported operating system: {s}\n", .{@tagName(builtin.target.os.tag)});
            return error.UnsupportedOS;
        },
    }
}

// Linux implementation using /proc filesystem
fn findProcessesLinux(allocator: std.mem.Allocator, process_names: []const []const u8, out: *std.ArrayListUnmanaged(ProcessInfo)) !void {
    var proc_dir = try std.fs.cwd().openDir("/proc", .{ .iterate = true });
    defer proc_dir.close();

    var iter = proc_dir.iterate();
    while (try iter.next()) |entry| {
        // Check if entry is a directory with numeric name (PID)
        const pid = std.fmt.parseInt(u32, entry.name, 10) catch continue;

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
        var stat_rest = stat_line;
        if (std.mem.indexOf(u8, stat_rest, " ")) |space_idx| {
            stat_rest = stat_rest[space_idx + 1 ..];
        } else continue;

        if (std.mem.indexOf(u8, stat_rest, ")")) |paren_idx| {
            stat_rest = stat_rest[paren_idx + 2 ..];
        } else continue;

        var tokens = std.mem.tokenizeScalar(u8, stat_rest, ' ');
        _ = tokens.next(); // state
        _ = tokens.next(); // ppid

        var i: usize = 0;
        while (i < 9) : (i += 1) {
            _ = tokens.next();
        }
        const utime_str = tokens.next() orelse continue;
        const stime_str = tokens.next() orelse continue;

        i = 0;
        while (i < 6) : (i += 1) {
            _ = tokens.next();
        }
        const starttime_str = tokens.next() orelse continue;

        // After starttime (field 22): vsize (field 23), then rss (field 24)
        // cutime and cstime come BEFORE starttime, not after
        const vsize_str = tokens.next() orelse continue;
        const rss_str = tokens.next() orelse continue; // rss (field 24)

        const utime = try std.fmt.parseInt(u64, utime_str, 10);
        const stime = try std.fmt.parseInt(u64, stime_str, 10);
        const starttime = try std.fmt.parseInt(u64, starttime_str, 10);
        _ = try std.fmt.parseInt(u64, vsize_str, 10); // vsize - not used but need to skip it
        const rss = std.fmt.parseInt(u64, rss_str, 10) catch {
            // If parsing fails (e.g., max u64), skip this process
            continue;
        };

        // Sanity check: RSS should be reasonable (less than 100 million pages = ~400GB)
        // Field 25 often contains max u64, so this check prevents reading wrong field
        if (rss > 100_000_000) {
            continue;
        }

        const page_size: u64 = 4096;
        const memory_bytes = @as(u128, rss) * @as(u128, page_size);
        const memory_kb_128 = memory_bytes / 1024;

        // Check for overflow - if memory_kb would exceed reasonable limits, skip this process
        if (memory_kb_128 > 1_000_000_000_000) { // More than 1TB in KB is unreasonable
            continue;
        }

        const memory_kb = @as(u64, @intCast(memory_kb_128));

        var cpu_percent: f64 = 0.0;
        if (std.fs.cwd().openFile("/proc/uptime", .{})) |uptime_file| {
            defer uptime_file.close();
            var uptime_buf: [64]u8 = undefined;
            if (uptime_file.readAll(&uptime_buf)) |uptime_len| {
                if (uptime_len > 0) {
                    var uptime_tokens = std.mem.tokenizeScalar(u8, uptime_buf[0..uptime_len], ' ');
                    const uptime_sec_str = uptime_tokens.next() orelse "";
                    const uptime_sec = std.fmt.parseFloat(f64, uptime_sec_str) catch 0.0;

                    const clock_ticks_per_sec: u64 = 100;
                    const total_cpu_time = @as(f64, @floatFromInt(utime + stime)) / @as(f64, @floatFromInt(clock_ticks_per_sec));
                    const process_start_sec = @as(f64, @floatFromInt(starttime)) / @as(f64, @floatFromInt(clock_ticks_per_sec));
                    const process_elapsed_sec = uptime_sec - process_start_sec;

                    if (process_elapsed_sec > 0) {
                        cpu_percent = (total_cpu_time / process_elapsed_sec) * 100.0;
                    }
                }
            } else |_| {}
        } else |_| {}

        var disk_read_bytes: ?u64 = null;
        var disk_write_bytes: ?u64 = null;

        const io_path = try std.fmt.allocPrint(allocator, "{d}/io", .{pid});
        defer allocator.free(io_path);

        if (proc_dir.openFile(io_path, .{})) |io_file| {
            defer io_file.close();
            var io_buf: [2048]u8 = undefined;
            if (io_file.readAll(&io_buf)) |io_len| {
                const io_content = io_buf[0..io_len];
                var io_lines = std.mem.tokenizeScalar(u8, io_content, '\n');
                while (io_lines.next()) |line| {
                    if (std.mem.startsWith(u8, line, "read_bytes:")) {
                        var io_tokens = std.mem.tokenizeScalar(u8, line, ' ');
                        _ = io_tokens.next();
                        if (io_tokens.next()) |val| {
                            disk_read_bytes = std.fmt.parseInt(u64, val, 10) catch null;
                        }
                    } else if (std.mem.startsWith(u8, line, "write_bytes:")) {
                        var io_tokens = std.mem.tokenizeScalar(u8, line, ' ');
                        _ = io_tokens.next();
                        if (io_tokens.next()) |val| {
                            disk_write_bytes = std.fmt.parseInt(u64, val, 10) catch null;
                        }
                    }
                }
            } else |_| {}
        } else |_| {}

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
        } else |_| {}

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

// Windows implementation using Windows API
fn findProcessesWindows(allocator: std.mem.Allocator, process_names: []const []const u8, out: *std.ArrayListUnmanaged(ProcessInfo)) !void {
    // Use wmic command to get process information on Windows
    // Full Windows API implementation would require CreateToolhelp32Snapshot, Process32First, etc.
    // For now, we'll use a simpler approach with system commands
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Use wmic to get process information (available on Windows)
    const wmic_cmd = try std.fmt.allocPrint(arena_allocator, "wmic process get ProcessId,Name,WorkingSetSize,PageFileUsage /format:csv", .{});
    defer arena_allocator.free(wmic_cmd);

    var process = std.process.Child.init(&.{ "cmd", "/c", wmic_cmd }, allocator);
    process.stdin_behavior = .Ignore;
    process.stdout_behavior = .Pipe;
    process.stderr_behavior = .Ignore;

    try process.spawn();
    defer _ = process.kill() catch {};

    const stdout = try process.stdout.?.readToEndAlloc(arena_allocator, 10 * 1024 * 1024);
    _ = try process.wait();

    // Parse wmic output (CSV format)
    var lines = std.mem.tokenizeScalar(u8, stdout, '\n');
    _ = lines.next(); // Skip header line

    while (lines.next()) |line| {
        if (line.len == 0) continue;

        var fields = std.mem.tokenizeScalar(u8, line, ',');
        _ = fields.next(); // Skip first empty field (CSV quirk)
        const name_field = fields.next() orelse continue;
        const pid_field = fields.next() orelse continue;
        const mem_field = fields.next() orelse continue;
        _ = fields.next(); // Skip PageFileUsage

        const pid = std.fmt.parseInt(u32, std.mem.trim(u8, pid_field, " \r\n"), 10) catch continue;
        const name = std.mem.trim(u8, name_field, " \r\n");
        const mem_bytes = std.fmt.parseInt(u64, std.mem.trim(u8, mem_field, " \r\n"), 10) catch continue;
        const memory_kb = mem_bytes / 1024;

        // Check if process name matches
        var matches = false;
        for (process_names) |search_name| {
            if (std.mem.indexOf(u8, name, search_name) != null) {
                matches = true;
                break;
            }
        }
        if (!matches) continue;

        const name_dup = try allocator.dupe(u8, name);
        try out.append(allocator, ProcessInfo{
            .pid = pid,
            .name = name_dup,
            .cpu_percent = 0.0, // CPU calculation requires more complex Windows API calls
            .memory_kb = memory_kb,
            .disk_read_bytes = null, // Requires I/O counters from Windows API
            .disk_write_bytes = null,
            .open_files = null, // Requires handle enumeration from Windows API
        });
    }
}

// macOS implementation using ps command
fn findProcessesMacOS(allocator: std.mem.Allocator, process_names: []const []const u8, out: *std.ArrayListUnmanaged(ProcessInfo)) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Use ps command to get process information
    var process = std.process.Child.init(&.{ "ps", "-ax", "-o", "pid=,comm=,rss=,pcpu=" }, allocator);
    process.stdin_behavior = .Ignore;
    process.stdout_behavior = .Pipe;
    process.stderr_behavior = .Ignore;

    try process.spawn();
    defer _ = process.kill() catch {};

    const stdout = try process.stdout.?.readToEndAlloc(arena_allocator, 10 * 1024 * 1024);
    _ = try process.wait();

    // Parse ps output
    var lines = std.mem.tokenizeScalar(u8, stdout, '\n');

    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // ps output format: "PID COMM RSS %CPU"
        var fields = std.mem.tokenizeScalar(u8, line, ' ');
        const pid_str = fields.next() orelse continue;
        const comm = fields.next() orelse continue;
        const rss_str = fields.next() orelse continue;
        const pcpu_str = fields.next() orelse "0.0";

        const pid = std.fmt.parseInt(u32, pid_str, 10) catch continue;
        const rss_kb = std.fmt.parseInt(u64, rss_str, 10) catch continue;
        const cpu_percent = std.fmt.parseFloat(f64, pcpu_str) catch 0.0;

        // Check if process name matches
        var matches = false;
        for (process_names) |search_name| {
            if (std.mem.indexOf(u8, comm, search_name) != null) {
                matches = true;
                break;
            }
        }
        if (!matches) continue;

        const name_dup = try allocator.dupe(u8, comm);
        try out.append(allocator, ProcessInfo{
            .pid = pid,
            .name = name_dup,
            .cpu_percent = cpu_percent,
            .memory_kb = rss_kb,
            .disk_read_bytes = null, // Requires I/O stats from sysctl or libproc
            .disk_write_bytes = null,
            .open_files = null, // Requires file descriptor count from libproc
        });
    }
}

fn formatBytes(allocator: std.mem.Allocator, bytes: u64) ![]const u8 {
    const bytes_f64 = @as(f64, @floatFromInt(bytes));
    const kb = bytes_f64 / 1024.0;
    const mb = kb / 1024.0;
    const gb = mb / 1024.0;

    if (gb >= 1.0) {
        const gb_int = @as(u64, @intFromFloat(gb));
        const mb_remainder = mb - (@as(f64, @floatFromInt(gb_int)) * 1024.0);
        const decimal = @as(u64, @intFromFloat(mb_remainder * 10.0 / 1024.0));
        return try std.fmt.allocPrint(allocator, "{d}.{d} GB", .{ gb_int, decimal });
    } else if (mb >= 1.0) {
        const mb_int = @as(u64, @intFromFloat(mb));
        const kb_remainder = kb - (@as(f64, @floatFromInt(mb_int)) * 1024.0);
        const decimal = @as(u64, @intFromFloat(kb_remainder * 10.0 / 1024.0));
        return try std.fmt.allocPrint(allocator, "{d}.{d} MB", .{ mb_int, decimal });
    } else if (kb >= 1.0) {
        const kb_int = @as(u64, @intFromFloat(kb));
        return try std.fmt.allocPrint(allocator, "{d} KB", .{kb_int});
    } else {
        return try std.fmt.allocPrint(allocator, "{d} B", .{bytes});
    }
}
