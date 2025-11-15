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

## Platform Support

`psmon` supports multiple operating systems:

- **Linux**: Full support with CPU, memory, disk I/O, and open file counts
  - Uses `/proc` filesystem for process information
  - Requires sufficient permissions (some features may require root)
  
- **Windows**: Basic support with process name, PID, and memory
  - Uses `wmic` command to query process information
  - CPU, disk I/O, and open files are not yet implemented
  - Requires Windows with `wmic` available (Windows 10/11)
  
- **macOS**: Basic support with process name, PID, memory, and CPU
  - Uses `ps` command to query process information
  - Disk I/O and open files are not yet implemented
  - Requires standard Unix tools (`ps`)

## Requirements

- **Linux**: `/proc` filesystem and sufficient permissions
- **Windows**: `wmic` command (available on Windows 10/11)
- **macOS**: Standard Unix tools (`ps` command)

