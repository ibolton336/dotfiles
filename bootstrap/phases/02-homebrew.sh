#!/bin/bash
#
# Bootstrap Phase 2: Homebrew Installation
# Installs Homebrew package manager and all required packages from brewfile
#

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/error-handling.sh"

# Configuration
readonly BREWFILE_PATH="${DOTFILES_ROOT}/manifests/brewfile"
readonly HOMEBREW_PREFIX="/opt/homebrew"  # Apple Silicon default
readonly HOMEBREW_PREFIX_INTEL="/usr/local"  # Intel Mac default
readonly HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# Detect architecture and set appropriate Homebrew prefix
detect_homebrew_prefix() {
    if [[ "$(uname -m)" == "arm64" ]]; then
        echo "$HOMEBREW_PREFIX"
    else
        echo "$HOMEBREW_PREFIX_INTEL"
    fi
}

# Check if Homebrew is installed
is_homebrew_installed() {
    command -v brew >/dev/null 2>&1
}

# Install Homebrew
install_homebrew() {
    log_step "Installing Homebrew package manager"

    if is_homebrew_installed; then
        log_info "Homebrew is already installed"
        return 0
    fi

    log_info "Downloading and installing Homebrew..."
    log_info "You may be prompted for your password to install Xcode command line tools"

    # Download and run the official Homebrew installer
    if ! curl -fsSL "$HOMEBREW_INSTALL_URL" | bash; then
        log_error "Failed to install Homebrew"
        return 1
    fi

    # Add Homebrew to PATH for current session
    local homebrew_prefix
    homebrew_prefix=$(detect_homebrew_prefix)

    if [[ -d "$homebrew_prefix/bin" ]]; then
        export PATH="$homebrew_prefix/bin:$PATH"
        log_debug "Added $homebrew_prefix/bin to PATH for current session"
    fi

    # Verify installation
    if is_homebrew_installed; then
        log_success "Homebrew installed successfully"
        log_info "Homebrew version: $(brew --version | head -n1)"
    else
        log_error "Homebrew installation verification failed"
        return 1
    fi
}

# Configure Homebrew settings
configure_homebrew() {
    log_step "Configuring Homebrew settings"

    # Disable analytics (privacy)
    log_info "Disabling Homebrew analytics"
    export HOMEBREW_NO_ANALYTICS=1
    brew analytics off 2>/dev/null || true

    # Disable auto-update during install (speeds up installs)
    export HOMEBREW_NO_AUTO_UPDATE=1
    log_debug "Disabled Homebrew auto-update for faster installs"

    # Enable developer tools
    export HOMEBREW_DEVELOPER=1
    log_debug "Enabled Homebrew developer mode"

    log_success "Homebrew configuration completed"
}

# Validate brewfile exists
validate_brewfile() {
    log_step "Validating Brewfile"

    if [[ ! -f "$BREWFILE_PATH" ]]; then
        log_error "Brewfile not found: $BREWFILE_PATH"
        return 1
    fi

    # Check if brewfile is readable and has content
    if [[ ! -r "$BREWFILE_PATH" ]]; then
        log_error "Brewfile is not readable: $BREWFILE_PATH"
        return 1
    fi

    local line_count
    line_count=$(wc -l < "$BREWFILE_PATH")
    if [[ $line_count -lt 5 ]]; then
        log_warning "Brewfile seems unusually short ($line_count lines)"
    fi

    log_success "Brewfile validated: $BREWFILE_PATH ($line_count lines)"
}

# Install packages from brewfile
install_brewfile_packages() {
    log_step "Installing packages from Brewfile"

    log_info "Installing packages from: $BREWFILE_PATH"
    log_info "This may take 10-30 minutes depending on your internet connection"

    # Count packages for progress tracking
    local tap_count cask_count brew_count
    tap_count=$(grep -c "^tap " "$BREWFILE_PATH" || echo "0")
    cask_count=$(grep -c "^cask " "$BREWFILE_PATH" || echo "0")
    brew_count=$(grep -c "^brew " "$BREWFILE_PATH" || echo "0")

    log_info "Package summary: $tap_count taps, $brew_count formulae, $cask_count casks"

    # Run brew bundle install
    if ! brew bundle install --file="$BREWFILE_PATH"; then
        log_error "Some packages failed to install"
        log_info "Checking for installation issues..."

        # Try to identify and report problematic packages
        if ! brew bundle check --file="$BREWFILE_PATH"; then
            log_warning "Some packages from the Brewfile are not installed"
            log_info "You can review and install missing packages later with:"
            log_info "  brew bundle install --file=$BREWFILE_PATH"
        fi

        # Don't fail the phase for package installation issues
        log_warning "Continuing despite package installation warnings"
    fi

    log_success "Brewfile package installation completed"
}

