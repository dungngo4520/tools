// Configuration for build system

pub const libraries = .{};

pub const tool_dirs = .{
    "echo",
    "hello",
    "psu",
};

pub const targets = .{
    "x86_64-windows-gnu",
    "aarch64-windows-gnu",
    "x86_64-linux-gnu",
    "aarch64-linux-gnu",
    "riscv64-linux-gnu",
    "x86_64-macos-none",
    "aarch64-macos-none",
};
