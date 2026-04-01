#!/bin/bash
#
# Bootstrap Phase 3: System Tools Installation
# Installs essential system tools and validates the development environment
#

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/error-handling.sh"

# Configuration
readonly HOMEBREW_PREFIX_ARM="/opt/homebrew"
readonly HOMEBREW_PREFIX_INTEL="/usr/local"

# Get the correct Homebrew prefix for this system
get_homebrew_prefix() {
    if [[ "$(uname -m)" == "arm64" ]]; then
        echo "$HOMEBREW_PREFIX_ARM"
    else
        echo "$HOMEBREW_PREFIX_INTEL"
    fi
}

# Verify Homebrew is installed and accessible
verify_homebrew() {
    log_step "Verifying Homebrew installation"

    if ! command -v brew >/dev/null 2>&1; then
        # Try to add Homebrew to PATH
        local homebrew_prefix
        homebrew_prefix=$(get_homebrew_prefix)

        if [[ -x "$homebrew_prefix/bin/brew" ]]; then
            export PATH="$homebrew_prefix/bin:$PATH"
            log_info "Added Homebrew to PATH: $homebrew_prefix/bin"
        else
            log_error "Homebrew not found at expected location: $homebrew_prefix"
            log_info "Please ensure Homebrew was installed in phase 2"
            return 1
        fi
    fi

    local brew_version
    brew_version=$(brew --version | head -n1)
    local brew_prefix
    brew_prefix=$(brew --prefix)

    log_success "Homebrew verified: $brew_version"
    log_info "Homebrew prefix: $brew_prefix"

    # Ensure PATH includes Homebrew
    if ! echo "$PATH" | grep -q "$(brew --prefix)/bin"; then
        export PATH="$(brew --prefix)/bin:$PATH"
        log_debug "Added $(brew --prefix)/bin to PATH"
    fi
}

