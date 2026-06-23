#!/usr/bin/env bash
# ============================================================
#  lib_validate.sh — Core Validation Library
#  Source this file — do not run directly
# ============================================================

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── log_msg ───────────────────────────────────────────────────
log_msg() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="${LOGS:-/tmp}/portal.log"
    # Create log dir if needed
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
    echo "[$ts] [$level] $msg" >> "$log_file" 2>/dev/null || true
    case "$level" in
        INFO)  echo -e "${CYAN}[INFO]${NC}  $msg" ;;
        OK)    echo -e "${GREEN}[OK]${NC}    $msg" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  $msg" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $msg" ;;
    esac
}

# ── validate_filename ─────────────────────────────────────────
# Sets: V_STUDENT_ID  V_ASSIGN_ID  V_DATE_STR  V_EXT
validate_filename() {
    local fname="$1"
    local pattern='^[Ss]([0-9]{3})_[Aa]([0-9]{2})_([0-9]{4}-[0-9]{2}-[0-9]{2})\.([a-zA-Z0-9]+)$'

    if [[ ! "$fname" =~ $pattern ]]; then
        log_msg ERROR "Invalid filename format: '$fname'"
        log_msg INFO  "Expected format: SXXX_AXX_YYYY-MM-DD.ext  e.g. S001_A01_2026-12-01.py"
        return 1
    fi

    V_STUDENT_ID=$(echo "$fname" | sed -E 's/^[Ss]([0-9]{3})_.*/S\1/')
    V_ASSIGN_ID=$( echo "$fname" | sed -E 's/^[Ss][0-9]{3}_[Aa]([0-9]{2})_.*/A\1/')
    V_DATE_STR=$(  echo "$fname" | sed -E 's/.*_([0-9]{4}-[0-9]{2}-[0-9]{2})\..*/\1/')
    V_EXT=$(       echo "$fname" | sed -E 's/.*\.([a-zA-Z0-9]+)$/\1/')
    return 0
}

# ── validate_extension ────────────────────────────────────────
validate_extension() {
    local ext="${1,,}"
    local allowed="${ALLOWED_EXTENSIONS:-py sh c cpp java txt pdf md}"
    for a in $allowed; do
        [[ "$ext" == "$a" ]] && return 0
    done
    log_msg ERROR "Extension '.$ext' not allowed. Allowed: $allowed"
    return 1
}

# ── validate_filesize ─────────────────────────────────────────
validate_filesize() {
    local fpath="$1"
    local max_kb="${MAX_FILE_SIZE_KB:-5120}"
    local size_kb; size_kb=$(du -k "$fpath" | cut -f1)
    if (( size_kb > max_kb )); then
        log_msg ERROR "File too large: ${size_kb}KB exceeds ${max_kb}KB limit"
        return 1
    fi
    return 0
}

# ── validate_student ──────────────────────────────────────────
# Sets: V_STUDENT_NAME  V_STUDENT_EMAIL
validate_student() {
    local sid="$1"
    local registry="${CONFIG:-}/students.conf"

    # Try to find students.conf
    if [[ ! -f "$registry" ]]; then
        # Fallback: search common locations
        for try in \
            "${CONFIG}/students.conf" \
            "$(dirname "${BASH_SOURCE[0]}")/../config/students.conf"
        do
            [[ -f "$try" ]] && registry="$try" && break
        done
    fi

    if [[ ! -f "$registry" ]]; then
        log_msg ERROR "students.conf not found. Looked at: $registry"
        return 1
    fi

    local record; record=$(grep -i "^${sid}|" "$registry" 2>/dev/null || true)

    if [[ -z "$record" ]]; then
        log_msg ERROR "Student ID '$sid' not found in registry"
        return 1
    fi

    V_STUDENT_NAME=$(echo  "$record" | cut -d'|' -f2)
    V_STUDENT_EMAIL=$(echo "$record" | cut -d'|' -f3)
    return 0
}

# ── check_deadline ────────────────────────────────────────────
# Returns: 0=on-time  1=late  2=not-found
# Sets: V_DEADLINE_STR  V_ASSIGN_NAME  V_MINUTES_LATE
check_deadline() {
    local aid="$1"
    local deadlines="${CONFIG:-}/deadlines.conf"

    # Fallback search
    if [[ ! -f "$deadlines" ]]; then
        for try in \
            "${CONFIG}/deadlines.conf" \
            "$(dirname "${BASH_SOURCE[0]}")/../config/deadlines.conf"
        do
            [[ -f "$try" ]] && deadlines="$try" && break
        done
    fi

    if [[ ! -f "$deadlines" ]]; then
        log_msg WARN "deadlines.conf not found — skipping deadline check"
        V_ASSIGN_NAME="$aid"
        V_DEADLINE_STR="N/A"
        V_MINUTES_LATE=0
        return 0
    fi

    local record; record=$(grep -i "^${aid}|" "$deadlines" 2>/dev/null || true)

    if [[ -z "$record" ]]; then
        log_msg WARN "Assignment '$aid' not in deadlines.conf"
        V_ASSIGN_NAME="$aid"
        V_DEADLINE_STR="N/A"
        V_MINUTES_LATE=0
        return 2
    fi

    V_DEADLINE_STR=$(echo "$record" | cut -d'|' -f2)
    V_ASSIGN_NAME=$(echo  "$record" | cut -d'|' -f3)
    V_MINUTES_LATE=0

    local now_epoch deadline_epoch
    now_epoch=$(date +%s)
    deadline_epoch=$(date -d "$V_DEADLINE_STR" +%s 2>/dev/null || echo 0)

    if [[ "$deadline_epoch" == "0" ]]; then
        log_msg WARN "Could not parse deadline date: '$V_DEADLINE_STR'"
        return 0
    fi

    if (( now_epoch > deadline_epoch )); then
        V_MINUTES_LATE=$(( (now_epoch - deadline_epoch) / 60 ))
        log_msg WARN "LATE — $aid is ${V_MINUTES_LATE} min past deadline ($V_DEADLINE_STR)"
        return 1
    fi

    local mins_left=$(( (deadline_epoch - now_epoch) / 60 ))
    log_msg OK "On-time — $V_ASSIGN_NAME (${mins_left} min remaining)"
    return 0
}

# ── run_all_validations ───────────────────────────────────────
# Prints: VALID_ONTIME | VALID_LATE | INVALID
run_all_validations() {
    local fpath="$1"
    local fname; fname=$(basename "$fpath")

    validate_filename  "$fname"       || { echo "INVALID"; return 0; }
    validate_extension "$V_EXT"       || { echo "INVALID"; return 0; }
    validate_filesize  "$fpath"       || { echo "INVALID"; return 0; }
    validate_student   "$V_STUDENT_ID" || { echo "INVALID"; return 0; }

    set +e
    check_deadline "$V_ASSIGN_ID"
    local dl=$?
    set -e

    if (( dl == 1 )); then
        echo "VALID_LATE"
    else
        echo "VALID_ONTIME"
    fi
    return 0
}
