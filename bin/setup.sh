#!/usr/bin/env bash
# ============================================================
#  setup.sh — One-Time Installation & Setup Script
#  Unix Classroom File Submission Portal
# ============================================================
#  Run once as root to install the portal system-wide.
#
#  Usage (as root):
#    sudo ./setup.sh
#
#  Or for local/demo mode (no root):
#    ./setup.sh --local
# ============================================================

set -euo pipefail

INSTALL_DIR="/opt/submission_portal"
SERVICE_FILE="/etc/systemd/system/submission-portal.service"
LOCAL_MODE=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

[[ "${1:-}" == "--local" ]] && {
    LOCAL_MODE=1
    INSTALL_DIR="$(pwd)"
    echo -e "${YELLOW}Running in LOCAL (demo) mode — no root required${NC}"
}

echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║   Unix Classroom File Submission Portal           ║"
echo "  ║   Setup & Installation                            ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Root check ────────────────────────────────────────────────
if [[ $LOCAL_MODE -eq 0 ]] && [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run as root or use --local for demo mode${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTAL_ROOT="$(dirname "$SCRIPT_DIR")"

# ── Create directory structure ────────────────────────────────
echo -e "\n${BOLD}[1/5] Creating directory structure...${NC}"
DIRS=("$INSTALL_DIR/bin" "$INSTALL_DIR/config"
      "$INSTALL_DIR/drop_zone" "$INSTALL_DIR/drop_zone/quarantine"
      "$INSTALL_DIR/submissions" "$INSTALL_DIR/graded"
      "$INSTALL_DIR/reports" "$INSTALL_DIR/logs")
for d in "${DIRS[@]}"; do
    mkdir -p "$d"
    echo "    Created: $d"
done

# ── Copy files ────────────────────────────────────────────────
echo -e "\n${BOLD}[2/5] Copying scripts and config...${NC}"
cp "$PORTAL_ROOT/bin/"*.sh "$INSTALL_DIR/bin/"
cp "$PORTAL_ROOT/config/"*.conf "$INSTALL_DIR/config/"
chmod +x "$INSTALL_DIR/bin/"*.sh
echo "    Scripts installed to $INSTALL_DIR/bin/"

# ── Update portal.conf with real install path ─────────────────
sed -i "s|PORTAL_ROOT=.*|PORTAL_ROOT=\"$INSTALL_DIR\"|" \
    "$INSTALL_DIR/config/portal.conf" 2>/dev/null || true

# ── Set permissions ───────────────────────────────────────────
echo -e "\n${BOLD}[3/5] Setting permissions...${NC}"
chmod 1777 "$INSTALL_DIR/drop_zone"          # world-writable + sticky bit
chmod 750  "$INSTALL_DIR/bin/"*.sh
chmod 755  "$INSTALL_DIR/submissions"
chmod 750  "$INSTALL_DIR/graded"
chmod 755  "$INSTALL_DIR/reports"
chmod 750  "$INSTALL_DIR/logs"

if [[ $LOCAL_MODE -eq 0 ]]; then
    # Create a portal group
    groupadd -f portal_students 2>/dev/null || true
    groupadd -f portal_instructors 2>/dev/null || true
    chown -R root:portal_instructors "$INSTALL_DIR"
    chown root:portal_students "$INSTALL_DIR/drop_zone"
    echo "    Groups: portal_students, portal_instructors created"
fi
echo "    Permissions set"

# ── Install systemd service (root only) ───────────────────────
if [[ $LOCAL_MODE -eq 0 ]] && command -v systemctl &>/dev/null; then
    echo -e "\n${BOLD}[4/5] Installing systemd service...${NC}"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Unix Classroom File Submission Portal Watcher
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/bin/watcher.sh start
ExecStop=$INSTALL_DIR/bin/watcher.sh stop
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable submission-portal
    echo "    Service installed: submission-portal"
    echo "    Start with: sudo systemctl start submission-portal"
else
    echo -e "\n${BOLD}[4/5] Skipping systemd (local mode)...${NC}"
    echo "    Start watcher with: $INSTALL_DIR/bin/watcher.sh start"
fi

# ── Create convenience symlinks ───────────────────────────────
echo -e "\n${BOLD}[5/5] Creating symlinks...${NC}"
if [[ $LOCAL_MODE -eq 0 ]]; then
    ln -sf "$INSTALL_DIR/bin/submit.sh"   /usr/local/bin/portal-submit
    ln -sf "$INSTALL_DIR/bin/watcher.sh"  /usr/local/bin/portal-watch
    ln -sf "$INSTALL_DIR/bin/grade_submission.sh" /usr/local/bin/portal-grade
    ln -sf "$INSTALL_DIR/bin/generate_report.sh"  /usr/local/bin/portal-report
    echo "    portal-submit, portal-watch, portal-grade, portal-report → /usr/local/bin/"
else
    echo "    (Skipped — local mode)"
fi

# ── Done ──────────────────────────────────────────────────────
echo -e "\n${GREEN}${BOLD}✔ Installation complete!${NC}\n"
echo "  Portal root   : $INSTALL_DIR"
echo "  Drop zone     : $INSTALL_DIR/drop_zone"
echo "  Submissions   : $INSTALL_DIR/submissions"
echo "  Graded        : $INSTALL_DIR/graded"
echo "  Reports       : $INSTALL_DIR/reports"
echo ""
echo -e "${BOLD}Quick start:${NC}"
echo "  1. Edit deadlines : $INSTALL_DIR/config/deadlines.conf"
echo "  2. Edit students  : $INSTALL_DIR/config/students.conf"
echo "  3. Start watcher  : $INSTALL_DIR/bin/watcher.sh start"
echo "  4. Students submit: $INSTALL_DIR/bin/submit.sh S001 A01 file.py"
echo "  5. Grade file     : $INSTALL_DIR/bin/grade_submission.sh S001 A01 85 \"Well done!\""
echo "  6. View reports   : $INSTALL_DIR/reports/"
echo ""
