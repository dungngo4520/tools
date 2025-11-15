# Zig Tools Workspace

A collection of Zig tools with shared libraries.

## Building

```bash
zig build                                 # Build all tools
zig build -Dtool=echo                     # Build specific tool
zig build -Dtarget=aarch64-linux-gnu      # Cross-compile
zig build -Dall-targets                   # Build for all targets
zig build clean                           # Clean build artifacts
```

## Project Structure

```text
.
├── build.zig                # Build system
├── build.config.zig         # Configuration
├── libs/zig-arg/            # Shared libraries
└── tools/                   # Tools
    ├── echo/
    ├── hello/
    └── psu/
```

## Configuration

Edit `build.config.zig` to add tools, libraries, and targets.

```zig
pub const libraries = .{
    .@"zig-arg" = "libs/zig-arg/src/arg.zig",
};

pub const tool_dirs = .{
    "echo",
    "hello",
    "psu",
};

pub const targets = .{
    "x86_64-linux-gnu",
    "aarch64-linux-gnu",
    "x86_64-windows-gnu",
    // ... more targets
};
```

## Adding Tools

1. Create `my-tool/main.zig`:

    ```zig
    const std = @import("std");
    const arg = @import("zig-arg");

    pub fn main() void {
        std.debug.print("Hello!\n", .{});
    }
    ```

2. Add to `build.config.zig`:

    ```zig
    pub const tool_dirs = .{
        "echo",
        "hello",
        "psu",
        "my-tool",
    };
    ```

3. Build:

    ```bash
    zig build -Dtool=my-tool
    ```

## Adding Libraries

1. Create `libs/my-lib/src/lib.zig`
2. Add to `build.config.zig`:

    ```zig
    pub const libraries = .{
        .@"zig-arg" = "libs/zig-arg/src/arg.zig",
        .@"my-lib" = "libs/my-lib/src/lib.zig",
    };
    ```

3. Use in tools:

    ```zig
    const my_lib = @import("my-lib");
    ```

## Requirements

- Zig 0.15.2+
