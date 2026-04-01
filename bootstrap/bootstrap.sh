#!/bin/bash
#
# Dotfiles Bootstrap Script
# Automated migration and setup for macOS development environment
#
# This script orchestrates the complete setup of a development environment
# based on the thoughtbot dotfiles framework with rcm for symlink management.
#
# Usage:
#   bash ~/dotfiles/bootstrap/bootstrap.sh [options]
#
# Options:
#   -h, --help           Show this help message
#   -v, --verbose        Enable verbose output
#   -d, --debug          Enable debug mode
#   -r, --resume         Resume from last failed/interrupted phase
#   -f, --force          Force fresh start (ignore previous state)
#   -p, --phase PHASE    Run only specific phase (01-09)
#   -l, --list-phases    List all available phases
#   --dry-run            Show what would be done without executing
#   --log-file FILE      Write logs to specified file
#

set -euo pipefail

# Script metadata
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="Dotfiles Bootstrap"
readonly MIN_MACOS_VERSION="11.0"

# Determine script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DOTFILES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly LIB_DIR="$SCRIPT_DIR/lib"
readonly PHASES_DIR="$SCRIPT_DIR/phases"

# Source utility libraries
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/error-handling.sh"

# Global configuration
VERBOSE=${VERBOSE:-false}
DEBUG=${DEBUG:-false}
DRY_RUN=${DRY_RUN:-false}
FORCE_FRESH=${FORCE_FRESH:-false}
RESUME_MODE=${RESUME_MODE:-false}
SPECIFIC_PHASE=""
LOG_FILE=""

# Phase definitions (order matters!)
readonly PHASES=(
    "01-preflight"
    "02-homebrew"
    "03-system-tools"
    "04-dotfiles-setup"
    "05-dev-tools"
    "06-vim-setup"
    "07-app-installs"
    "08-shell-setup"
    "09-postflight"
)

# Phase descriptions
declare -A PHASE_DESCRIPTIONS=(
    ["01-preflight"]="System checks and preparation"
    ["02-homebrew"]="Homebrew installation and packages"
    ["03-system-tools"]="Essential system tools installation"
    ["04-dotfiles-setup"]="Dotfiles cloning and symlink creation"
    ["05-dev-tools"]="Development tools and version managers"
    ["06-vim-setup"]="Vim configuration and plugins"
    ["07-app-installs"]="Applications and extensions"
    ["08-shell-setup"]="Shell configuration and setup"
    ["09-postflight"]="Final verification and cleanup"
)

# Show usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $(basename "$0") [OPTIONS]

DESCRIPTION:
    Automated setup script for macOS development environment using the
    thoughtbot dotfiles framework. Sets up a complete development environment
    with all necessary tools, applications, and configurations.

OPTIONS:
    -h, --help              Show this help message and exit
    -v, --verbose           Enable verbose output (show detailed progress)
    -d, --debug             Enable debug mode (show all commands)
    -r, --resume            Resume from last failed/interrupted phase
    -f, --force             Force fresh start (ignore previous state)
    -p, --phase PHASE       Run only specific phase (01-09)
    -l, --list-phases       List all available phases and exit
    --dry-run              Show what would be done without executing
    --log-file FILE         Write detailed logs to specified file

EXAMPLES:
    # Full automated setup
    $(basename "$0")

    # Resume after interruption
    $(basename "$0") --resume

    # Run only homebrew installation
    $(basename "$0") --phase 02-homebrew

    # Verbose output with logging
    $(basename "$0") --verbose --log-file ~/bootstrap.log

    # Debug mode for troubleshooting
    $(basename "$0") --debug

PHASES:
$(list_phases_formatted)

ENVIRONMENT:
    VERBOSE=true            Same as --verbose
    DEBUG=true              Same as --debug
    DRY_RUN=true           Same as --dry-run
    LOG_FILE=path          Same as --log-file

For more information, see: $DOTFILES_ROOT/docs/MIGRATION.md
EOF
}

# Format phases list for display
list_phases_formatted() {
    for phase in "${PHASES[@]}"; do
        printf "    %-15s %s\n" "$phase" "${PHASE_DESCRIPTIONS[$phase]}"
    done
}