# Install essential command line tools
install_essential_tools() {
    log_step "Installing essential command line tools"

    local essential_tools=(
        "git"
        "curl"
        "wget"
        "jq"
        "universal-ctags"
        "zsh"
        "vim"
        "tmux"
        "tree"
        "htop"
    )

    local failed_tools=()

    log_info "Ensuring essential tools are installed..."

    for tool in "${essential_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_info "Installing $tool..."

            if brew install "$tool"; then
                log_debug "✓ $tool installed successfully"
            else
                log_warning "✗ Failed to install $tool"
                failed_tools+=("$tool")
            fi
        else
            log_debug "✓ $tool already available"
        fi
    done

    if [[ ${#failed_tools[@]} -gt 0 ]]; then
        log_warning "Some tools failed to install: ${failed_tools[*]}"
        log_info "These tools may be installed via dependencies or alternative names"
    else
        log_success "All essential tools are available"
    fi
}

# Configure Git global settings
configure_git() {
    log_step "Configuring Git global settings"

    # Check if git is available
    if ! command -v git >/dev/null 2>&1; then
        log_error "Git is not available in PATH"
        return 1
    fi

    local git_version
    git_version=$(git --version)
    log_info "Git version: $git_version"

    # Set up basic Git configuration if not already set
    local current_name current_email
    current_name=$(git config --global user.name 2>/dev/null || echo "")
    current_email=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -z "$current_name" ]]; then
        log_info "Git user.name not set - will be configured via dotfiles"
    else
        log_info "Git user.name: $current_name"
    fi

    if [[ -z "$current_email" ]]; then
        log_info "Git user.email not set - will be configured via dotfiles"
    else
        log_info "Git user.email: $current_email"
    fi

    # Enable credential helper for macOS
    if ! git config --global credential.helper >/dev/null 2>&1; then
        log_info "Configuring Git credential helper for macOS"
        git config --global credential.helper osxkeychain
    fi

    # Set default branch name if not set
    local default_branch
    default_branch=$(git config --global init.defaultBranch 2>/dev/null || echo "")
    if [[ -z "$default_branch" ]]; then
        log_info "Setting default Git branch name to 'main'"
        git config --global init.defaultBranch main
    fi

    log_success "Git configuration completed"
}

# Install and configure Zsh
setup_zsh() {
    log_step "Setting up Zsh shell"

    # Check if Zsh is available
    if ! command -v zsh >/dev/null 2>&1; then
        log_error "Zsh is not available in PATH"
        return 1
    fi

    local zsh_version zsh_path
    zsh_version=$(zsh --version)
    zsh_path=$(which zsh)

    log_info "Zsh version: $zsh_version"
    log_info "Zsh location: $zsh_path"

    # Check if Homebrew zsh is in /etc/shells
    if ! grep -q "$zsh_path" /etc/shells 2>/dev/null; then
        log_info "Adding Homebrew Zsh to /etc/shells"

        if echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null; then
            log_debug "Added $zsh_path to /etc/shells"
        else
            log_warning "Failed to add Zsh to /etc/shells"
            log_info "You may need to do this manually later"
        fi
    else
        log_debug "Homebrew Zsh already in /etc/shells"
    fi

    # Check current shell
    local current_shell
    current_shell=$(dscl . -read ~/ UserShell | sed 's/UserShell: //')

    if [[ "$current_shell" == "$zsh_path" ]]; then
        log_info "Default shell is already set to Homebrew Zsh"
    else
        log_info "Current shell: $current_shell"
        log_info "Will set default shell to Zsh in shell setup phase"
    fi

    log_success "Zsh setup completed"
}

# Install development build tools
install_build_tools() {
    log_step "Installing development build tools"

    # Check if Xcode Command Line Tools are properly installed
    if ! xcode-select -p >/dev/null 2>&1; then
        log_warning "Xcode Command Line Tools not found"
        log_info "Installing Command Line Tools..."

        if ! xcode-select --install; then
            log_error "Failed to install Xcode Command Line Tools"
            return 1
        fi

        log_info "Please follow the installation prompts and restart the bootstrap after installation"
        return 1
    fi

    local xcode_path
    xcode_path=$(xcode-select -p)
    log_info "Xcode Command Line Tools: $xcode_path"

    # Verify essential build tools
    local build_tools=("make" "gcc" "clang")
    local missing_tools=()

    for tool in "${build_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local tool_path
            tool_path=$(which "$tool")
            log_debug "✓ $tool: $tool_path"
        else
            log_warning "✗ $tool not found"
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warning "Missing build tools: ${missing_tools[*]}"
        log_info "Command Line Tools installation may be incomplete"
    else
        log_success "Build tools verification completed"
    fi

    # Install additional build dependencies via Homebrew
    local additional_tools=("pkg-config" "autoconf" "automake" "cmake")

    log_info "Installing additional build dependencies..."
    for tool in "${additional_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            if brew install "$tool" 2>/dev/null; then
                log_debug "✓ Installed $tool"
            else
                log_debug "! $tool installation skipped (may already be available)"
            fi
        fi
    done

    log_success "Build tools installation completed"
}

# Validate PATH configuration
validate_path() {
    log_step "Validating PATH configuration"

    log_info "Current PATH:"
    echo "$PATH" | tr ':' '\n' | head -20 | sed 's/^/  /'

    # Check for Homebrew in PATH
    local homebrew_prefix
    homebrew_prefix=$(brew --prefix 2>/dev/null || echo "")

    if [[ -n "$homebrew_prefix" ]]; then
        if echo "$PATH" | grep -q "$homebrew_prefix/bin"; then
            log_debug "✓ Homebrew bin directory in PATH"
        else
            log_warning "! Homebrew bin directory not in PATH"
            log_info "This will be configured in the shell setup phase"
        fi

        if echo "$PATH" | grep -q "$homebrew_prefix/sbin"; then
            log_debug "✓ Homebrew sbin directory in PATH"
        else
            log_debug "! Homebrew sbin directory not in PATH (optional)"
        fi
    fi

    # Check for essential tools in PATH
    local essential_commands=("git" "zsh" "vim" "brew")
    local missing_commands=()

    for cmd in "${essential_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            local cmd_path
            cmd_path=$(which "$cmd")
            log_debug "✓ $cmd: $cmd_path"
        else
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Essential commands not found in PATH: ${missing_commands[*]}"
        return 1
    fi

    log_success "PATH validation completed"
}

# Test essential tool functionality
test_tool_functionality() {
    log_step "Testing essential tool functionality"

    # Test Git
    log_info "Testing Git functionality..."
    if git --version >/dev/null 2>&1; then
        log_debug "✓ Git version check passed"
    else
        log_error "✗ Git version check failed"
        return 1
    fi

    # Test curl
    log_info "Testing curl functionality..."
    if curl --version >/dev/null 2>&1; then
        log_debug "✓ curl version check passed"
    else
        log_error "✗ curl version check failed"
        return 1
    fi

    # Test jq
    log_info "Testing jq functionality..."
    if echo '{"test": "value"}' | jq -r .test >/dev/null 2>&1; then
        log_debug "✓ jq JSON parsing test passed"
    else
        log_warning "✗ jq functionality test failed"
    fi

    # Test vim
    log_info "Testing vim functionality..."
    if vim --version >/dev/null 2>&1; then
        log_debug "✓ vim version check passed"
    else
        log_warning "✗ vim version check failed"
    fi

    log_success "Tool functionality tests completed"
}

# Install mas (Mac App Store CLI)
install_mas() {
    log_step "Installing Mac App Store CLI (mas)"

    if command -v mas >/dev/null 2>&1; then
        local mas_version
        mas_version=$(mas version)
        log_info "mas is already installed: $mas_version"
    else
        log_info "Installing mas (Mac App Store CLI)..."

        if brew install mas; then
            log_success "mas installed successfully"

            local mas_version
            mas_version=$(mas version 2>/dev/null || echo "unknown")
            log_info "mas version: $mas_version"
        else
            log_warning "Failed to install mas"
            log_info "App Store apps will need to be installed manually"
        fi
    fi

    # Check if signed into App Store
    if command -v mas >/dev/null 2>&1; then
        if mas account >/dev/null 2>&1; then
            local account
            account=$(mas account)
            log_info "Signed into App Store as: $account"
        else
            log_warning "Not signed into Mac App Store"
            log_info "Sign into the App Store to install App Store applications automatically"
        fi
    fi
}

# Show installed tools summary
show_tools_summary() {
    log_step "System Tools Installation Summary"

    log_info "Essential tools installed:"

    local tools_to_check=(
        "git"
        "zsh"
        "vim"
        "tmux"
        "curl"
        "wget"
        "jq"
        "tree"
        "htop"
        "universal-ctags"
        "brew"
        "mas"
    )

    for tool in "${tools_to_check[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local tool_path version_info
            tool_path=$(which "$tool")

            case "$tool" in
                git) version_info=$(git --version 2>/dev/null | cut -d' ' -f3) ;;
                vim) version_info=$(vim --version 2>/dev/null | head -n1 | grep -o '[0-9]\+\.[0-9]\+') ;;
                zsh) version_info=$(zsh --version 2>/dev/null | cut -d' ' -f2) ;;
                brew) version_info=$(brew --version 2>/dev/null | head -n1 | cut -d' ' -f2) ;;
                *) version_info="" ;;
            esac

            if [[ -n "$version_info" ]]; then
                log_info "  ✓ $tool ($version_info): $tool_path"
            else
                log_info "  ✓ $tool: $tool_path"
            fi
        else
            log_info "  ✗ $tool: not found"
        fi
    done

    # Show PATH summary
    log_info "Key directories in PATH:"
    echo "$PATH" | tr ':' '\n' | grep -E "(brew|bin|local)" | head -10 | sed 's/^/  /'

    log_success "System tools installation phase completed successfully"
}

# Main execution
main() {
    log_header "Phase 3: System Tools Installation"

    # Skip if dry run
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would install and configure essential system tools"
        return 0
    fi

    # Execute installation steps
    verify_homebrew
    install_essential_tools
    configure_git
    setup_zsh
    install_build_tools
    install_mas
    validate_path
    test_tool_functionality
    show_tools_summary

    log_success "System tools installation phase completed"
}

# Execute main function
main "$@"