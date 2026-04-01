#!/bin/bash
#
# macOS System Preferences Automation
# Configures essential developer settings
# Run: bash ~/dotfiles/scripts/mac-defaults.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$DOTFILES_ROOT/bootstrap/lib/logging.sh" ]]; then
    source "$DOTFILES_ROOT/bootstrap/lib/logging.sh"
else
    log_info() { echo "→ $*"; }
    log_success() { echo "✓ $*"; }
    log_warning() { echo "⚠ $*"; }
    log_header() { echo; echo "▶ $*"; echo; }
    log_step() { echo "→ $*"; }
fi

log_header "macOS Developer Settings"
log_info "Applying recommended developer defaults..."
log_info "Some changes require a logout or restart to take effect."
echo

# Close System Preferences to prevent overrides
osascript -e 'tell application "System Preferences" to quit' 2>/dev/null || true
osascript -e 'tell application "System Settings" to quit' 2>/dev/null || true

# ==============================================================================
# Dock
# ==============================================================================
log_step "Configuring Dock"

# Auto-hide the Dock
defaults write com.apple.dock autohide -bool true

# Remove the auto-hide delay
defaults write com.apple.dock autohide-delay -float 0

# Speed up the auto-hide animation
defaults write com.apple.dock autohide-time-modifier -float 0.3

# Set Dock icon size
defaults write com.apple.dock tilesize -int 48

# Minimize windows using scale effect (faster than genie)
defaults write com.apple.dock mineffect -string "scale"

# Don't show recent applications in Dock
defaults write com.apple.dock show-recents -bool false

# Don't automatically rearrange Spaces based on most recent use
defaults write com.apple.dock mru-spaces -bool false

log_success "Dock configured"

# ==============================================================================
# Finder
# ==============================================================================
log_step "Configuring Finder"

# Show hidden files
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Display full POSIX path as Finder window title
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# When performing a search, search the current folder by default
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Use list view by default
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Avoid creating .DS_Store files on network or USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Show the ~/Library folder
chflags nohidden ~/Library 2>/dev/null || true

log_success "Finder configured"

# ==============================================================================
# Keyboard
# ==============================================================================
log_step "Configuring Keyboard"

# Fast key repeat rate
defaults write NSGlobalDomain KeyRepeat -int 2

# Short delay until key repeat
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Disable press-and-hold for keys in favor of key repeat
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Disable auto-correct
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Disable automatic capitalization
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# Disable automatic period substitution
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# Disable smart dashes
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Disable smart quotes
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

# Enable full keyboard access for all controls (Tab between all UI elements)
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

log_success "Keyboard configured"

# ==============================================================================
# Trackpad
# ==============================================================================
log_step "Configuring Trackpad"

# Enable tap to click
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Enable three-finger drag
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true

log_success "Trackpad configured"

# ==============================================================================
# Screenshots
# ==============================================================================
log_step "Configuring Screenshots"

# Save screenshots to ~/Screenshots
mkdir -p "$HOME/Screenshots"
defaults write com.apple.screencapture location -string "$HOME/Screenshots"

# Save screenshots in PNG format
defaults write com.apple.screencapture type -string "png"

# Disable shadow in screenshots
defaults write com.apple.screencapture disable-shadow -bool true

log_success "Screenshots configured"

# ==============================================================================
# Activity Monitor
# ==============================================================================
log_step "Configuring Activity Monitor"

# Show the main window when launching Activity Monitor
defaults write com.apple.ActivityMonitor OpenMainWindow -bool true

# Show all processes
defaults write com.apple.ActivityMonitor ShowCategory -int 0

# Sort by CPU usage
defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
defaults write com.apple.ActivityMonitor SortDirection -int 0

log_success "Activity Monitor configured"

# ==============================================================================
# TextEdit
# ==============================================================================
log_step "Configuring TextEdit"

# Use plain text mode for new documents
defaults write com.apple.TextEdit RichText -int 0

# Open and save files as UTF-8
defaults write com.apple.TextEdit PlainTextEncoding -int 4
defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4

log_success "TextEdit configured"

# ==============================================================================
# Safari (Developer Settings)
# ==============================================================================
log_step "Configuring Safari developer settings"

# Enable the Develop menu and Web Inspector
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true

# Add a context menu item for showing the Web Inspector in web views
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true

log_success "Safari developer settings configured"

# ==============================================================================
# Apply Changes
# ==============================================================================
echo
log_step "Applying changes..."

# Restart affected applications
for app in "Dock" "Finder" "SystemUIServer"; do
    killall "$app" 2>/dev/null || true
done

echo
log_success "macOS developer settings applied!"
log_info "Some changes may require a logout or restart to take full effect."
log_info "Caps Lock → Escape mapping must be set manually in:"
log_info "  System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys"