# Echo Tool

A command-line echo utility written in Zig, similar to the Unix `echo` command.

## Usage

```bash
./echo [ARGS...]
```

## Examples

```bash
# Echo single argument
./echo "hello"
# Output: hello

# Echo multiple arguments
./echo hello world
# Output: hello world

# Echo with spaces
./echo "foo bar" "baz qux"
# Output: foo bar baz qux
```

## Description

The `echo` tool prints its command-line arguments to stdout, separated by spaces, with a trailing newline.
This mirrors the behavior of the standard Unix `echo` command.

## Features

- Accepts any number of arguments
- Separates arguments with spaces
- Adds trailing newline
- Cross-platform support (Linux, Windows, macOS)
