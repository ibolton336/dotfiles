#!/bin/bash
#
# Bootstrap System Self-Test
# Validates bootstrap scripts, manifests, and configuration integrity
# Run: bash ~/dotfiles/scripts/test-bootstrap.sh
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

check() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$label"
    else
        fail "$label"
    fi
}

echo
echo "▶ Bootstrap System Self-Test"
echo

# ---- Directory Structure ----
echo "→ Directory Structure"
check "bootstrap/ exists" test -d "$DOTFILES_ROOT/bootstrap"
check "bootstrap/lib/ exists" test -d "$DOTFILES_ROOT/bootstrap/lib"
check "bootstrap/phases/ exists" test -d "$DOTFILES_ROOT/bootstrap/phases"
check "manifests/ exists" test -d "$DOTFILES_ROOT/manifests"
check "manifests/extensions/ exists" test -d "$DOTFILES_ROOT/manifests/extensions"
check "templates/ exists" test -d "$DOTFILES_ROOT/templates"
check "scripts/ exists" test -d "$DOTFILES_ROOT/scripts"
check "docs/ exists" test -d "$DOTFILES_ROOT/docs"
echo

# ---- Script Syntax ----
echo "→ Script Syntax Validation (bash -n)"
for script in \
    "$DOTFILES_ROOT/bootstrap/bootstrap.sh" \
    "$DOTFILES_ROOT/bootstrap/lib/logging.sh" \
    "$DOTFILES_ROOT/bootstrap/lib/error-handling.sh" \
    "$DOTFILES_ROOT/bootstrap/phases/"*.sh \
    "$DOTFILES_ROOT/scripts/"*.sh; do

    if [[ -f "$script" ]]; then
        local_name="${script#$DOTFILES_ROOT/}"
        check "$local_name" bash -n "$script"
    fi
done
echo

# ---- Phase Scripts ----
echo "→ Phase Scripts"
for phase_num in 01 02 03 04 05 06 07 08 09; do
    phase_file="$DOTFILES_ROOT/bootstrap/phases/${phase_num}-"*.sh
    if ls $phase_file >/dev/null 2>&1; then
        phase_name=$(basename $phase_file)
        check "Phase $phase_name exists" test -f $phase_file
        check "Phase $phase_name is executable" test -x $phase_file
    else
        fail "Phase ${phase_num}-*.sh missing"
    fi
done
echo

# ---- Manifest Files ----
echo "→ Manifest Files"
check "brewfile exists" test -f "$DOTFILES_ROOT/manifests/brewfile"
check "npm-global.txt exists" test -f "$DOTFILES_ROOT/manifests/npm-global.txt"
check "versions.txt exists" test -f "$DOTFILES_ROOT/manifests/versions.txt"
check "app-store-apps.txt exists" test -f "$DOTFILES_ROOT/manifests/app-store-apps.txt"
check "vscode.txt exists" test -f "$DOTFILES_ROOT/manifests/extensions/vscode.txt"
check "cursor.txt exists" test -f "$DOTFILES_ROOT/manifests/extensions/cursor.txt"
check "shell-completions.txt exists" test -f "$DOTFILES_ROOT/manifests/shell-completions.txt"

# Validate brewfile has content
if [[ -f "$DOTFILES_ROOT/manifests/brewfile" ]]; then
    brew_lines=$(grep -c "^[a-z]" "$DOTFILES_ROOT/manifests/brewfile" || echo "0")
    if [[ $brew_lines -gt 10 ]]; then
        pass "brewfile has $brew_lines package declarations"
    else
        fail "brewfile seems too small ($brew_lines lines)"
    fi
fi
echo

# ---- Template Files ----
echo "→ Template Files"
check "zshenv.local template" test -f "$DOTFILES_ROOT/templates/.zshenv.local.template"
check "gitconfig.local template" test -f "$DOTFILES_ROOT/templates/gitconfig.local.template"
check "ssh config template" test -f "$DOTFILES_ROOT/templates/.ssh/config.template"
echo

# ---- Documentation ----
echo "→ Documentation"
check "MIGRATION.md" test -f "$DOTFILES_ROOT/docs/MIGRATION.md"
check "TROUBLESHOOTING.md" test -f "$DOTFILES_ROOT/docs/TROUBLESHOOTING.md"
check "ARCHITECTURE.md" test -f "$DOTFILES_ROOT/docs/ARCHITECTURE.md"
check "CUSTOMIZATION.md" test -f "$DOTFILES_ROOT/docs/CUSTOMIZATION.md"
check "SECRETS.md" test -f "$DOTFILES_ROOT/docs/SECRETS.md"
echo

# ---- RCM Configuration ----
echo "→ RCM Configuration"
check "rcrc exists" test -f "$DOTFILES_ROOT/rcrc"

if [[ -f "$DOTFILES_ROOT/rcrc" ]]; then
    for dir in bootstrap manifests docs templates scripts; do
        if grep -q "$dir" "$DOTFILES_ROOT/rcrc"; then
            pass "rcrc excludes $dir"
        else
            fail "rcrc does not exclude $dir"
        fi
    done
fi
echo

# ---- Bootstrap Dry Run ----
echo "→ Bootstrap Dry Run"
if bash "$DOTFILES_ROOT/bootstrap/bootstrap.sh" --dry-run --phase 01-preflight >/dev/null 2>&1; then
    pass "Dry run of phase 01-preflight succeeds"
else
    fail "Dry run of phase 01-preflight failed"
fi

if bash "$DOTFILES_ROOT/bootstrap/bootstrap.sh" --help >/dev/null 2>&1; then
    pass "Help flag works"
else
    fail "Help flag failed"
fi

if bash "$DOTFILES_ROOT/bootstrap/bootstrap.sh" --list-phases >/dev/null 2>&1; then
    pass "List phases flag works"
else
    fail "List phases flag failed"
fi
echo

# ---- Idempotency Check ----
echo "→ Idempotency Check (sourcing libraries twice)"
if bash -c 'source "'$DOTFILES_ROOT'/bootstrap/lib/logging.sh" && source "'$DOTFILES_ROOT'/bootstrap/lib/logging.sh" && log_info "test"' >/dev/null 2>&1; then
    pass "logging.sh safe to source twice"
else
    fail "logging.sh fails when sourced twice"
fi

if bash -c 'source "'$DOTFILES_ROOT'/bootstrap/lib/error-handling.sh" && source "'$DOTFILES_ROOT'/bootstrap/lib/error-handling.sh"' >/dev/null 2>&1; then
    pass "error-handling.sh safe to source twice"
else
    fail "error-handling.sh fails when sourced twice"
fi
echo

# ---- Results ----
TOTAL=$((PASS + FAIL))
echo "▶ Results: $PASS passed, $FAIL failed (out of $TOTAL)"
echo

if [[ $FAIL -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed — review output above"
    exit 1
fi