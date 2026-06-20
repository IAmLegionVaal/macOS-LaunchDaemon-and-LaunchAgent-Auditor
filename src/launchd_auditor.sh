#!/bin/bash
set -u

OUTPUT_DIR=""
HOURS=24

usage() { echo "Usage: launchd_auditor.sh [--hours N] [--output DIR]"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
case "$HOURS" in ''|*[!0-9]*) echo "--hours must be numeric" >&2; exit 2 ;; esac
[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 1; }

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./launchd-audit-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/launchd-audit.txt"
CSV="$OUTPUT_DIR/jobs.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"; : > "$ERRORS"
echo 'plist,label,owner,mode,program,program_exists,signature_valid,status' > "$CSV"

section() { title="$1"; shift; { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true; }
section "Collection metadata" /bin/bash -c 'date -u +%Y-%m-%dT%H:%M:%SZ; hostname; sw_vers; id'
section "Loaded system jobs" /bin/launchctl print system
section "Disabled system jobs" /bin/launchctl print-disabled system
section "Recent launchd events" /bin/bash -c "/usr/bin/log show --last ${HOURS}h --style compact --predicate 'process == \"launchd\" OR subsystem == \"com.apple.xpc.launchd\"' 2>/dev/null | tail -n 3000"

TOTAL=0
REVIEW=0
for dir in /System/Library/LaunchDaemons /System/Library/LaunchAgents /Library/LaunchDaemons /Library/LaunchAgents /Users/*/Library/LaunchAgents; do
  [ -d "$dir" ] || continue
  for plist in "$dir"/*.plist; do
    [ -f "$plist" ] || continue
    TOTAL=$((TOTAL + 1))
    label=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist" 2>/dev/null || basename "$plist")
    program=$(/usr/libexec/PlistBuddy -c 'Print :Program' "$plist" 2>/dev/null || true)
    if [ -z "$program" ]; then
      program=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist" 2>/dev/null || true)
    fi
    owner=$(stat -f '%Su:%Sg' "$plist" 2>/dev/null || echo unknown)
    mode=$(stat -f '%Lp' "$plist" 2>/dev/null || echo unknown)
    program_exists=false
    [ -n "$program" ] && [ -e "$program" ] && program_exists=true
    signature_valid="not-tested"
    if [ -n "$program" ] && [ -e "$program" ]; then
      if /usr/bin/codesign --verify --deep --strict "$program" >/dev/null 2>&1; then signature_valid=true; else signature_valid=false; fi
    fi
    status="OK"
    /usr/bin/plutil -lint "$plist" >/dev/null 2>&1 || status="INVALID_PLIST"
    case "$dir" in /Library/*|/Users/*) [ "$owner" = "root:wheel" ] || status="REVIEW_OWNER" ;; esac
    [ -n "$program" ] && [ "$program_exists" = false ] && status="MISSING_PROGRAM"
    [ "$status" = "OK" ] || REVIEW=$((REVIEW + 1))
    safe() { printf '%s' "$1" | sed 's/"/""/g'; }
    printf '"%s","%s","%s","%s","%s","%s","%s","%s"\n' \
      "$(safe "$plist")" "$(safe "$label")" "$(safe "$owner")" "$mode" "$(safe "$program")" "$program_exists" "$signature_valid" "$status" >> "$CSV"
  done
done

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "jobs_audited": $TOTAL,
  "findings_for_review": $REVIEW,
  "overall_status": "$([ "$REVIEW" -eq 0 ] && echo Healthy || echo 'Attention required')"
}
EOF
printf '\nLaunchd audit completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
