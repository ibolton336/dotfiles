#!/bin/bash
#
# Bootstrap Phase 8: Shell Setup
# Configures zsh as default shell and verifies shell environment
#

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/error-handling.sh"

# Set zsh as default shell
set_default_shell() {
    log_step "Setting default shell to Zsh"

    local zsh_path
    zsh_path=$(which zsh 2>/dev/null || echo "")

    if [[ -z "$zsh_path" ]]; then
        log_error "Zsh not found in PATH"
        return 1
    fi

    # Get current default shell
    local current_shell
    current_shell=$(dscl . -read ~/ UserShell 2>/dev/null | sed 's/UserShell: //' || echo "$SHELL")

    if [[ "$current_shell" == "$zsh_path" ]]; then
        log_info "Default shell is already: $zsh_path"
        return 0
    fi

    log_info "Current default shell: $current_shell"
    log_info "Changing to: $zsh_path"

    # Ensure zsh is in /etc/shells
    if ! grep -qF "$zsh_path" /etc/shells 2>/dev/null; then
        log_info "Adding $zsh_path to /etc/shells"
        echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
    fi

    # Change default shell
    if chsh -s "$zsh_path"; then
        log_success "Default shell changed to: $zsh_path"
    else
        log_warning "Failed to change default shell"
        log_info "You can change it manually with: chsh -s $zsh_path"
    fi
}

# Verify zsh configuration loads correctly
verify_zsh_config() {
    log_step "Verifying Zsh configuration"

    local zsh_path
    zsh_path=$(which zsh)

    # Test that zsh starts without errors
    log_info "Testing Zsh startup..."
    local zsh_output
    if zsh_output=$("$zsh_path" -l -c 'echo "ZSH_OK"' 2>&1); then
        if echo "$zsh_output" | grep -q "ZSH_OK"; then
            log_success "Zsh starts successfully"
        else
            log_warning "Zsh starts but produced unexpected output"
        fi
    else
        log_warning "Zsh login shell test returned non-zero exit"
        log_info "There may be errors in your zsh configuration"
    fi

    # Test that key configuration files are being sourced
    local config_files=(
        "$HOME/.zshrc"
        "$HOME/.zshenv"
        "$HOME/.aliases"
    )

    log_info "Configuration files:"
    for file in "${config_files[@]}"; do
        if [[ -L "$file" ]]; then
            log_info "  $file -> $(readlink "$file")"
        elif [[ -f "$file" ]]; then
            log_info "  $file (regular file)"
        else
            log_warning "  $file (missing)"
        fi
    done
}

# Verify shell functions work
verify_shell_functions() {
    log_step "Verifying shell functions"

    local zsh_path
    zsh_path=$(which zsh)

    # Test key functions from dotfiles
    local functions_to_test=("g" "mcd" "envup")
    local available=0 missing=0

    for func in "${functions_to_test[@]}"; do
        if "$zsh_path" -c "autoload -Uz $func; type $func" >/dev/null 2>&1; then
            log_debug "  Function available: $func"
            available=$((available + 1))
        else
            # Try checking if function file exists
            if [[ -f "$HOME/.zsh/functions/$func" ]]; then
                log_debug "  Function file exists: $func"
                available=$((available + 1))
            else
                log_debug "  Function not found: $func"
                missing=$((missing + 1))
            fi
        fi
    done

    log_info "Shell functions: $available available, $missing missing"

    # Test aliases
    log_info "Checking aliases file..."
    if [[ -f "$HOME/.aliases" ]]; then
        local alias_count
        alias_count=$(grep -c "^alias " "$HOME/.aliases" 2>/dev/null || echo "0")
        log_info "  $alias_count aliases defined in .aliases"
    fi

    if [[ -f "$HOME/.aliases.local" ]]; then
        local local_alias_count
        local_alias_count=$(grep -c "^alias " "$HOME/.aliases.local" 2>/dev/null || echo "0")
        log_info "  $local_alias_count aliases defined in .aliases.local"
    fi

    log_success "Shell functions verification completed"
}

# Verify fzf integration
verify_fzf_integration() {
    log_step "Verifying fzf integration"

    if command -v fzf >/dev/null 2>&1; then
        local fzf_version
        fzf_version=$(fzf --version 2>/dev/null | head -n1)
        log_info "fzf version: $fzf_version"

        # Check for fzf shell integration files
        local fzf_dir
        fzf_dir="$(brew --prefix 2>/dev/null)/opt/fzf" 2>/dev/null || fzf_dir=""

        if [[ -n "$fzf_dir" && -d "$fzf_dir" ]]; then
            if [[ -f "$fzf_dir/shell/completion.zsh" ]]; then
                log_debug "  fzf completion available"
            fi
            if [[ -f "$fzf_dir/shell/key-bindings.zsh" ]]; then
                log_debug "  fzf key bindings available"
            fi

            # Install fzf shell integration if not already done
            if [[ ! -f "$HOME/.fzf.zsh" ]]; then
                log_info "Setting up fzf shell integration..."
                if "$fzf_dir/install" --key-bindings --completion --no-update-rc --no-bash --no-fish >/dev/null 2>&1; then
                    log_success "fzf shell integration installed"
                else
                    log_warning "fzf shell integration setup had issues"
                fi
            else
                log_debug "  fzf shell integration already configured"
            fi
        fi

        log_success "fzf integration verified"
    else
        log_warning "fzf not found - fuzzy finding features will not be available"
    fi
}

# Verify key tools are accessible from shell
verify_path_tools() {
    log_step "Verifying tools accessible from shell PATH"

    local tools=(
        "git" "vim" "tmux" "brew" "rcup"
        "fzf" "rg" "ag" "jq" "tree"
        "node" "python3" "ruby" "go"
    )

    local available=0 missing=0

    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            available=$((available + 1))
        else
            log_debug "  Not in PATH: $tool"
            missing=$((missing + 1))
        fi
    done

    log_info "Tools in PATH: $available available, $missing not found"
    log_info "Note: Some tools may become available after opening a new shell session"

    log_success "PATH tools verification completed"
}

# Show shell setup summary
show_summary() {
    log_step "Shell Setup Summary"

    local zsh_path
    zsh_path=$(which zsh 2>/dev/null || echo "not found")
    log_info "Zsh: $zsh_path"
    log_info "Zsh version: $(zsh --version 2>/dev/null | cut -d' ' -f2 || echo 'unknown')"

    local current_shell
    current_shell=$(dscl . -read ~/ UserShell 2>/dev/null | sed 's/UserShell: //' || echo "$SHELL")
    log_info "Default shell: $current_shell"

    # Show zsh config directories
    log_info "Configuration directories:"
    local dirs=("$HOME/.zsh/configs" "$HOME/.zsh/functions" "$HOME/.zsh/completion")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local file_count
            file_count=$(find "$dir" -type f | wc -l | tr -d ' ')
            log_info "  $dir ($file_count files)"
        fi
    done

    log_success "Shell setup phase completed successfully"
}

# Main execution
main() {
    log_header "Phase 8: Shell Setup"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would configure default shell and verify shell environment"
        return 0
    fi

    set_default_shell
    verify_zsh_config
    verify_shell_functions
    verify_fzf_integration
    verify_path_tools
    show_summary

    log_success "Shell setup phase completed"
}

main "$@"