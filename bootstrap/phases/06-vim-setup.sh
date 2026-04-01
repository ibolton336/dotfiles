#!/bin/bash
#
# Bootstrap Phase 6: Vim Setup
# Installs vim-plug plugin manager and configures Vim with plugins
#

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/error-handling.sh"

# Configuration
readonly VIM_PLUG_URL="https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
readonly VIM_PLUG_PATH="$HOME/.vim/autoload/plug.vim"
readonly VIMRC_PATH="$HOME/.vimrc"
readonly VIMRC_BUNDLES_PATH="$HOME/.vimrc.bundles"

# Verify Vim is installed and accessible
verify_vim() {
    log_step "Verifying Vim installation"

    if ! command -v vim >/dev/null 2>&1; then
        log_error "Vim is not available in PATH"
        log_info "Vim should have been installed in the system tools phase"
        return 1
    fi

    local vim_version vim_features
    vim_version=$(vim --version | head -n1)
    log_info "Vim version: $vim_version"

    # Check for required features
    vim_features=$(vim --version | grep -E '^\+|^-' | tr '\n' ' ')
    log_debug "Vim features: $vim_features"

    # Check for essential features
    if vim --version | grep -q '+python3'; then
        log_debug "✓ Python3 support available"
    else
        log_debug "! Python3 support not available (some plugins may not work)"
    fi

    if vim --version | grep -q '+clipboard'; then
        log_debug "✓ Clipboard support available"
    else
        log_debug "! Clipboard support not available"
    fi

    log_success "Vim verification completed"
}

# Check if vim configuration files exist
check_vim_config() {
    log_step "Checking Vim configuration files"

    if [[ -L "$VIMRC_PATH" ]]; then
        local target
        target=$(readlink "$VIMRC_PATH")
        log_info "vimrc is symlinked to: $target"

        if [[ -f "$VIMRC_PATH" ]]; then
            log_debug "✓ vimrc is accessible"
        else
            log_warning "✗ vimrc symlink is broken"
            return 1
        fi
    elif [[ -f "$VIMRC_PATH" ]]; then
        log_info "vimrc exists as regular file"
    else
        log_warning "vimrc not found - it should be created by dotfiles setup"
        return 1
    fi

    if [[ -L "$VIMRC_BUNDLES_PATH" ]]; then
        local target
        target=$(readlink "$VIMRC_BUNDLES_PATH")
        log_info "vimrc.bundles is symlinked to: $target"

        if [[ -f "$VIMRC_BUNDLES_PATH" ]]; then
            log_debug "✓ vimrc.bundles is accessible"
        else
            log_warning "✗ vimrc.bundles symlink is broken"
            return 1
        fi
    elif [[ -f "$VIMRC_BUNDLES_PATH" ]]; then
        log_info "vimrc.bundles exists as regular file"
    else
        log_warning "vimrc.bundles not found - this is required for plugin management"
        return 1
    fi

    log_success "Vim configuration files check completed"
}

# Install vim-plug plugin manager
install_vim_plug() {
    log_step "Installing vim-plug plugin manager"

    if [[ -f "$VIM_PLUG_PATH" ]]; then
        log_info "vim-plug is already installed"

        # Check if it's up to date (optional update)
        if confirm "Update vim-plug to the latest version?" "y"; then
            log_info "Updating vim-plug..."
            if curl -fsSL "$VIM_PLUG_URL" -o "$VIM_PLUG_PATH"; then
                log_success "vim-plug updated successfully"
            else
                log_warning "Failed to update vim-plug, using existing version"
            fi
        fi
    else
        log_info "Installing vim-plug plugin manager..."

        # Create vim autoload directory if it doesn't exist
        mkdir -p "$(dirname "$VIM_PLUG_PATH")"

        # Download vim-plug
        if curl -fsSL "$VIM_PLUG_URL" -o "$VIM_PLUG_PATH"; then
            log_success "vim-plug installed successfully"
        else
            log_error "Failed to download vim-plug"
            return 1
        fi
    fi

    # Verify installation
    if [[ -f "$VIM_PLUG_PATH" ]]; then
        local plug_size
        plug_size=$(wc -c < "$VIM_PLUG_PATH")
        log_debug "vim-plug size: $plug_size bytes"

        if [[ $plug_size -gt 1000 ]]; then
            log_debug "✓ vim-plug appears to be properly installed"
        else
            log_warning "! vim-plug file seems unusually small"
        fi
    fi
}

