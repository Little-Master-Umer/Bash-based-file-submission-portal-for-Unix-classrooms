#!/usr/bin/env bash
# ============================================================
#  generate_report.sh — Per-Student Submission Report
#  Unix Classroom File Submission Portal
# ============================================================
#  Generates a human-readable + machine-readable report for
#  one or all students.
#
#  Usage:
#    ./generate_report.sh [STUDENT_ID | --all]
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTAL_ROOT="$(dirname "$SCRIPT_DIR")"


# Always resolve paths from actual script location
SUBMISSIONS="$PORTAL_ROOT/submissions"
GRADED="$PORTAL_ROOT/graded"
REPORTS="$PORTAL_ROOT/reports"
LOGS="$PORTAL_ROOT/logs"
CONFIG="$PORTAL_ROOT/config"

# Load extra settings but re-assert paths after
if [[ -f "$PORTAL_ROOT/config/portal.conf" ]]; then
    source "$PORTAL_ROOT/config/portal.conf" 2>/dev/null || true
fi
SUBMISSIONS="$PORTAL_ROOT/submissions"
GRADED="$PORTAL_ROOT/graded"
REPORTS="$PORTAL_ROOT/reports"
LOGS="$PORTAL_ROOT/logs"
CONFIG="$PORTAL_ROOT/config"
export CONFIG LOGS SUBMISSIONS GRADED REPORTS

source "$SCRIPT_DIR/lib_validate.sh"

DEADLINES_FILE="$CONFIG/deadlines.conf"
STUDENTS_FILE="$CONFIG/students.conf"

# ── Load all assignment IDs from deadlines config ────────────
get_all_assignments() {
    grep -v '^#' "$DEADLINES_FILE" 2>/dev/null | grep -v '^$' | cut -d'|' -f1
}

# ── Get assignment name by ID ────────────────────────────────
get_assign_name() {
    local aid="$1"
    grep -i "^${aid}|" "$DEADLINES_FILE" 2>/dev/null | cut -d'|' -f3 | head -1
}

# ── Get deadline string by ID ─────────────────────────────────
get_deadline() {
    local aid="$1"
    grep -i "^${aid}|" "$DEADLINES_FILE" 2>/dev/null | cut -d'|' -f2 | head -1
}

# ── Generate report for a single student ─────────────────────
generate_student_report() {
    local sid="${1^^}"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local report_file="$REPORTS/${sid}_report.txt"
    local json_file="$REPORTS/${sid}_report.json"

    # Lookup student name
    local sname semail
    sname=$(grep -i "^${sid}|" "$STUDENTS_FILE" 2>/dev/null | cut -d'|' -f2 || echo "Unknown")
    semail=$(grep -i "^${sid}|" "$STUDENTS_FILE" 2>/dev/null | cut -d'|' -f3 || echo "Unknown")

    # Collect stats
    local total_assignments on_time_count late_count missing_count total_grade grade_count
    total_assignments=$(get_all_assignments | wc -l | tr -d ' ')
    on_time_count=0; late_count=0; missing_count=0; total_grade=0; grade_count=0

    local assignment_rows=""
    local json_assignments="["

    while IFS= read -r aid; do
        local aname; aname=$(get_assign_name "$aid")
        local deadline; deadline=$(get_deadline "$aid")
        local sub_dir="$SUBMISSIONS/$sid/$aid"
        local grade_file; grade_file=$(find "$GRADED/$sid/$aid/" -name ".grade_${aid}.txt" 2>/dev/null | head -1 || true)

        local sub_status="MISSING"
        local sub_time="—"
        local is_late_flag="—"
        local grade_val="—"
        local letter="—"
        local feedback="—"
        local file_name="—"

        # Check submission
        if [[ -d "$sub_dir" ]]; then
            local meta_file; meta_file=$(find "$sub_dir" -name ".meta_*.txt" 2>/dev/null | head -1 || true)
            if [[ -n "$meta_file" ]]; then
                sub_time=$(grep '^submitted=' "$meta_file" | cut -d= -f2)
                is_late_flag=$(grep '^is_late=' "$meta_file" | cut -d= -f2)
                file_name=$(grep '^filename=' "$meta_file" | cut -d= -f2)
                sub_status=$( [[ "$is_late_flag" == "1" ]] && echo "LATE" || echo "ON-TIME" )
                if [[ "$is_late_flag" == "1" ]]; then
                    (( late_count++ )) || true
                else
                    (( on_time_count++ )) || true
                fi
            fi
        else
            (( missing_count++ )) || true || true
        fi

        # Check grade
        if [[ -n "$grade_file" ]]; then
            grade_val=$(grep '^grade\s*=' "$grade_file" | cut -d= -f2 | tr -d ' ')
            letter=$(grep '^letter_grade\s*=' "$grade_file" | cut -d= -f2 | tr -d ' ')
            feedback=$(grep '^feedback\s*=' "$grade_file" | cut -d= -f2 | sed 's/^ *//')
            if [[ "$grade_val" =~ ^[0-9]+$ ]]; then
                total_grade=$(( total_grade + grade_val )) || true
                (( grade_count++ )) || true || true
            fi
        fi

        # Table row
        assignment_rows+=$(printf "  %-6s  %-38s  %-10s  %-8s  %-6s  %-6s\n" \
            "$aid" "${aname:0:38}" "$sub_status" \
            "${sub_time:0:10}" "$grade_val" "$letter")
        assignment_rows+=$'\n'

        # JSON entry
        json_assignments+="{\"id\":\"$aid\",\"name\":\"$aname\",\"status\":\"$sub_status\","
        json_assignments+="\"submitted_at\":\"$sub_time\",\"grade\":\"$grade_val\","
        json_assignments+="\"letter\":\"$letter\",\"feedback\":\"$feedback\","
        json_assignments+="\"deadline\":\"$deadline\"},"

    done < <(get_all_assignments)

    json_assignments="${json_assignments%,}]"

    # Average grade
    local avg_grade="N/A"
    (( grade_count > 0 )) && avg_grade=$(( total_grade / grade_count ))

    # ── Write text report ─────────────────────────────────────
    {
        echo "╔══════════════════════════════════════════════════════════════════════╗"
        echo "║          UNIX CLASSROOM FILE SUBMISSION PORTAL                      ║"
        echo "║                 STUDENT SUBMISSION REPORT                           ║"
        echo "╚══════════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "  Generated : $ts"
        echo "  Student   : $sname  ($sid)"
        echo "  Email     : $semail"
        echo ""
        echo "  ── Summary ──────────────────────────────────────────────────────────"
        printf "  %-22s %s\n" "Total Assignments:"  "$total_assignments"
        printf "  %-22s %s\n" "Submitted On-Time:"  "$on_time_count"
        printf "  %-22s %s\n" "Submitted Late:"     "$late_count"
        printf "  %-22s %s\n" "Missing:"            "$missing_count"
        printf "  %-22s %s\n" "Graded:"             "$grade_count"
        printf "  %-22s %s\n" "Average Grade:"      "$avg_grade"
        echo ""
        echo "  ── Assignments ──────────────────────────────────────────────────────"
        printf "  %-6s  %-38s  %-10s  %-8s  %-6s  %-6s\n" \
            "ID" "Name" "Status" "Date" "Grade" "Letter"
        echo "  ──────────────────────────────────────────────────────────────────────"
        echo "$assignment_rows"
        echo "════════════════════════════════════════════════════════════════════════"
    } > "$report_file"

    # ── Write JSON report ────────────────────────────────────
    cat > "$json_file" <<JSON
{
  "generated_at": "$ts",
  "student": {
    "id": "$sid",
    "name": "$sname",
    "email": "$semail"
  },
  "summary": {
    "total_assignments": $total_assignments,
    "on_time": $on_time_count,
    "late": $late_count,
    "missing": $missing_count,
    "graded": $grade_count,
    "average_grade": "$avg_grade"
  },
  "assignments": $json_assignments
}
JSON

    log_msg OK "Report generated → $report_file"
    echo -e "${GREEN}Report:${NC} $report_file"
    echo -e "${GREEN}JSON:${NC}   $json_file"
}

