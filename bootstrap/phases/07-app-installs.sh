#!/bin/bash
#
# Bootstrap Phase 7: Application Installs
# Installs IDE extensions, shell completions, and App Store apps
#

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/error-handling.sh"

# Configuration
readonly VSCODE_EXT_FILE="${DOTFILES_ROOT}/manifests/extensions/vscode.txt"
readonly CURSOR_EXT_FILE="${DOTFILES_ROOT}/manifests/extensions/cursor.txt"
readonly APP_STORE_FILE="${DOTFILES_ROOT}/manifests/app-store-apps.txt"

# Install VS Code extensions
install_vscode_extensions() {
    log_step "Installing VS Code extensions"

    if ! command -v code >/dev/null 2>&1; then
        log_warning "VS Code CLI (code) not found in PATH"
        log_info "Install VS Code first, or add 'code' to PATH via:"
        log_info "  VS Code > Command Palette > 'Shell Command: Install code command in PATH'"
        return 0
    fi

    if [[ ! -f "$VSCODE_EXT_FILE" ]]; then
        log_warning "VS Code extensions manifest not found: $VSCODE_EXT_FILE"
        return 0
    fi

    local installed=0 failed=0 skipped=0

    # Get already-installed extensions
    local existing_extensions
    existing_extensions=$(code --list-extensions 2>/dev/null || echo "")

    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue

        local ext_id
        ext_id=$(echo "$line" | awk '{print $1}')
        [[ -z "$ext_id" ]] && continue

        if echo "$existing_extensions" | grep -qi "^${ext_id}$"; then
            skipped=$((skipped + 1))
            continue
        fi

        log_info "Installing VS Code extension: $ext_id"
        if code --install-extension "$ext_id" --force >/dev/null 2>&1; then
            installed=$((installed + 1))
        else
            log_debug "Failed to install: $ext_id"
            failed=$((failed + 1))
        fi
    done < "$VSCODE_EXT_FILE"

    log_info "VS Code extensions: $installed installed, $skipped already present, $failed failed"
    log_success "VS Code extension installation completed"
}

# Install Cursor IDE extensions
install_cursor_extensions() {
    log_step "Installing Cursor IDE extensions"

    if ! command -v cursor >/dev/null 2>&1; then
        log_warning "Cursor CLI not found in PATH"
        log_info "Cursor extensions can be installed manually after Cursor is set up"
        return 0
    fi

    if [[ ! -f "$CURSOR_EXT_FILE" ]]; then
        log_warning "Cursor extensions manifest not found: $CURSOR_EXT_FILE"
        return 0
    fi

    local installed=0 failed=0 skipped=0

    local existing_extensions
    existing_extensions=$(cursor --list-extensions 2>/dev/null || echo "")

    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue

        local ext_id
        ext_id=$(echo "$line" | awk '{print $1}')
        [[ -z "$ext_id" ]] && continue

        if echo "$existing_extensions" | grep -qi "^${ext_id}$"; then
            skipped=$((skipped + 1))
            continue
        fi

        log_info "Installing Cursor extension: $ext_id"
        if cursor --install-extension "$ext_id" --force >/dev/null 2>&1; then
            installed=$((installed + 1))
        else
            log_debug "Failed to install: $ext_id"
            failed=$((failed + 1))
        fi
    done < "$CURSOR_EXT_FILE"

    log_info "Cursor extensions: $installed installed, $skipped already present, $failed failed"
    log_success "Cursor extension installation completed"
}

# Install App Store applications via mas
install_app_store_apps() {
    log_step "Installing App Store applications"

    if ! command -v mas >/dev/null 2>&1; then
        log_warning "mas (Mac App Store CLI) not found"
        log_info "Install with: brew install mas"
        return 0
    fi

    if [[ ! -f "$APP_STORE_FILE" ]]; then
        log_warning "App Store apps manifest not found: $APP_STORE_FILE"
        return 0
    fi

    # Check App Store sign-in
    if ! mas account >/dev/null 2>&1; then
        log_warning "Not signed into the Mac App Store"
        log_info "Sign into the App Store app first, then re-run this phase"
        return 0
    fi

    local installed=0 failed=0 skipped=0

    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue

        local app_id app_name
        app_id=$(echo "$line" | awk '{print $1}')
        app_name=$(echo "$line" | sed 's/^[0-9]*[[:space:]]*//')
        [[ -z "$app_id" ]] && continue

        # Check if already installed
        if mas list | grep -q "^$app_id "; then
            skipped=$((skipped + 1))
            continue
        fi

        log_info "Installing App Store app: $app_name ($app_id)"
        if mas install "$app_id" >/dev/null 2>&1; then
            installed=$((installed + 1))
        else
            log_debug "Failed to install app $app_id"
            failed=$((failed + 1))
        fi
    done < "$APP_STORE_FILE"

    log_info "App Store apps: $installed installed, $skipped already present, $failed failed"
    log_success "App Store installation completed"
}

# Set up shell completions for installed tools
setup_shell_completions() {
    log_step "Setting up shell completions"

    local completions_dir="${HOME}/.zsh/completion"
    mkdir -p "$completions_dir"

    # Docker completions
    if command -v docker >/dev/null 2>&1; then
        if docker completion zsh > "$completions_dir/_docker" 2>/dev/null; then
            log_debug "Generated docker completion"
        fi
    fi

    # kubectl completions
    if command -v kubectl >/dev/null 2>&1; then
        if kubectl completion zsh > "$completions_dir/_kubectl" 2>/dev/null; then
            log_debug "Generated kubectl completion"
        fi
    fi

    # GitHub CLI completions
    if command -v gh >/dev/null 2>&1; then
        if gh completion -s zsh > "$completions_dir/_gh" 2>/dev/null; then
            log_debug "Generated gh completion"
        fi
    fi

    # Helm completions
    if command -v helm >/dev/null 2>&1; then
        if helm completion zsh > "$completions_dir/_helm" 2>/dev/null; then
            log_debug "Generated helm completion"
        fi
    fi

    # Terraform completions (requires manual setup)
    if command -v terraform >/dev/null 2>&1; then
        log_debug "Terraform completions configured via zsh plugin or manual setup"
    fi

    log_success "Shell completions setup completed"
}

# Show installation summary
show_summary() {
    log_step "Application Installation Summary"

    log_info "IDE Extensions:"
    if command -v code >/dev/null 2>&1; then
        local vscode_count
        vscode_count=$(code --list-extensions 2>/dev/null | wc -l | tr -d ' ')
        log_info "  VS Code: $vscode_count extensions installed"
    else
        log_info "  VS Code: not available"
    fi

    if command -v cursor >/dev/null 2>&1; then
        local cursor_count
        cursor_count=$(cursor --list-extensions 2>/dev/null | wc -l | tr -d ' ')
        log_info "  Cursor: $cursor_count extensions installed"
    else
        log_info "  Cursor: not available"
    fi

    log_info "Shell Completions:"
    local comp_dir="${HOME}/.zsh/completion"
    if [[ -d "$comp_dir" ]]; then
        local comp_count
        comp_count=$(find "$comp_dir" -name '_*' -type f | wc -l | tr -d ' ')
        log_info "  $comp_count completion files in $comp_dir"
    fi

    log_success "Application installation phase completed successfully"
}

# Main execution
main() {
    log_header "Phase 7: Application Installs"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would install IDE extensions, shell completions, and App Store apps"
        return 0
    fi

    install_vscode_extensions
    install_cursor_extensions
    install_app_store_apps
    setup_shell_completions
    show_summary

    log_success "Application installation phase completed"
}

main "$@"