#!/bin/bash
#
# Bootstrap Phase 4: Dotfiles Setup
# Sets up dotfiles repository with rcm symlink management
#

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/error-handling.sh"

# Configuration
readonly DOTFILES_TARGET_DIR="$HOME/dotfiles"
readonly DOTFILES_LOCAL_DIR="$HOME/dotfiles-local"
readonly RCRC_FILE="$HOME/.rcrc"

# Verify RCM is installed
verify_rcm() {
    log_step "Verifying RCM installation"

    if ! command -v rcup >/dev/null 2>&1; then
        log_error "RCM not found. It should have been installed in the Homebrew phase"
        log_info "Install RCM manually: brew install rcm"
        return 1
    fi

    local rcm_version
    rcm_version=$(rcup -h 2>&1 | head -n1 || echo "unknown version")
    log_success "RCM is installed: $rcm_version"
}

# Check if we're already running from the target dotfiles directory
check_current_location() {
    log_step "Checking current dotfiles location"

    local current_dir
    current_dir="$(cd "$DOTFILES_ROOT" && pwd)"
    local target_dir
    target_dir="$(cd "$(dirname "$DOTFILES_TARGET_DIR")" && pwd)/$(basename "$DOTFILES_TARGET_DIR")" 2>/dev/null || echo "$DOTFILES_TARGET_DIR"

    log_debug "Current location: $current_dir"
    log_debug "Target location: $target_dir"

    if [[ "$current_dir" == "$target_dir" ]]; then
        log_info "Already running from target dotfiles directory"
        return 0
    else
        log_info "Running from: $current_dir"
        log_info "Will set up at: $target_dir"
        return 1
    fi
}

# Setup dotfiles repository
setup_dotfiles_repo() {
    log_step "Setting up dotfiles repository"

    if check_current_location; then
        log_info "Using existing dotfiles repository at: $DOTFILES_ROOT"

        # Ensure we're in a git repository
        if [[ ! -d "$DOTFILES_ROOT/.git" ]]; then
            log_warning "Current dotfiles directory is not a git repository"
            log_info "This may be expected for some setups"
        else
            # Check for updates if we're in a git repo
            log_info "Checking for dotfiles updates..."

            cd "$DOTFILES_ROOT"

            # Fetch latest changes
            if git fetch --quiet 2>/dev/null; then
                local local_commit remote_commit
                local_commit=$(git rev-parse HEAD 2>/dev/null)
                remote_commit=$(git rev-parse @{u} 2>/dev/null || echo "$local_commit")

                if [[ "$local_commit" != "$remote_commit" ]]; then
                    log_info "Updates available in remote repository"

                    if confirm "Pull latest dotfiles updates?" "y"; then
                        if git pull --quiet; then
                            log_success "Dotfiles updated successfully"
                        else
                            log_warning "Failed to update dotfiles, continuing with current version"
                        fi
                    fi
                else
                    log_info "Dotfiles are up to date"
                fi
            else
                log_debug "Unable to check for updates (no remote or network issue)"
            fi
        fi

        return 0
    fi

    # We need to set up the dotfiles in the target location
    if [[ -d "$DOTFILES_TARGET_DIR" ]]; then
        log_warning "Target dotfiles directory already exists: $DOTFILES_TARGET_DIR"

        if [[ -d "$DOTFILES_TARGET_DIR/.git" ]]; then
            log_info "Existing directory appears to be a git repository"

            if confirm "Update existing dotfiles repository?"; then
                cd "$DOTFILES_TARGET_DIR"
                if git fetch && git pull; then
                    log_success "Existing dotfiles repository updated"
                else
                    log_warning "Failed to update existing repository, continuing anyway"
                fi
            fi
        else
            if confirm "Move existing directory and replace with fresh clone?"; then
                backup_file "$DOTFILES_TARGET_DIR" "dotfiles-backup"
                rm -rf "$DOTFILES_TARGET_DIR"
                clone_dotfiles_repo
            fi
        fi
    else
        clone_dotfiles_repo
    fi
}

