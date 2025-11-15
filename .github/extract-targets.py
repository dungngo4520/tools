#!/usr/bin/env python3
import re

with open("build.config.zig", "r") as f:
    content = f.read()

match = re.search(r"pub const targets = \.(.*?)\};", content, re.DOTALL)
if match:
    targets_section = match.group(1)
    targets = re.findall(r'"([^"]+)"', targets_section)
    print("[" + ", ".join(f'"{t}"' for t in targets) + "]")
