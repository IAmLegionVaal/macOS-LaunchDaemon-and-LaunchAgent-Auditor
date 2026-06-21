# macOS LaunchDaemon and LaunchAgent Auditor

A macOS support toolkit for auditing and repairing selected launchd jobs.

## Audit script

```bash
chmod +x src/launchd_auditor.sh
sudo ./src/launchd_auditor.sh
```

The audit checks system and user LaunchDaemons and LaunchAgents, plist validity, ownership, permissions, executable targets, loaded state and recent failures.

## Repair script

Restart one loaded job:

```bash
chmod +x src/launchd_job_repair.sh
./src/launchd_job_repair.sh \
  --restart-label com.example.agent \
  --domain user
```

Reload one user LaunchAgent or third-party LaunchDaemon plist:

```bash
sudo ./src/launchd_job_repair.sh \
  --reload-plist /Library/LaunchDaemons/com.example.service.plist \
  --domain system
```

Preview either action with `--dry-run`.

## What the repair does

- Restarts one selected loaded job with `launchctl kickstart`.
- Validates a selected plist before reloading it.
- Backs up a plist before unload and reload operations.
- Restricts plist repairs to standard third-party LaunchAgents and LaunchDaemons folders.
- Supports confirmation prompts, dry-run, logs and post-repair verification.
- Returns clear success, cancellation, warning and invalid-argument exit codes.

## Safety and limitations

The repair never deletes plist files. It does not modify Apple-protected system plist files. A job with a damaged executable, invalid configuration or missing dependency may still fail after reload and require vendor-specific repair.

## Author

Dewald Pretorius — L2 IT Support Engineer
