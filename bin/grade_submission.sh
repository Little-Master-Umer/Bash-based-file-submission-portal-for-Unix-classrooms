#!/usr/bin/env bash
# ============================================================
#  grade_submission.sh — Mark & Move Submissions to Graded
#  Unix Classroom File Submission Portal
# ============================================================
#  Usage:
#    ./grade_submission.sh <student_id> <assign_id> <grade> [feedback]
#
#  Example:
#    ./grade_submission.sh S001 A01 85 "Great work on loops!"
#
#  Grades:  0–100 (integer)  or  EXEMPT / MISSING
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTAL_ROOT="$(dirname "$SCRIPT_DIR")"

SUBMISSIONS="$PORTAL_ROOT/submissions"
GRADED="$PORTAL_ROOT/graded"
REPORTS="$PORTAL_ROOT/reports"
LOGS="$PORTAL_ROOT/logs"
CONFIG="$PORTAL_ROOT/config"
export CONFIG LOGS SUBMISSIONS GRADED REPORTS
source "$SCRIPT_DIR/lib_validate.sh"

# ── Argument validation ──────────────────────────────────────
if (( $# < 3 )); then
    echo -e "${RED}Usage: $0 <STUDENT_ID> <ASSIGN_ID> <GRADE> [FEEDBACK]${NC}"
    echo    "  GRADE: 0–100  |  EXEMPT  |  MISSING"
    exit 1
fi

STUDENT_ID="${1^^}"
ASSIGN_ID="${2^^}"
GRADE="$3"
FEEDBACK="${4:-No feedback provided}"
GRADER="${SUDO_USER:-${USER:-instructor}}"
GRADE_TS=$(date '+%Y-%m-%d %H:%M:%S')

# ── Validate grade value ─────────────────────────────────────
validate_grade() {
    local g="$1"
    if [[ "$g" =~ ^(EXEMPT|MISSING)$ ]]; then return 0; fi
    if [[ "$g" =~ ^[0-9]+$ ]] && (( g >= 0 && g <= 100 )); then return 0; fi
    log_msg ERROR "Invalid grade '$g'. Must be 0–100, EXEMPT, or MISSING"
    exit 1
}
validate_grade "$GRADE"

# ── Locate the submitted file ─────────────────────────────────
SRC_DIR="$SUBMISSIONS/$STUDENT_ID/$ASSIGN_ID"
if [[ ! -d "$SRC_DIR" ]]; then
    log_msg ERROR "No submission found at: $SRC_DIR"
    exit 1
fi

# Find the main submission file (skip versioned backups)
SUBMITTED_FILE=$(find "$SRC_DIR" -maxdepth 1 -type f \
    ! -name '.*' ! -name '*_v[0-9]*.*' | head -1)

if [[ -z "$SUBMITTED_FILE" ]]; then
    log_msg ERROR "No file found in $SRC_DIR"
    exit 1
fi

FNAME=$(basename "$SUBMITTED_FILE")

# ── Build destination ─────────────────────────────────────────
DEST_DIR="$GRADED/$STUDENT_ID/$ASSIGN_ID"
mkdir -p "$DEST_DIR"
DEST_FILE="$DEST_DIR/$FNAME"

# ── Copy to graded (keep original in submissions) ─────────────
cp "$SUBMITTED_FILE" "$DEST_FILE"
chmod 440 "$DEST_FILE"   # read-only for instructor+owner

# ── Determine letter grade ────────────────────────────────────
letter_grade() {
    local g="$1"
    if   [[ "$g" == "EXEMPT"  ]]; then echo "EX"
    elif [[ "$g" == "MISSING" ]]; then echo "F"
    elif (( g >= 90 ));           then echo "A"
    elif (( g >= 80 ));           then echo "B"
    elif (( g >= 70 ));           then echo "C"
    elif (( g >= 60 ));           then echo "D"
    else                               echo "F"
    fi
}
LETTER=$(letter_grade "$GRADE")

# ── Retrieve metadata ────────────────────────────────────────
META=$(find "$SRC_DIR" -name ".meta_*.txt" | head -1)
IS_LATE="0"
MINUTES_LATE="0"
[[ -n "$META" ]] && {
    IS_LATE=$(grep '^is_late=' "$META" | cut -d= -f2)
    MINUTES_LATE=$(grep '^minutes_late=' "$META" 2>/dev/null | cut -d= -f2 || echo 0)
}

# ── Write grade record ───────────────────────────────────────
GRADE_FILE="$DEST_DIR/.grade_${ASSIGN_ID}.txt"
{
    echo "=============================="
    echo " GRADE RECORD"
    echo "=============================="
    echo "student_id   = $STUDENT_ID"
    echo "assign_id    = $ASSIGN_ID"
    echo "filename     = $FNAME"
    echo "grade        = $GRADE"
    echo "letter_grade = $LETTER"
    echo "is_late      = $IS_LATE"
    echo "minutes_late = $MINUTES_LATE"
    echo "feedback     = $FEEDBACK"
    echo "graded_by    = $GRADER"
    echo "graded_at    = $GRADE_TS"
    echo "=============================="
} > "$GRADE_FILE"

log_msg OK "Graded: $STUDENT_ID / $ASSIGN_ID → $GRADE ($LETTER)  [$FEEDBACK]"

# ── Append to master gradebook ───────────────────────────────
GRADEBOOK="$GRADED/gradebook.csv"
if [[ ! -f "$GRADEBOOK" ]]; then
    echo "timestamp,student_id,assign_id,filename,grade,letter,is_late,minutes_late,grader,feedback" \
        > "$GRADEBOOK"
fi
echo "$GRADE_TS,$STUDENT_ID,$ASSIGN_ID,$FNAME,$GRADE,$LETTER,$IS_LATE,$MINUTES_LATE,$GRADER,\"$FEEDBACK\"" \
    >> "$GRADEBOOK"

echo -e "\n${GREEN}${BOLD}✔ Grade recorded successfully${NC}"
printf "  %-14s %s\n" "Student:"  "$STUDENT_ID"
printf "  %-14s %s\n" "Assignment:" "$ASSIGN_ID"
printf "  %-14s %s (%s)\n" "Grade:" "$GRADE" "$LETTER"
printf "  %-14s %s\n" "Feedback:" "$FEEDBACK"

# Refresh report
"$SCRIPT_DIR/generate_report.sh" "$STUDENT_ID" &
