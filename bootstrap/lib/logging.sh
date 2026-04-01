#!/bin/bash
#
# Shared logging utilities for dotfiles bootstrap
# Provides colored output, progress indicators, and structured logging
#

# Prevent multiple sourcing
[[ -n "${_LOGGING_SOURCED:-}" ]] && return 0
readonly _LOGGING_SOURCED=1

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m' # No Color

# Symbol constants
readonly CHECKMARK="✓"
readonly CROSS="✗"
readonly ARROW="→"
readonly BULLET="•"
readonly SPINNER_CHARS="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

# Global variables for logging state
VERBOSE=${VERBOSE:-false}
DEBUG=${DEBUG:-false}
LOG_FILE=${LOG_FILE:-""}
SPINNER_PID=""

# Initialize logging
init_logging() {
    # Set up log file if specified
    if [[ -n "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        exec 3>&1 4>&2 # Save original stdout/stderr
        if [[ "$DEBUG" == "true" ]]; then
            exec 1> >(tee -a "$LOG_FILE")
            exec 2> >(tee -a "$LOG_FILE" >&2)
        fi
    fi
}

# Clean timestamp for logs
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Base logging function
_log() {
    local level="$1"
    local color="$2"
    local symbol="$3"
    shift 3
    local message="$*"

    # Write to log file with timestamp if enabled
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(timestamp)] [$level] $message" >> "$LOG_FILE"
    fi

    # Output to console with colors
    echo -e "${color}${symbol} ${message}${NC}"
}

# Success message (green checkmark)
log_success() {
    _log "SUCCESS" "$GREEN" "$CHECKMARK" "$@"
}

# Error message (red cross)
log_error() {
    _log "ERROR" "$RED" "$CROSS" "$@" >&2
}

# Warning message (yellow exclamation)
log_warning() {
    _log "WARNING" "$YELLOW" "⚠" "$@"
}

# Info message (blue arrow)
log_info() {
    _log "INFO" "$BLUE" "$ARROW" "$@"
}

# Debug message (gray bullet, only shown if DEBUG=true)
log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        _log "DEBUG" "$GRAY" "$BULLET" "$@"
    fi
}

# Verbose message (only shown if VERBOSE=true)
log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        _log "VERBOSE" "$CYAN" "$BULLET" "$@"
    fi
}

# Header message (prominent purple)
log_header() {
    echo
    _log "HEADER" "$PURPLE" "▶" "$@"
    echo
}

# Step message (white arrow)
log_step() {
    _log "STEP" "$WHITE" "$ARROW" "$@"
}

# Spinner functions for long-running operations
start_spinner() {
    local message="$1"
    if [[ -n "$SPINNER_PID" ]]; then
        stop_spinner
    fi

    # Don't show spinner in non-interactive mode
    if [[ ! -t 1 ]]; then
        log_info "$message..."
        return
    fi

    log_info "$message..."

    # Start spinner in background
    {
        local i=0
        while true; do
            printf "\r${BLUE}${SPINNER_CHARS:$i:1}${NC} $message..."
            i=$(((i + 1) % ${#SPINNER_CHARS}))
            sleep 0.1
        done
    } &

    SPINNER_PID=$!
    disown # Detach from shell job control
}

# Stop the spinner
stop_spinner() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
        printf "\r\033[K" # Clear the line
    fi
}

# Progress bar for tracked operations
show_progress() {
    local current="$1"
    local total="$2"
    local message="$3"

    # Don't show progress bar in non-interactive mode
    if [[ ! -t 1 ]]; then
        log_info "[$current/$total] $message"
        return
    fi

    local percent=$((current * 100 / total))
    local filled=$((current * 40 / total))
    local empty=$((40 - filled))

    printf "\r${BLUE}["
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %d%% (%d/%d) %s${NC}" "$percent" "$current" "$total" "$message"

    if [[ "$current" -eq "$total" ]]; then
        echo # New line when complete
    fi
}

# Ask user for confirmation (returns 0 for yes, 1 for no)
confirm() {
    local message="$1"
    local default="${2:-n}" # Default to 'n' if not specified

    if [[ "$default" == "y" ]]; then
        local prompt="[Y/n]"
    else
        local prompt="[y/N]"
    fi

    echo -en "${YELLOW}? ${message} ${prompt} ${NC}"

    # In non-interactive mode, use default
    if [[ ! -t 0 ]]; then
        echo "$default"
        [[ "$default" == "y" ]]
        return $?
    fi

    read -r response

    # Use default if empty response
    if [[ -z "$response" ]]; then
        response="$default"
    fi

    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# Prompt for user input with default value
prompt() {
    local message="$1"
    local default="$2"
    local prompt_text="${CYAN}? ${message}"

    if [[ -n "$default" ]]; then
        prompt_text="${prompt_text} (${default})"
    fi

    echo -en "${prompt_text}: ${NC}"

    # In non-interactive mode, use default
    if [[ ! -t 0 ]]; then
        echo "$default"
        return 0
    fi

    read -r response

    # Use default if empty response
    if [[ -z "$response" && -n "$default" ]]; then
        response="$default"
    fi

    echo "$response"
}

# Check if we're running in a supported environment
check_environment() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This bootstrap script is designed for macOS only"
        return 1
    fi

    if ! command -v bash >/dev/null 2>&1; then
        log_error "Bash is required but not found"
        return 1
    fi

    # Check for minimum bash version (4.0+)
    if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
        log_warning "Old bash version detected (${BASH_VERSION}). Some features may not work correctly."
    fi

    return 0
}

# Cleanup function to stop spinner on exit
cleanup_logging() {
    stop_spinner

    # Restore original stdout/stderr if we redirected them
    if [[ -n "$LOG_FILE" ]]; then
        exec 1>&3 2>&4
        exec 3>&- 4>&-
    fi
}

# Set up cleanup trap
trap cleanup_logging EXIT

# Export functions for use in other scripts
export -f log_success log_error log_warning log_info log_debug log_verbose
export -f log_header log_step start_spinner stop_spinner show_progress
export -f confirm prompt check_environment timestamp