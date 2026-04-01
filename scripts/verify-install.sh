#!/bin/bash
#
# Installation Verification Script
# Validates that the development environment is properly configured
# Run: bash ~/dotfiles/scripts/verify-install.sh
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$DOTFILES_ROOT/bootstrap/lib/logging.sh" ]]; then
    source "$DOTFILES_ROOT/bootstrap/lib/logging.sh"
else
    log_info() { echo "→ $*"; }
    log_success() { echo "✓ $*"; }
    log_warning() { echo "⚠ $*"; }
    log_error() { echo "✗ $*" >&2; }
    log_header() { echo; echo "▶ $*"; echo; }
    log_step() { echo "→ $*"; }
fi

PASS=0
WARN=0
FAIL=0

check() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        log_success "$label"
        PASS=$((PASS + 1))
    else
        log_error "$label"
        FAIL=$((FAIL + 1))
    fi
}

check_warn() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        log_success "$label"
        PASS=$((PASS + 1))
    else
        log_warning "$label"
        WARN=$((WARN + 1))
    fi
}

# ---- Symlinks ----
log_header "Dotfile Symlinks"

check ".zshrc symlink" test -L "$HOME/.zshrc"
check ".zshenv symlink" test -L "$HOME/.zshenv"
check ".vimrc symlink" test -L "$HOME/.vimrc"
check ".gitconfig symlink" test -L "$HOME/.gitconfig"
check ".aliases symlink" test -L "$HOME/.aliases"
check ".tmux.conf symlink" test -L "$HOME/.tmux.conf"
check_warn ".rcrc symlink" test -f "$HOME/.rcrc"
check_warn ".git_template symlink" test -d "$HOME/.git_template"

# ---- Core Tools ----
log_header "Core Tools"

check "Homebrew" command -v brew
check "Git" command -v git
check "Zsh" command -v zsh
check "Vim" command -v vim
check "tmux" command -v tmux
check "curl" command -v curl
check "jq" command -v jq
check "rcup (RCM)" command -v rcup

# ---- Search and Navigation ----
log_header "Search and Navigation Tools"

check "ripgrep (rg)" command -v rg
check_warn "silver_searcher (ag)" command -v ag
check "fzf" command -v fzf
check_warn "fd" command -v fd
check_warn "tree" command -v tree
check_warn "bat" command -v bat

# ---- Development Runtimes ----
log_header "Development Runtimes"

check_warn "Node.js" command -v node
check_warn "npm" command -v npm
check_warn "Python 3" command -v python3
check_warn "Ruby" command -v ruby
check_warn "Go" command -v go

# ---- Version Managers ----
log_header "Version Managers"

check_warn "asdf" command -v asdf

# ---- Editors and IDEs ----
log_header "Editors and IDEs"

check "Vim" command -v vim
check_warn "VS Code (code)" command -v code
check_warn "Cursor" command -v cursor

# ---- Vim Plugins ----
log_header "Vim Configuration"

check "vim-plug installed" test -f "$HOME/.vim/autoload/plug.vim"
check_warn "Vim plugins directory" test -d "$HOME/.vim/plugged"
check "vimrc.bundles" test -f "$HOME/.vimrc.bundles"

# ---- Shell Configuration ----
log_header "Shell Configuration"

check "Zsh configs directory" test -d "$HOME/.zsh/configs"
check "Zsh functions directory" test -d "$HOME/.zsh/functions"
check_warn "Zsh completion directory" test -d "$HOME/.zsh/completion"
check_warn "fzf integration" test -f "$HOME/.fzf.zsh"

# ---- Git Configuration ----
log_header "Git Configuration"

check "Git user.name set" git config --global user.name
check "Git user.email set" git config --global user.email
check_warn "Git default branch is main" bash -c '[[ "$(git config --global init.defaultBranch)" == "main" ]]'
check_warn "Git template directory" test -d "$HOME/.git_template"

# ---- Security ----
log_header "Security"

check_warn "SSH directory exists" test -d "$HOME/.ssh"
check_warn "SSH key exists" test -f "$HOME/.ssh/id_ed25519"
check_warn "SSH config exists" test -f "$HOME/.ssh/config"
check_warn "1Password CLI" command -v op

# ---- Results ----
log_header "Verification Results"

TOTAL=$((PASS + WARN + FAIL))
log_info "Passed:   $PASS / $TOTAL"

if [[ $WARN -gt 0 ]]; then
    log_info "Warnings: $WARN / $TOTAL"
fi

if [[ $FAIL -gt 0 ]]; then
    log_info "Failed:   $FAIL / $TOTAL"
fi

echo
if [[ $FAIL -eq 0 ]]; then
    log_success "Environment verification passed!"
    exit 0
else
    log_error "Some checks failed — review the output above"
    exit 1
fi