#!/usr/bin/env bash
# ============================================================
#  submit.sh — Student Submission Script
#  Unix Classroom File Submission Portal
# ============================================================
#  Usage: bash bin/submit.sh <STUDENT_ID> <ASSIGN_ID> <FILE>
#  Example: bash bin/submit.sh S001 A01 /home/umer/hw.cpp
# ============================================================

# NOTE: No set -euo pipefail here — we handle errors manually
# so late submissions and warnings don't kill the script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTAL_ROOT="$(dirname "$SCRIPT_DIR")"

# Always set paths from PORTAL_ROOT — never from portal.conf
CONFIG="$PORTAL_ROOT/config"
LOGS="$PORTAL_ROOT/logs"
DROP_ZONE="$PORTAL_ROOT/drop_zone"

# Load extra settings (extensions, file size) from portal.conf
# but immediately re-set the paths it may have overwritten
if [[ -f "$PORTAL_ROOT/config/portal.conf" ]]; then
    source "$PORTAL_ROOT/config/portal.conf" 2>/dev/null || true
fi
CONFIG="$PORTAL_ROOT/config"
LOGS="$PORTAL_ROOT/logs"
DROP_ZONE="$PORTAL_ROOT/drop_zone"

export CONFIG LOGS DROP_ZONE
source "$SCRIPT_DIR/lib_validate.sh"

# ── Make sure required dirs exist ─────────────────────────────
mkdir -p "$LOGS" "$DROP_ZONE"

# ── Banner ────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "  ┌──────────────────────────────────────────┐"
echo "  │  Unix Classroom Submission Portal  v1.0  │"
echo "  └──────────────────────────────────────────┘"
echo -e "${NC}"

# ── Check arguments ───────────────────────────────────────────
if [[ $# -lt 3 ]]; then
    echo -e "${RED}Usage: bash bin/submit.sh <STUDENT_ID> <ASSIGN_ID> <FILE_PATH>${NC}"
    echo    "  Example: bash bin/submit.sh S001 A01 /home/umer/hw.cpp"
    exit 1
fi

INPUT_SID="${1^^}"
INPUT_AID="${2^^}"
SOURCE_FILE="$3"

# ── Check source file exists ──────────────────────────────────
if [[ ! -f "$SOURCE_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} File not found: $SOURCE_FILE"
    exit 1
fi

# ── Validate student ──────────────────────────────────────────
if ! validate_student "$INPUT_SID"; then
    echo -e "${RED}[ERROR]${NC} Student '$INPUT_SID' not found in registry."
    echo    "  Check config/students.conf and make sure the ID is correct."
    exit 1
fi
echo -e "  ${GREEN}✔${NC} Student verified: ${BOLD}${V_STUDENT_NAME}${NC} ($INPUT_SID)"

# ── Validate extension ────────────────────────────────────────
EXT="${SOURCE_FILE##*.}"
if ! validate_extension "$EXT"; then
    echo -e "${RED}[ERROR]${NC} File extension '.$EXT' is not allowed."
    exit 1
fi

# ── Validate file size ────────────────────────────────────────
if ! validate_filesize "$SOURCE_FILE"; then
    echo -e "${RED}[ERROR]${NC} File is too large."
    exit 1
fi

# ── Build canonical filename ──────────────────────────────────
DATE_STR=$(date '+%Y-%m-%d')
CANONICAL="${INPUT_SID}_${INPUT_AID}_${DATE_STR}.${EXT,,}"

# ── Check deadline ────────────────────────────────────────────
# Capture return code safely without set -e killing the script
set +e
check_deadline "$INPUT_AID"
DL_STATUS=$?
set -e

case $DL_STATUS in
    0)
        echo -e "  ${GREEN}✔${NC} Deadline OK — ${BOLD}${V_ASSIGN_NAME:-$INPUT_AID}${NC}"
        echo -e "     Deadline: ${V_DEADLINE_STR:-N/A}"
        ;;
    1)
        echo -e "  ${YELLOW}⚠  LATE SUBMISSION${NC} — ${V_MINUTES_LATE:-?} minutes past deadline"
        echo -e "     Deadline was : ${V_DEADLINE_STR:-N/A}"
        echo -e "     Submission will be marked LATE."
        echo ""
        read -rp "  Continue with late submission? [y/N] " confirm
        if [[ "${confirm,,}" != "y" ]]; then
            echo "  Submission cancelled."
            exit 0
        fi
        ;;
    2)
        echo -e "  ${YELLOW}⚠  Assignment '$INPUT_AID' not found in deadlines.conf${NC}"
        read -rp "  Submit anyway? [y/N] " confirm
        if [[ "${confirm,,}" != "y" ]]; then
            echo "  Submission cancelled."
            exit 0
        fi
        ;;
esac

# ── Copy to drop zone ─────────────────────────────────────────
DEST="$DROP_ZONE/$CANONICAL"

if [[ -f "$DEST" ]]; then
    echo -e "  ${YELLOW}[WARN]${NC} A file with this name already exists in drop zone — overwriting"
fi

cp "$SOURCE_FILE" "$DEST"
chmod 664 "$DEST"

# ── Success message ───────────────────────────────────────────
echo ""
echo -e "  ${GREEN}${BOLD}✔ File submitted successfully!${NC}"
printf "  %-20s %s\n" "Original file:"  "$(basename "$SOURCE_FILE")"
printf "  %-20s %s\n" "Submitted as:"   "$CANONICAL"
printf "  %-20s %s\n" "Submitted at:"   "$(date '+%Y-%m-%d %H:%M:%S')"
printf "  %-20s %s\n" "Assignment:"     "${V_ASSIGN_NAME:-$INPUT_AID}"
echo ""
echo -e "  ${CYAN}Your original file is safe — this was a copy.${NC}"
echo -e "  ${CYAN}Now run the watcher to process it:${NC}"
echo -e "  ${BOLD}  bash bin/watcher.sh once${NC}"
echo ""