# ── Generate for all students ────────────────────────────────
generate_all_reports() {
    log_msg INFO "Generating reports for all students..."
    while IFS='|' read -r sid _rest; do
        [[ "$sid" =~ ^#  ]] && continue
        [[ -z "$sid" ]] && continue
        generate_student_report "$sid"
    done < "$STUDENTS_FILE"
    log_msg OK "All reports generated in $REPORTS/"
}

# ── Generate class summary report ────────────────────────────
generate_class_summary() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local summary_file="$REPORTS/class_summary.txt"
    {
        echo "╔══════════════════════════════════════════════════════════════════════╗"
        echo "║          UNIX CLASSROOM FILE SUBMISSION PORTAL                      ║"
        echo "║                   CLASS SUMMARY REPORT                              ║"
        echo "╚══════════════════════════════════════════════════════════════════════╝"
        echo "  Generated : $ts"
        echo ""

        local total_subs on_time late missing
        total_subs=$(find "$SUBMISSIONS" -type f ! -name '.*' 2>/dev/null | wc -l)
        late=$(grep -r '^is_late=1' "$SUBMISSIONS" 2>/dev/null | wc -l)
        on_time=$(( total_subs - late ))
        missing=0

        printf "  %-25s %s\n" "Total Submissions:"  "$total_subs"
        printf "  %-25s %s\n" "On-Time:"            "$on_time"
        printf "  %-25s %s\n" "Late:"               "$late"
        echo ""

        echo "  ── Gradebook Summary ────────────────────────────────────────────────"
        if [[ -f "$GRADED/gradebook.csv" ]]; then
            echo "  $(wc -l < "$GRADED/gradebook.csv") entries in gradebook"
            echo ""
            echo "  Top 5 Recent Grades:"
            tail -5 "$GRADED/gradebook.csv" | while IFS=',' read -r ts sid aid fn gr lt _rest; do
                printf "    %-6s  %-6s  %s\n" "$sid" "$aid" "$gr"
            done
        else
            echo "  No grades recorded yet."
        fi
        echo ""
        echo "════════════════════════════════════════════════════════════════════════"
    } > "$summary_file"
    echo -e "${GREEN}Class summary:${NC} $summary_file"
}

# ── Entry point ───────────────────────────────────────────────
mkdir -p "$REPORTS"
case "${1:---all}" in
    --all)    generate_all_reports; generate_class_summary ;;
    --summary) generate_class_summary ;;
    *)        generate_student_report "$1" ;;
esac