# Show phases list
show_phases() {
    log_header "Available Bootstrap Phases"
    list_phases_formatted
    echo
    log_info "Use --phase PHASE_NAME to run a specific phase"
    log_info "Example: $(basename "$0") --phase 02-homebrew"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                export VERBOSE
                shift
                ;;
            -d|--debug)
                DEBUG=true
                VERBOSE=true
                export DEBUG VERBOSE
                set -x # Enable bash debugging
                shift
                ;;
            -r|--resume)
                RESUME_MODE=true
                shift
                ;;
            -f|--force)
                FORCE_FRESH=true
                shift
                ;;
            -p|--phase)
                if [[ -n "${2:-}" ]]; then
                    SPECIFIC_PHASE="$2"
                    shift 2
                else
                    log_error "Phase argument required for --phase"
                    exit 1
                fi
                ;;
            -l|--list-phases)
                show_phases
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                export DRY_RUN
                shift
                ;;
            --log-file)
                if [[ -n "${2:-}" ]]; then
                    LOG_FILE="$2"
                    export LOG_FILE
                    shift 2
                else
                    log_error "File path required for --log-file"
                    exit 1
                fi
                ;;
            --)
                shift
                break
                ;;
            -*)
                log_error "Unknown option: $1"
                log_info "Use --help for usage information"
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                log_info "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Validate specific phase argument
validate_phase() {
    local phase="$1"

    for valid_phase in "${PHASES[@]}"; do
        if [[ "$phase" == "$valid_phase" ]]; then
            return 0
        fi
    done

    log_error "Invalid phase: $phase"
    log_info "Available phases:"
    list_phases_formatted
    return 1
}

# Check system requirements
check_system_requirements() {
    log_step "Checking system requirements"

    # Check macOS version
    local macos_version
    macos_version=$(sw_vers -productVersion)
    log_debug "macOS version: $macos_version"

    # Simple version comparison (assumes major.minor format)
    if ! version_ge "$macos_version" "$MIN_MACOS_VERSION"; then
        log_error "macOS $MIN_MACOS_VERSION or later is required (found: $macos_version)"
        return 1
    fi

    # Check for required directories
    if [[ ! -d "$PHASES_DIR" ]]; then
        log_error "Phases directory not found: $PHASES_DIR"
        return 1
    fi

    # Check internet connectivity
    if ! ping -c 1 google.com >/dev/null 2>&1 && ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_warning "No internet connectivity detected"
        log_info "Some phases may fail without internet access"

        if ! confirm "Continue without internet connectivity?"; then
            return 1
        fi
    fi

    log_success "System requirements check passed"
}

# Version comparison helper
version_ge() {
    local version1="$1"
    local version2="$2"

    # Convert versions to comparable numbers (e.g., 11.0 -> 1100, 10.15 -> 1015)
    local v1_major v1_minor v2_major v2_minor
    v1_major="${version1%%.*}"
    v1_minor="${version1#*.}"; v1_minor="${v1_minor%%.*}"
    v2_major="${version2%%.*}"
    v2_minor="${version2#*.}"; v2_minor="${v2_minor%%.*}"

    local v1_num=$((v1_major * 100 + v1_minor))
    local v2_num=$((v2_major * 100 + v2_minor))

    [[ $v1_num -ge $v2_num ]]
}

# Execute a bootstrap phase
execute_phase() {
    local phase="$1"
    local phase_script="$PHASES_DIR/${phase}.sh"

    log_debug "Checking for phase script: $phase_script"

    if [[ ! -f "$phase_script" ]]; then
        log_error "Phase script not found: $phase_script"
        return 1
    fi

    if [[ ! -x "$phase_script" ]]; then
        log_debug "Making phase script executable: $phase_script"
        chmod +x "$phase_script"
    fi

    log_header "Phase: $phase - ${PHASE_DESCRIPTIONS[$phase]}"

    # Set current phase in state
    set_current_phase "$phase"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $phase_script"
        return 0
    fi

    # Execute the phase script
    start_spinner "Running phase $phase"

    local start_time end_time duration
    start_time=$(date +%s)

    # Run the phase script with proper environment
    if DOTFILES_ROOT="$DOTFILES_ROOT" bash "$phase_script"; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        stop_spinner
        mark_phase_completed "$phase"
        log_success "Phase $phase completed in ${duration}s"
        return 0
    else
        local exit_code=$?
        stop_spinner
        mark_phase_failed "$phase"
        log_error "Phase $phase failed with exit code $exit_code"
        return $exit_code
    fi
}

# Get phases to run based on mode and state
get_phases_to_run() {
    local phases_to_run=()

    if [[ -n "$SPECIFIC_PHASE" ]]; then
        # Single phase mode
        phases_to_run=("$SPECIFIC_PHASE")
    elif [[ "$RESUME_MODE" == "true" ]]; then
        # Resume mode - skip completed phases
        for phase in "${PHASES[@]}"; do
            if ! is_phase_completed "$phase"; then
                phases_to_run+=("$phase")
            else
                log_debug "Skipping completed phase: $phase"
            fi
        done
    else
        # Normal mode - run all phases
        phases_to_run=("${PHASES[@]}")
    fi

    printf '%s\n' "${phases_to_run[@]}"
}