# Update and upgrade existing packages
update_homebrew() {
    log_step "Updating Homebrew and packages"

    # Temporarily re-enable auto-update for the update process
    unset HOMEBREW_NO_AUTO_UPDATE

    log_info "Updating Homebrew..."
    if ! retry_command 3 5 "brew update"; then
        log_warning "Failed to update Homebrew, continuing anyway"
    fi

    # Check if any installed packages need upgrading
    local outdated_packages
    outdated_packages=$(brew outdated --quiet || echo "")

    if [[ -n "$outdated_packages" ]]; then
        local package_count
        package_count=$(echo "$outdated_packages" | wc -l)
        log_info "Found $package_count packages that can be upgraded"

        if confirm "Upgrade outdated packages?"; then
            log_info "Upgrading packages..."
            if ! brew upgrade; then
                log_warning "Some packages failed to upgrade, continuing anyway"
            fi
        else
            log_info "Skipping package upgrades"
        fi
    else
        log_info "All packages are up to date"
    fi

    # Re-disable auto-update
    export HOMEBREW_NO_AUTO_UPDATE=1

    log_success "Homebrew update completed"
}

# Cleanup Homebrew
cleanup_homebrew() {
    log_step "Cleaning up Homebrew"

    # Clean up old versions and cached downloads
    log_info "Removing old package versions and cached files..."
    if ! brew cleanup --prune=1; then
        log_warning "Homebrew cleanup had some issues, continuing anyway"
    fi

    # Show disk space saved
    log_info "Homebrew cleanup completed"
}

# Verify Homebrew installation and configuration
verify_homebrew() {
    log_step "Verifying Homebrew installation"

    # Run brew doctor
    log_info "Running Homebrew diagnostics..."
    if brew doctor; then
        log_success "Homebrew diagnostics passed"
    else
        log_warning "Homebrew diagnostics found some issues"
        log_info "These issues may not affect functionality"
        log_info "Review the output above and fix if necessary"
    fi

    # Verify critical tools are available
    local critical_tools=("git" "curl" "jq")
    local missing_tools=()

    for tool in "${critical_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Critical tools not found in PATH: ${missing_tools[*]}"
        log_info "Current PATH: $PATH"
        return 1
    fi

    # Check if RCM was installed (needed later in phase 4)
    if ! command -v rcup >/dev/null 2>&1; then
        log_warning "RCM (rcup) not found in PATH yet"
        log_info "It may become available after shell restart, or install with: brew install rcm"
    fi

    log_success "Homebrew installation verified successfully"
}

# Show installation summary
show_summary() {
    log_step "Installation Summary"

    # Show Homebrew info
    local homebrew_prefix
    homebrew_prefix=$(brew --prefix 2>/dev/null || echo "unknown")
    log_info "Homebrew prefix: $homebrew_prefix"

    # Count installed packages
    local installed_formulae installed_casks
    installed_formulae=$(brew list --formula | wc -l | tr -d ' ')
    installed_casks=$(brew list --cask | wc -l | tr -d ' ')

    log_info "Installed formulae: $installed_formulae"
    log_info "Installed casks: $installed_casks"

    # Show important PATH information
    log_info "Key tools installed:"
    for tool in git rcup jq; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_info "  $tool: $(command -v "$tool")"
        fi
    done

    log_success "Homebrew installation phase completed successfully"
}

# Main execution
main() {
    log_header "Phase 2: Homebrew Installation"

    # Skip if dry run
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would install Homebrew and packages from $BREWFILE_PATH"
        return 0
    fi

    # Execute installation steps
    validate_brewfile
    install_homebrew
    configure_homebrew
    install_brewfile_packages
    update_homebrew
    cleanup_homebrew
    verify_homebrew
    show_summary

    log_success "Homebrew installation phase completed"
}

# Execute main function
main "$@"