#!/usr/bin/env bash
# ============================================================
#  watcher.sh — Drop-Zone Watcher Daemon
#  Unix Classroom File Submission Portal
# ============================================================
#  Usage: bash bin/watcher.sh [start|stop|status|once]
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTAL_ROOT="$(dirname "$SCRIPT_DIR")"

# Set all paths from PORTAL_ROOT FIRST — before sourcing portal.conf
CONFIG="$PORTAL_ROOT/config"
DROP_ZONE="$PORTAL_ROOT/drop_zone"
SUBMISSIONS="$PORTAL_ROOT/submissions"
GRADED="$PORTAL_ROOT/graded"
REPORTS="$PORTAL_ROOT/reports"
LOGS="$PORTAL_ROOT/logs"

# Load extra settings (extensions, file size, watch interval)
if [[ -f "$PORTAL_ROOT/config/portal.conf" ]]; then
    source "$PORTAL_ROOT/config/portal.conf" 2>/dev/null || true
fi

# Re-assert paths in case portal.conf overwrote them
CONFIG="$PORTAL_ROOT/config"
DROP_ZONE="$PORTAL_ROOT/drop_zone"
SUBMISSIONS="$PORTAL_ROOT/submissions"
GRADED="$PORTAL_ROOT/graded"
REPORTS="$PORTAL_ROOT/reports"
LOGS="$PORTAL_ROOT/logs"
WATCH_INTERVAL="${WATCH_INTERVAL:-5}"

export CONFIG LOGS DROP_ZONE SUBMISSIONS GRADED REPORTS

source "$SCRIPT_DIR/lib_validate.sh"

PID_FILE="/tmp/submission_portal_watcher.pid"
PROCESSED_LOG="$LOGS/processed.log"

# ── Ensure directories exist ──────────────────────────────────
setup_dirs() {
    mkdir -p "$DROP_ZONE" "$DROP_ZONE/quarantine" \
             "$SUBMISSIONS" "$GRADED" "$REPORTS" "$LOGS"
    chmod 1777 "$DROP_ZONE"
    log_msg INFO "Directories verified"
}

# ── Idempotency check ─────────────────────────────────────────
is_processed() {
    grep -qF "$1" "$PROCESSED_LOG" 2>/dev/null
}

mark_processed() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')|$1" >> "$PROCESSED_LOG"
}

