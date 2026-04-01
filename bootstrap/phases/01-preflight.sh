#!/bin/bash
#
# Bootstrap Phase 1: Preflight Checks
# System verification and preparation for bootstrap process
#

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/error-handling.sh"

# Configuration
readonly MIN_MACOS_VERSION="11.0"
readonly MIN_DISK_SPACE_GB=20
readonly REQUIRED_CONNECTIVITY_HOSTS=("github.com" "raw.githubusercontent.com" "formulae.brew.sh")

# Check macOS version compatibility
check_macos_version() {
    log_step "Checking macOS version compatibility"

    local current_version
    current_version=$(sw_vers -productVersion)

    log_info "Current macOS version: $current_version"
    log_info "Minimum required version: $MIN_MACOS_VERSION"

    # Simple version comparison for major.minor format
    local current_major current_minor min_major min_minor
    current_major="${current_version%%.*}"
    current_minor="${current_version#*.}"; current_minor="${current_minor%%.*}"
    min_major="${MIN_MACOS_VERSION%%.*}"
    min_minor="${MIN_MACOS_VERSION#*.}"; min_minor="${min_minor%%.*}"

    local current_num=$((current_major * 100 + current_minor))
    local min_num=$((min_major * 100 + min_minor))

    if [[ $current_num -lt $min_num ]]; then
        log_error "Unsupported macOS version: $current_version"
        log_error "Please upgrade to macOS $MIN_MACOS_VERSION or later"
        return 1
    fi

    log_success "macOS version check passed"
}

# Check system architecture
check_system_architecture() {
    log_step "Checking system architecture"

    local arch
    arch=$(uname -m)

    case "$arch" in
        arm64)
            log_info "System architecture: Apple Silicon (arm64)"
            log_info "Will use /opt/homebrew for Homebrew installation"
            ;;
        x86_64)
            log_info "System architecture: Intel (x86_64)"
            log_info "Will use /usr/local for Homebrew installation"
            ;;
        *)
            log_warning "Unknown system architecture: $arch"
            log_info "Proceeding with caution..."
            ;;
    esac

    log_success "System architecture check completed"
}

# Check available disk space
check_disk_space() {
    log_step "Checking available disk space"

    # Get available space on root filesystem in GB
    local available_space_kb
    available_space_kb=$(df / | tail -1 | awk '{print $4}')
    local available_space_gb=$((available_space_kb / 1024 / 1024))

    log_info "Available disk space: ${available_space_gb}GB"
    log_info "Minimum required space: ${MIN_DISK_SPACE_GB}GB"

    if [[ $available_space_gb -lt $MIN_DISK_SPACE_GB ]]; then
        log_error "Insufficient disk space: ${available_space_gb}GB available, ${MIN_DISK_SPACE_GB}GB required"
        log_info "Please free up disk space and try again"
        return 1
    fi

    if [[ $available_space_gb -lt 50 ]]; then
        log_warning "Low disk space: ${available_space_gb}GB available"
        log_info "Consider freeing up more space for a smoother installation"

        if ! confirm "Continue with low disk space?"; then
            return 1
        fi
    fi

    log_success "Disk space check passed"
}

# Check internet connectivity
check_internet_connectivity() {
    log_step "Checking internet connectivity"

    local connectivity_ok=false

    for host in "${REQUIRED_CONNECTIVITY_HOSTS[@]}"; do
        log_debug "Testing connectivity to $host"

        if ping -c 1 -W 3000 "$host" >/dev/null 2>&1; then
            log_debug "✓ $host is reachable"
            connectivity_ok=true
        elif nc -z "$host" 443 2>/dev/null; then
            log_debug "✓ $host is reachable (HTTPS)"
            connectivity_ok=true
        else
            log_warning "✗ Cannot reach $host"
        fi
    done

    if [[ "$connectivity_ok" == "true" ]]; then
        log_success "Internet connectivity check passed"
    else
        log_error "No internet connectivity detected"
        log_info "The following hosts must be reachable:"
        for host in "${REQUIRED_CONNECTIVITY_HOSTS[@]}"; do
            log_info "  - $host"
        done
        return 1
    fi

    # Test DNS resolution
    log_debug "Testing DNS resolution"
    if ! nslookup github.com >/dev/null 2>&1; then
        log_warning "DNS resolution issues detected"
        log_info "You may need to configure DNS settings"
    fi
}

# Check for Command Line Tools
check_command_line_tools() {
    log_step "Checking for Xcode Command Line Tools"

    # Check if Command Line Tools are installed
    if xcode-select -p >/dev/null 2>&1; then
        local xcode_path
        xcode_path=$(xcode-select -p)
        log_info "Command Line Tools found at: $xcode_path"

        # Verify key tools are available
        if command -v git >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
            log_success "Command Line Tools are properly installed"
        else
            log_warning "Command Line Tools installation may be incomplete"
            install_command_line_tools
        fi
    else
        log_info "Command Line Tools not found"
        install_command_line_tools
    fi
}

# Install Command Line Tools
install_command_line_tools() {
    log_info "Installing Xcode Command Line Tools..."
    log_info "You may be prompted to install or update the Command Line Tools"

    # Trigger Command Line Tools installation
    if xcode-select --install 2>/dev/null; then
        log_info "Command Line Tools installer launched"
        log_info "Please follow the prompts to complete installation"
        log_info "After installation completes, run the bootstrap script again"
        return 1
    else
        # Tools might already be installed or installer failed
        log_info "Command Line Tools installer could not be launched"
        log_info "They may already be installed or installation failed"

        # Try to verify installation
        if command -v git >/dev/null 2>&1; then
            log_info "Essential tools are available, continuing"
        else
            log_error "Essential development tools are not available"
            log_info "Please install Xcode Command Line Tools manually:"
            log_info "  1. Open Terminal"
            log_info "  2. Run: xcode-select --install"
            log_info "  3. Follow the installation prompts"
            return 1
        fi
    fi
}