# Parse vim bundles from vimrc.bundles
parse_vim_bundles() {
    if [[ ! -f "$VIMRC_BUNDLES_PATH" ]]; then
        log_warning "vimrc.bundles not found, cannot determine plugins to install"
        return 1
    fi

    # Extract plugin names from Plug commands
    # This matches lines like: Plug 'author/plugin'
    local plugins
    plugins=$(grep "^Plug " "$VIMRC_BUNDLES_PATH" | sed "s/.*'\([^']*\)'.*/\1/" | sort | uniq)

    if [[ -n "$plugins" ]]; then
        log_info "Found $(echo "$plugins" | wc -l) plugins to install:"
        echo "$plugins" | sed 's/^/  /'
    else
        log_warning "No plugins found in vimrc.bundles"
    fi
}

# Install vim plugins using vim-plug
install_vim_plugins() {
    log_step "Installing Vim plugins"

    if [[ ! -f "$VIM_PLUG_PATH" ]]; then
        log_error "vim-plug not installed, cannot install plugins"
        return 1
    fi

    if [[ ! -f "$VIMRC_BUNDLES_PATH" ]]; then
        log_error "vimrc.bundles not found, cannot install plugins"
        return 1
    fi

    # Show what plugins will be installed
    parse_vim_bundles

    log_info "Installing and updating Vim plugins..."
    log_info "This may take a few minutes depending on the number of plugins"

    # Run vim-plug install and update in headless mode
    # The +qa ensures vim exits after running the commands
    local vim_commands=(
        "+PlugInstall --sync"
        "+PlugUpdate"
        "+PlugClean!"
        "+qa"
    )

    # Execute vim commands
    if vim "${vim_commands[@]}" </dev/null; then
        log_success "Vim plugins installed successfully"
    else
        local exit_code=$?
        log_warning "Vim plugin installation had some issues (exit code: $exit_code)"
        log_info "Some plugins may have failed to install or update"

        # Don't fail the entire phase for plugin issues
        log_info "Continuing with Vim setup..."
    fi
}

# Verify vim plugin installation
verify_vim_plugins() {
    log_step "Verifying Vim plugin installation"

    local plugged_dir="$HOME/.vim/plugged"

    if [[ ! -d "$plugged_dir" ]]; then
        log_warning "Vim plugins directory not found: $plugged_dir"
        log_info "Plugins may not have been installed successfully"
        return 0
    fi

    # Count installed plugins
    local plugin_count
    plugin_count=$(find "$plugged_dir" -maxdepth 1 -type d | wc -l)
    # Subtract 1 for the plugged directory itself
    plugin_count=$((plugin_count - 1))

    if [[ $plugin_count -gt 0 ]]; then
        log_success "Found $plugin_count installed plugins in $plugged_dir"

        # List some plugins for verification
        log_info "Installed plugins:"
        find "$plugged_dir" -maxdepth 1 -type d -not -name "plugged" | head -10 | sed 's|.*/||' | sed 's/^/  /'

        if [[ $plugin_count -gt 10 ]]; then
            log_info "  ... and $((plugin_count - 10)) more"
        fi
    else
        log_warning "No plugins found in $plugged_dir"
    fi
}

# Test basic vim functionality
test_vim_functionality() {
    log_step "Testing Vim functionality"

    # Test basic vim startup
    log_info "Testing basic Vim startup..."

    if echo | vim -es -c 'q!' 2>/dev/null; then
        log_debug "✓ Vim starts successfully"
    else
        log_error "✗ Vim fails to start properly"
        return 1
    fi

    # Test vim configuration loading
    log_info "Testing Vim configuration loading..."

    if echo | vim -es -c 'echo "Config test"' -c 'q!' 2>/dev/null; then
        log_debug "✓ Vim loads configuration without errors"
    else
        log_warning "! Vim configuration may have issues"
    fi

    # Test plugin availability (check for a common plugin command)
    log_info "Testing plugin functionality..."

    # Try to run a plugin command that should be available
    if echo | vim -es -c 'PlugStatus' -c 'q!' 2>/dev/null; then
        log_debug "✓ vim-plug commands are available"
    else
        log_debug "! vim-plug commands may not be working"
    fi

    log_success "Vim functionality tests completed"
}