# Clone dotfiles repository
clone_dotfiles_repo() {
    log_info "Cloning dotfiles repository..."

    # If we're running this bootstrap, we must have the repo somewhere
    # Copy from current location to target location
    log_info "Copying dotfiles from $DOTFILES_ROOT to $DOTFILES_TARGET_DIR"

    if cp -R "$DOTFILES_ROOT" "$DOTFILES_TARGET_DIR"; then
        log_success "Dotfiles repository copied successfully"
    else
        log_error "Failed to copy dotfiles repository"
        return 1
    fi
}

# Setup local dotfiles directory
setup_dotfiles_local() {
    log_step "Setting up local dotfiles directory"

    if [[ -d "$DOTFILES_LOCAL_DIR" ]]; then
        log_info "Local dotfiles directory already exists: $DOTFILES_LOCAL_DIR"
        return 0
    fi

    log_info "Creating local dotfiles directory: $DOTFILES_LOCAL_DIR"
    mkdir -p "$DOTFILES_LOCAL_DIR"

    # Create a basic README for the local directory
    cat > "$DOTFILES_LOCAL_DIR/README.md" << 'EOF'
# Local Dotfiles

This directory contains your personal dotfiles that override or extend the main dotfiles.

## Usage

- Add files here to override main dotfiles (e.g., `zshrc.local`)
- Create directories to mirror the main dotfiles structure
- All `*.local` files are automatically sourced by the main dotfiles

## Examples

- `zshrc.local` - Additional zsh configuration
- `gitconfig.local` - Personal git configuration
- `bin/` - Personal scripts that will be added to PATH

## Security

This directory is intended for your personal, private configuration.
Never commit sensitive information like passwords or API keys.
EOF

    log_success "Local dotfiles directory created"
}

