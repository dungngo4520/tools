# Zig Tools Workspace

This workspace organizes multiple small Zig tools, each stored in its own folder with independent documentation.

## Project Structure

```
tools/
├── build.zig              # Zig build script
├── README.md              # This file
├── .editorconfig           # Editor settings
├── .gitignore              # Git ignore rules
├── hello/
│   ├── main.zig           # Hello tool source
│   └── README.md          # Hello tool documentation
└── echo/
    ├── main.zig           # Echo tool source
    └── README.md          # Echo tool documentation
```

## Build Output Structure

Built binaries are organized by target triple in `zig-out/`:

```
zig-out/
├── native/                     # Native (host) target binaries
│   ├── hello
│   └── echo
├── aarch64-linux-gnu/          # ARM64 Linux
│   ├── hello
│   └── echo
└── x86_64-windows-gnu/         # x86_64 Windows
    ├── hello.exe
    └── echo.exe
```

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

Output location: `zig-out/native/`

### Cross-compilation

Cross-compile to a specific target triple:

```bash
zig build -Dtarget=aarch64-linux-gnu
```

Output location: `zig-out/aarch64-linux-gnu/`

Supported targets (examples):

- `x86_64-linux-gnu` — x86_64 Linux
- `aarch64-linux-gnu` — ARM64 Linux
- `x86_64-windows-gnu` — x86_64 Windows
- `aarch64-macos` — ARM64 macOS (Apple Silicon)
- `x86_64-macos` — Intel macOS

### Clean

Remove build artifacts:

```bash
zig build clean-dist
```

## Project Options

- `-Dtool=<name|all>` — Build a specific tool or 'all' (default: all)

## Tools

Each tool has its own documentation:

- **[hello](hello/README.md)** — Simple greeting utility
- **[echo](echo/README.md)** — Echo command-line arguments

## Notes

- Zig 0.15.1+ is required and must be available on `PATH`.
- The build system is fully cross-platform and does not rely on shell scripts or system commands.
- CI workflow included in `.github/workflows/ci.yml` for cross-building and artifact upload.
