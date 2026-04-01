#!/bin/bash
#
# Bootstrap Phase 5: Development Tools Installation
# Installs and configures development tools and version managers
#

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/error-handling.sh"

# Configuration
readonly VERSIONS_FILE="${DOTFILES_ROOT}/manifests/versions.txt"
readonly ASDF_DIR="${ASDF_DIR:-$HOME/.asdf}"
readonly ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"

# Verify asdf is installed
verify_asdf() {
    log_step "Verifying asdf installation"

    if ! command -v asdf >/dev/null 2>&1; then
        # Try to source asdf if it's installed via Homebrew
        local homebrew_prefix
        homebrew_prefix=$(brew --prefix 2>/dev/null || echo "")

        if [[ -n "$homebrew_prefix" && -f "$homebrew_prefix/opt/asdf/libexec/asdf.sh" ]]; then
            source "$homebrew_prefix/opt/asdf/libexec/asdf.sh"
            log_info "Sourced asdf from Homebrew installation"
        elif [[ -f "$ASDF_DIR/asdf.sh" ]]; then
            source "$ASDF_DIR/asdf.sh"
            log_info "Sourced asdf from $ASDF_DIR"
        else
            log_error "asdf not found. It should have been installed in the Homebrew phase"
            log_info "Install asdf manually: brew install asdf"
            return 1
        fi
    fi

    local asdf_version
    asdf_version=$(asdf --version 2>/dev/null || echo "unknown")
    log_success "asdf is available: $asdf_version"

    # Show asdf info
    log_info "asdf installation directory: $(asdf where asdf 2>/dev/null || echo 'unknown')"
}

