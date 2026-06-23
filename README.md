# Unix Classroom File Submission Portal

A multi-user Bash shell script system for managing student assignment submissions on a Unix/Linux server.

---

## Project Overview

| Item | Detail |
|------|--------|
| **Project #** | 5 |
| **Difficulty** | Medium |
| **Category** | Learning Management Systems |
| **Skills** | Shell Scripting, Permissions, Date Commands, Automation |
| **Language** | Bash |
| **Lines of Code** | ~700+ |

---

## Architecture

```
submission_portal/
├── bin/
│   ├── lib_validate.sh       # Core validation library (sourced by others)
│   ├── watcher.sh            # Drop-zone watcher daemon
│   ├── submit.sh             # Student submission script
│   ├── grade_submission.sh   # Instructor grading script
│   ├── generate_report.sh    # Per-student & class report generator
│   ├── admin.sh              # Interactive instructor dashboard (TUI)
│   └── setup.sh              # One-time installation script
├── config/
│   ├── portal.conf           # Global settings
│   ├── deadlines.conf        # Assignment deadlines
│   └── students.conf         # Student registry
├── drop_zone/                # Students drop files here (chmod 1777)
│   └── quarantine/           # Invalid files moved here
├── submissions/              # Validated, organised submissions
│   └── S001/A01/             # Per-student, per-assignment
├── graded/
│   ├── gradebook.csv         # Master gradebook (CSV)
│   └── S001/A01/             # Graded files + .grade_*.txt records
├── reports/
│   ├── S001_report.txt       # Human-readable per-student report
│   ├── S001_report.json      # Machine-readable JSON report
│   └── class_summary.txt     # Class-wide summary
└── logs/
    ├── portal.log            # Main event log
    └── processed.log         # Processed-file registry (idempotency)
```

---

## Quick Start

### 1. Install (system-wide, as root)
```bash
sudo bash bin/setup.sh
```

### 2. Install (local demo mode, no root)
```bash
bash bin/setup.sh --local
```

### 3. Configure
```bash
# Edit assignment deadlines
nano config/deadlines.conf

# Edit student registry
nano config/students.conf

# Edit global settings
nano config/portal.conf
```

### 4. Start the Watcher Daemon
```bash
bin/watcher.sh start     # background daemon
bin/watcher.sh status    # check status
bin/watcher.sh stop      # stop daemon
bin/watcher.sh once      # single scan pass (useful for testing)
```

### 5. Student Submits a File
```bash
bin/submit.sh S001 A01 ./my_homework.py
```

The script will:
- Verify the student exists
- Check the deadline (warn if late, ask confirmation)
- Validate file type and size
- Rename to canonical format: `S001_A01_2025-06-10.py`
- Drop into the drop zone for the watcher to pick up

### 6. Grade a Submission
```bash
bin/grade_submission.sh S001 A01 88 "Good use of loops, minor style issues"
```

### 7. Generate Reports
```bash
bin/generate_report.sh S001         # single student
bin/generate_report.sh --all        # all students
bin/generate_report.sh --summary    # class summary only
```

### 8. Open Admin Dashboard
```bash
bin/admin.sh
```

---

## File Naming Convention

```
STUDENTID_ASSIGNMENTID_YYYY-MM-DD.ext

Examples:
  S001_A01_2025-06-10.py
  S042_A03_2025-07-01.c
  S007_A05_2025-07-20.pdf
```

| Part | Pattern | Example |
|------|---------|---------|
| Student ID | `S` + 3 digits | `S001` |
| Assignment ID | `A` + 2 digits | `A01` |
| Date | `YYYY-MM-DD` | `2025-06-10` |
| Extension | alphanumeric | `.py`, `.sh`, `.c` |

---

## Configuration Files

### `config/portal.conf`
```bash
PORTAL_ROOT="/opt/submission_portal"
ALLOWED_EXTENSIONS="py sh c cpp java txt pdf md"
MAX_FILE_SIZE_KB=5120       # 5 MB
WATCH_INTERVAL=5            # seconds between scans
LOG_RETENTION_DAYS=30
ENABLE_EMAIL=0
INSTRUCTOR_EMAIL="instructor@university.edu"
```

### `config/deadlines.conf`
```
# FORMAT: ASSIGNMENT_ID|DEADLINE_DATETIME|ASSIGNMENT_NAME
A01|2025-06-15 23:59:59|Introduction to Shell Scripting
A02|2025-06-22 23:59:59|File Permissions & Ownership
```

### `config/students.conf`
```
# FORMAT: STUDENT_ID|FULL_NAME|EMAIL|UNIX_USER
S001|Alice Johnson|alice@university.edu|alice
S002|Bob Smith|bob@university.edu|bob
```

---

## Validation Pipeline

Every file passing through the drop zone is checked in order:

1. **Filename format** — must match `SXXX_AXX_YYYY-MM-DD.ext`
2. **Extension** — must be in `ALLOWED_EXTENSIONS`
3. **File size** — must be ≤ `MAX_FILE_SIZE_KB`
4. **Student registry** — student ID must exist in `students.conf`
5. **Deadline** — compared against `deadlines.conf` using `date` epoch arithmetic

Outcome:
- `VALID_ONTIME` → moved to `submissions/`, metadata written
- `VALID_LATE`   → moved to `submissions/`, flagged as late
- `INVALID`      → moved to `drop_zone/quarantine/`, logged

---

## Unix Concepts Demonstrated

| Concept | Where Used |
|---------|-----------|
| **Permissions & sticky bit** | `chmod 1777 drop_zone` |
| **File ownership** | Groups: `portal_students`, `portal_instructors` |
| **Date arithmetic** | `date +%s` epoch comparison for deadlines |
| **Process management** | PID file, `kill -0`, background `&` |
| **Regex in Bash** | `[[ "$fname" =~ $pattern ]]` |
| **Here-docs** | Systemd service file, JSON output |
| **File locking** | Processed-log idempotency |
| **`find` / `grep`** | File discovery, metadata search |
| **CSV generation** | Master gradebook |
| **Logging** | Timestamped, colour-coded, file + stdout |
| **Daemon pattern** | `start/stop/status` with PID file |
| **`inotifywait` alternative** | Polling loop (no extra deps needed) |

---

## Extending the Portal

- **Email notifications**: Set `ENABLE_EMAIL=1` and configure `INSTRUCTOR_EMAIL`; add `mail` calls in `lib_validate.sh`
- **`inotifywait`**: Replace the polling loop in `watcher.sh` with `inotifywait -m -e close_write "$DROP_ZONE"` for real-time detection (requires `inotify-tools`)
- **Web front-end**: Parse the JSON reports (`reports/*.json`) in any web framework
- **Plagiarism check**: Add a `check_similarity.sh` step after validation using `diff` or `moss`
- **Rubric grading**: Extend `.grade_*.txt` format with per-criterion scores

---

## License
MIT — free to use in academic and personal projects.
