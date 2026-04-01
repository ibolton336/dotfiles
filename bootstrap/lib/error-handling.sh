#!/bin/bash
#
# Error handling and recovery utilities for dotfiles bootstrap
# Provides robust error handling, state persistence, and resume capability
#

# Prevent multiple sourcing
[[ -n "${_ERROR_HANDLING_SOURCED:-}" ]] && return 0
readonly _ERROR_HANDLING_SOURCED=1

# Source logging utilities if available
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/logging.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
else
    # Fallback logging functions if logging.sh not available
    log_error() { echo "ERROR: $*" >&2; }
    log_info() { echo "INFO: $*"; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "DEBUG: $*"; }
fi

# Global variables for error handling
readonly STATE_DIR="${HOME}/.cache/dotfiles-bootstrap"
readonly STATE_FILE="${STATE_DIR}/bootstrap-state.json"
readonly BACKUP_DIR="${STATE_DIR}/backups"
readonly LOCK_FILE="${STATE_DIR}/bootstrap.lock"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_COMMAND_NOT_FOUND=127
readonly EXIT_USER_ABORT=130
readonly EXIT_DEPENDENCY_ERROR=2
readonly EXIT_PERMISSION_ERROR=3
readonly EXIT_NETWORK_ERROR=4
readonly EXIT_DISK_SPACE_ERROR=5

# Initialize error handling system
init_error_handling() {
    # Create state directory
    mkdir -p "$STATE_DIR" "$BACKUP_DIR"

    # Set up error traps
    set -eE # Exit on any error, including in functions and subshells
    trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR
    trap 'handle_interrupt' INT TERM
    trap 'cleanup_on_exit' EXIT

    # Create lock file to prevent concurrent runs
    if ! create_lock_file; then
        log_error "Another bootstrap process is already running"
        log_info "If you're sure no other process is running, remove: $LOCK_FILE"
        exit 1
    fi

    # Initialize state if it doesn't exist
    init_state_file
}

# Create lock file with PID
create_lock_file() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")

        # Check if the process is still running
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            return 1 # Lock file exists and process is running
        else
            # Stale lock file, remove it
            rm -f "$LOCK_FILE"
        fi
    fi

    echo $$ > "$LOCK_FILE"
    return 0
}

