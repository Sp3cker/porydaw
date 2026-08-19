---
name: no-long-script-timeouts
description: "Disable the deadline instead of assigning timeouts longer than 180 seconds"
condition: "[\"']?timeout[\"']?\\s*:\\s*3600"
scope: "tool:bash"
---

For scripts that can run longer than 180 seconds, set `timeout` to `0` to disable the command deadline. Never assign a finite timeout greater than 180 seconds; it can cancel valid long-running verification.