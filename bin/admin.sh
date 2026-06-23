#!/usr/bin/env bash
# ============================================================
#  admin.sh — Instructor Admin Dashboard (Terminal UI)
#  Unix Classroom File Submission Portal
# ============================================================
#  Usage: bash bin/admin.sh
# ============================================================

# NO set -euo pipefail — handle errors manually so menu never crashes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTAL_ROOT="$(dirname "$SCRIPT_DIR")"

# Set ALL paths from PORTAL_ROOT FIRST
CONFIG="$PORTAL_ROOT/config"
LOGS="$PORTAL_ROOT/logs"
DROP_ZONE="$PORTAL_ROOT/drop_zone"
SUBMISSIONS="$PORTAL_ROOT/submissions"
GRADED="$PORTAL_ROOT/graded"
REPORTS="$PORTAL_ROOT/reports"

# Load extra settings, then re-assert paths so portal.conf can't overwrite them
if [[ -f "$PORTAL_ROOT/config/portal.conf" ]]; then
    source "$PORTAL_ROOT/config/portal.conf" 2>/dev/null || true
fi
CONFIG="$PORTAL_ROOT/config"
LOGS="$PORTAL_ROOT/logs"
DROP_ZONE="$PORTAL_ROOT/drop_zone"
SUBMISSIONS="$PORTAL_ROOT/submissions"
GRADED="$PORTAL_ROOT/graded"
REPORTS="$PORTAL_ROOT/reports"

export CONFIG LOGS DROP_ZONE SUBMISSIONS GRADED REPORTS

source "$SCRIPT_DIR/lib_validate.sh"

# Ensure dirs exist
mkdir -p "$LOGS" "$DROP_ZONE" "$SUBMISSIONS" "$GRADED" "$REPORTS"

# ── UI helpers ────────────────────────────────────────────────
clear_screen() { printf '\033[2J\033[H'; }

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════════════════════════════╗"
    echo "  ║       Unix Classroom File Submission Portal  — Admin         ║"
    echo "  ╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}  $(date '+%A, %d %B %Y  %H:%M:%S')\n"
}

show_stats() {
    local total_subs pending graded late
    total_subs=$(find "$SUBMISSIONS" -type f ! -name '.*' 2>/dev/null | wc -l)
    pending=$(find    "$DROP_ZONE"   -maxdepth 1 -type f  2>/dev/null | wc -l)
    graded=$(find     "$GRADED"      -name ".grade_*.txt" 2>/dev/null | wc -l)
    late=$(grep -rl   '^is_late=1'   "$SUBMISSIONS"       2>/dev/null | wc -l || echo 0)

    echo -e "  ${BOLD}── Quick Stats ─────────────────────────────────────────────────${NC}"
    printf "  %-28s ${GREEN}%s${NC}\n"  "Total submissions:"    "$total_subs"
    printf "  %-28s ${YELLOW}%s${NC}\n" "Pending in drop zone:" "$pending"
    printf "  %-28s ${CYAN}%s${NC}\n"   "Graded:"               "$graded"
    printf "  %-28s ${RED}%s${NC}\n"    "Late submissions:"     "$late"
    echo ""
}

show_menu() {
    echo -e "  ${BOLD}── Submissions & Reports ───────────────────────────────────────${NC}"
    echo "   [1] View submission status (all students)"
    echo "   [2] Grade a submission"
    echo "   [3] Generate student report"
    echo "   [4] Generate ALL reports"
    echo "   [5] View gradebook"
    echo "   [6] View portal log (last 20 lines)"
    echo "   [7] List quarantined files"
    echo "   [8] Process drop zone now"
    echo "   [9] View upcoming deadlines"
    echo ""
    echo -e "  ${BOLD}── Assignment Management ───────────────────────────────────────${NC}"
    echo "   [a] Add a new assignment"
    echo "   [r] Remove an assignment"
    echo "   [d] Change an assignment deadline"
    echo "   [l] List all assignments"
    echo ""
    echo -e "  ${BOLD}── Student Management ──────────────────────────────────────────${NC}"
    echo "   [s] Add a new student"
    echo "   [x] Remove a student"
    echo "   [v] View all students (with IDs)"
    echo ""
    echo "   [q] Quit"
    echo ""
}