# Remove lock file
remove_lock_file() {
    [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE"
}

# Initialize state file with default structure
init_state_file() {
    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" << 'EOF'
{
  "bootstrap_version": "1.0.0",
  "start_time": "",
  "last_update": "",
  "current_phase": "",
  "completed_phases": [],
  "failed_phases": [],
  "environment": {
    "os": "",
    "shell": "",
    "user": ""
  },
  "resume_data": {},
  "backups": []
}
EOF
    fi

    # Update environment info
    update_state_field "environment.os" "$(uname -s)"
    update_state_field "environment.shell" "$SHELL"
    update_state_field "environment.user" "$USER"
    update_state_field "last_update" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Set start time if not already set
    local start_time
    start_time=$(get_state_field "start_time")
    if [[ -z "$start_time" || "$start_time" == "null" ]]; then
        update_state_field "start_time" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    fi
}

# Get a field from the state file using jq
get_state_field() {
    local field="$1"
    if [[ -f "$STATE_FILE" ]] && command -v jq >/dev/null 2>&1; then
        jq -r ".$field // empty" "$STATE_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Update a field in the state file using jq
update_state_field() {
    local field="$1"
    local value="$2"

    if command -v jq >/dev/null 2>&1 && [[ -f "$STATE_FILE" ]]; then
        local temp_file
        temp_file=$(mktemp)
        if jq ".$field = \"$value\"" "$STATE_FILE" > "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$STATE_FILE" || rm -f "$temp_file"
            # Avoid recursion when updating last_update
            if [[ "$field" != "last_update" ]]; then
                update_state_field "last_update" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            fi
        else
            rm -f "$temp_file"
        fi
    else
        log_debug "jq not available or state file missing, skipping state update for $field"
    fi
}

# Add a value to an array in the state file
add_to_state_array() {
    local array_field="$1"
    local value="$2"

    if command -v jq >/dev/null 2>&1 && [[ -f "$STATE_FILE" ]]; then
        local temp_file
        temp_file=$(mktemp)
        if jq ".$array_field += [\"$value\"] | .$array_field |= unique" "$STATE_FILE" > "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$STATE_FILE" || rm -f "$temp_file"
            update_state_field "last_update" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        else
            rm -f "$temp_file"
        fi
    else
        log_debug "jq not available or state file missing, skipping array update for $array_field"
    fi
}

# Check if a phase has been completed
is_phase_completed() {
    local phase="$1"
    local completed_phases
    completed_phases=$(get_state_field "completed_phases")

    if [[ -n "$completed_phases" ]] && command -v jq >/dev/null 2>&1; then
        echo "$completed_phases" | jq -r '.[]' | grep -q "^$phase$"
    else
        return 1
    fi
}

# Mark a phase as completed
mark_phase_completed() {
    local phase="$1"
    log_debug "Marking phase '$phase' as completed"
    add_to_state_array "completed_phases" "$phase"
    update_state_field "current_phase" ""
}

# Mark a phase as failed
mark_phase_failed() {
    local phase="$1"
    log_debug "Marking phase '$phase' as failed"
    add_to_state_array "failed_phases" "$phase"
    update_state_field "current_phase" ""
}

# Set current phase
set_current_phase() {
    local phase="$1"
    log_debug "Setting current phase to '$phase'"
    update_state_field "current_phase" "$phase"
}

# Main error handler
handle_error() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"
    local current_phase
    current_phase=$(get_state_field "current_phase")

    # Stop any running spinners
    stop_spinner 2>/dev/null || true

    log_error "Command failed with exit code $exit_code"
    log_error "Failed command: $command"
    log_error "Line number: $line_number"

    if [[ -n "$current_phase" ]]; then
        log_error "Current phase: $current_phase"
        mark_phase_failed "$current_phase"
    fi

    # Create error report
    create_error_report "$exit_code" "$line_number" "$command" "$current_phase"

    # Offer recovery options
    offer_recovery_options "$exit_code"

    # Don't exit automatically; let the main script handle it
    return $exit_code
}

# Handle interrupt signals (Ctrl+C)
handle_interrupt() {
    local current_phase
    current_phase=$(get_state_field "current_phase")

    stop_spinner 2>/dev/null || true

    log_info ""
    log_warning "Bootstrap process interrupted by user"

    if [[ -n "$current_phase" ]]; then
        log_info "Current phase '$current_phase' was interrupted"
        log_info "You can resume from this point by running the bootstrap script again"
    fi

    cleanup_on_exit
    exit $EXIT_USER_ABORT
}

# Cleanup on exit
cleanup_on_exit() {
    stop_spinner 2>/dev/null || true
    remove_lock_file
    log_debug "Cleanup completed"
}

# Create detailed error report
create_error_report() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"
    local current_phase="$4"

    local error_report="${STATE_DIR}/error-report-$(date +%Y%m%d_%H%M%S).log"

    cat > "$error_report" << EOF
Bootstrap Error Report
======================

Timestamp: $(date)
Exit Code: $exit_code
Line Number: $line_number
Failed Command: $command
Current Phase: ${current_phase:-"none"}

Environment:
- OS: $(uname -a)
- Shell: $SHELL ($BASH_VERSION)
- User: $USER
- PWD: $PWD
- PATH: $PATH

Recent Commands:
$(history | tail -10)

State Information:
$(cat "$STATE_FILE" 2>/dev/null || echo "State file not available")

System Information:
$(sw_vers 2>/dev/null || echo "System version not available")
$(df -h / 2>/dev/null || echo "Disk space not available")
$(free -m 2>/dev/null || echo "Memory info not available")

EOF

    log_info "Error report saved to: $error_report"
}

# Offer recovery options to the user
offer_recovery_options() {
    local exit_code="$1"

    echo
    log_info "Recovery Options:"
    log_info "1. Resume bootstrap (will skip completed phases)"
    log_info "2. Restart from beginning"
    log_info "3. Exit and troubleshoot manually"
    echo

    # Provide specific guidance based on exit code
    case $exit_code in
        $EXIT_COMMAND_NOT_FOUND)
            log_warning "A required command was not found. You may need to:"
            log_info "  - Install missing dependencies manually"
            log_info "  - Check your PATH configuration"
            ;;
        $EXIT_NETWORK_ERROR)
            log_warning "Network error detected. You may need to:"
            log_info "  - Check your internet connection"
            log_info "  - Configure proxy settings if needed"
            log_info "  - Try again later if servers are temporarily unavailable"
            ;;
        $EXIT_PERMISSION_ERROR)
            log_warning "Permission error detected. You may need to:"
            log_info "  - Run with appropriate permissions"
            log_info "  - Check file ownership and permissions"
            log_info "  - Ensure you have write access to target directories"
            ;;
        $EXIT_DISK_SPACE_ERROR)
            log_warning "Disk space error detected. You may need to:"
            log_info "  - Free up disk space"
            log_info "  - Clean temporary files"
            log_info "  - Move large files to external storage"
            ;;
    esac
}

