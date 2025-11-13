# Zig Tools Workspace

This workspace organizes multiple small Zig tools, each stored in its own folder with independent documentation.

## Build System

The project uses Zig's native build system (`zig build`). No shell scripts or system commands are required, making it fully cross-platform compatible.

### Building

Build all tools for native target:

```bash
zig build
```

Build a specific tool:

```bash
zig build -Dtool=hello
```

Output location: `zig-out/<target>/bin/` (where `<target>` is the target triple, e.g., `x86_64-linux-gnu`)

### Cross-compilation

Cross-compile to a specific target triple:

```bash
zig build -Dtarget=aarch64-linux-gnu
```

Output location: `zig-out/<target>/bin/` (where `<target>` is the specified target triple)

Supported targets (examples):

- `x86_64-linux-gnu` — x86_64 Linux
- `aarch64-linux-gnu` — ARM64 Linux
- `x86_64-windows-gnu` — x86_64 Windows
- `aarch64-macos` — ARM64 macOS (Apple Silicon)
- `x86_64-macos` — Intel macOS

### Clean

Remove build artifacts:

```bash
zig build clean
```

## Project Options

- `-Dtool=<name|all>` — Build a specific tool or 'all' (default: all)

## Tools

Each tool has its own documentation:

- **[hello](hello/README.md)** — Simple greeting utility
- **[echo](echo/README.md)** — Echo command-line arguments
- **[psmon](psmon/README.md)** — Process monitor for resource usage

## Notes

- Zig 0.15.1+ is required and must be available on `PATH`.
- The build system is fully cross-platform and does not rely on shell scripts or system commands.
- CI workflow included in `.github/workflows/ci.yml` for cross-building and artifact upload.