view_all_students() {
    echo -e "\n  ${BOLD}── Student Submission Overview ─────────────────────────────────${NC}"
    printf "  %-8s %-22s %-6s %-6s %-6s\n" "ID" "Name" "Subs" "Graded" "Late"
    echo "  ────────────────────────────────────────────────────────"
    while IFS='|' read -r sid sname _rest; do
        [[ "$sid" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${sid// }" ]] && continue
        sid="${sid// /}"
        local nsubs ngraded nlate
        nsubs=$(find   "$SUBMISSIONS/$sid" -type f ! -name '.*' 2>/dev/null | wc -l)
        ngraded=$(find "$GRADED/$sid"      -name ".grade_*.txt" 2>/dev/null | wc -l)
        nlate=$(grep -rl '^is_late=1'      "$SUBMISSIONS/$sid"  2>/dev/null | wc -l || echo 0)
        printf "  %-8s %-22s %-6s %-6s %-6s\n" \
            "$sid" "${sname:0:22}" "$nsubs" "$ngraded" "$nlate"
    done < "$CONFIG/students.conf"
    echo ""
}

grade_prompt() {
    echo -e "\n  ${BOLD}── Grade a Submission ──────────────────────────────────────────${NC}"
    read -rp "  Student ID  (e.g. S001): " gsid
    read -rp "  Assignment  (e.g. A01):  " gaid
    read -rp "  Grade (0-100 / EXEMPT / MISSING): " ggrade
    read -rp "  Feedback: " gfeedback
    echo ""
    bash "$SCRIPT_DIR/grade_submission.sh" "$gsid" "$gaid" "$ggrade" "$gfeedback" || \
        echo -e "${RED}Grading failed — check student ID and assignment ID${NC}"
}

view_gradebook() {
    local gb="$GRADED/gradebook.csv"
    echo -e "\n  ${BOLD}── Gradebook (last 15 entries) ─────────────────────────────────${NC}"
    if [[ -f "$gb" ]]; then
        printf "  %-20s %-8s %-6s %-6s %-6s\n" "Timestamp" "Student" "Assign" "Grade" "Letter"
        echo "  ──────────────────────────────────────────────────────"
        tail -15 "$gb" | while IFS=',' read -r ts sid aid _fn gr lt _rest; do
            printf "  %-20s %-8s %-6s %-6s %-6s\n" \
                "${ts:0:19}" "$sid" "$aid" "$gr" "$lt"
        done
    else
        echo "  No gradebook found yet."
    fi
    echo ""
}

view_deadlines() {
    echo -e "\n  ${BOLD}── Assignment Deadlines ────────────────────────────────────────${NC}"
    local now; now=$(date +%s)
    printf "  %-6s %-38s %-22s %s\n" "ID" "Name" "Deadline" "Status"
    echo "  ──────────────────────────────────────────────────────────────"
    while IFS='|' read -r aid dl aname; do
        [[ "$aid" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${aid// }" ]] && continue
        local dep; dep=$(date -d "$dl" +%s 2>/dev/null || echo 0)
        local status
        if (( dep > now )); then
            local hrs=$(( (dep - now) / 3600 ))
            status="${GREEN}Open (${hrs}h left)${NC}"
        else
            status="${RED}CLOSED${NC}"
        fi
        printf "  %-6s %-38s %-22s " "$aid" "${aname:0:38}" "$dl"
        echo -e "$status"
    done < "$CONFIG/deadlines.conf"
    echo ""
}

# ── next_student_id ───────────────────────────────────────────
# Returns the next available SXXX id (e.g. S009 if S008 is highest)
next_student_id() {
    local last
    last=$(grep -v '^#' "$CONFIG/students.conf" 2>/dev/null \
           | grep -v '^$' \
           | cut -d'|' -f1 \
           | sed 's/[^0-9]//g' \
           | sort -n \
           | tail -1)
    printf "S%03d" $(( 10#${last:-0} + 1 ))
}

# ── next_assignment_id ────────────────────────────────────────
# Returns the next available AXXXX id (e.g. A06 if A05 is highest)
next_assignment_id() {
    local last
    last=$(grep -v '^#' "$CONFIG/deadlines.conf" 2>/dev/null \
           | grep -v '^$' \
           | cut -d'|' -f1 \
           | sed 's/[^0-9]//g' \
           | sort -n \
           | tail -1)
    printf "A%02d" $(( 10#${last:-0} + 1 ))
}

# ── list_assignments ──────────────────────────────────────────
list_assignments() {
    echo -e "\n  ${BOLD}── All Assignments ─────────────────────────────────────────────${NC}"
    local now; now=$(date +%s)
    printf "  %-6s  %-38s  %-22s  %s\n" "ID" "Name" "Deadline" "Status"
    echo "  ────────────────────────────────────────────────────────────────────"
    local count=0
    while IFS='|' read -r aid dl aname; do
        [[ "$aid" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${aid//[[:space:]]/}" ]] && continue
        local dep; dep=$(date -d "$dl" +%s 2>/dev/null || echo 0)
        local status
        if (( dep > now )); then
            local hrs=$(( (dep - now) / 3600 ))
            status="${GREEN}Open (${hrs}h left)${NC}"
        else
            status="${RED}CLOSED${NC}"
        fi
        printf "  %-6s  %-38s  %-22s  " "$aid" "${aname:0:38}" "$dl"
        echo -e "$status"
        (( count++ )) || true
    done < "$CONFIG/deadlines.conf"
    echo ""
    echo -e "  ${CYAN}Total: $count assignment(s)${NC}"
    echo ""
}

# ── add_assignment ────────────────────────────────────────────
add_assignment() {
    echo -e "\n  ${BOLD}── Add New Assignment ──────────────────────────────────────────${NC}"

    local suggested_id; suggested_id=$(next_assignment_id)
    echo -e "  ${CYAN}Suggested next ID: ${BOLD}$suggested_id${NC}"
    echo ""

    read -rp "  Assignment ID (e.g. A06) [Enter for $suggested_id]: " new_aid
    new_aid="${new_aid^^}"
    [[ -z "$new_aid" ]] && new_aid="$suggested_id"

    # Validate format
    if [[ ! "$new_aid" =~ ^A[0-9]{2,}$ ]]; then
        echo -e "  ${RED}Invalid ID format. Must be A followed by digits (e.g. A06).${NC}"
        return 1
    fi

    # Check for duplicates
    if grep -qi "^${new_aid}|" "$CONFIG/deadlines.conf" 2>/dev/null; then
        echo -e "  ${RED}Assignment '$new_aid' already exists.${NC}"
        return 1
    fi

    read -rp "  Assignment name: " new_aname
    if [[ -z "$new_aname" ]]; then
        echo -e "  ${RED}Assignment name cannot be empty.${NC}"
        return 1
    fi

    echo ""
    echo -e "  ${YELLOW}Enter deadline (format: YYYY-MM-DD HH:MM:SS)${NC}"
    read -rp "  Deadline: " new_dl
    if [[ -z "$new_dl" ]]; then
        echo -e "  ${RED}Deadline cannot be empty.${NC}"
        return 1
    fi

    # Validate the date parses correctly
    if ! date -d "$new_dl" +%s &>/dev/null; then
        echo -e "  ${RED}Invalid date format. Use: YYYY-MM-DD HH:MM:SS${NC}"
        return 1
    fi

    echo ""
    echo -e "  ${BOLD}Confirm adding:${NC}"
    echo -e "    ID       : ${CYAN}${new_aid}${NC}"
    echo -e "    Name     : $new_aname"
    echo -e "    Deadline : $new_dl"
    read -rp "  Save? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "  Cancelled."
        return 0
    fi

    echo "${new_aid}|${new_dl}|${new_aname}" >> "$CONFIG/deadlines.conf"
    log_msg OK "Assignment added: $new_aid — $new_aname (deadline: $new_dl)"
    echo -e "\n  ${GREEN}✔ Assignment ${BOLD}${new_aid}${NC}${GREEN} added successfully!${NC}"
    echo -e "  All existing assignments:"
    list_assignments
}

# ── remove_assignment ─────────────────────────────────────────
remove_assignment() {
    echo -e "\n  ${BOLD}── Remove Assignment ───────────────────────────────────────────${NC}"
    list_assignments

    read -rp "  Assignment ID to remove (e.g. A06): " del_aid
    del_aid="${del_aid^^}"

    if [[ -z "$del_aid" ]]; then
        echo "  Cancelled."
        return 0
    fi

    if ! grep -qi "^${del_aid}|" "$CONFIG/deadlines.conf" 2>/dev/null; then
        echo -e "  ${RED}Assignment '$del_aid' not found.${NC}"
        return 1
    fi

    local aname; aname=$(grep -i "^${del_aid}|" "$CONFIG/deadlines.conf" | cut -d'|' -f3 | head -1)
    echo -e "\n  ${YELLOW}⚠  You are about to remove:${NC}"
    echo -e "    ID   : ${CYAN}${del_aid}${NC}"
    echo -e "    Name : $aname"
    echo -e "  ${YELLOW}This does NOT delete existing submissions or grades.${NC}"
    read -rp "  Confirm removal? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "  Cancelled."
        return 0
    fi

    # Remove the matching line (case-insensitive)
    local tmp; tmp=$(mktemp)
    grep -iv "^${del_aid}|" "$CONFIG/deadlines.conf" > "$tmp"
    mv "$tmp" "$CONFIG/deadlines.conf"

    log_msg OK "Assignment removed: $del_aid ($aname)"
    echo -e "\n  ${GREEN}✔ Assignment ${BOLD}${del_aid}${NC}${GREEN} removed.${NC}"
    echo -e "  Remaining assignments:"
    list_assignments
}

# ── change_deadline ───────────────────────────────────────────
change_deadline() {
    echo -e "\n  ${BOLD}── Change Assignment Deadline ──────────────────────────────────${NC}"
    list_assignments

    read -rp "  Assignment ID to update (e.g. A01): " upd_aid
    upd_aid="${upd_aid^^}"

    if [[ -z "$upd_aid" ]]; then
        echo "  Cancelled."
        return 0
    fi

    if ! grep -qi "^${upd_aid}|" "$CONFIG/deadlines.conf" 2>/dev/null; then
        echo -e "  ${RED}Assignment '$upd_aid' not found.${NC}"
        return 1
    fi

    local cur_dl cur_name
    cur_dl=$(grep -i "^${upd_aid}|" "$CONFIG/deadlines.conf" | cut -d'|' -f2 | head -1)
    cur_name=$(grep -i "^${upd_aid}|" "$CONFIG/deadlines.conf" | cut -d'|' -f3 | head -1)

    echo -e "\n  Assignment : ${CYAN}${upd_aid}${NC} — $cur_name"
    echo -e "  Current deadline : ${YELLOW}$cur_dl${NC}"
    echo ""
    read -rp "  New deadline (YYYY-MM-DD HH:MM:SS): " new_dl

    if [[ -z "$new_dl" ]]; then
        echo "  Cancelled."
        return 0
    fi

    if ! date -d "$new_dl" +%s &>/dev/null; then
        echo -e "  ${RED}Invalid date format. Use: YYYY-MM-DD HH:MM:SS${NC}"
        return 1
    fi

    read -rp "  Confirm change from '$cur_dl'  →  '$new_dl'? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "  Cancelled."
        return 0
    fi

    local tmp; tmp=$(mktemp)
    while IFS= read -r raw_line; do
        # Pass through comment lines and blank lines unchanged
        if [[ "$raw_line" =~ ^[[:space:]]*# ]] || [[ -z "${raw_line//[[:space:]]/}" ]]; then
            echo "$raw_line"
            continue
        fi
        local aid dl aname
        IFS='|' read -r aid dl aname <<< "$raw_line"
        if [[ "${aid,,}" == "${upd_aid,,}" ]]; then
            echo "${aid}|${new_dl}|${aname}"
        else
            echo "${aid}|${dl}|${aname}"
        fi
    done < "$CONFIG/deadlines.conf" > "$tmp"
    mv "$tmp" "$CONFIG/deadlines.conf"

    log_msg OK "Deadline updated: $upd_aid — $cur_dl → $new_dl"
    echo -e "\n  ${GREEN}✔ Deadline updated for ${BOLD}${upd_aid}${NC}${GREEN}!${NC}"
    echo -e "  Updated assignments:"
    list_assignments
}

# ── add_student ───────────────────────────────────────────────
add_student() {
    echo -e "\n  ${BOLD}── Add New Student ─────────────────────────────────────────────${NC}"

    local suggested_id; suggested_id=$(next_student_id)
    echo -e "  ${CYAN}Suggested next ID: ${BOLD}$suggested_id${NC}"
    echo ""

    read -rp "  Student ID (e.g. S009) [Enter for $suggested_id]: " new_sid
    new_sid="${new_sid^^}"
    [[ -z "$new_sid" ]] && new_sid="$suggested_id"

    if [[ ! "$new_sid" =~ ^S[0-9]{3,}$ ]]; then
        echo -e "  ${RED}Invalid ID format. Must be S followed by 3+ digits (e.g. S009).${NC}"
        return 1
    fi

    if grep -qi "^${new_sid}|" "$CONFIG/students.conf" 2>/dev/null; then
        echo -e "  ${RED}Student ID '$new_sid' already exists.${NC}"
        return 1
    fi

    read -rp "  Full name: " new_sname
    if [[ -z "$new_sname" ]]; then
        echo -e "  ${RED}Name cannot be empty.${NC}"
        return 1
    fi

    read -rp "  Email: " new_semail
    if [[ -z "$new_semail" ]]; then
        echo -e "  ${RED}Email cannot be empty.${NC}"
        return 1
    fi

    read -rp "  Unix username (optional, press Enter to skip): " new_suser
    [[ -z "$new_suser" ]] && new_suser="${new_sname%% *}"   # default: first name

    echo ""
    echo -e "  ${BOLD}Confirm adding:${NC}"
    echo -e "    ID       : ${CYAN}${new_sid}${NC}"
    echo -e "    Name     : $new_sname"
    echo -e "    Email    : $new_semail"
    echo -e "    Unix user: $new_suser"
    read -rp "  Save? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "  Cancelled."
        return 0
    fi

    echo "${new_sid}|${new_sname}|${new_semail}|${new_suser}" >> "$CONFIG/students.conf"
    log_msg OK "Student added: $new_sid — $new_sname ($new_semail)"
    echo -e "\n  ${GREEN}✔ Student ${BOLD}${new_sid}${NC}${GREEN} added successfully!${NC}"
    echo -e "  All students:"
    view_all_students_detail
}

# ── remove_student ────────────────────────────────────────────
remove_student() {
    echo -e "\n  ${BOLD}── Remove Student ──────────────────────────────────────────────${NC}"
    view_all_students_detail

    read -rp "  Student ID to remove (e.g. S009): " del_sid
    del_sid="${del_sid^^}"

    if [[ -z "$del_sid" ]]; then
        echo "  Cancelled."
        return 0
    fi

    if ! grep -qi "^${del_sid}|" "$CONFIG/students.conf" 2>/dev/null; then
        echo -e "  ${RED}Student '$del_sid' not found.${NC}"
        return 1
    fi

    local sname semail
    sname=$(grep -i "^${del_sid}|" "$CONFIG/students.conf" | cut -d'|' -f2 | head -1)
    semail=$(grep -i "^${del_sid}|" "$CONFIG/students.conf" | cut -d'|' -f3 | head -1)

    echo -e "\n  ${YELLOW}⚠  You are about to remove:${NC}"
    echo -e "    ID    : ${CYAN}${del_sid}${NC}"
    echo -e "    Name  : $sname"
    echo -e "    Email : $semail"
    echo -e "  ${YELLOW}This does NOT delete existing submissions or grades.${NC}"
    read -rp "  Confirm removal? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "  Cancelled."
        return 0
    fi

    local tmp; tmp=$(mktemp)
    grep -iv "^${del_sid}|" "$CONFIG/students.conf" > "$tmp"
    mv "$tmp" "$CONFIG/students.conf"

    log_msg OK "Student removed: $del_sid ($sname)"
    echo -e "\n  ${GREEN}✔ Student ${BOLD}${del_sid}${NC}${GREEN} removed from registry.${NC}"
    echo -e "  Remaining students:"
    view_all_students_detail
}

# ── view_all_students_detail ──────────────────────────────────
# Detailed student listing with IDs, emails, submission counts
view_all_students_detail() {
    echo -e "\n  ${BOLD}── Student Registry ────────────────────────────────────────────${NC}"
    printf "  %-8s  %-22s  %-32s  %-6s  %-6s  %-6s\n" \
        "ID" "Name" "Email" "Subs" "Graded" "Late"
    echo "  ──────────────────────────────────────────────────────────────────────────────"
    local count=0
    while IFS='|' read -r sid sname semail _rest; do
        [[ "$sid" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${sid//[[:space:]]/}" ]] && continue
        local nsubs ngraded nlate
        nsubs=$(find   "$SUBMISSIONS/$sid" -type f ! -name '.*' 2>/dev/null | wc -l)
        ngraded=$(find "$GRADED/$sid"      -name ".grade_*.txt" 2>/dev/null | wc -l)
        nlate=$(grep -rl '^is_late=1'      "$SUBMISSIONS/$sid"  2>/dev/null | wc -l || echo 0)
        printf "  ${CYAN}%-8s${NC}  %-22s  %-32s  %-6s  %-6s  %-6s\n" \
            "$sid" "${sname:0:22}" "${semail:0:32}" "$nsubs" "$ngraded" "$nlate"
        (( count++ )) || true
    done < "$CONFIG/students.conf"
    echo ""
    echo -e "  ${CYAN}Total: $count student(s)${NC}"
    echo ""
}

list_quarantine() {
    echo -e "\n  ${BOLD}── Quarantined Files ───────────────────────────────────────────${NC}"
    local q="$DROP_ZONE/quarantine"
    if [[ -d "$q" ]] && [[ -n "$(ls -A "$q" 2>/dev/null)" ]]; then
        ls -lh "$q/"
    else
        echo "  Quarantine is empty — no rejected files."
    fi
    echo ""
}

# ── Main interactive loop ─────────────────────────────────────
while true; do
    clear_screen
    print_header
    show_stats
    show_menu

    read -rp "  Select option: " choice
    echo ""

    case "$choice" in
        1) view_all_students ;;
        2) grade_prompt ;;
        3)
            read -rp "  Student ID (e.g. S001): " rid
            bash "$SCRIPT_DIR/generate_report.sh" "$rid" || \
                echo -e "${RED}Report failed — check student ID${NC}"
            ;;
        4)
            bash "$SCRIPT_DIR/generate_report.sh" --all || \
                echo -e "${RED}Report generation failed${NC}"
            ;;
        5) view_gradebook ;;
        6)
            echo -e "\n  ${BOLD}── Last 20 log lines ───────────────────────────────────────────${NC}"
            if [[ -f "$LOGS/portal.log" ]]; then
                tail -20 "$LOGS/portal.log"
            else
                echo "  No log file yet."
            fi
            echo ""
            ;;
        7) list_quarantine ;;
        8)
            echo -e "\n  Processing drop zone...\n"
            bash "$SCRIPT_DIR/watcher.sh" once
            ;;
        9) view_deadlines ;;
        # ── Assignment management ──────────────────────────────
        a|A) add_assignment ;;
        r|R) remove_assignment ;;
        d|D) change_deadline ;;
        l|L) list_assignments ;;
        # ── Student management ─────────────────────────────────
        s|S) add_student ;;
        x|X) remove_student ;;
        v|V) view_all_students_detail ;;
        q|Q)
            echo -e "  ${CYAN}Goodbye!${NC}\n"
            exit 0
            ;;
        *)
            echo -e "  ${RED}Invalid option. Choose 1-9, a/r/d/l, s/x/v, or q.${NC}"
            ;;
    esac

    read -rp "  Press Enter to continue..." _dummy
done