# Backup existing dotfiles
backup_existing_dotfiles() {
    log_step "Backing up existing dotfiles"

    local files_to_backup=(
        "$HOME/.zshrc"
        "$HOME/.zshenv"
        "$HOME/.vimrc"
        "$HOME/.gitconfig"
        "$HOME/.tmux.conf"
    )

    local backed_up_files=()

    for file in "${files_to_backup[@]}"; do
        if [[ -f "$file" && ! -L "$file" ]]; then
            log_info "Backing up existing file: $file"
            if backup_file "$file"; then
                backed_up_files+=("$file")
            fi
        fi
    done

    if [[ ${#backed_up_files[@]} -gt 0 ]]; then
        log_success "Backed up ${#backed_up_files[@]} existing dotfiles"
        log_info "Backups are stored in: $(dirname "$(get_state_field "backups" | head -n1)" 2>/dev/null || echo "$HOME/.cache/dotfiles-bootstrap/backups")"
    else
        log_info "No existing dotfiles to backup"
    fi
}

# Setup rcrc configuration
setup_rcrc() {
    log_step "Setting up RCM configuration"

    local target_dotfiles_dir="$DOTFILES_TARGET_DIR"

    # If we're running from the same location, use current location
    if check_current_location; then
        target_dotfiles_dir="$DOTFILES_ROOT"
    fi

    # Check if rcrc already exists and has correct configuration
    if [[ -f "$RCRC_FILE" ]]; then
        log_info "Existing .rcrc file found"

        # Check if it points to our dotfiles directory
        if grep -q "$target_dotfiles_dir" "$RCRC_FILE" 2>/dev/null; then
            log_info "rcrc already configured correctly"
            return 0
        else
            log_warning "rcrc exists but doesn't point to our dotfiles directory"
            backup_file "$RCRC_FILE" "rcrc-backup"
        fi
    fi

    log_info "Creating .rcrc configuration file"

    # Create rcrc configuration
    # Note: The main dotfiles repo already has an rcrc file, but we need to ensure
    # the HOME/.rcrc points to the right dotfiles directory
    cat > "$RCRC_FILE" << EOF
DOTFILES_DIRS="$DOTFILES_LOCAL_DIR $target_dotfiles_dir"
EXCLUDES="README*.md LICENSE bootstrap manifests docs templates"
COPY_ALWAYS="git_template/HEAD"
EOF

    log_success "RCM configuration created at: $RCRC_FILE"
}

# Run rcup to create symlinks
run_rcup() {
    log_step "Creating dotfiles symlinks with rcup"

    log_info "Running rcup to create symlinks..."
    log_info "This will create symlinks from your home directory to the dotfiles"

    # Run rcup with verbose output if debug mode is enabled
    local rcup_args=()

    if [[ "${DEBUG:-false}" == "true" ]]; then
        rcup_args+=("-v")
    fi

    if ! rcup "${rcup_args[@]}"; then
        log_error "rcup failed to create symlinks"
        return 1
    fi

    log_success "Dotfiles symlinks created successfully"
}

# Verify symlinks were created correctly
verify_symlinks() {
    log_step "Verifying dotfiles symlinks"

    local expected_links=(
        "$HOME/.zshrc"
        "$HOME/.zshenv"
        "$HOME/.vimrc"
        "$HOME/.gitconfig"
        "$HOME/.aliases"
    )

    local missing_links=()
    local broken_links=()
    local correct_links=()

    for link in "${expected_links[@]}"; do
        if [[ -L "$link" ]]; then
            if [[ -e "$link" ]]; then
                correct_links+=("$link")
                log_debug "✓ $link -> $(readlink "$link")"
            else
                broken_links+=("$link")
                log_warning "✗ $link -> $(readlink "$link") (broken)"
            fi
        elif [[ -e "$link" ]]; then
            log_warning "! $link exists but is not a symlink"
        else
            missing_links+=("$link")
            log_debug "✗ $link (missing)"
        fi
    done

    # Report results
    log_info "Symlink verification results:"
    log_info "  Correct symlinks: ${#correct_links[@]}"

    if [[ ${#missing_links[@]} -gt 0 ]]; then
        log_warning "  Missing symlinks: ${#missing_links[@]}"
    fi

    if [[ ${#broken_links[@]} -gt 0 ]]; then
        log_error "  Broken symlinks: ${#broken_links[@]}"
        return 1
    fi

    # Check for .git_template directory
    if [[ -L "$HOME/.git_template" ]]; then
        log_debug "✓ Git template directory symlink exists"
    else
        log_warning "Git template directory symlink missing"
    fi

    log_success "Dotfiles symlink verification completed"
}

# Run post-up hooks
run_post_up_hooks() {
    log_step "Running post-up hooks"

    local target_dotfiles_dir="$DOTFILES_TARGET_DIR"

    # If we're running from the same location, use current location
    if check_current_location; then
        target_dotfiles_dir="$DOTFILES_ROOT"
    fi

    local post_up_hook="$target_dotfiles_dir/hooks/post-up"

    if [[ -f "$post_up_hook" ]]; then
        log_info "Executing post-up hook: $post_up_hook"

        if bash "$post_up_hook"; then
            log_success "Post-up hook executed successfully"
        else
            log_warning "Post-up hook had some issues, continuing anyway"
        fi
    else
        log_info "No post-up hook found, skipping"
    fi
}

# Show dotfiles setup summary
show_summary() {
    log_step "Dotfiles Setup Summary"

    local target_dotfiles_dir="$DOTFILES_TARGET_DIR"
    if check_current_location; then
        target_dotfiles_dir="$DOTFILES_ROOT"
    fi

    log_info "Dotfiles directory: $target_dotfiles_dir"
    log_info "Local overrides: $DOTFILES_LOCAL_DIR"
    log_info "RCM configuration: $RCRC_FILE"

    # Show some key symlinks
    log_info "Key configuration files:"
    for file in .zshrc .vimrc .gitconfig; do
        if [[ -L "$HOME/$file" ]]; then
            log_info "  $file -> $(readlink "$HOME/$file")"
        fi
    done

    log_success "Dotfiles setup phase completed successfully"
}

# Main execution
main() {
    log_header "Phase 4: Dotfiles Setup"

    # Skip if dry run
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would set up dotfiles repository and create symlinks"
        return 0
    fi

    # Execute setup steps
    verify_rcm
    setup_dotfiles_local
    backup_existing_dotfiles
    setup_dotfiles_repo
    setup_rcrc
    run_rcup
    verify_symlinks
    run_post_up_hooks
    show_summary

    log_success "Dotfiles setup phase completed"
}

# Execute main function
main "$@"