#!/bin/bash
#
# Bootstrap Phase 9: Postflight Verification
# Final verification, system preferences prompt, and next steps
#

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/error-handling.sh"

# Run comprehensive verification
run_verification() {
    log_step "Running comprehensive verification"

    local checks_passed=0
    local checks_failed=0
    local checks_warned=0

    # Check 1: Shell configuration
    log_info "Checking shell configuration..."
    if [[ -L "$HOME/.zshrc" && -f "$HOME/.zshrc" ]]; then
        log_debug "  ✓ .zshrc symlink is valid"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "  ✗ .zshrc symlink issue"
        checks_failed=$((checks_failed + 1))
    fi

    # Check 2: Git configuration
    log_info "Checking git configuration..."
    if [[ -L "$HOME/.gitconfig" && -f "$HOME/.gitconfig" ]]; then
        if git config --global user.name >/dev/null 2>&1; then
            log_debug "  ✓ Git is properly configured"
            checks_passed=$((checks_passed + 1))
        else
            log_warning "  ⚠ Git config exists but user.name not set"
            checks_warned=$((checks_warned + 1))
        fi
    else
        log_warning "  ✗ .gitconfig symlink issue"
        checks_failed=$((checks_failed + 1))
    fi

    # Check 3: Vim configuration
    log_info "Checking vim configuration..."
    if [[ -L "$HOME/.vimrc" && -f "$HOME/.vimrc" ]] && command -v vim >/dev/null 2>&1; then
        log_debug "  ✓ Vim is configured"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "  ✗ Vim configuration issue"
        checks_failed=$((checks_failed + 1))
    fi

    # Check 4: Homebrew
    log_info "Checking Homebrew..."
    if command -v brew >/dev/null 2>&1; then
        log_debug "  ✓ Homebrew is available"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "  ✗ Homebrew not found"
        checks_failed=$((checks_failed + 1))
    fi

    # Check 5: Key development tools
    log_info "Checking development tools..."
    local dev_tools=("git" "vim" "tmux" "fzf" "rg" "jq")
    local dev_available=0
    for tool in "${dev_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            dev_available=$((dev_available + 1))
        fi
    done

    if [[ $dev_available -eq ${#dev_tools[@]} ]]; then
        log_debug "  ✓ All core development tools available ($dev_available/${#dev_tools[@]})"
        checks_passed=$((checks_passed + 1))
    elif [[ $dev_available -gt 3 ]]; then
        log_warning "  ⚠ Most development tools available ($dev_available/${#dev_tools[@]})"
        checks_warned=$((checks_warned + 1))
    else
        log_warning "  ✗ Many development tools missing ($dev_available/${#dev_tools[@]})"
        checks_failed=$((checks_failed + 1))
    fi

    # Check 6: RCM and symlinks
    log_info "Checking RCM symlinks..."
    if command -v rcup >/dev/null 2>&1; then
        local symlink_count
        symlink_count=$(find "$HOME" -maxdepth 1 -type l -lname "*/dotfiles/*" 2>/dev/null | wc -l | tr -d ' ')
        if [[ $symlink_count -gt 5 ]]; then
            log_debug "  ✓ $symlink_count dotfile symlinks active"
            checks_passed=$((checks_passed + 1))
        else
            log_warning "  ⚠ Only $symlink_count dotfile symlinks found"
            checks_warned=$((checks_warned + 1))
        fi
    else
        log_warning "  ✗ RCM not available"
        checks_failed=$((checks_failed + 1))
    fi

    # Report
    echo
    local total=$((checks_passed + checks_failed + checks_warned))
    log_info "Verification Results: $checks_passed passed, $checks_warned warnings, $checks_failed failed (out of $total)"

    if [[ $checks_failed -eq 0 ]]; then
        log_success "All critical checks passed!"
    else
        log_warning "Some checks failed — review the output above"
    fi
}

# Prompt for system preferences automation
prompt_system_preferences() {
    log_step "System preferences automation"

    local mac_defaults_script="${DOTFILES_ROOT}/scripts/mac-defaults.sh"

    if [[ -f "$mac_defaults_script" ]]; then
        log_info "A system preferences automation script is available."
        log_info "It will configure:"
        log_info "  - Dock auto-hide and settings"
        log_info "  - Finder (show hidden files, extensions, path bar)"
        log_info "  - Keyboard (key repeat rate, Caps Lock to Escape)"
        log_info "  - Trackpad (tap to click, tracking speed)"
        echo

        if confirm "Apply recommended macOS developer settings?"; then
            log_info "Applying system preferences..."
            if bash "$mac_defaults_script"; then
                log_success "System preferences applied"
                log_info "Some changes may require a logout to take effect"
            else
                log_warning "Some preferences may not have applied correctly"
            fi
        else
            log_info "Skipped. You can run it later with:"
            log_info "  bash $mac_defaults_script"
        fi
    else
        log_info "System preferences script not found (optional)"
        log_info "You can configure macOS settings manually in System Preferences"
    fi
}

# Prompt for secrets setup
prompt_secrets_setup() {
    log_step "Secrets and credentials setup"

    local secrets_script="${DOTFILES_ROOT}/scripts/secrets-setup.sh"

    if [[ -f "$secrets_script" ]]; then
        log_info "A secrets setup wizard is available to configure:"
        log_info "  - SSH keys and signing configuration"
        log_info "  - Git credential configuration"
        log_info "  - 1Password CLI integration"
        log_info "  - Shell environment secrets (.zsh_secrets)"
        echo

        if confirm "Run the secrets setup wizard now?"; then
            if bash "$secrets_script"; then
                log_success "Secrets setup completed"
            else
                log_warning "Secrets setup had some issues"
            fi
        else
            log_info "Skipped. You can run it later with:"
            log_info "  bash $secrets_script"
        fi
    else
        log_info "Secrets setup script not found (optional)"
        log_info "Configure secrets manually as needed"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log_step "Cleaning up temporary files"

    # Remove error reports older than 7 days
    local state_dir="$HOME/.cache/dotfiles-bootstrap"
    if [[ -d "$state_dir" ]]; then
        find "$state_dir" -name "error-report-*.log" -mtime +7 -delete 2>/dev/null || true
        log_debug "Cleaned up old error reports"
    fi

    # Clean Homebrew cache
    if command -v brew >/dev/null 2>&1; then
        brew cleanup --prune=1 >/dev/null 2>&1 || true
        log_debug "Cleaned Homebrew cache"
    fi

    log_success "Cleanup completed"
}

# Show next steps
show_next_steps() {
    log_header "Setup Complete — Next Steps"

    echo
    log_info "1. Open a new terminal window or run:"
    log_info "     exec zsh"
    echo
    log_info "2. Verify your environment:"
    log_info "     git --version && node --version && python3 --version"
    echo
    log_info "3. Configure any remaining secrets:"
    log_info "     bash ~/dotfiles/scripts/secrets-setup.sh"
    echo
    log_info "4. (Optional) Apply macOS developer settings:"
    log_info "     bash ~/dotfiles/scripts/mac-defaults.sh"
    echo
    log_info "5. Customize your local overrides:"
    log_info "     Edit files in ~/dotfiles-local/"
    echo
    log_info "6. Read the documentation:"
    log_info "     cat ~/dotfiles/docs/MIGRATION.md"
    echo
    log_success "Your development environment is ready!"
}

# Main execution
main() {
    log_header "Phase 9: Postflight Verification"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run final verification and show next steps"
        return 0
    fi

    run_verification
    cleanup_temp_files
    prompt_system_preferences
    prompt_secrets_setup
    show_next_steps

    log_success "Postflight verification phase completed"
}

main "$@"