# Install asdf plugins
install_asdf_plugins() {
    log_step "Installing asdf plugins"

    # Define plugins to install
    local plugins=(
        "nodejs"
        "python"
        "ruby"
        "golang"
        "rust"
        "java"
        "terraform"
        "kubectl"
        "helm"
    )

    local installed_plugins failed_plugins
    installed_plugins=()
    failed_plugins=()

    log_info "Installing asdf plugins for language management..."

    for plugin in "${plugins[@]}"; do
        log_info "Installing asdf plugin: $plugin"

        if asdf plugin list | grep -q "^$plugin$"; then
            log_debug "✓ $plugin plugin already installed"
            installed_plugins+=("$plugin")
        elif asdf plugin add "$plugin" 2>/dev/null; then
            log_debug "✓ $plugin plugin installed successfully"
            installed_plugins+=("$plugin")
        else
            log_warning "✗ Failed to install $plugin plugin"
            failed_plugins+=("$plugin")
        fi
    done

    log_info "Plugin installation summary:"
    log_info "  Installed: ${#installed_plugins[@]} plugins"

    if [[ ${#failed_plugins[@]} -gt 0 ]]; then
        log_warning "  Failed: ${failed_plugins[*]}"
        log_info "Failed plugins can be installed manually later"
    fi

    # Special setup for Node.js plugin
    if printf '%s\n' "${installed_plugins[@]}" | grep -q "nodejs"; then
        log_info "Importing Node.js release team keyring..."
        if bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-release-team-keyring' 2>/dev/null; then
            log_debug "✓ Node.js keyring imported"
        else
            log_warning "! Node.js keyring import failed (may not affect installation)"
        fi
    fi

    log_success "asdf plugin installation completed"
}

# Parse versions file
parse_versions_file() {
    local tool="$1"

    if [[ ! -f "$VERSIONS_FILE" ]]; then
        log_warning "Versions file not found: $VERSIONS_FILE"
        return 1
    fi

    # Extract version for the given tool (ignore comments and empty lines)
    grep "^$tool " "$VERSIONS_FILE" 2>/dev/null | head -n1 | cut -d' ' -f2- || echo ""
}

# Install tool versions from versions file
install_tool_versions() {
    log_step "Installing tool versions from manifest"

    if [[ ! -f "$VERSIONS_FILE" ]]; then
        log_warning "Versions file not found: $VERSIONS_FILE"
        log_info "Skipping version installations"
        return 0
    fi

    log_info "Installing tools and versions from: $VERSIONS_FILE"

    # Read tools and versions from file
    local tools_installed=0
    local tools_failed=0

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue

        # Parse tool and version
        local tool version
        tool=$(echo "$line" | cut -d' ' -f1)
        version=$(echo "$line" | cut -d' ' -f2-)

        # Skip if tool is not available via asdf
        if ! asdf plugin list | grep -q "^$tool$"; then
            log_debug "Skipping $tool (plugin not installed)"
            continue
        fi

        log_info "Installing $tool $version..."

        # Check if already installed
        if asdf list "$tool" 2>/dev/null | grep -q "$version"; then
            log_debug "✓ $tool $version already installed"
            tools_installed=$((tools_installed + 1))
            continue
        fi

        # Install the version
        if asdf install "$tool" "$version"; then
            log_debug "✓ $tool $version installed successfully"
            tools_installed=$((tools_installed + 1))
        else
            log_warning "✗ Failed to install $tool $version"
            tools_failed=$((tools_failed + 1))
        fi

    done < "$VERSIONS_FILE"

    log_info "Tool installation summary:"
    log_info "  Successful: $tools_installed"

    if [[ $tools_failed -gt 0 ]]; then
        log_warning "  Failed: $tools_failed"
        log_info "Failed installations can be retried manually"
    fi

    log_success "Tool versions installation completed"
}

# Set global default versions
set_global_versions() {
    log_step "Setting global default versions"

    # Define default global versions (latest stable of each)
    local global_versions=(
        "nodejs $(parse_versions_file nodejs | head -n1)"
        "python $(parse_versions_file python | head -n1)"
        "ruby $(parse_versions_file ruby | head -n1)"
        "golang $(parse_versions_file golang | head -n1)"
    )

    local globals_set=0
    local globals_failed=0

    for global_spec in "${global_versions[@]}"; do
        local tool version
        tool=$(echo "$global_spec" | cut -d' ' -f1)
        version=$(echo "$global_spec" | cut -d' ' -f2-)

        # Skip if empty version
        [[ -z "$version" ]] && continue

        # Skip if tool plugin not available
        if ! asdf plugin list | grep -q "^$tool$"; then
            log_debug "Skipping global $tool (plugin not available)"
            continue
        fi

        # Skip if version not installed
        if ! asdf list "$tool" 2>/dev/null | grep -q "$version"; then
            log_debug "Skipping global $tool $version (version not installed)"
            continue
        fi

        log_info "Setting global $tool version to $version"

        if asdf global "$tool" "$version"; then
            log_debug "✓ Global $tool version set to $version"
            globals_set=$((globals_set + 1))
        else
            log_warning "✗ Failed to set global $tool version"
            globals_failed=$((globals_failed + 1))
        fi
    done

    log_info "Global versions summary:"
    log_info "  Set: $globals_set"

    if [[ $globals_failed -gt 0 ]]; then
        log_warning "  Failed: $globals_failed"
    fi

    log_success "Global versions configuration completed"
}

# Install global npm packages
install_global_npm_packages() {
    log_step "Installing global npm packages"

    local npm_manifest="${DOTFILES_ROOT}/manifests/npm-global.txt"

    if [[ ! -f "$npm_manifest" ]]; then
        log_warning "npm global packages manifest not found: $npm_manifest"
        return 0
    fi

    # Check if Node.js/npm is available
    if ! command -v npm >/dev/null 2>&1; then
        # Try to reshim asdf to make node/npm available
        if command -v asdf >/dev/null 2>&1; then
            asdf reshim nodejs 2>/dev/null || true
        fi

        if ! command -v npm >/dev/null 2>&1; then
            log_warning "npm not available, skipping global package installation"
            return 0
        fi
    fi

    local npm_version node_version
    npm_version=$(npm --version 2>/dev/null || echo "unknown")
    node_version=$(node --version 2>/dev/null || echo "unknown")

    log_info "Node.js version: $node_version"
    log_info "npm version: $npm_version"
    log_info "Installing global npm packages from: $npm_manifest"

    # Read packages from manifest (skip comments)
    local packages_to_install=()
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue

        # Extract package name (first word)
        local package_name
        package_name=$(echo "$line" | awk '{print $1}')
        [[ -n "$package_name" ]] && packages_to_install+=("$package_name")
    done < "$npm_manifest"

    if [[ ${#packages_to_install[@]} -eq 0 ]]; then
        log_info "No npm packages to install"
        return 0
    fi

    log_info "Installing ${#packages_to_install[@]} global npm packages..."

    local installed_count=0
    local failed_count=0

    for package in "${packages_to_install[@]}"; do
        log_info "Installing npm package: $package"

        if npm install -g "$package" >/dev/null 2>&1; then
            log_debug "✓ $package installed successfully"
            installed_count=$((installed_count + 1))
        else
            log_warning "✗ Failed to install $package"
            failed_count=$((failed_count + 1))
        fi
    done

    log_info "Global npm packages summary:"
    log_info "  Installed: $installed_count"

    if [[ $failed_count -gt 0 ]]; then
        log_warning "  Failed: $failed_count"
        log_info "Failed packages can be installed manually with: npm install -g PACKAGE"
    fi

    # Refresh asdf shims for newly installed packages
    if command -v asdf >/dev/null 2>&1; then
        asdf reshim nodejs 2>/dev/null || true
        log_debug "Refreshed asdf shims for Node.js"
    fi

    log_success "Global npm packages installation completed"
}

# Verify development tools installation
verify_dev_tools() {
    log_step "Verifying development tools installation"

    # Test asdf managed tools
    local tools_to_test=("node" "python3" "ruby" "go")
    local available_tools=()
    local missing_tools=()

    for tool in "${tools_to_test[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local tool_path version_info
            tool_path=$(which "$tool")

            case "$tool" in
                node) version_info=$(node --version 2>/dev/null) ;;
                python3) version_info=$(python3 --version 2>/dev/null | cut -d' ' -f2) ;;
                ruby) version_info=$(ruby --version 2>/dev/null | cut -d' ' -f2) ;;
                go) version_info=$(go version 2>/dev/null | cut -d' ' -f3 | sed 's/go//') ;;
                *) version_info="" ;;
            esac

            available_tools+=("$tool")
            log_debug "✓ $tool: $tool_path ($version_info)"
        else
            missing_tools+=("$tool")
            log_warning "✗ $tool: not found in PATH"
        fi
    done

    # Test package managers
    local package_managers=("npm" "pip3" "gem" "cargo")
    for pm in "${package_managers[@]}"; do
        if command -v "$pm" >/dev/null 2>&1; then
            log_debug "✓ $pm: $(which "$pm")"
        else
            log_debug "! $pm: not available"
        fi
    done

    # Show current tool versions managed by asdf
    if command -v asdf >/dev/null 2>&1; then
        log_info "Current asdf tool versions:"
        asdf current 2>/dev/null | sed 's/^/  /' || log_debug "No asdf versions set"
    fi

    log_info "Development tools verification summary:"
    log_info "  Available: ${available_tools[*]}"

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warning "  Missing: ${missing_tools[*]}"
        log_info "Missing tools may be available after shell restart"
    fi

    log_success "Development tools verification completed"
}

# Show development environment summary
show_dev_summary() {
    log_step "Development Tools Installation Summary"

    # Show asdf info
    if command -v asdf >/dev/null 2>&1; then
        log_info "asdf version: $(asdf --version 2>/dev/null)"

        log_info "Installed asdf plugins:"
        asdf plugin list | sed 's/^/  /' 2>/dev/null || log_info "  No plugins installed"

        log_info "Tool versions in use:"
        asdf current | sed 's/^/  /' 2>/dev/null || log_info "  No versions set"
    fi

    # Show key development tools
    log_info "Development environment ready:"

    local dev_tools=("node" "npm" "python3" "pip3" "ruby" "gem" "go" "rust" "cargo")
    for tool in "${dev_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version_info
            case "$tool" in
                node) version_info=$(node --version 2>/dev/null) ;;
                npm) version_info="v$(npm --version 2>/dev/null)" ;;
                python3) version_info="v$(python3 --version 2>/dev/null | cut -d' ' -f2)" ;;
                pip3) version_info="v$(pip3 --version 2>/dev/null | cut -d' ' -f2)" ;;
                ruby) version_info="v$(ruby --version 2>/dev/null | cut -d' ' -f2)" ;;
                gem) version_info="v$(gem --version 2>/dev/null)" ;;
                go) version_info=$(go version 2>/dev/null | cut -d' ' -f3) ;;
                rust) version_info=$(rustc --version 2>/dev/null | cut -d' ' -f2) ;;
                cargo) version_info="v$(cargo --version 2>/dev/null | cut -d' ' -f2)" ;;
                *) version_info="" ;;
            esac

            log_info "  ✓ $tool ${version_info}"
        fi
    done

    log_success "Development tools installation phase completed successfully"
}

# Main execution
main() {
    log_header "Phase 5: Development Tools Installation"

    # Skip if dry run
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would install development tools and version managers"
        return 0
    fi

    # Execute installation steps
    verify_asdf
    install_asdf_plugins
    install_tool_versions
    set_global_versions
    install_global_npm_packages
    verify_dev_tools
    show_dev_summary

    log_success "Development tools installation phase completed"
}

# Execute main function
main "$@"