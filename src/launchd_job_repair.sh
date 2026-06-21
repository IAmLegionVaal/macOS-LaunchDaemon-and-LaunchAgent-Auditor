#!/bin/bash
set -u

DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
LABEL=""
PLIST=""
DOMAIN="user"
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: launchd_job_repair.sh [options]

  --restart-label LABEL  Restart one loaded launchd job.
  --reload-plist PLIST   Validate, unload and reload one launchd plist.
  --domain user|system   Target domain (default: user).
  --dry-run              Show commands without changing the Mac.
  --yes                  Skip confirmation prompts.
  --output DIR           Save logs and verification output in DIR.
  -h, --help             Show help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --restart-label) LABEL="${2:-}"; shift 2 ;;
    --reload-plist) PLIST="${2:-}"; shift 2 ;;
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 3; }
case "$DOMAIN" in user|system) : ;; *) echo "--domain must be user or system." >&2; exit 2 ;; esac
if [ -n "$LABEL" ] && [ -n "$PLIST" ]; then echo "Choose one repair action." >&2; exit 2; fi
if [ -z "$LABEL" ] && [ -z "$PLIST" ]; then echo "Choose --restart-label or --reload-plist." >&2; exit 2; fi

TARGET_USER="${SUDO_USER:-$(id -un)}"
if [ "$TARGET_USER" = "root" ]; then
  TARGET_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || echo root)
fi
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null) || { echo "Target user not found." >&2; exit 3; }
TARGET_HOME=$(/usr/bin/dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
[ -n "$TARGET_HOME" ] || TARGET_HOME="$HOME"

if [ -n "$PLIST" ]; then
  case "$PLIST" in
    /Library/LaunchAgents/*.plist|/Library/LaunchDaemons/*.plist|"$TARGET_HOME"/Library/LaunchAgents/*.plist) : ;;
    *) echo "Plist must be in a standard non-system launchd folder." >&2; exit 2 ;;
  esac
  [ -f "$PLIST" ] || { echo "Plist not found: $PLIST" >&2; exit 2; }
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./launchd-job-repair-$STAMP}"
BACKUP_DIR="$OUTPUT_DIR/backup"
mkdir -p "$OUTPUT_DIR" "$BACKUP_DIR"
LOG="$OUTPUT_DIR/repair.log"
VERIFY="$OUTPUT_DIR/verification.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() {
  $ASSUME_YES && return 0
  printf '%s [y/N]: ' "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
run_action() {
  description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then
    printf 'DRY-RUN:' >> "$LOG"; for arg in "$@"; do printf ' %q' "$arg" >> "$LOG"; done; printf '\n' >> "$LOG"; return 0
  fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
launch_domain() {
  if [ "$DOMAIN" = "system" ]; then echo system; else echo "gui/$TARGET_UID"; fi
}
run_launchctl() {
  description="$1"; shift
  if [ "$DOMAIN" = "system" ] && [ "$(id -u)" -ne 0 ]; then
    run_action "$description" /usr/bin/sudo /bin/launchctl "$@"
  else
    run_action "$description" /bin/launchctl "$@"
  fi
}
verify() {
  {
    echo "Collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Target domain: $(launch_domain)"
    if [ -n "$LABEL" ]; then
      echo "Job state:"
      /bin/launchctl print "$(launch_domain)/$LABEL" 2>&1 | head -n 250 || true
    fi
    if [ -n "$PLIST" ]; then
      echo "Plist validation:"
      /usr/bin/plutil -lint "$PLIST" 2>&1 || true
      echo "Plist metadata:"
      /bin/ls -lOe "$PLIST" 2>&1 || true
    fi
  } > "$VERIFY" 2>&1
}

verify
if [ -n "$LABEL" ]; then
  if ! confirm "Restart launchd job $LABEL in $(launch_domain)?"; then log "Repair cancelled."; exit 10; fi
  run_launchctl "Restarting launchd job $LABEL" kickstart -k "$(launch_domain)/$LABEL" || true
else
  /usr/bin/plutil -lint "$PLIST" >> "$LOG" 2>&1 || { log "Plist validation failed; no changes made."; exit 20; }
  if ! confirm "Reload $PLIST in $(launch_domain)?"; then log "Repair cancelled."; exit 10; fi
  if ! $DRY_RUN; then /bin/cp -p "$PLIST" "$BACKUP_DIR/$(basename "$PLIST")" 2>/dev/null || true; fi
  run_launchctl "Unloading $PLIST" bootout "$(launch_domain)" "$PLIST" || true
  run_launchctl "Loading $PLIST" bootstrap "$(launch_domain)" "$PLIST" || true
fi

if ! $DRY_RUN; then sleep 3; fi
verify
if [ "$FAILURES" -gt 0 ]; then log "Repair completed with $FAILURES warning(s)."; exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0