# Backup a file or directory
backup_file() {
    local source="$1"
    local backup_name="${2:-$(basename "$source")}"

    if [[ ! -e "$source" ]]; then
        log_debug "Skipping backup of non-existent file: $source"
        return 0
    fi

    local backup_path="${BACKUP_DIR}/${backup_name}-$(date +%Y%m%d_%H%M%S)"

    if cp -R "$source" "$backup_path" 2>/dev/null; then
        log_debug "Backed up '$source' to '$backup_path'"
        add_to_state_array "backups" "$backup_path"
        return 0
    else
        log_warning "Failed to backup '$source'"
        return 1
    fi
}

# Restore a backup
restore_backup() {
    local backup_path="$1"
    local restore_path="$2"

    if [[ ! -e "$backup_path" ]]; then
        log_error "Backup file not found: $backup_path"
        return 1
    fi

    if cp -R "$backup_path" "$restore_path" 2>/dev/null; then
        log_info "Restored backup from '$backup_path' to '$restore_path'"
        return 0
    else
        log_error "Failed to restore backup from '$backup_path'"
        return 1
    fi
}

# List all available backups
list_backups() {
    local backups
    backups=$(get_state_field "backups")

    if [[ -n "$backups" ]] && command -v jq >/dev/null 2>&1; then
        echo "$backups" | jq -r '.[]' | while read -r backup; do
            if [[ -e "$backup" ]]; then
                log_info "Available backup: $backup"
            fi
        done
    else
        log_info "No backups found"
    fi
}

# Check system requirements and dependencies
check_dependencies() {
    local missing_deps=()

    # Check for required commands
    local required_commands=("curl" "git" "brew")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        return $EXIT_DEPENDENCY_ERROR
    fi

    return 0
}

# Retry a command with exponential backoff
retry_command() {
    local max_attempts="${1:-3}"
    local delay="${2:-1}"
    local command="${*:3}"

    local attempt=1
    local exit_code=0

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $command"

        if eval "$command"; then
            return 0
        else
            exit_code=$?
            if [[ $attempt -eq $max_attempts ]]; then
                log_error "Command failed after $max_attempts attempts: $command"
                return $exit_code
            fi

            log_warning "Command failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2)) # Exponential backoff
            ((attempt++))
        fi
    done

    return $exit_code
}

# Get bootstrap resume information
get_resume_info() {
    local start_time completed_phases current_phase
    start_time=$(get_state_field "start_time")
    completed_phases=$(get_state_field "completed_phases")
    current_phase=$(get_state_field "current_phase")

    echo "Bootstrap Resume Information:"
    echo "  Start time: ${start_time:-"Unknown"}"
    echo "  Current phase: ${current_phase:-"None"}"

    if [[ -n "$completed_phases" ]] && command -v jq >/dev/null 2>&1; then
        echo "  Completed phases:"
        echo "$completed_phases" | jq -r '.[]' | sed 's/^/    /'
    else
        echo "  Completed phases: None"
    fi
}

# Reset bootstrap state (for fresh start)
reset_bootstrap_state() {
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log_info "Bootstrap state reset"
    fi

    if [[ -d "$BACKUP_DIR" ]]; then
        rm -rf "$BACKUP_DIR"
        log_info "Backups cleared"
    fi

    init_state_file
}

# Export functions for use in other scripts
export -f init_error_handling create_lock_file remove_lock_file
export -f get_state_field update_state_field add_to_state_array
export -f is_phase_completed mark_phase_completed mark_phase_failed set_current_phase
export -f backup_file restore_backup list_backups
export -f check_dependencies retry_command get_resume_info reset_bootstrap_state