# Setup vim directories
setup_vim_directories() {
    log_step "Setting up Vim directories"

    local vim_dirs=(
        "$HOME/.vim/backup"
        "$HOME/.vim/swap"
        "$HOME/.vim/undo"
        "$HOME/.vim/autoload"
        "$HOME/.vim/bundle"
        "$HOME/.vim/colors"
    )

    for dir in "${vim_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_debug "Created directory: $dir"
        fi
    done

    log_success "Vim directories setup completed"
}

# Configure vim for development
configure_vim_dev_environment() {
    log_step "Configuring Vim for development"

    # Check if fzf is available (used by vim configuration)
    if command -v fzf >/dev/null 2>&1; then
        log_debug "✓ fzf is available for Vim integration"
    else
        log_debug "! fzf not available (some Vim features may not work)"
    fi

    # Check if ripgrep is available (used for searching)
    if command -v rg >/dev/null 2>&1; then
        log_debug "✓ ripgrep is available for Vim searching"
    else
        log_debug "! ripgrep not available (some search features may not work)"
    fi

    # Check if git is available (for git plugins)
    if command -v git >/dev/null 2>&1; then
        log_debug "✓ Git is available for Vim Git integration"
    else
        log_debug "! Git not available (Git plugins will not work)"
    fi

    # Check if ctags is available
    if command -v ctags >/dev/null 2>&1; then
        log_debug "✓ ctags is available for code navigation"

        local ctags_version
        ctags_version=$(ctags --version 2>/dev/null | head -n1 || echo "unknown")
        log_debug "ctags version: $ctags_version"
    else
        log_debug "! ctags not available (code navigation features limited)"
    fi

    log_success "Vim development environment check completed"
}

# Show vim setup summary
show_vim_summary() {
    log_step "Vim Setup Summary"

    # Show vim information
    local vim_version
    vim_version=$(vim --version | head -n1)
    log_info "Vim: $vim_version"

    if [[ -f "$VIM_PLUG_PATH" ]]; then
        log_info "Plugin manager: vim-plug installed"
    else
        log_warning "Plugin manager: vim-plug NOT installed"
    fi

    # Count plugins
    local plugged_dir="$HOME/.vim/plugged"
    if [[ -d "$plugged_dir" ]]; then
        local plugin_count
        plugin_count=$(find "$plugged_dir" -maxdepth 1 -type d | wc -l)
        plugin_count=$((plugin_count - 1))
        log_info "Installed plugins: $plugin_count"
    else
        log_info "Installed plugins: 0 (plugins directory not found)"
    fi

    # Show configuration files
    log_info "Configuration files:"
    if [[ -L "$VIMRC_PATH" ]]; then
        log_info "  vimrc: symlinked to $(readlink "$VIMRC_PATH")"
    elif [[ -f "$VIMRC_PATH" ]]; then
        log_info "  vimrc: exists as regular file"
    else
        log_warning "  vimrc: NOT FOUND"
    fi

    if [[ -L "$VIMRC_BUNDLES_PATH" ]]; then
        log_info "  vimrc.bundles: symlinked to $(readlink "$VIMRC_BUNDLES_PATH")"
    elif [[ -f "$VIMRC_BUNDLES_PATH" ]]; then
        log_info "  vimrc.bundles: exists as regular file"
    else
        log_warning "  vimrc.bundles: NOT FOUND"
    fi

    # Show supporting tools
    log_info "Supporting tools:"
    local tools=("fzf" "rg" "ag" "ctags" "git")
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_info "  ✓ $tool: $(which "$tool")"
        else
            log_info "  ✗ $tool: not available"
        fi
    done

    log_success "Vim setup phase completed successfully"
}

# Main execution
main() {
    log_header "Phase 6: Vim Setup"

    # Skip if dry run
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would install vim-plug and configure Vim plugins"
        return 0
    fi

    # Execute setup steps
    verify_vim
    check_vim_config
    setup_vim_directories
    install_vim_plug
    install_vim_plugins
    verify_vim_plugins
    test_vim_functionality
    configure_vim_dev_environment
    show_vim_summary

    log_success "Vim setup phase completed"
}

# Execute main function
main "$@"