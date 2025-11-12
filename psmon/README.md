# psmon - Process Monitor

A command-line tool to monitor resource usage of processes by name.

## Usage

```bash
psmon <process_name1> [process_name2] ...
```

## Description

`psmon` searches for processes matching the given names and displays their resource usage information including:

- **Process name** and **PID**
- **CPU percentage** - CPU usage as a percentage
- **Memory (KB)** - Resident Set Size (RSS) in kilobytes
- **Disk Read** - Total bytes read from disk (optional, requires permissions)
- **Disk Write** - Total bytes written to disk (optional, requires permissions)
- **Network I/O** - Currently not implemented (shows N/A)
- **Open Files** - Number of open file descriptors (optional, requires permissions)

## Examples

Monitor a single process:
```bash
psmon firefox
```

Monitor multiple processes:
```bash
psmon firefox chrome vscode
```

## Output Format

The output is formatted as a table with proper tab padding:

```text
PROCESS              PID      CPU %      MEMORY (KB)  DISK READ    DISK WRITE   NET READ     OPEN FILES
----------------------------------------------------------------------------------------------------
firefox              12345    5.23       524288       1024 MB      512 MB       N/A          42
```

## Notes

- Process name matching is done by substring search (case-sensitive)
- Some information (disk I/O, open files) may not be available if you don't have sufficient permissions
- CPU percentage is calculated based on total CPU time since process start
- On multi-core systems, CPU percentage can exceed 100%
- Network I/O monitoring is not yet implemented

## Requirements

- Linux system with `/proc` filesystem
- Sufficient permissions to read process information (some features require root)