# Show bootstrap summary
show_bootstrap_summary() {
    local phases_to_run=("$@")

    log_header "Bootstrap Summary"
    log_info "Script Version: $SCRIPT_VERSION"
    log_info "Dotfiles Root: $DOTFILES_ROOT"
    log_info "Mode: $(get_mode_description)"

    if [[ ${#phases_to_run[@]} -gt 0 ]]; then
        log_info "Phases to run:"
        for phase in "${phases_to_run[@]}"; do
            log_info "  $phase - ${PHASE_DESCRIPTIONS[$phase]}"
        done
    else
        log_info "No phases to run"
    fi

    if [[ -n "$LOG_FILE" ]]; then
        log_info "Logging to: $LOG_FILE"
    fi

    echo
}

# Get mode description for summary
get_mode_description() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Dry run (simulation only)"
    elif [[ -n "$SPECIFIC_PHASE" ]]; then
        echo "Single phase ($SPECIFIC_PHASE)"
    elif [[ "$RESUME_MODE" == "true" ]]; then
        echo "Resume from last failure"
    elif [[ "$FORCE_FRESH" == "true" ]]; then
        echo "Fresh start (ignoring previous state)"
    else
        echo "Full bootstrap"
    fi
}

# Main bootstrap execution
main() {
    # Initialize systems
    init_logging
    init_error_handling

    # Parse command line arguments
    parse_arguments "$@"

    # Show banner
    log_header "$SCRIPT_NAME v$SCRIPT_VERSION"
    log_info "Automated macOS development environment setup"
    echo

    # Validate specific phase if provided
    if [[ -n "$SPECIFIC_PHASE" ]]; then
        if ! validate_phase "$SPECIFIC_PHASE"; then
            exit 1
        fi
    fi

    # Handle force fresh start
    if [[ "$FORCE_FRESH" == "true" && "$DRY_RUN" != "true" ]]; then
        log_info "Force fresh start requested - resetting bootstrap state"
        reset_bootstrap_state
    fi

    # Show resume information if applicable
    if [[ "$RESUME_MODE" == "true" ]]; then
        log_info "Resume mode activated"
        get_resume_info
        echo
    fi

    # Check system requirements (skip in dry-run for specific phases)
    if [[ "$DRY_RUN" != "true" || -z "$SPECIFIC_PHASE" ]]; then
        if ! check_system_requirements; then
            log_error "System requirements check failed"
            exit 1
        fi
    fi

    # Get phases to run
    local phases_to_run
    readarray -t phases_to_run < <(get_phases_to_run)

    # Show summary
    show_bootstrap_summary "${phases_to_run[@]}"

    # Confirm execution unless in specific phase mode
    if [[ -z "$SPECIFIC_PHASE" && "$DRY_RUN" != "true" ]]; then
        if ! confirm "Proceed with bootstrap?"; then
            log_info "Bootstrap cancelled by user"
            exit 0
        fi
        echo
    fi

    # Execute phases
    if [[ ${#phases_to_run[@]} -eq 0 ]]; then
        log_info "All phases already completed!"
        log_info "Use --force to run from beginning or --phase to run specific phase"
        exit 0
    fi

    local total_phases=${#phases_to_run[@]}
    local current_phase_num=0
    local failed_phases=()

    log_info "Starting bootstrap execution..."
    echo

    for phase in "${phases_to_run[@]}"; do
        current_phase_num=$((current_phase_num + 1))

        # Show progress
        show_progress "$current_phase_num" "$total_phases" "Phase: $phase"

        # Execute phase
        if ! execute_phase "$phase"; then
            failed_phases+=("$phase")

            # In single phase mode, exit immediately
            if [[ -n "$SPECIFIC_PHASE" ]]; then
                exit 1
            fi

            # Ask user what to do
            echo
            log_error "Phase $phase failed"

            if confirm "Continue with remaining phases?"; then
                log_info "Continuing with next phase..."
                continue
            else
                log_info "Bootstrap stopped by user"
                break
            fi
        fi

        echo
    done

    # Show final results
    log_header "Bootstrap Results"

    local successful_phases=$((current_phase_num - ${#failed_phases[@]}))
    log_info "Phases completed: $successful_phases/$current_phase_num"

    if [[ ${#failed_phases[@]} -eq 0 ]]; then
        log_success "All phases completed successfully!"

        if [[ "$DRY_RUN" != "true" ]]; then
            log_info "Your development environment is ready!"
            log_info "Open a new terminal to use the new configuration"

            if [[ -f "$DOTFILES_ROOT/docs/MIGRATION.md" ]]; then
                log_info "See $DOTFILES_ROOT/docs/MIGRATION.md for next steps"
            fi
        fi
    else
        log_warning "Some phases failed:"
        for phase in "${failed_phases[@]}"; do
            log_warning "  $phase - ${PHASE_DESCRIPTIONS[$phase]}"
        done

        log_info "You can resume the bootstrap with: $(basename "$0") --resume"
        log_info "Or run individual phases with: $(basename "$0") --phase PHASE_NAME"

        exit 1
    fi
}

# Execute main function with all arguments
main "$@"