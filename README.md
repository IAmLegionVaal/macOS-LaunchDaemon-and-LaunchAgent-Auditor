# macOS LaunchDaemon and LaunchAgent Auditor

A read-only Bash toolkit for auditing launchd jobs, persistence locations, ownership, permissions, signatures, disabled jobs, and recent failures.

## Checks performed

- System and user LaunchDaemons and LaunchAgents
- Plist validity, labels, program paths, arguments, and run conditions
- Ownership and permission findings
- Missing or unsigned executable targets
- Loaded and disabled launchd jobs
- Recent launchd and service failure events
- Text, CSV, and JSON reports

## Usage

```bash
chmod +x src/launchd_auditor.sh
sudo ./src/launchd_auditor.sh
```

## Safety

The script never loads, unloads, enables, disables, deletes, edits, or restarts launchd jobs.

## Author

Dewald Pretorius — L2 IT Support Engineer