# Check system permissions
check_system_permissions() {
    log_step "Checking system permissions"

    # Check if running as root (not recommended)
    if [[ $EUID -eq 0 ]]; then
        log_error "Running as root is not recommended"
        log_info "Please run this script as a regular user"
        return 1
    fi

    # Check write permissions to home directory
    if [[ ! -w "$HOME" ]]; then
        log_error "No write permission to home directory: $HOME"
        return 1
    fi

    # Check if sudo is available (might be needed for some operations)
    if sudo -n true 2>/dev/null; then
        log_info "Passwordless sudo is available"
    else
        log_info "sudo access is available (may prompt for password)"
    fi

    log_success "System permissions check passed"
}

# Check existing dotfiles
check_existing_dotfiles() {
    log_step "Checking for existing dotfiles"

    local existing_files=()
    local dotfiles_to_check=(
        "$HOME/.zshrc"
        "$HOME/.vimrc"
        "$HOME/.gitconfig"
        "$HOME/.tmux.conf"
    )

    for file in "${dotfiles_to_check[@]}"; do
        if [[ -f "$file" && ! -L "$file" ]]; then
            existing_files+=("$file")
        fi
    done

    if [[ ${#existing_files[@]} -gt 0 ]]; then
        log_warning "Found existing dotfiles that will be replaced:"
        for file in "${existing_files[@]}"; do
            log_info "  - $file"
        done

        log_info "These files will be backed up before replacement"

        if ! confirm "Continue with existing dotfiles backup and replacement?"; then
            log_info "Bootstrap cancelled by user"
            return 1
        fi
    else
        log_info "No conflicting dotfiles found"
    fi

    log_success "Existing dotfiles check completed"
}

# Check for existing package managers
check_existing_package_managers() {
    log_step "Checking for existing package managers"

    # Check for Homebrew
    if command -v brew >/dev/null 2>&1; then
        local brew_prefix
        brew_prefix=$(brew --prefix)
        log_info "Homebrew already installed at: $brew_prefix"
        log_info "Will use existing installation"
    else
        log_info "Homebrew not found - will install during bootstrap"
    fi

    # Check for MacPorts (potential conflict)
    if command -v port >/dev/null 2>&1; then
        log_warning "MacPorts detected - this may conflict with Homebrew"
        log_info "Consider uninstalling MacPorts if you encounter issues"
    fi

    # Check for Fink (potential conflict)
    if [[ -d "/sw" ]]; then
        log_warning "Fink installation detected - this may conflict with Homebrew"
    fi

    log_success "Package manager check completed"
}

# Backup critical system files
backup_critical_files() {
    log_step "Backing up critical system files"

    local files_to_backup=(
        "$HOME/.zshrc"
        "$HOME/.bash_profile"
        "$HOME/.profile"
        "$HOME/.gitconfig"
    )

    local backed_up_count=0

    for file in "${files_to_backup[@]}"; do
        if [[ -f "$file" && ! -L "$file" ]]; then
            if backup_file "$file"; then
                backed_up_count=$((backed_up_count + 1))
                log_debug "Backed up: $file"
            fi
        fi
    done

    if [[ $backed_up_count -gt 0 ]]; then
        log_success "Backed up $backed_up_count critical files"
    else
        log_info "No critical files needed backup"
    fi
}

# Check system locale
check_system_locale() {
    log_step "Checking system locale settings"

    local locale_output
    locale_output=$(locale 2>/dev/null || echo "")

    if [[ -n "$locale_output" ]]; then
        log_debug "Current locale settings:"
        log_debug "$locale_output"

        # Check for UTF-8 support
        if echo "$locale_output" | grep -q "UTF-8"; then
            log_success "UTF-8 locale support detected"
        else
            log_warning "UTF-8 locale support not detected"
            log_info "Some tools may not work correctly with non-UTF-8 locales"
        fi
    else
        log_warning "Could not determine locale settings"
    fi
}

# Show system information summary
show_system_summary() {
    log_step "System Information Summary"

    log_info "Operating System: $(sw_vers -productName) $(sw_vers -productVersion)"
    log_info "Build Version: $(sw_vers -buildVersion)"
    log_info "Architecture: $(uname -m)"
    log_info "Hostname: $(hostname)"
    log_info "User: $USER"
    log_info "Shell: $SHELL"
    log_info "Home Directory: $HOME"

    # Show hardware info
    local memory_gb
    memory_gb=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')
    log_info "Memory: ${memory_gb}GB"

    local cpu_cores
    cpu_cores=$(sysctl -n hw.ncpu)
    log_info "CPU Cores: $cpu_cores"

    log_success "System summary completed"
}

# Main preflight execution
main() {
    log_header "Phase 1: Preflight Checks"
    log_info "Verifying system requirements and preparing for bootstrap..."
    echo

    # Skip if dry run
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would perform preflight checks"
        return 0
    fi

    # Execute all preflight checks
    show_system_summary
    check_macos_version
    check_system_architecture
    check_disk_space
    check_internet_connectivity
    check_command_line_tools
    check_system_permissions
    check_existing_dotfiles
    check_existing_package_managers
    backup_critical_files
    check_system_locale

    log_header "Preflight Checks Summary"
    log_success "All preflight checks completed successfully!"
    log_info "System is ready for bootstrap process"
    echo

    log_success "Preflight checks phase completed"
}

# Execute main function
main "$@"