# ── Process one file ──────────────────────────────────────────
process_file() {
    local fpath="$1"
    local fname; fname=$(basename "$fpath")

    log_msg INFO "=== Processing: $fname ==="

    if is_processed "$fname"; then
        log_msg WARN "Already processed, skipping: $fname"
        return 0
    fi

    # Run validations in the current shell so V_* variables (V_STUDENT_ID,
    # V_ASSIGN_ID, V_EXT, V_STUDENT_NAME …) are visible after the call.
    # We redirect the human-readable log output to a temp file and only
    # read back the final status word (last non-empty line) to avoid
    # ANSI colour codes polluting the comparison.
    local _val_tmp; _val_tmp=$(mktemp)
    local status
    set +e
    run_all_validations "$fpath" > "$_val_tmp" 2>/dev/null
    set -e

    # Extract the clean status word (last non-empty line, strip whitespace)
    status=$(grep -E '^(VALID_ONTIME|VALID_LATE|INVALID)$' "$_val_tmp" | tail -1 | tr -d '[:space:]')
    rm -f "$_val_tmp"

    # If validation produced no recognised status, treat as invalid
    if [[ -z "$status" ]]; then
        status="INVALID"
    fi

    if [[ "$status" == "INVALID" ]]; then
        mkdir -p "$DROP_ZONE/quarantine"
        mv "$fpath" "$DROP_ZONE/quarantine/$fname"
        log_msg ERROR "REJECTED → quarantine: $fname"
        mark_processed "$fname"
        return 0
    fi

    local is_late=0
    [[ "$status" == "VALID_LATE" ]] && is_late=1

    # Build destination
    local assign_dir="$SUBMISSIONS/$V_STUDENT_ID/$V_ASSIGN_ID"
    mkdir -p "$assign_dir"

    local dest="$assign_dir/$fname"

    # Version old file if duplicate
    if [[ -f "$dest" ]]; then
        local ver_ts; ver_ts=$(date '+%H%M%S')
        mv "$dest" "${dest%.*}_v${ver_ts}.${V_EXT}"
        log_msg WARN "Duplicate — old version backed up"
    fi

    mv "$fpath" "$dest"
    chmod 640 "$dest"

    # Write metadata
    local meta="$assign_dir/.meta_${fname%.*}.txt"
    {
        echo "student_id=$V_STUDENT_ID"
        echo "student_name=${V_STUDENT_NAME:-Unknown}"
        echo "assign_id=$V_ASSIGN_ID"
        echo "assign_name=${V_ASSIGN_NAME:-$V_ASSIGN_ID}"
        echo "submitted=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "filename=$fname"
        echo "extension=$V_EXT"
        echo "status=$status"
        echo "is_late=$is_late"
        [[ "$is_late" == "1" ]] && echo "minutes_late=${V_MINUTES_LATE:-0}"
        echo "deadline=${V_DEADLINE_STR:-N/A}"
        echo "file_size_kb=$(du -k "$dest" | cut -f1)"
    } > "$meta"

    log_msg OK "ACCEPTED [$status] → $dest"   # status is already a clean word here
    mark_processed "$fname"

    # Trigger report in background
    bash "$SCRIPT_DIR/generate_report.sh" "$V_STUDENT_ID" &
}

# ── Scan drop zone once ───────────────────────────────────────
scan_once() {
    local count=0
    while IFS= read -r -d '' fpath; do
        local fname; fname=$(basename "$fpath")
        [[ "$fname" == .* ]]          && continue
        [[ "$fname" == *~ ]]          && continue
        [[ "$fpath" == */quarantine/* ]] && continue
        process_file "$fpath"
        (( count++ )) || true
    done < <(find "$DROP_ZONE" -maxdepth 1 -type f -print0 2>/dev/null)

    (( count == 0 )) && log_msg INFO "Drop zone empty — nothing to process"
}

# ── Daemon ────────────────────────────────────────────────────
start_daemon() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo -e "${YELLOW}Watcher already running (PID $(cat "$PID_FILE"))${NC}"
        exit 0
    fi
    setup_dirs
    echo $$ > "$PID_FILE"
    log_msg INFO "Watcher started (PID $$)"
    echo -e "${GREEN}${BOLD}✔ Watcher started (PID $$)${NC}"
    echo    "   Drop zone : $DROP_ZONE"
    echo    "   Interval  : ${WATCH_INTERVAL}s"
    while true; do
        scan_once
        sleep "$WATCH_INTERVAL"
    done
}

stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid; pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null && echo -e "${GREEN}Watcher stopped (PID $pid)${NC}"
        rm -f "$PID_FILE"
    else
        echo -e "${YELLOW}Watcher not running${NC}"
    fi
}

show_status() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo -e "${GREEN}● Watcher RUNNING (PID $(cat "$PID_FILE"))${NC}"
    else
        echo -e "${RED}○ Watcher STOPPED${NC}"
    fi
    local total; total=$(wc -l < "$PROCESSED_LOG" 2>/dev/null || echo 0)
    echo "  Total processed : $total files"
    echo "  Pending in drop : $(find "$DROP_ZONE" -maxdepth 1 -type f 2>/dev/null | wc -l) files"
}

# ── Entry point ───────────────────────────────────────────────
case "${1:-once}" in
    start)  setup_dirs; start_daemon ;;
    stop)   stop_daemon ;;
    status) show_status ;;
    once)   setup_dirs; log_msg INFO "Single scan"; scan_once ;;
    *)      echo "Usage: $0 {start|stop|status|once}"; exit 1 ;;
esac
